// video-streamer-server は公開フォルダの動画を LAN 内に配信する HTTP サーバー。
package main

import (
	"flag"
	"fmt"
	"log"
	"net/http"
	"os"
	"os/exec"
	"path/filepath"
	"time"

	"github.com/shinshu68/video-streamer/server/internal/config"
	"github.com/shinshu68/video-streamer/server/internal/httpapi"
	"github.com/shinshu68/video-streamer/server/internal/library"
	"github.com/shinshu68/video-streamer/server/internal/thumbnail"
)

func main() {
	configPath := flag.String("config", defaultConfigPath(), "設定ファイルのパス")
	flag.Parse()

	cfg, err := config.Load(*configPath)
	if err != nil {
		log.Fatal(err)
	}
	lib, err := library.New(cfg.Root, cfg.Cache)
	if err != nil {
		log.Fatal(err)
	}

	ffmpeg := cfg.FFmpeg
	if ffmpeg == "" {
		ffmpeg = "ffmpeg"
	}
	gen := thumbnail.FFmpeg{Path: ffmpeg}
	if _, err := exec.LookPath(gen.Path); err != nil {
		log.Printf("ffmpeg が見つからないため、サムネイルは生成できません: %v", err)
	}
	if _, err := exec.LookPath(gen.ProbePath()); err != nil {
		log.Printf("ffprobe が見つからないため、サムネイルは先頭のフレームで作ります: %v", err)
	}
	thumbs := thumbnail.NewCache(
		filepath.Join(cfg.Cache, "thumbnails"),
		gen,
		thumbnailConcurrency,
	)

	srv := &http.Server{
		Addr:              fmt.Sprintf(":%d", cfg.Port),
		Handler:           httpapi.NewHandler(lib, thumbs),
		ReadHeaderTimeout: 10 * time.Second,
		// 長い動画の配信が途中で切れないよう、WriteTimeout は設定しない。
	}
	log.Printf("公開フォルダ %s を :%d で配信します", cfg.Root, cfg.Port)
	log.Fatal(srv.ListenAndServe())
}

// thumbnailConcurrency は同時に動かす ffmpeg の数。HDD のシークが重ならないよう小さくする。
const thumbnailConcurrency = 2

// defaultConfigPath は exe と同じフォルダの config.json を返す。
func defaultConfigPath() string {
	return filepath.Join(exeDir(), "config.json")
}

// exeDir は exe のあるフォルダを返す。分からない場合はカレントディレクトリ。
func exeDir() string {
	exe, err := os.Executable()
	if err != nil {
		return "."
	}
	return filepath.Dir(exe)
}
