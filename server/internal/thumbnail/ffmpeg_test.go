package thumbnail

import (
	"bytes"
	"context"
	"image/jpeg"
	"os"
	"os/exec"
	"path/filepath"
	"strconv"
	"testing"
)

// requireFFmpeg は ffmpeg を返す。ffmpeg か ffprobe がない環境ではテストを飛ばす。
func requireFFmpeg(t *testing.T) FFmpeg {
	t.Helper()
	path, err := exec.LookPath("ffmpeg")
	if err != nil {
		t.Skip("ffmpeg がないため飛ばします")
	}
	f := FFmpeg{Path: path}
	if _, err := exec.LookPath(f.ProbePath()); err != nil {
		t.Skip("ffprobe がないため飛ばします")
	}
	return f
}

// makeVideo は ffmpeg のテストパターンから seconds 秒のダミー動画を作る。
func makeVideo(t *testing.T, f FFmpeg, seconds int) string {
	t.Helper()
	path := filepath.Join(t.TempDir(), "dummy.mp4")
	out, err := exec.Command(f.Path, "-hide_banner", "-loglevel", "error",
		"-f", "lavfi", "-i", "testsrc=size=640x360:rate=10:duration="+strconv.Itoa(seconds),
		"-pix_fmt", "yuv420p", "-y", path,
	).CombinedOutput()
	if err != nil {
		t.Fatalf("ダミー動画を作れません: %v: %s", err, out)
	}
	return path
}

// frameAt は seek 秒の位置のフレームを Generate と同じ条件で切り出し、その中身を返す。
func frameAt(t *testing.T, f FFmpeg, video string, seek float64) []byte {
	t.Helper()
	out := filepath.Join(t.TempDir(), "frame.jpg")
	if err := f.run(context.Background(), video, out, seek); err != nil {
		t.Fatal(err)
	}
	data, err := os.ReadFile(out)
	if err != nil {
		t.Fatal(err)
	}
	return data
}

func generate(t *testing.T, f FFmpeg, video string) []byte {
	t.Helper()
	out := filepath.Join(t.TempDir(), "thumb.jpg")
	if err := f.Generate(context.Background(), video, out); err != nil {
		t.Fatalf("Generate() error = %v", err)
	}
	data, err := os.ReadFile(out)
	if err != nil {
		t.Fatal(err)
	}
	return data
}

func TestFFmpeg_ProbePathIsNextToFFmpeg(t *testing.T) {
	for _, tt := range []struct {
		ffmpeg string
		want   string
	}{
		{"ffmpeg", "ffprobe"},
		{"ffmpeg.exe", "ffprobe.exe"},
		{filepath.Join("tools", "bin", "ffmpeg.exe"), filepath.Join("tools", "bin", "ffprobe.exe")},
	} {
		if got := (FFmpeg{Path: tt.ffmpeg}).ProbePath(); got != tt.want {
			t.Errorf("ProbePath() for %q = %q, want %q", tt.ffmpeg, got, tt.want)
		}
	}
}

func TestFFmpeg_WritesJPEGWithFixedWidth(t *testing.T) {
	f := requireFFmpeg(t)
	video := makeVideo(t, f, 3)

	cfg, err := jpeg.DecodeConfig(bytes.NewReader(generate(t, f, video)))
	if err != nil {
		t.Fatalf("not a JPEG: %v", err)
	}
	if cfg.Width != Width || cfg.Height != 180 {
		t.Errorf("size = %dx%d, want %dx180", cfg.Width, cfg.Height, Width)
	}
}

func TestFFmpeg_UsesFrameAtTenPercentOfDuration(t *testing.T) {
	f := requireFFmpeg(t)
	video := makeVideo(t, f, 20)

	got := generate(t, f, video)

	if !bytes.Equal(got, frameAt(t, f, video, 2)) {
		t.Error("thumbnail is not the frame at 2s (10% of 20s)")
	}
	if bytes.Equal(got, frameAt(t, f, video, 0)) {
		t.Error("thumbnail is the first frame")
	}
}

func TestFFmpeg_UsesFirstFrameWhenFFprobeIsMissing(t *testing.T) {
	f := requireFFmpeg(t)
	video := makeVideo(t, f, 20)
	// ffprobe のないフォルダから ffmpeg を呼ぶため、リンクを作る。
	link := filepath.Join(t.TempDir(), "ffmpeg"+filepath.Ext(f.Path))
	if err := os.Symlink(f.Path, link); err != nil {
		t.Skipf("シンボリックリンクを作れない環境です: %v", err)
	}
	noProbe := FFmpeg{Path: link}

	if !bytes.Equal(generate(t, noProbe, video), frameAt(t, f, video, 0)) {
		t.Error("thumbnail is not the first frame")
	}
}

func TestFFmpeg_FailsForBrokenVideo(t *testing.T) {
	f := requireFFmpeg(t)
	video := filepath.Join(t.TempDir(), "broken.mp4")
	if err := os.WriteFile(video, []byte("not a video"), 0o644); err != nil {
		t.Fatal(err)
	}

	if err := f.Generate(context.Background(), video, filepath.Join(t.TempDir(), "thumb.jpg")); err == nil {
		t.Error("Generate() error = nil, want error")
	}
}

func TestFFmpeg_FailsWhenExecutableIsMissing(t *testing.T) {
	missing := FFmpeg{Path: filepath.Join(t.TempDir(), "no-such-ffmpeg")}

	if err := missing.Generate(context.Background(), "video.mp4", filepath.Join(t.TempDir(), "thumb.jpg")); err == nil {
		t.Error("Generate() error = nil, want error")
	}
}
