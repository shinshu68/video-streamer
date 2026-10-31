package library

import (
	"errors"
	"os/exec"
	"path/filepath"
	"syscall"
	"testing"
)

func mustSetAttr(t *testing.T, path string, attr uint32) {
	t.Helper()
	p, err := syscall.UTF16PtrFromString(path)
	if err != nil {
		t.Fatal(err)
	}
	if err := syscall.SetFileAttributes(p, attr); err != nil {
		t.Fatal(err)
	}
	// 属性が付いたままだと t.TempDir の後片付けで消せないことがあるため戻す。
	t.Cleanup(func() { syscall.SetFileAttributes(p, syscall.FILE_ATTRIBUTE_NORMAL) })
}

func mustJunction(t *testing.T, target, link string) {
	t.Helper()
	if out, err := exec.Command("cmd", "/c", "mklink", "/J", link, target).CombinedOutput(); err != nil {
		t.Fatalf("mklink /J: %v: %s", err, out)
	}
}

// shortName は path の最後の要素の 8.3 形式の短縮名を返す。
func shortName(t *testing.T, path string) string {
	t.Helper()
	p, err := syscall.UTF16PtrFromString(path)
	if err != nil {
		t.Fatal(err)
	}
	buf := make([]uint16, syscall.MAX_PATH)
	if _, err := syscall.GetShortPathName(p, &buf[0], uint32(len(buf))); err != nil {
		t.Fatal(err)
	}
	return filepath.Base(syscall.UTF16ToString(buf))
}

func TestWindowsPath_ExcludedDirCannotBeReachedByAlias(t *testing.T) {
	_, root, _ := newTestLibrary(t)
	cache := filepath.Join(root, "video-streamer-cache")
	mustMkdir(t, cache)
	mustWrite(t, filepath.Join(cache, "thumb.mp4"), "dummy")
	lib, err := New(root, cache)
	if err != nil {
		t.Fatal(err)
	}

	for _, alias := range []string{"video-streamer-cache.", "video-streamer-cache ", "video-streamer-cache. ."} {
		for _, rel := range []string{alias, alias + "/thumb.mp4"} {
			if _, _, err := lib.Resolve(rel); !errors.Is(err, ErrNotFound) {
				t.Errorf("Resolve(%q) error = %v, want ErrNotFound", rel, err)
			}
		}
	}
}

func TestWindowsPath_ExcludedDirCannotBeReachedByShortName(t *testing.T) {
	_, root, _ := newTestLibrary(t)
	cache := filepath.Join(root, "video-streamer-cache")
	mustMkdir(t, cache)
	short := shortName(t, cache)
	if short == filepath.Base(cache) {
		t.Skip("このボリュームでは短縮名が作られない")
	}
	lib, err := New(root, cache)
	if err != nil {
		t.Fatal(err)
	}

	if _, _, err := lib.Resolve(short); !errors.Is(err, ErrNotFound) {
		t.Errorf("Resolve(%q) error = %v, want ErrNotFound", short, err)
	}
}

func TestWindowsAttr_ExcludesHiddenAndSystemEntries(t *testing.T) {
	lib, root, _ := newTestLibrary(t)
	mustMkdir(t, filepath.Join(root, "システムフォルダ"))
	mustWrite(t, filepath.Join(root, "隠し動画.mp4"), "dummy")
	mustSetAttr(t, filepath.Join(root, "システムフォルダ"), syscall.FILE_ATTRIBUTE_DIRECTORY|syscall.FILE_ATTRIBUTE_SYSTEM)
	mustSetAttr(t, filepath.Join(root, "隠し動画.mp4"), syscall.FILE_ATTRIBUTE_HIDDEN)

	_, entries, err := lib.List("")
	if err != nil {
		t.Fatalf("List() error = %v", err)
	}
	for _, e := range entries {
		if e.Name == "システムフォルダ" || e.Name == "隠し動画.mp4" {
			t.Errorf("entries contains %q", e.Name)
		}
	}
	for _, rel := range []string{"システムフォルダ", "隠し動画.mp4"} {
		if _, _, err := lib.Resolve(rel); !errors.Is(err, ErrNotFound) {
			t.Errorf("Resolve(%q) error = %v, want ErrNotFound", rel, err)
		}
	}
}

func TestWindowsAttr_ServesReadOnlyVideo(t *testing.T) {
	lib, root, _ := newTestLibrary(t)
	mustSetAttr(t, filepath.Join(root, "b.mp4"), syscall.FILE_ATTRIBUTE_READONLY)

	f, _, err := lib.OpenVideo("b.mp4")
	if err != nil {
		t.Fatalf("OpenVideo() error = %v", err)
	}
	f.Close()
}

func TestWindowsAttr_DoesNotFollowJunction(t *testing.T) {
	lib, root, outside := newTestLibrary(t)
	mustJunction(t, outside, filepath.Join(root, "junction"))

	if _, _, err := lib.Resolve("junction/secret.mp4"); !errors.Is(err, ErrNotFound) {
		t.Errorf("Resolve() error = %v, want ErrNotFound", err)
	}
	_, entries, err := lib.List("")
	if err != nil {
		t.Fatalf("List() error = %v", err)
	}
	for _, e := range entries {
		if e.Name == "junction" {
			t.Error("entries contains junction")
		}
	}
}
