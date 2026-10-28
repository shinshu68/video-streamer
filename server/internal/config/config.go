// Package config はサーバーの設定ファイル (JSON) を読み込む。
package config

import (
	"bytes"
	"encoding/json"
	"errors"
	"fmt"
	"os"
)

// Config は設定ファイルの内容。項目は docs/deployment.md の「設定ファイル」に合わせる。
type Config struct {
	// Root は公開フォルダのパス。
	Root string `json:"root"`
	// Port は待ち受けるポート番号。
	Port int `json:"port"`
	// Cache はサムネイルなどのキャッシュを置くフォルダのパス。
	Cache string `json:"cache"`
	// FFmpeg は ffmpeg の実行ファイルのパス。省略時は空文字列。
	FFmpeg string `json:"ffmpeg"`
}

// Load は path の設定ファイルを読み込み、必須項目がそろっているかを検証する。
func Load(path string) (Config, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		return Config{}, fmt.Errorf("設定ファイルを読めません: %w", err)
	}

	dec := json.NewDecoder(bytes.NewReader(data))
	dec.DisallowUnknownFields()
	var cfg Config
	if err := dec.Decode(&cfg); err != nil {
		return Config{}, fmt.Errorf("設定ファイルの形式が不正です (%s): %w", path, err)
	}

	if cfg.Root == "" {
		return Config{}, errors.New("設定ファイルに root がありません")
	}
	if cfg.Port < 1 || cfg.Port > 65535 {
		return Config{}, fmt.Errorf("設定ファイルの port が不正です: %d", cfg.Port)
	}
	if cfg.Cache == "" {
		return Config{}, errors.New("設定ファイルに cache がありません")
	}
	return cfg, nil
}
