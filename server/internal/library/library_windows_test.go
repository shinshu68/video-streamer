package library

import (
	"os"
	"os/exec"
	"path/filepath"
	"testing"
)

func TestVideos_ReportsIncompleteWhenSubfolderCannotBeRead(t *testing.T) {
	lib, root, _ := newTestLibrary(t)
	dir := filepath.Join(root, "読めない")
	if err := os.Mkdir(dir, 0o755); err != nil {
		t.Fatal(err)
	}
	const everyone = "*S-1-1-0"
	if out, err := exec.Command("icacls", dir, "/deny", everyone+":(RX)").CombinedOutput(); err != nil {
		t.Fatalf("icacls: %v: %s", err, out)
	}
	t.Cleanup(func() {
		exec.Command("icacls", dir, "/remove:d", everyone).Run()
	})

	videos, complete, err := lib.Videos()
	if err != nil {
		t.Fatal(err)
	}
	if complete {
		t.Error("complete = true, want false")
	}
	if len(videos) == 0 {
		t.Error("読めるフォルダの動画を返しません")
	}
}
