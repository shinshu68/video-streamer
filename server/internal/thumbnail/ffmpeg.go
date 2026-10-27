package thumbnail

import (
	"bytes"
	"context"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strconv"
	"strings"
)

// Width はサムネイルの幅 (px)。
const Width = 320

// seekRatio はフレームを切り出す位置 (動画の長さに対する割合)。
const seekRatio = 0.1

// FFmpeg は ffprobe で動画の長さを調べ、ffmpeg でフレームを切り出す Generator。
type FFmpeg struct {
	// Path は ffmpeg の実行ファイルのパス。名前だけなら PATH から探す。
	Path string
}

// ProbePath は ffmpeg と同じフォルダにある ffprobe のパスを返す。名前だけなら PATH から探す。
func (f FFmpeg) ProbePath() string {
	dir, base := filepath.Split(f.Path)
	return dir + "ffprobe" + filepath.Ext(base)
}

// Generate は動画の長さの 10% の位置のフレームを out に書き出す。
// 長さが分からないときや、その位置で切り出せないときは、先頭のフレームで作り直す。
func (f FFmpeg) Generate(ctx context.Context, video, out string) error {
	if d, err := f.duration(ctx, video); err == nil {
		if err := f.run(ctx, video, out, d*seekRatio); err == nil && isNonEmptyFile(out) {
			return nil
		}
	}
	if err := f.run(ctx, video, out, 0); err != nil {
		return err
	}
	if !isNonEmptyFile(out) {
		return fmt.Errorf("ffmpeg がフレームを書き出しませんでした: %s", video)
	}
	return nil
}

// duration は動画の長さ (秒) を返す。
func (f FFmpeg) duration(ctx context.Context, video string) (float64, error) {
	cmd := exec.CommandContext(ctx, f.ProbePath(),
		"-v", "error",
		"-show_entries", "format=duration",
		"-of", "default=noprint_wrappers=1:nokey=1",
		video,
	)
	out, err := cmd.Output()
	if err != nil {
		return 0, fmt.Errorf("ffprobe の実行に失敗しました: %w", err)
	}
	d, err := strconv.ParseFloat(strings.TrimSpace(string(out)), 64)
	if err != nil || d <= 0 {
		return 0, fmt.Errorf("動画の長さが分かりません: %q", out)
	}
	return d, nil
}

func (f FFmpeg) run(ctx context.Context, video, out string, seek float64) error {
	cmd := exec.CommandContext(ctx, f.Path,
		"-hide_banner", "-loglevel", "error", "-nostdin",
		"-ss", strconv.FormatFloat(seek, 'f', 3, 64),
		"-i", video,
		"-frames:v", "1",
		// 高さは縦横比を保ち、JPEG のエンコーダーが受け付ける偶数にそろえる。
		// ffmpeg 9 の JPEG のエンコーダーは一般的な mp4 の limited range の色を受け付けないため、full range に変換する。
		"-vf", fmt.Sprintf("scale=%d:-2:out_range=full", Width),
		"-q:v", "4",
		"-y", out,
	)
	var stderr bytes.Buffer
	cmd.Stderr = &stderr
	if err := cmd.Run(); err != nil {
		return fmt.Errorf("ffmpeg の実行に失敗しました: %w: %s", err, strings.TrimSpace(stderr.String()))
	}
	return nil
}

func isNonEmptyFile(path string) bool {
	fi, err := os.Stat(path)
	return err == nil && fi.Size() > 0
}
