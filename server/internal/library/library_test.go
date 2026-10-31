package library

import (
	"errors"
	"os"
	"path/filepath"
	"reflect"
	"runtime"
	"sort"
	"testing"
)

// newTestLibrary は次の構成の公開フォルダと、その外にあるフォルダを作る。
//
//	root/
//	├── フォルダA/
//	│   ├── サブフォルダB/
//	│   └── 動画C.mp4
//	├── .hidden/
//	├── .隠し動画.mp4
//	├── b.mp4
//	├── a.MP4
//	├── memo.txt
//	└── z/
func newTestLibrary(t *testing.T) (lib *Library, root string, outside string) {
	t.Helper()
	base := t.TempDir()
	root = filepath.Join(base, "root")
	outside = filepath.Join(base, "outside")

	for _, dir := range []string{"フォルダA/サブフォルダB", ".hidden", "z"} {
		mustMkdir(t, filepath.Join(root, dir))
	}
	for _, file := range []string{"フォルダA/動画C.mp4", ".隠し動画.mp4", "b.mp4", "a.MP4", "memo.txt"} {
		mustWrite(t, filepath.Join(root, file), "dummy")
	}
	mustMkdir(t, outside)
	mustWrite(t, filepath.Join(outside, "secret.mp4"), "secret")

	lib, err := New(root)
	if err != nil {
		t.Fatal(err)
	}
	return lib, root, outside
}

func mustMkdir(t *testing.T, path string) {
	t.Helper()
	if err := os.MkdirAll(path, 0o755); err != nil {
		t.Fatal(err)
	}
}

func mustWrite(t *testing.T, path, content string) {
	t.Helper()
	if err := os.WriteFile(path, []byte(content), 0o644); err != nil {
		t.Fatal(err)
	}
}

func mustSymlink(t *testing.T, target, link string) {
	t.Helper()
	if err := os.Symlink(target, link); err != nil {
		t.Skipf("シンボリックリンクを作れない環境です: %v", err)
	}
}

func TestResolve_NormalizesPath(t *testing.T) {
	lib, root, _ := newTestLibrary(t)
	tests := []struct {
		rel       string
		wantClean string
	}{
		{"", ""},
		{"/", ""},
		{"フォルダA", "フォルダA"},
		{"フォルダA/", "フォルダA"},
		{"./フォルダA//サブフォルダB", "フォルダA/サブフォルダB"},
		{`フォルダA\動画C.mp4`, "フォルダA/動画C.mp4"},
	}
	for _, tt := range tests {
		t.Run(tt.rel, func(t *testing.T) {
			abs, clean, err := lib.Resolve(tt.rel)
			if err != nil {
				t.Fatalf("Resolve() error = %v", err)
			}
			if clean != tt.wantClean {
				t.Errorf("clean = %q, want %q", clean, tt.wantClean)
			}
			if want := filepath.Join(root, filepath.FromSlash(tt.wantClean)); abs != want {
				t.Errorf("abs = %q, want %q", abs, want)
			}
		})
	}
}

func TestResolve_RejectsPathOutsideRoot(t *testing.T) {
	lib, _, _ := newTestLibrary(t)
	for _, rel := range []string{
		"..",
		"../outside/secret.mp4",
		"フォルダA/../../outside",
		`..\outside`,
		"C:/Windows",
		"b.mp4:stream",
	} {
		t.Run(rel, func(t *testing.T) {
			if _, _, err := lib.Resolve(rel); !errors.Is(err, ErrForbidden) {
				t.Errorf("Resolve(%q) error = %v, want ErrForbidden", rel, err)
			}
		})
	}
}

func TestResolve_TreatsMissingAndHiddenPathAsNotFound(t *testing.T) {
	lib, _, _ := newTestLibrary(t)
	for _, rel := range []string{"missing", "フォルダA/missing.mp4", ".hidden", ".隠し動画.mp4"} {
		t.Run(rel, func(t *testing.T) {
			if _, _, err := lib.Resolve(rel); !errors.Is(err, ErrNotFound) {
				t.Errorf("Resolve(%q) error = %v, want ErrNotFound", rel, err)
			}
		})
	}
}

func TestResolve_DoesNotFollowSymlink(t *testing.T) {
	lib, root, outside := newTestLibrary(t)
	mustSymlink(t, outside, filepath.Join(root, "link-dir"))
	mustSymlink(t, filepath.Join(outside, "secret.mp4"), filepath.Join(root, "link.mp4"))

	for _, rel := range []string{"link-dir", "link-dir/secret.mp4", "link.mp4"} {
		t.Run(rel, func(t *testing.T) {
			if _, _, err := lib.Resolve(rel); !errors.Is(err, ErrNotFound) {
				t.Errorf("Resolve(%q) error = %v, want ErrNotFound", rel, err)
			}
		})
	}
}

func TestList_ReturnsDirsFirstThenVideosByName(t *testing.T) {
	lib, _, _ := newTestLibrary(t)

	clean, entries, err := lib.List("")
	if err != nil {
		t.Fatalf("List() error = %v", err)
	}
	if clean != "" {
		t.Errorf("clean = %q, want empty", clean)
	}
	var got [][2]string
	for _, e := range entries {
		got = append(got, [2]string{string(e.Type), e.Path})
	}
	want := [][2]string{
		{"dir", "z"},
		{"dir", "フォルダA"},
		{"video", "a.MP4"},
		{"video", "b.mp4"},
	}
	if !reflect.DeepEqual(got, want) {
		t.Errorf("entries = %v, want %v", got, want)
	}
}

func TestList_ReturnsSizeAndModifiedOnlyForVideos(t *testing.T) {
	lib, _, _ := newTestLibrary(t)

	_, entries, err := lib.List("フォルダA")
	if err != nil {
		t.Fatalf("List() error = %v", err)
	}
	if len(entries) != 2 {
		t.Fatalf("len(entries) = %d, want 2", len(entries))
	}
	dir, video := entries[0], entries[1]
	if dir.Path != "フォルダA/サブフォルダB" || dir.Size != 0 || dir.Modified != nil {
		t.Errorf("dir = %+v", dir)
	}
	if video.Path != "フォルダA/動画C.mp4" || video.Size != int64(len("dummy")) || video.Modified == nil {
		t.Errorf("video = %+v", video)
	}
	if video.Modified != nil && video.Modified.Nanosecond() != 0 {
		t.Errorf("Modified = %v, want truncated to seconds", video.Modified)
	}
}

func TestList_ExcludesSymlinks(t *testing.T) {
	lib, root, outside := newTestLibrary(t)
	mustSymlink(t, outside, filepath.Join(root, "link-dir"))
	mustSymlink(t, filepath.Join(outside, "secret.mp4"), filepath.Join(root, "link.mp4"))

	_, entries, err := lib.List("")
	if err != nil {
		t.Fatalf("List() error = %v", err)
	}
	for _, e := range entries {
		if e.Name == "link-dir" || e.Name == "link.mp4" {
			t.Errorf("entries contains symlink %q", e.Name)
		}
	}
}

func TestList_ReturnsEmptySliceForEmptyDir(t *testing.T) {
	lib, _, _ := newTestLibrary(t)

	_, entries, err := lib.List("z")
	if err != nil {
		t.Fatalf("List() error = %v", err)
	}
	if entries == nil || len(entries) != 0 {
		t.Errorf("entries = %#v, want empty non-nil slice", entries)
	}
}

func TestList_TreatsFileAsNotFound(t *testing.T) {
	lib, _, _ := newTestLibrary(t)

	if _, _, err := lib.List("b.mp4"); !errors.Is(err, ErrNotFound) {
		t.Errorf("List() error = %v, want ErrNotFound", err)
	}
}

func TestList_TreatsMissingRootAsNotFound(t *testing.T) {
	lib, err := New(filepath.Join(t.TempDir(), "disconnected"))
	if err != nil {
		t.Fatal(err)
	}

	if _, _, err := lib.List(""); !errors.Is(err, ErrNotFound) {
		t.Errorf("List() error = %v, want ErrNotFound", err)
	}
}

func TestOpenVideo_OpensVideoFile(t *testing.T) {
	lib, _, _ := newTestLibrary(t)

	f, fi, err := lib.OpenVideo("フォルダA/動画C.mp4")
	if err != nil {
		t.Fatalf("OpenVideo() error = %v", err)
	}
	defer f.Close()
	if fi.Name() != "動画C.mp4" {
		t.Errorf("Name() = %q", fi.Name())
	}
}

func TestVideo_ReturnsPathAndInfo(t *testing.T) {
	lib, root, _ := newTestLibrary(t)

	abs, clean, fi, err := lib.Video(`フォルダA\動画C.mp4`)
	if err != nil {
		t.Fatalf("Video() error = %v", err)
	}
	if want := filepath.Join(root, "フォルダA", "動画C.mp4"); abs != want {
		t.Errorf("abs = %q, want %q", abs, want)
	}
	if clean != "フォルダA/動画C.mp4" {
		t.Errorf("clean = %q", clean)
	}
	if fi.Size() != int64(len("dummy")) {
		t.Errorf("Size() = %d", fi.Size())
	}
}

func TestVideo_RejectsNonVideo(t *testing.T) {
	lib, _, _ := newTestLibrary(t)
	for _, rel := range []string{"memo.txt", "フォルダA", "", "missing.mp4", "../outside/secret.mp4"} {
		t.Run(rel, func(t *testing.T) {
			if _, _, _, err := lib.Video(rel); err == nil {
				t.Errorf("Video(%q) error = nil, want error", rel)
			}
		})
	}
}

func TestOpenVideo_RejectsNonVideo(t *testing.T) {
	lib, _, _ := newTestLibrary(t)
	for _, rel := range []string{"memo.txt", "フォルダA", ""} {
		t.Run(rel, func(t *testing.T) {
			if _, _, err := lib.OpenVideo(rel); !errors.Is(err, ErrNotFound) {
				t.Errorf("OpenVideo(%q) error = %v, want ErrNotFound", rel, err)
			}
		})
	}
}

func TestNew_ExcludedDirIsNotListedOrResolved(t *testing.T) {
	_, root, _ := newTestLibrary(t)
	cache := filepath.Join(root, "フォルダA", "cache")
	mustMkdir(t, cache)
	mustWrite(t, filepath.Join(cache, "thumb.mp4"), "dummy")
	lib, err := New(root, cache)
	if err != nil {
		t.Fatal(err)
	}

	_, entries, err := lib.List("フォルダA")
	if err != nil {
		t.Fatalf("List() error = %v", err)
	}
	for _, e := range entries {
		if e.Name == "cache" {
			t.Errorf("excluded dir is listed: %+v", e)
		}
	}
	for _, rel := range []string{"フォルダA/cache", "フォルダA/cache/thumb.mp4"} {
		if _, _, err := lib.Resolve(rel); !errors.Is(err, ErrNotFound) {
			t.Errorf("Resolve(%q) error = %v, want ErrNotFound", rel, err)
		}
	}
}

func TestNew_ExcludedDirIgnoresCaseOnWindows(t *testing.T) {
	if runtime.GOOS != "windows" {
		t.Skip("大文字小文字を区別しないのは Windows だけ")
	}
	_, root, _ := newTestLibrary(t)
	mustMkdir(t, filepath.Join(root, "Cache"))
	lib, err := New(root, filepath.Join(root, "CACHE"))
	if err != nil {
		t.Fatal(err)
	}

	if _, _, err := lib.Resolve("Cache"); !errors.Is(err, ErrNotFound) {
		t.Errorf("Resolve() error = %v, want ErrNotFound", err)
	}
}

func TestNew_RejectsExcludingRootOrItsParent(t *testing.T) {
	_, root, _ := newTestLibrary(t)

	for _, ex := range []string{root, filepath.Dir(root)} {
		if _, err := New(root, ex); err == nil {
			t.Errorf("New(root, %q) error = nil, want error", ex)
		}
	}
}

func TestNew_AllowsExcludedDirOutsideRoot(t *testing.T) {
	_, root, outside := newTestLibrary(t)

	lib, err := New(root, outside)
	if err != nil {
		t.Fatalf("New() error = %v", err)
	}
	if _, _, err := lib.Resolve("フォルダA"); err != nil {
		t.Errorf("Resolve() error = %v", err)
	}
}

func TestVideos_ReturnsVideosOfAllFolders(t *testing.T) {
	lib, _, _ := newTestLibrary(t)

	videos, err := lib.Videos()
	if err != nil {
		t.Fatal(err)
	}
	var paths []string
	for _, v := range videos {
		paths = append(paths, v.Path)
	}
	sort.Strings(paths)
	want := []string{"a.MP4", "b.mp4", "フォルダA/動画C.mp4"}
	if !reflect.DeepEqual(paths, want) {
		t.Errorf("paths = %v, want %v", paths, want)
	}
}

func TestVideos_FailsWhenRootIsMissing(t *testing.T) {
	lib, err := New(filepath.Join(t.TempDir(), "未接続"))
	if err != nil {
		t.Fatal(err)
	}

	if _, err := lib.Videos(); !errors.Is(err, ErrNotFound) {
		t.Errorf("err = %v, want ErrNotFound", err)
	}
}

func TestVideoEntry_ReturnsSameEntryAsList(t *testing.T) {
	lib, _, _ := newTestLibrary(t)

	_, entries, err := lib.List("フォルダA")
	if err != nil {
		t.Fatal(err)
	}
	got, err := lib.VideoEntry("フォルダA/動画C.mp4")
	if err != nil {
		t.Fatal(err)
	}
	if !reflect.DeepEqual(got, entries[len(entries)-1]) {
		t.Errorf("got = %+v, want %+v", got, entries[len(entries)-1])
	}
}
