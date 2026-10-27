package thumbnail

import (
	"context"
	"errors"
	"os"
	"path/filepath"
	"sync"
	"sync/atomic"
	"testing"
	"time"
)

// fakeGenerator は動画のパスを中身にしたファイルを書き出し、呼ばれた回数を数える。
type fakeGenerator struct {
	calls   atomic.Int32
	running atomic.Int32
	maxRun  atomic.Int32
	delay   time.Duration
	err     error
}

func (g *fakeGenerator) Generate(ctx context.Context, video, out string) error {
	g.calls.Add(1)
	n := g.running.Add(1)
	defer g.running.Add(-1)
	for {
		m := g.maxRun.Load()
		if n <= m || g.maxRun.CompareAndSwap(m, n) {
			break
		}
	}
	time.Sleep(g.delay)
	if g.err != nil {
		return g.err
	}
	return os.WriteFile(out, []byte("jpeg:"+video), 0o644)
}

// fakeVideo はテスト用のダミーの動画ファイルを作り、その情報を返す。
func fakeVideo(t *testing.T, dir, name string) (string, os.FileInfo) {
	t.Helper()
	path := filepath.Join(dir, name)
	if err := os.WriteFile(path, []byte("dummy video "+name), 0o644); err != nil {
		t.Fatal(err)
	}
	fi, err := os.Stat(path)
	if err != nil {
		t.Fatal(err)
	}
	return path, fi
}

func TestCache_GeneratesOnceAndReusesFile(t *testing.T) {
	gen := &fakeGenerator{}
	cache := NewCache(filepath.Join(t.TempDir(), "cache"), gen, 2)
	video, fi := fakeVideo(t, t.TempDir(), "a.mp4")

	first, err := cache.Path(context.Background(), video, "a.mp4", fi)
	if err != nil {
		t.Fatalf("Path() error = %v", err)
	}
	second, err := cache.Path(context.Background(), video, "a.mp4", fi)
	if err != nil {
		t.Fatalf("Path() error = %v", err)
	}

	if first != second {
		t.Errorf("paths differ: %q, %q", first, second)
	}
	if got := gen.calls.Load(); got != 1 {
		t.Errorf("Generate called %d times, want 1", got)
	}
	if data, _ := os.ReadFile(first); string(data) != "jpeg:"+video {
		t.Errorf("content = %q", data)
	}
}

func TestCache_RegeneratesWhenVideoChanges(t *testing.T) {
	gen := &fakeGenerator{}
	cache := NewCache(t.TempDir(), gen, 2)
	dir := t.TempDir()
	video, before := fakeVideo(t, dir, "a.mp4")
	if err := os.Chtimes(video, time.Now(), before.ModTime().Add(time.Hour)); err != nil {
		t.Fatal(err)
	}
	after, err := os.Stat(video)
	if err != nil {
		t.Fatal(err)
	}

	p1, _ := cache.Path(context.Background(), video, "a.mp4", before)
	p2, _ := cache.Path(context.Background(), video, "a.mp4", after)

	if p1 == p2 {
		t.Error("same cache path for changed video")
	}
	if got := gen.calls.Load(); got != 2 {
		t.Errorf("Generate called %d times, want 2", got)
	}
}

func TestCache_SharesGenerationAmongConcurrentRequests(t *testing.T) {
	gen := &fakeGenerator{delay: 50 * time.Millisecond}
	cache := NewCache(t.TempDir(), gen, 2)
	video, fi := fakeVideo(t, t.TempDir(), "a.mp4")

	var wg sync.WaitGroup
	for range 10 {
		wg.Go(func() {
			if _, err := cache.Path(context.Background(), video, "a.mp4", fi); err != nil {
				t.Errorf("Path() error = %v", err)
			}
		})
	}
	wg.Wait()

	if got := gen.calls.Load(); got != 1 {
		t.Errorf("Generate called %d times, want 1", got)
	}
}

func TestCache_LimitsConcurrentGeneration(t *testing.T) {
	gen := &fakeGenerator{delay: 50 * time.Millisecond}
	cache := NewCache(t.TempDir(), gen, 2)
	dir := t.TempDir()

	var wg sync.WaitGroup
	for _, name := range []string{"a.mp4", "b.mp4", "c.mp4", "d.mp4", "e.mp4"} {
		video, fi := fakeVideo(t, dir, name)
		wg.Go(func() {
			if _, err := cache.Path(context.Background(), video, name, fi); err != nil {
				t.Errorf("Path() error = %v", err)
			}
		})
	}
	wg.Wait()

	if got := gen.maxRun.Load(); got > 2 {
		t.Errorf("max concurrent generation = %d, want <= 2", got)
	}
	if got := gen.calls.Load(); got != 5 {
		t.Errorf("Generate called %d times, want 5", got)
	}
}

func TestCache_ReturnsErrorAndRetriesNextTime(t *testing.T) {
	gen := &fakeGenerator{err: errors.New("broken video")}
	dir := t.TempDir()
	cache := NewCache(dir, gen, 2)
	video, fi := fakeVideo(t, t.TempDir(), "a.mp4")

	if _, err := cache.Path(context.Background(), video, "a.mp4", fi); err == nil {
		t.Fatal("Path() error = nil, want error")
	}
	if entries, _ := os.ReadDir(dir); len(entries) != 0 {
		t.Errorf("cache dir has leftover files: %v", entries)
	}

	gen.err = nil
	if _, err := cache.Path(context.Background(), video, "a.mp4", fi); err != nil {
		t.Fatalf("Path() error = %v", err)
	}
	if got := gen.calls.Load(); got != 2 {
		t.Errorf("Generate called %d times, want 2", got)
	}
}

func TestCache_ReturnsWhenRequestIsCanceled(t *testing.T) {
	gen := &fakeGenerator{delay: time.Second}
	cache := NewCache(t.TempDir(), gen, 2)
	video, fi := fakeVideo(t, t.TempDir(), "a.mp4")
	ctx, cancel := context.WithTimeout(context.Background(), 20*time.Millisecond)
	defer cancel()

	if _, err := cache.Path(ctx, video, "a.mp4", fi); !errors.Is(err, context.DeadlineExceeded) {
		t.Errorf("Path() error = %v, want DeadlineExceeded", err)
	}
}
