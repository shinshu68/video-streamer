// video-streamer-server は公開フォルダの動画を LAN 内に配信する HTTP サーバー。
package main

import (
	"flag"
	"fmt"
	"log"
	"net/http"
	"os"
	"path/filepath"
	"time"

	"github.com/shinshu68/video-streamer/server/internal/config"
	"github.com/shinshu68/video-streamer/server/internal/httpapi"
	"github.com/shinshu68/video-streamer/server/internal/library"
)

func main() {
	configPath := flag.String("config", defaultConfigPath(), "設定ファイルのパス")
	flag.Parse()

	cfg, err := config.Load(*configPath)
	if err != nil {
		log.Fatal(err)
	}
	lib, err := library.New(cfg.Root)
	if err != nil {
		log.Fatal(err)
	}

	srv := &http.Server{
		Addr:              fmt.Sprintf(":%d", cfg.Port),
		Handler:           httpapi.NewHandler(lib),
		ReadHeaderTimeout: 10 * time.Second,
		// 長い動画の配信が途中で切れないよう、WriteTimeout は設定しない。
	}
	log.Printf("公開フォルダ %s を :%d で配信します", cfg.Root, cfg.Port)
	log.Fatal(srv.ListenAndServe())
}

// defaultConfigPath は exe と同じフォルダの config.json を返す。
func defaultConfigPath() string {
	exe, err := os.Executable()
	if err != nil {
		return "config.json"
	}
	return filepath.Join(filepath.Dir(exe), "config.json")
}
