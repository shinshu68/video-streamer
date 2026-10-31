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
	"maps"
	"os"
	"path/filepath"
	"slices"
	"sync"
	"time"

	"github.com/shinshu68/video-streamer/server/internal/library"
)

// hashedBytes は識別子の計算に使う、動画の先頭と末尾それぞれの長さ。
const hashedBytes = 1 << 20

// formatVersion は索引のファイルの形と識別子の作り方の版。変えたら上げる。
// 版が違う索引は読まずに作り直す。
const formatVersion = 1

// missingRetryAfter は走査しても見つからなかった識別子のために、再び走査するまでの時間。
const missingRetryAfter = 10 * time.Minute

// incompleteRetryAfter は不完全な走査のあとの missingRetryAfter の代わりの時間。
// 読めないフォルダが残り続けても要求のたびに全体を走査しないよう、覚えないことはしない。
const incompleteRetryAfter = time.Minute

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
	lib    *library.Library
	path   string
	now    func() time.Time
	videos func() ([]library.Entry, bool, error)

	scanMu     sync.Mutex
	identifyMu sync.Mutex

	mu      sync.Mutex
	records map[string]record
	loaded  bool
	retryAt map[string]time.Time
}

// Open は path に索引を保存する Index を返す。保存された索引は初めて使うときに読み込む。
func Open(lib *library.Library, path string) *Index {
	return &Index{
		lib:     lib,
		path:    path,
		now:     time.Now,
		videos:  lib.Videos,
		records: map[string]record{},
		retryAt: map[string]time.Time{},
	}
}

// load は保存された索引をまだ読めていなければ読み込み、メモリの内容とまとめる。
// 読めるまでは次の呼び出しで読み直す。x.mu を持って呼ぶ。
func (x *Index) load() {
	if x.loaded {
		return
	}
	data, err := os.ReadFile(x.path)
	if errors.Is(err, fs.ErrNotExist) {
		// ドライブが未接続でも ErrNotExist になるため、それだけでは索引がまだないと判断できない。
		if err := os.MkdirAll(filepath.Dir(x.path), 0o755); err != nil {
			log.Printf("索引のフォルダを使えないため、読めるまで保存しません: %v", err)
			return
		}
		x.loaded = true
		return
	}
	if err != nil {
		log.Printf("索引を読めないため、読めるまで保存しません: %v", err)
		return
	}
	x.loaded = true
	var f file
	if err := json.Unmarshal(data, &f); err != nil {
		log.Printf("索引の形式が不正なため作り直します: %v", err)
		return
	}
	if f.Version == formatVersion && f.Videos != nil {
		maps.Copy(f.Videos, x.records)
		x.records = f.Videos
	}
}

// IdentifyWithin は entries の動画に、wait の間に求められた識別子を設定する。
// 間に合わなかった動画の識別子は空のままにし、計算は戻ったあとも続ける。
func (x *Index) IdentifyWithin(entries []library.Entry, wait time.Duration) {
	if x.setKnownIDs(entries) {
		return
	}
	pending := slices.Clone(entries)
	done := make(chan struct{})
	go func() {
		defer close(done)
		x.Identify(pending)
	}()
	select {
	case <-done:
	case <-time.After(wait):
	}
	x.setKnownIDs(entries)
}

// setKnownIDs は索引にある動画の識別子を entries に設定し、全ての動画に設定できたかを返す。
func (x *Index) setKnownIDs(entries []library.Entry) bool {
	x.mu.Lock()
	defer x.mu.Unlock()
	x.load()
	complete := true
	for i := range entries {
		e := &entries[i]
		if e.Type != library.EntryVideo {
			continue
		}
		known, ok := x.records[e.Path]
		if ok && known.Size == e.Size && known.Modified == e.Modified.Unix() {
			e.ID = known.ID
		} else {
			complete = false
		}
	}
	return complete
}

// Identify は entries の動画に識別子を設定する。読めない動画の識別子は空のままにする。
func (x *Index) Identify(entries []library.Entry) {
	x.identifyMu.Lock()
	defer x.identifyMu.Unlock()

	x.mu.Lock()
	x.load()
	x.mu.Unlock()

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
// 走査しても見つからなかった識別子は、missingRetryAfter の間は走査し直さない。
// 走査が不完全だったときは incompleteRetryAfter の間だけにする。
func (x *Index) Find(ids []string) ([]library.Entry, error) {
	found := x.lookup(ids)
	if x.needsScan(ids, found) {
		var err error
		found, err = x.search(ids)
		if err != nil {
			return nil, fmt.Errorf("公開フォルダを走査できません: %w", err)
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

// needsScan は ids のうち、found になく、最近の走査でも見つからなかったわけではないものがあるかを返す。
func (x *Index) needsScan(ids []string, found map[string]library.Entry) bool {
	x.mu.Lock()
	defer x.mu.Unlock()
	now := x.now()
	for _, id := range ids {
		if _, ok := found[id]; ok {
			continue
		}
		if at, ok := x.retryAt[id]; !ok || !now.Before(at) {
			return true
		}
	}
	return false
}

// search は公開フォルダ全体を走査して ids の動画を探し、見つからなかった識別子を覚える。
func (x *Index) search(ids []string) (map[string]library.Entry, error) {
	x.scanMu.Lock()
	defer x.scanMu.Unlock()
	found := x.lookup(ids)
	if !x.needsScan(ids, found) {
		return found, nil
	}

	videos, complete, err := x.videos()
	if err != nil {
		return nil, err
	}
	x.Identify(videos)
	found = x.lookup(ids)

	retryAfter := missingRetryAfter
	if !complete || slices.ContainsFunc(videos, func(e library.Entry) bool { return e.ID == "" }) {
		retryAfter = incompleteRetryAfter
	}

	x.mu.Lock()
	defer x.mu.Unlock()
	now := x.now()
	maps.DeleteFunc(x.retryAt, func(_ string, at time.Time) bool {
		return !now.Before(at)
	})
	for _, id := range ids {
		if _, ok := found[id]; !ok {
			x.retryAt[id] = now.Add(retryAfter)
		}
	}
	return found, nil
}

// lookup は索引から ids の動画を探す。索引の内容が今のファイルと合わないものは除く。
func (x *Index) lookup(ids []string) map[string]library.Entry {
	x.mu.Lock()
	x.load()
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
	x.load()
	if !x.loaded {
		return
	}
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
