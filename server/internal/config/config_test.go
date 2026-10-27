package config

import (
	"os"
	"path/filepath"
	"testing"
)

func writeConfig(t *testing.T, content string) string {
	t.Helper()
	path := filepath.Join(t.TempDir(), "config.json")
	if err := os.WriteFile(path, []byte(content), 0o644); err != nil {
		t.Fatal(err)
	}
	return path
}

func TestLoad_ReadsRootAndPort(t *testing.T) {
	path := writeConfig(t, `{"root": "E:\\Videos", "port": 8765}`)

	cfg, err := Load(path)
	if err != nil {
		t.Fatalf("Load() error = %v", err)
	}
	if cfg.Root != `E:\Videos` || cfg.Port != 8765 || cfg.FFmpeg != "" {
		t.Errorf("Load() = %+v", cfg)
	}
}

func TestLoad_ReadsOptionalFFmpegPath(t *testing.T) {
	path := writeConfig(t, `{"root": "E:\\Videos", "port": 8765, "ffmpeg": "C:\\tools\\ffmpeg.exe"}`)

	cfg, err := Load(path)
	if err != nil {
		t.Fatalf("Load() error = %v", err)
	}
	if cfg.FFmpeg != `C:\tools\ffmpeg.exe` {
		t.Errorf("FFmpeg = %q", cfg.FFmpeg)
	}
}

func TestLoad_RejectsInvalidConfig(t *testing.T) {
	tests := []struct {
		name    string
		content string
	}{
		{"root がない", `{"port": 8765}`},
		{"port がない", `{"root": "/videos"}`},
		{"port が範囲外", `{"root": "/videos", "port": 70000}`},
		{"未知の項目がある", `{"root": "/videos", "port": 8765, "prot": 1}`},
		{"JSON として壊れている", `{"root": `},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			if _, err := Load(writeConfig(t, tt.content)); err == nil {
				t.Error("Load() error = nil, want error")
			}
		})
	}
}

func TestLoad_FailsWhenFileIsMissing(t *testing.T) {
	if _, err := Load(filepath.Join(t.TempDir(), "missing.json")); err == nil {
		t.Error("Load() error = nil, want error")
	}
}
