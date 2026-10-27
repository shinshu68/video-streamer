// Package httpapi は docs/api.md のエンドポイントを提供する HTTP ハンドラー。
package httpapi

import (
	"encoding/json"
	"errors"
	"log"
	"net/http"
	"os"

	"github.com/shinshu68/video-streamer/server/internal/library"
	"github.com/shinshu68/video-streamer/server/internal/thumbnail"
)

// NewHandler は lib を公開する HTTP ハンドラーを返す。サムネイルは thumbs で生成する。
func NewHandler(lib *library.Library, thumbs *thumbnail.Cache) http.Handler {
	mux := http.NewServeMux()
	mux.HandleFunc("GET /api/list", func(w http.ResponseWriter, r *http.Request) {
		handleList(w, r, lib)
	})
	mux.HandleFunc("GET /api/thumbnail", func(w http.ResponseWriter, r *http.Request) {
		handleThumbnail(w, r, lib, thumbs)
	})
	mux.HandleFunc("GET /media/{path...}", func(w http.ResponseWriter, r *http.Request) {
		handleMedia(w, r, lib)
	})
	return mux
}

type listResponse struct {
	Path    string          `json:"path"`
	Entries []library.Entry `json:"entries"`
}

type errorResponse struct {
	Error string `json:"error"`
}

func handleList(w http.ResponseWriter, r *http.Request, lib *library.Library) {
	clean, entries, err := lib.List(r.URL.Query().Get("path"))
	if err != nil {
		status := statusFor(err)
		writeJSON(w, status, errorResponse{Error: http.StatusText(status)})
		return
	}
	writeJSON(w, http.StatusOK, listResponse{Path: clean, Entries: entries})
}

func handleThumbnail(w http.ResponseWriter, r *http.Request, lib *library.Library, thumbs *thumbnail.Cache) {
	video, clean, fi, err := lib.Video(r.URL.Query().Get("path"))
	if err != nil {
		status := statusFor(err)
		writeJSON(w, status, errorResponse{Error: http.StatusText(status)})
		return
	}
	path, err := thumbs.Path(r.Context(), video, clean, fi)
	if err != nil {
		if r.Context().Err() != nil {
			return
		}
		log.Printf("サムネイルを生成できません (%s): %v", clean, err)
		writeJSON(w, http.StatusInternalServerError, errorResponse{Error: http.StatusText(http.StatusInternalServerError)})
		return
	}
	f, err := os.Open(path)
	if err != nil {
		log.Printf("サムネイルを開けません (%s): %v", clean, err)
		writeJSON(w, http.StatusInternalServerError, errorResponse{Error: http.StatusText(http.StatusInternalServerError)})
		return
	}
	defer f.Close()

	w.Header().Set("Content-Type", "image/jpeg")
	http.ServeContent(w, r, "", fi.ModTime(), f)
}

func handleMedia(w http.ResponseWriter, r *http.Request, lib *library.Library) {
	f, fi, err := lib.OpenVideo(r.PathValue("path"))
	if err != nil {
		status := statusFor(err)
		http.Error(w, http.StatusText(status), status)
		return
	}
	defer f.Close()

	w.Header().Set("Content-Type", "video/mp4")
	http.ServeContent(w, r, fi.Name(), fi.ModTime(), f)
}

func statusFor(err error) int {
	switch {
	case errors.Is(err, library.ErrForbidden):
		return http.StatusForbidden
	case errors.Is(err, library.ErrNotFound):
		return http.StatusNotFound
	default:
		log.Printf("内部エラー: %v", err)
		return http.StatusInternalServerError
	}
}

func writeJSON(w http.ResponseWriter, status int, body any) {
	w.Header().Set("Content-Type", "application/json; charset=utf-8")
	w.WriteHeader(status)
	if err := json.NewEncoder(w).Encode(body); err != nil {
		log.Printf("レスポンスを書き込めません: %v", err)
	}
}
