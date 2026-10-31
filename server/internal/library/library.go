// Package library は公開フォルダ配下のパスの検証と、フォルダの一覧を扱う。
//
// パスの扱いは docs/api.md の「共通」に合わせる。
package library

import (
	"errors"
	"fmt"
	"io/fs"
	"log"
	"os"
	"path/filepath"
	"sort"
	"strings"
	"time"
)

var (
	// ErrForbidden は公開フォルダの外を指すパスを表す。
	ErrForbidden = errors.New("forbidden")
	// ErrNotFound は存在しないパスや、扱わないファイルを指すパスを表す。
	ErrNotFound = errors.New("not found")
)

// EntryType は一覧の要素の種類。
type EntryType string

const (
	EntryDir   EntryType = "dir"
	EntryVideo EntryType = "video"
)

// Entry は一覧の1要素。ID、Size、Modified は動画のときだけ持つ。ID は index パッケージが設定する。
type Entry struct {
	Type     EntryType  `json:"type"`
	ID       string     `json:"id,omitempty"`
	Name     string     `json:"name"`
	Path     string     `json:"path"`
	Size     int64      `json:"size,omitempty"`
	Modified *time.Time `json:"modified,omitempty"`
}

// Library は1つの公開フォルダを表す。
type Library struct {
	root     string
	excluded []string
}

// New は root を公開フォルダとする Library を作る。
// excluded のフォルダ (サーバーのキャッシュなど) は、root の中にあっても扱わない。
// 外付けHDDが未接続でも起動できるよう、root の存在はここでは確かめない。
func New(root string, excluded ...string) (*Library, error) {
	abs, err := filepath.Abs(root)
	if err != nil {
		return nil, fmt.Errorf("公開フォルダのパスを解決できません: %w", err)
	}
	l := &Library{root: abs}
	for _, ex := range excluded {
		exAbs, err := filepath.Abs(ex)
		if err != nil {
			return nil, fmt.Errorf("除外するフォルダのパスを解決できません: %w", err)
		}
		if contains(exAbs, abs) {
			return nil, fmt.Errorf("公開フォルダ %s を含むフォルダ %s は除外できません", abs, exAbs)
		}
		l.excluded = append(l.excluded, exAbs)
	}
	return l, nil
}

// contains は dir が path そのものか、path を含むフォルダかを返す。
func contains(dir, path string) bool {
	rel, err := filepath.Rel(dir, path)
	return err == nil && rel != ".." && !strings.HasPrefix(rel, ".."+string(filepath.Separator))
}

// isExcluded は fi のフォルダが除外するフォルダかを返す。
// Windows は末尾のドットや空白、短縮名でも同じフォルダを指すため、パスの文字列では比べない。
func (l *Library) isExcluded(fi fs.FileInfo) bool {
	if !fi.IsDir() {
		return false
	}
	for _, ex := range l.excluded {
		exInfo, err := os.Lstat(ex)
		if err == nil && os.SameFile(fi, exInfo) {
			return true
		}
	}
	return false
}

// Resolve は公開フォルダからの相対パス rel を検証し、実際のパスと、
// "/" 区切りに正規化した相対パスを返す。
func (l *Library) Resolve(rel string) (abs string, clean string, err error) {
	elems, err := splitPath(rel)
	if err != nil {
		return "", "", err
	}

	abs = l.root
	for _, elem := range elems {
		abs = filepath.Join(abs, elem)
		// 最後に EvalSymlinks で root 配下かを比べる方法は、
		// Windows のジャンクションやドライブ文字の表記ゆれで判定を誤りやすいため使わない。
		fi, err := os.Lstat(abs)
		if err != nil {
			return "", "", ErrNotFound
		}
		if !isPlainDirOrFile(fi.Mode()) || hasHiddenOrSystemAttr(fi) || l.isExcluded(fi) {
			return "", "", ErrNotFound
		}
	}
	return abs, strings.Join(elems, "/"), nil
}

// driveStreamOrNULChars はドライブ文字 (C:) や NTFS の代替データストリーム (a.mp4:stream) を
// 表す区切りと NUL で、パスの要素に含められない文字。
const driveStreamOrNULChars = ":\x00"

func splitPath(rel string) ([]string, error) {
	var elems []string
	for _, elem := range strings.Split(strings.ReplaceAll(rel, `\`, "/"), "/") {
		switch {
		case elem == "" || elem == ".":
			continue
		case elem == "..":
			return nil, ErrForbidden
		case strings.ContainsAny(elem, driveStreamOrNULChars):
			return nil, ErrForbidden
		case strings.HasPrefix(elem, "."):
			return nil, ErrNotFound
		}
		elems = append(elems, elem)
	}
	return elems, nil
}

// isPlainDirOrFile は通常のフォルダか通常のファイルかを返す。
// シンボリックリンク、Windows のジャンクション (ModeIrregular)、デバイスなどは false。
func isPlainDirOrFile(mode fs.FileMode) bool {
	t := mode.Type()
	return t == 0 || t == fs.ModeDir
}

// IsVideoName は name が動画として扱うファイル名かを返す。
func IsVideoName(name string) bool {
	return strings.EqualFold(filepath.Ext(name), ".mp4")
}

// List は rel のフォルダにあるフォルダと動画を、フォルダを先に名前順で返す。
// 返す相対パスは "/" 区切りに正規化したもの。
func (l *Library) List(rel string) (clean string, entries []Entry, err error) {
	abs, clean, err := l.Resolve(rel)
	if err != nil {
		return "", nil, err
	}
	if fi, err := os.Stat(abs); err != nil || !fi.IsDir() {
		return "", nil, ErrNotFound
	}
	dirEntries, err := os.ReadDir(abs)
	if err != nil {
		return "", nil, err
	}

	entries = []Entry{}
	for _, de := range dirEntries {
		name := de.Name()
		if strings.HasPrefix(name, ".") {
			continue
		}
		info, err := de.Info()
		if err != nil {
			// 一覧を作る間に消されたファイルは、一覧から外すだけでよい。
			continue
		}
		if hasHiddenOrSystemAttr(info) || l.isExcluded(info) {
			continue
		}
		path := joinRel(clean, name)
		switch de.Type() {
		case fs.ModeDir:
			entries = append(entries, Entry{Type: EntryDir, Name: name, Path: path})
		case 0:
			if !IsVideoName(name) {
				continue
			}
			entries = append(entries, videoEntry(name, path, info))
		}
	}

	sort.Slice(entries, func(i, j int) bool {
		if entries[i].Type != entries[j].Type {
			return entries[i].Type == EntryDir
		}
		return entries[i].Name < entries[j].Name
	})
	return clean, entries, nil
}

func videoEntry(name, path string, info fs.FileInfo) Entry {
	modified := info.ModTime().Truncate(time.Second)
	return Entry{Type: EntryVideo, Name: name, Path: path, Size: info.Size(), Modified: &modified}
}

// Videos は公開フォルダ全体の動画を返す。公開フォルダを読めないときはエラーを返す。
func (l *Library) Videos() ([]Entry, error) {
	videos := []Entry{}
	dirs := []string{""}
	for len(dirs) > 0 {
		dir := dirs[len(dirs)-1]
		dirs = dirs[:len(dirs)-1]
		_, entries, err := l.List(dir)
		if err != nil {
			if dir == "" {
				return nil, err
			}
			// 読めないサブフォルダが1つあっても、残りの動画は探せるようにする。
			log.Printf("フォルダを読めません (%s): %v", dir, err)
			continue
		}
		for _, e := range entries {
			if e.Type == EntryDir {
				dirs = append(dirs, e.Path)
			} else {
				videos = append(videos, e)
			}
		}
	}
	return videos, nil
}

func joinRel(dir, name string) string {
	if dir == "" {
		return name
	}
	return dir + "/" + name
}

// Video は rel の動画の実際のパス、正規化した相対パス、ファイルの情報を返す。
// 動画でないファイルやフォルダは ErrNotFound を返す。
func (l *Library) Video(rel string) (abs string, clean string, fi fs.FileInfo, err error) {
	abs, clean, err = l.Resolve(rel)
	if err != nil {
		return "", "", nil, err
	}
	if !IsVideoName(abs) {
		return "", "", nil, ErrNotFound
	}
	fi, err = os.Stat(abs)
	if err != nil || !fi.Mode().IsRegular() {
		return "", "", nil, ErrNotFound
	}
	return abs, clean, fi, nil
}

// VideoEntry は rel の動画の一覧の要素を返す。動画でないファイルやフォルダは ErrNotFound を返す。
func (l *Library) VideoEntry(rel string) (Entry, error) {
	_, clean, fi, err := l.Video(rel)
	if err != nil {
		return Entry{}, err
	}
	return videoEntry(fi.Name(), clean, fi), nil
}

// OpenVideo は rel の動画を開く。動画でないファイルやフォルダは ErrNotFound を返す。
func (l *Library) OpenVideo(rel string) (*os.File, fs.FileInfo, error) {
	abs, _, _, err := l.Video(rel)
	if err != nil {
		return nil, nil, err
	}
	f, err := os.Open(abs)
	if err != nil {
		return nil, nil, ErrNotFound
	}
	fi, err := f.Stat()
	if err != nil || !fi.Mode().IsRegular() {
		f.Close()
		return nil, nil, ErrNotFound
	}
	return f, fi, nil
}
