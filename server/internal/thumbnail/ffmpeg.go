package thumbnail

import (
	"bytes"
	"context"
	"fmt"
	"os"
	"os/exec"
	"strings"
)

// Width はサムネイルの幅 (px)。
const Width = 320

// seekSeconds はフレームを切り出す位置 (先頭からの秒数)。
const seekSeconds = 10

// FFmpeg は ffmpeg で動画からフレームを切り出す Generator。
type FFmpeg struct {
	// Path は ffmpeg の実行ファイルのパス。名前だけなら PATH から探す。
	Path string
}

// Generate は先頭から10秒の位置のフレームを out に書き出す。
// 10秒より短い動画では切り出せない (ffmpeg はエラーで終わるか、何も書き出さない) ため、先頭のフレームで作り直す。
func (f FFmpeg) Generate(ctx context.Context, video, out string) error {
	if err := f.run(ctx, video, out, seekSeconds); err == nil && isNonEmptyFile(out) {
		return nil
	}
	if err := f.run(ctx, video, out, 0); err != nil {
		return err
	}
	if !isNonEmptyFile(out) {
		return fmt.Errorf("ffmpeg がフレームを書き出しませんでした: %s", video)
	}
	return nil
}

func (f FFmpeg) run(ctx context.Context, video, out string, seek int) error {
	cmd := exec.CommandContext(ctx, f.Path,
		"-hide_banner", "-loglevel", "error", "-nostdin",
		"-ss", fmt.Sprint(seek),
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
