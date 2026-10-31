package index

import (
	"bytes"
	"maps"
	"os"
	"path/filepath"
	"slices"
	"testing"
	"time"

	"github.com/shinshu68/video-streamer/server/internal/library"
)

type fixture struct {
	root  string
	lib   *library.Library
	index string
}

func newFixture(t *testing.T) fixture {
	t.Helper()
	root := t.TempDir()
	lib, err := library.New(root)
	if err != nil {
		t.Fatal(err)
	}
	return fixture{root: root, lib: lib, index: filepath.Join(t.TempDir(), "cache", "index.json")}
}

func (f fixture) write(t *testing.T, rel, content string) {
	t.Helper()
	path := filepath.Join(f.root, filepath.FromSlash(rel))
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(path, []byte(content), 0o644); err != nil {
		t.Fatal(err)
	}
}

func (f fixture) move(t *testing.T, from, to string) {
	t.Helper()
	dst := filepath.Join(f.root, filepath.FromSlash(to))
	if err := os.MkdirAll(filepath.Dir(dst), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.Rename(filepath.Join(f.root, filepath.FromSlash(from)), dst); err != nil {
		t.Fatal(err)
	}
}

// list はフォルダの一覧に識別子を付けて返す。
func (f fixture) list(t *testing.T, x *Index, dir string) []library.Entry {
	t.Helper()
	_, entries, err := f.lib.List(dir)
	if err != nil {
		t.Fatal(err)
	}
	x.Identify(entries)
	return entries
}

func TestIdentify_IDDoesNotDependOnNameOrFolder(t *testing.T) {
	f := newFixture(t)
	f.write(t, "a.mp4", "same")
	f.write(t, "フォルダA/b.mp4", "same")
	f.write(t, "c.mp4", "diff")
	x := Open(f.lib, f.index)

	root := f.list(t, x, "")
	sub := f.list(t, x, "フォルダA")

	a, c, b := root[1], root[2], sub[0]
	if len(a.ID) != 64 {
		t.Errorf("ID = %q, want 64 hex digits", a.ID)
	}
	if a.ID != b.ID {
		t.Errorf("同じ中身で識別子が違います: %q, %q", a.ID, b.ID)
	}
	if a.ID == c.ID {
		t.Errorf("違う中身で識別子が同じです: %q", a.ID)
	}
}

func TestIdentify_LeavesDirsWithoutID(t *testing.T) {
	f := newFixture(t)
	f.write(t, "フォルダA/b.mp4", "x")
	x := Open(f.lib, f.index)

	if root := f.list(t, x, ""); root[0].ID != "" {
		t.Errorf("フォルダの ID = %q", root[0].ID)
	}
}

func TestIdentify_UsesSavedIDUntilSizeOrModifiedChanges(t *testing.T) {
	f := newFixture(t)
	f.write(t, "a.mp4", "before")
	first := f.list(t, Open(f.lib, f.index), "")[0].ID

	// サイズと更新日時が同じなら読み直さないことを、中身だけ変えて確かめる。
	path := filepath.Join(f.root, "a.mp4")
	fi, err := os.Stat(path)
	if err != nil {
		t.Fatal(err)
	}
	f.write(t, "a.mp4", "BEFORE")
	if err := os.Chtimes(path, fi.ModTime(), fi.ModTime()); err != nil {
		t.Fatal(err)
	}
	if got := f.list(t, Open(f.lib, f.index), "")[0].ID; got != first {
		t.Errorf("保存した識別子を使っていません: %q, want %q", got, first)
	}

	later := fi.ModTime().Add(time.Hour)
	if err := os.Chtimes(path, later, later); err != nil {
		t.Fatal(err)
	}
	if got := f.list(t, Open(f.lib, f.index), "")[0].ID; got == first {
		t.Errorf("更新日時が変わっても読み直していません: %q", got)
	}
}

// entries はフォルダの一覧を識別子なしで返す。
func (f fixture) entries(t *testing.T, dir string) []library.Entry {
	t.Helper()
	_, entries, err := f.lib.List(dir)
	if err != nil {
		t.Fatal(err)
	}
	return entries
}

func TestIdentifyWithin_SetsIDsComputedInTime(t *testing.T) {
	f := newFixture(t)
	f.write(t, "a.mp4", "a")
	x := Open(f.lib, f.index)

	entries := f.entries(t, "")
	x.IdentifyWithin(entries, time.Hour)

	if entries[0].ID == "" {
		t.Error("間に合った動画に識別子がありません")
	}
}

func TestIdentifyWithin_ReturnsAtDeadlineAndFinishesInBackground(t *testing.T) {
	f := newFixture(t)
	f.write(t, "a.mp4", "a")
	x := Open(f.lib, f.index)
	x.identifyMu.Lock()

	entries := f.entries(t, "")
	x.IdentifyWithin(entries, time.Millisecond)
	if entries[0].ID != "" {
		t.Errorf("計算が終わる前に識別子があります: %q", entries[0].ID)
	}

	x.identifyMu.Unlock()
	deadline := time.Now().Add(10 * time.Second)
	for time.Now().Before(deadline) {
		if _, err := os.Stat(f.index); err == nil {
			break
		}
		time.Sleep(time.Millisecond)
	}
	if got := f.savedPaths(t); !slices.Equal(got, []string{"a.mp4"}) {
		t.Errorf("応答のあとに計算した動画が保存されていません: %q", got)
	}
}

func TestIdentifyWithin_DoesNotWaitForKnownVideos(t *testing.T) {
	f := newFixture(t)
	f.write(t, "a.mp4", "a")
	x := Open(f.lib, f.index)
	want := f.list(t, x, "")[0].ID
	x.identifyMu.Lock()
	defer x.identifyMu.Unlock()

	entries := f.entries(t, "")
	x.IdentifyWithin(entries, time.Hour)

	if entries[0].ID != want {
		t.Errorf("ID = %q, want %q", entries[0].ID, want)
	}
}

func TestSetKnownIDs_SkipsChangedVideo(t *testing.T) {
	f := newFixture(t)
	f.write(t, "a.mp4", "a")
	x := Open(f.lib, f.index)
	f.list(t, x, "")
	f.write(t, "a.mp4", "changed")

	entries := f.entries(t, "")

	if x.setKnownIDs(entries) {
		t.Error("変わった動画まで設定できたと返しました")
	}
	if entries[0].ID != "" {
		t.Errorf("変わる前の識別子を返しました: %q", entries[0].ID)
	}
}

func TestComputeID_UsesSizeHeadAndTailOnly(t *testing.T) {
	const size = 3 * hashedBytes
	id := func(mutate func(b []byte)) string {
		t.Helper()
		b := make([]byte, size)
		mutate(b)
		got, err := computeID(bytes.NewReader(b), size)
		if err != nil {
			t.Fatal(err)
		}
		return got
	}

	base := id(func([]byte) {})
	if got := id(func(b []byte) { b[size/2] = 1 }); got != base {
		t.Error("中央の変更で識別子が変わりました")
	}
	if got := id(func(b []byte) { b[0] = 1 }); got == base {
		t.Error("先頭の変更で識別子が変わりません")
	}
	if got := id(func(b []byte) { b[size-1] = 1 }); got == base {
		t.Error("末尾の変更で識別子が変わりません")
	}
}

func TestOpen_RebuildsWhenFileIsBroken(t *testing.T) {
	f := newFixture(t)
	f.write(t, "a.mp4", "x")
	if err := os.MkdirAll(filepath.Dir(f.index), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(f.index, []byte("{broken"), 0o644); err != nil {
		t.Fatal(err)
	}

	if got := f.list(t, Open(f.lib, f.index), "")[0].ID; got == "" {
		t.Error("壊れた索引のあとで識別子を計算できません")
	}
}

// savedPaths は保存された索引にある動画のパスを返す。
func (f fixture) savedPaths(t *testing.T) []string {
	t.Helper()
	x := Open(f.lib, f.index)
	x.load()
	if !x.loaded {
		t.Fatal("保存された索引を読めません")
	}
	return slices.Sorted(maps.Keys(x.records))
}

func TestIdentify_KeepsSavedIndexWhenCacheDriveConnectsAfterOpen(t *testing.T) {
	f := newFixture(t)
	f.write(t, "a.mp4", "a")
	f.write(t, "フォルダA/b.mp4", "b")
	f.list(t, Open(f.lib, f.index), "")

	// ドライブの未接続は、キャッシュのフォルダへの経路を通らなくして再現する。
	cache := filepath.Dir(f.index)
	hidden := cache + ".hidden"
	if err := os.Rename(cache, hidden); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(cache, nil, 0o644); err != nil {
		t.Fatal(err)
	}

	x := Open(f.lib, f.index)
	f.list(t, x, "フォルダA")

	if err := os.Remove(cache); err != nil {
		t.Fatal(err)
	}
	if err := os.Rename(hidden, cache); err != nil {
		t.Fatal(err)
	}
	f.write(t, "フォルダA/c.mp4", "c")
	f.list(t, x, "フォルダA")

	want := []string{"a.mp4", "フォルダA/b.mp4", "フォルダA/c.mp4"}
	if got := f.savedPaths(t); !slices.Equal(got, want) {
		t.Errorf("保存された動画 = %q, want %q", got, want)
	}
}

func TestIdentify_ReturnsIDWhileIndexCannotBeRead(t *testing.T) {
	f := newFixture(t)
	f.write(t, "a.mp4", "a")
	if err := os.MkdirAll(f.index, 0o755); err != nil {
		t.Fatal(err)
	}

	if got := f.list(t, Open(f.lib, f.index), "")[0].ID; got == "" {
		t.Error("索引を読めない間に識別子を計算できません")
	}
}

func TestFind_UsesIndexSavedBeforeOpenWithoutScanning(t *testing.T) {
	f := newFixture(t)
	f.write(t, "a.mp4", "a")
	id := f.list(t, Open(f.lib, f.index), "")[0].ID
	f.write(t, "b.mp4", "b")

	x := Open(f.lib, f.index)
	videos, err := x.Find([]string{id})
	if err != nil {
		t.Fatal(err)
	}
	if len(videos) != 1 || videos[0].Name != "a.mp4" {
		t.Fatalf("videos = %+v", videos)
	}
	if _, ok := x.records["b.mp4"]; ok {
		t.Error("保存された索引で見つかる動画のために走査しました")
	}
}

// scanned は x が動画 rel を走査で見つけて索引に入れたかを返す。
func scanned(x *Index, rel string) bool {
	_, ok := x.records[rel]
	return ok
}

func TestFind_DoesNotRescanForMissingIDUntilRetryTime(t *testing.T) {
	f := newFixture(t)
	now := time.Now()
	x := Open(f.lib, f.index)
	x.now = func() time.Time { return now }
	if _, err := x.Find([]string{"unknown"}); err != nil {
		t.Fatal(err)
	}
	f.write(t, "a.mp4", "a")

	now = now.Add(missingRetryAfter - time.Second)
	if _, err := x.Find([]string{"unknown"}); err != nil {
		t.Fatal(err)
	}
	if scanned(x, "a.mp4") {
		t.Error("見つからなかった識別子のために走査し直しました")
	}

	now = now.Add(time.Second)
	if _, err := x.Find([]string{"unknown"}); err != nil {
		t.Fatal(err)
	}
	if !scanned(x, "a.mp4") {
		t.Error("時間がたっても走査し直しません")
	}
}

func TestFind_RescansSoonAfterIncompleteScan(t *testing.T) {
	cases := map[string]func(t *testing.T, f fixture, x *Index){
		"読めないサブフォルダがある": func(t *testing.T, f fixture, x *Index) {
			x.videos = func() ([]library.Entry, bool, error) {
				return []library.Entry{}, false, nil
			}
		},
		"識別子を計算できない動画がある": func(t *testing.T, f fixture, x *Index) {
			f.write(t, "消える.mp4", "a")
			entries := f.entries(t, "")
			if err := os.Remove(filepath.Join(f.root, "消える.mp4")); err != nil {
				t.Fatal(err)
			}
			x.videos = func() ([]library.Entry, bool, error) {
				return entries, true, nil
			}
		},
	}
	for name, makeIncomplete := range cases {
		t.Run(name, func(t *testing.T) {
			f := newFixture(t)
			now := time.Now()
			x := Open(f.lib, f.index)
			x.now = func() time.Time { return now }
			makeIncomplete(t, f, x)
			if _, err := x.Find([]string{"unknown"}); err != nil {
				t.Fatal(err)
			}
			x.videos = f.lib.Videos
			f.write(t, "a.mp4", "a")

			now = now.Add(incompleteRetryAfter - time.Second)
			if _, err := x.Find([]string{"unknown"}); err != nil {
				t.Fatal(err)
			}
			if scanned(x, "a.mp4") {
				t.Error("不完全な走査の直後に走査し直しました")
			}

			now = now.Add(time.Second)
			if _, err := x.Find([]string{"unknown"}); err != nil {
				t.Fatal(err)
			}
			if !scanned(x, "a.mp4") {
				t.Error("不完全な走査のあと、時間がたっても走査し直しません")
			}
		})
	}
}

func TestFind_ScansForAnotherMissingID(t *testing.T) {
	f := newFixture(t)
	x := Open(f.lib, f.index)
	if _, err := x.Find([]string{"unknown"}); err != nil {
		t.Fatal(err)
	}
	f.write(t, "a.mp4", "a")

	if _, err := x.Find([]string{"unknown", "another"}); err != nil {
		t.Fatal(err)
	}

	if !scanned(x, "a.mp4") {
		t.Error("初めて要求された識別子で走査しません")
	}
}

func TestFind_ReturnsMissingVideoOnceListed(t *testing.T) {
	f := newFixture(t)
	f.write(t, "a.mp4", "a")
	x := Open(f.lib, f.index)
	id := f.list(t, x, "")[0].ID
	f.move(t, "a.mp4", "移動先/a.mp4")
	if err := os.Remove(filepath.Join(f.root, "移動先", "a.mp4")); err != nil {
		t.Fatal(err)
	}
	if _, err := x.Find([]string{id}); err != nil {
		t.Fatal(err)
	}

	f.write(t, "移動先/a.mp4", "a")
	f.list(t, x, "移動先")

	videos, err := x.Find([]string{id})
	if err != nil {
		t.Fatal(err)
	}
	if len(videos) != 1 || videos[0].Path != "移動先/a.mp4" {
		t.Fatalf("videos = %+v", videos)
	}
}

func TestFind_RetriesScanAfterRootCouldNotBeRead(t *testing.T) {
	f := newFixture(t)
	root := filepath.Join(f.root, "未接続")
	lib, err := library.New(root)
	if err != nil {
		t.Fatal(err)
	}
	x := Open(lib, f.index)
	if _, err := x.Find([]string{"unknown"}); err == nil {
		t.Fatal("err = nil")
	}

	f.write(t, "未接続/a.mp4", "a")

	if _, err := x.Find([]string{"unknown"}); err != nil {
		t.Fatal(err)
	}
	if !scanned(x, "a.mp4") {
		t.Error("公開フォルダを読めるようになっても走査しません")
	}
}

func TestSearch_DoesNotRepeatScanFinishedWhileWaiting(t *testing.T) {
	f := newFixture(t)
	f.write(t, "a.mp4", "a")
	x := Open(f.lib, f.index)
	x.retryAt["unknown"] = x.now().Add(missingRetryAfter)

	if _, err := x.search([]string{"unknown"}); err != nil {
		t.Fatal(err)
	}

	if scanned(x, "a.mp4") {
		t.Error("待っている間に終わった走査のあとで、また走査しました")
	}
}

func TestFind_ReturnsVideosInRequestedOrder(t *testing.T) {
	f := newFixture(t)
	f.write(t, "a.mp4", "a")
	f.write(t, "b.mp4", "b")
	x := Open(f.lib, f.index)
	root := f.list(t, x, "")

	videos, err := x.Find([]string{root[1].ID, root[0].ID})
	if err != nil {
		t.Fatal(err)
	}
	if len(videos) != 2 || videos[0].Name != "b.mp4" || videos[1].Name != "a.mp4" {
		t.Fatalf("videos = %+v", videos)
	}
	if videos[0].ID != root[1].ID || videos[0].Size != 1 || videos[0].Modified == nil {
		t.Errorf("videos[0] = %+v", videos[0])
	}
}

func TestFind_FollowsMovedAndRenamedVideo(t *testing.T) {
	f := newFixture(t)
	f.write(t, "a.mp4", "a")
	x := Open(f.lib, f.index)
	id := f.list(t, x, "")[0].ID

	f.move(t, "a.mp4", "新しいフォルダ/b.mp4")

	videos, err := x.Find([]string{id})
	if err != nil {
		t.Fatal(err)
	}
	if len(videos) != 1 || videos[0].Path != "新しいフォルダ/b.mp4" {
		t.Fatalf("videos = %+v", videos)
	}
}

func TestFind_OmitsDeletedVideoAndUnknownID(t *testing.T) {
	f := newFixture(t)
	f.write(t, "a.mp4", "a")
	f.write(t, "b.mp4", "b")
	x := Open(f.lib, f.index)
	root := f.list(t, x, "")
	if err := os.Remove(filepath.Join(f.root, "a.mp4")); err != nil {
		t.Fatal(err)
	}

	videos, err := x.Find([]string{root[0].ID, "unknown", root[1].ID})
	if err != nil {
		t.Fatal(err)
	}
	if len(videos) != 1 || videos[0].Name != "b.mp4" {
		t.Fatalf("videos = %+v", videos)
	}
}

func TestFind_ReturnsOtherCopyWhenOneIsDeleted(t *testing.T) {
	f := newFixture(t)
	f.write(t, "a.mp4", "same")
	f.write(t, "b.mp4", "same")
	x := Open(f.lib, f.index)
	root := f.list(t, x, "")
	if err := os.Remove(filepath.Join(f.root, "a.mp4")); err != nil {
		t.Fatal(err)
	}

	videos, err := x.Find([]string{root[0].ID})
	if err != nil {
		t.Fatal(err)
	}
	if len(videos) != 1 || videos[0].Name != "b.mp4" {
		t.Fatalf("videos = %+v", videos)
	}
}

func TestFind_WithNoIDsReturnsEmptyList(t *testing.T) {
	f := newFixture(t)
	videos, err := Open(f.lib, f.index).Find(nil)
	if err != nil {
		t.Fatal(err)
	}
	if videos == nil || len(videos) != 0 {
		t.Fatalf("videos = %#v", videos)
	}
}

func TestFind_FailsWhenRootCannotBeRead(t *testing.T) {
	f := newFixture(t)
	lib, err := library.New(filepath.Join(f.root, "未接続"))
	if err != nil {
		t.Fatal(err)
	}

	if _, err := Open(lib, f.index).Find([]string{"unknown"}); err == nil {
		t.Fatal("err = nil")
	}
}
