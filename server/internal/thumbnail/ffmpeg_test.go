package thumbnail

import (
	"context"
	"image/jpeg"
	"os"
	"os/exec"
	"path/filepath"
	"strconv"
	"testing"
)

// requireFFmpeg は ffmpeg のパスを返す。ffmpeg がない環境ではテストを飛ばす。
func requireFFmpeg(t *testing.T) string {
	t.Helper()
	path, err := exec.LookPath("ffmpeg")
	if err != nil {
		t.Skip("ffmpeg がないため飛ばします")
	}
	return path
}

// makeVideo は ffmpeg のテストパターンから seconds 秒のダミー動画を作る。
func makeVideo(t *testing.T, ffmpeg string, seconds int) string {
	t.Helper()
	path := filepath.Join(t.TempDir(), "dummy.mp4")
	out, err := exec.Command(ffmpeg, "-hide_banner", "-loglevel", "error",
		"-f", "lavfi", "-i", "testsrc=size=640x360:rate=10:duration="+strconv.Itoa(seconds),
		"-pix_fmt", "yuv420p", "-y", path,
	).CombinedOutput()
	if err != nil {
		t.Fatalf("ダミー動画を作れません: %v: %s", err, out)
	}
	return path
}

func TestFFmpeg_WritesJPEGWithFixedWidth(t *testing.T) {
	ffmpeg := requireFFmpeg(t)
	for _, tt := range []struct {
		name    string
		seconds int
	}{
		{"10秒より長い動画", 12},
		{"10秒より短い動画", 3},
	} {
		t.Run(tt.name, func(t *testing.T) {
			video := makeVideo(t, ffmpeg, tt.seconds)
			out := filepath.Join(t.TempDir(), "thumb.jpg")

			if err := (FFmpeg{Path: ffmpeg}).Generate(context.Background(), video, out); err != nil {
				t.Fatalf("Generate() error = %v", err)
			}

			f, err := os.Open(out)
			if err != nil {
				t.Fatal(err)
			}
			defer f.Close()
			cfg, err := jpeg.DecodeConfig(f)
			if err != nil {
				t.Fatalf("not a JPEG: %v", err)
			}
			if cfg.Width != Width || cfg.Height != 180 {
				t.Errorf("size = %dx%d, want %dx180", cfg.Width, cfg.Height, Width)
			}
		})
	}
}

func TestFFmpeg_FailsForBrokenVideo(t *testing.T) {
	ffmpeg := requireFFmpeg(t)
	video := filepath.Join(t.TempDir(), "broken.mp4")
	if err := os.WriteFile(video, []byte("not a video"), 0o644); err != nil {
		t.Fatal(err)
	}

	err := (FFmpeg{Path: ffmpeg}).Generate(context.Background(), video, filepath.Join(t.TempDir(), "thumb.jpg"))
	if err == nil {
		t.Error("Generate() error = nil, want error")
	}
}

func TestFFmpeg_FailsWhenExecutableIsMissing(t *testing.T) {
	missing := filepath.Join(t.TempDir(), "no-such-ffmpeg")

	err := (FFmpeg{Path: missing}).Generate(context.Background(), "video.mp4", filepath.Join(t.TempDir(), "thumb.jpg"))
	if err == nil {
		t.Error("Generate() error = nil, want error")
	}
}
