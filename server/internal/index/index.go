// Package index は動画の識別子を求め、識別子とパスの索引をファイルに保存する。
//
// 識別子の作り方は docs/api.md の「一覧の取得」に合わせる。
package index

import (
	"crypto/sha256"
	"encoding/binary"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"io/fs"
	"log"
	"os"
	"path/filepath"
	"slices"
	"sync"

	"github.com/shinshu68/video-streamer/server/internal/library"
)

// hashedBytes は識別子の計算に使う、動画の先頭と末尾それぞれの長さ。
const hashedBytes = 1 << 20

// formatVersion は索引のファイルの形と識別子の作り方の版。変えたら上げる。
// 版が違う索引は読まずに作り直す。
const formatVersion = 1

type record struct {
	Size     int64  `json:"size"`
	Modified int64  `json:"modified"`
	ID       string `json:"id"`
}

type file struct {
	Version int               `json:"version"`
	Videos  map[string]record `json:"videos"`
}

// Index は動画の相対パスごとの識別子を、サイズと更新日時とともに覚えておく。
type Index struct {
	lib  *library.Library
	path string

	scanMu sync.Mutex

	mu      sync.Mutex
	records map[string]record
}

// Open は path に保存された索引を読み込む。読めないときは空の索引から始める。
func Open(lib *library.Library, path string) *Index {
	x := &Index{lib: lib, path: path, records: map[string]record{}}
	data, err := os.ReadFile(path)
	if errors.Is(err, fs.ErrNotExist) {
		return x
	}
	if err != nil {
		log.Printf("索引を読めないため作り直します: %v", err)
		return x
	}
	var f file
	if err := json.Unmarshal(data, &f); err != nil {
		log.Printf("索引の形式が不正なため作り直します: %v", err)
		return x
	}
	if f.Version == formatVersion && f.Videos != nil {
		x.records = f.Videos
	}
	return x
}

// Identify は entries の動画に識別子を設定する。読めない動画の識別子は空のままにする。
func (x *Index) Identify(entries []library.Entry) {
	changed := false
	for i := range entries {
		e := &entries[i]
		if e.Type != library.EntryVideo {
			continue
		}
		rec := record{Size: e.Size, Modified: e.Modified.Unix()}

		x.mu.Lock()
		known, ok := x.records[e.Path]
		x.mu.Unlock()
		if ok && known.Size == rec.Size && known.Modified == rec.Modified {
			e.ID = known.ID
			continue
		}

		id, err := x.compute(e.Path)
		if err != nil {
			log.Printf("識別子を計算できません (%s): %v", e.Path, err)
			continue
		}
		rec.ID = id
		e.ID = id
		changed = true

		x.mu.Lock()
		x.records[e.Path] = rec
		x.mu.Unlock()
	}
	if changed {
		x.save()
	}
}

func (x *Index) compute(rel string) (string, error) {
	f, fi, err := x.lib.OpenVideo(rel)
	if err != nil {
		return "", err
	}
	defer f.Close()
	return computeID(f, fi.Size())
}

func computeID(r io.ReaderAt, size int64) (string, error) {
	h := sha256.New()
	if err := binary.Write(h, binary.BigEndian, size); err != nil {
		return "", err
	}
	head := min(size, hashedBytes)
	if _, err := io.Copy(h, io.NewSectionReader(r, 0, head)); err != nil {
		return "", err
	}
	tail := max(size-hashedBytes, 0)
	if _, err := io.Copy(h, io.NewSectionReader(r, tail, size-tail)); err != nil {
		return "", err
	}
	return hex.EncodeToString(h.Sum(nil)), nil
}

// Find は ids の順に、今も存在する動画を返す。見つからない識別子は結果に含めない。
//
// 索引にない識別子があるときは、公開フォルダ全体を走査し直す。
func (x *Index) Find(ids []string) ([]library.Entry, error) {
	found := x.lookup(ids)
	for _, id := range ids {
		if _, ok := found[id]; !ok {
			if err := x.scan(); err != nil {
				return nil, fmt.Errorf("公開フォルダを走査できません: %w", err)
			}
			found = x.lookup(ids)
			break
		}
	}

	videos := []library.Entry{}
	for _, id := range ids {
		if e, ok := found[id]; ok {
			videos = append(videos, e)
		}
	}
	return videos, nil
}

func (x *Index) scan() error {
	x.scanMu.Lock()
	defer x.scanMu.Unlock()
	videos, err := x.lib.Videos()
	if err != nil {
		return err
	}
	x.Identify(videos)
	return nil
}

// lookup は索引から ids の動画を探す。索引の内容が今のファイルと合わないものは除く。
func (x *Index) lookup(ids []string) map[string]library.Entry {
	x.mu.Lock()
	records := map[string]record{}
	for path, rec := range x.records {
		if slices.Contains(ids, rec.ID) {
			records[path] = rec
		}
	}
	x.mu.Unlock()

	paths := make([]string, 0, len(records))
	for path := range records {
		paths = append(paths, path)
	}
	slices.Sort(paths)

	found := map[string]library.Entry{}
	for _, path := range paths {
		rec := records[path]
		if _, ok := found[rec.ID]; ok {
			continue
		}
		e, err := x.lib.VideoEntry(path)
		if err != nil || e.Size != rec.Size || e.Modified.Unix() != rec.Modified {
			continue
		}
		e.ID = rec.ID
		found[rec.ID] = e
	}
	return found
}

// save は索引をファイルに書き出す。失敗しても次の保存で書き直せるため、ログに残すだけにする。
func (x *Index) save() {
	x.mu.Lock()
	defer x.mu.Unlock()
	if err := x.writeFile(); err != nil {
		log.Printf("索引を保存できません: %v", err)
	}
}

func (x *Index) writeFile() error {
	data, err := json.Marshal(file{Version: formatVersion, Videos: x.records})
	if err != nil {
		return err
	}
	dir := filepath.Dir(x.path)
	if err := os.MkdirAll(dir, 0o755); err != nil {
		return err
	}
	tmp, err := os.CreateTemp(dir, "tmp-*.json")
	if err != nil {
		return err
	}
	defer os.Remove(tmp.Name())
	_, err = tmp.Write(data)
	if closeErr := tmp.Close(); err == nil {
		err = closeErr
	}
	if err != nil {
		return err
	}
	// 書きかけの索引を読み込まないよう、書き終えてから正式な名前にする。
	return os.Rename(tmp.Name(), x.path)
}
