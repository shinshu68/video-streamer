package httpapi

import (
	"context"
	"encoding/json"
	"errors"
	"io"
	"net/http"
	"net/http/httptest"
	"net/url"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/shinshu68/video-streamer/server/internal/index"
	"github.com/shinshu68/video-streamer/server/internal/library"
	"github.com/shinshu68/video-streamer/server/internal/thumbnail"
)

const dummyVideo = "0123456789abcdef"

const dummyJPEG = "dummy jpeg"

// stubGenerator は ffmpeg の代わりに、決まった中身のサムネイルを書き出す。err があれば失敗する。
type stubGenerator struct {
	err error
}

func (g stubGenerator) Generate(_ context.Context, _, out string) error {
	if g.err != nil {
		return g.err
	}
	return os.WriteFile(out, []byte(dummyJPEG), 0o644)
}

// newTestServer は次の構成の公開フォルダを持つテスト用サーバーを起動する。
//
//	root/
//	├── フォルダA/
//	│   └── 動画C.mp4
//	└── memo.txt
func newTestServer(t *testing.T) *httptest.Server {
	t.Helper()
	return newTestServerWithGenerator(t, stubGenerator{})
}

func newTestServerWithGenerator(t *testing.T, gen thumbnail.Generator) *httptest.Server {
	t.Helper()
	root := t.TempDir()
	if err := os.Mkdir(filepath.Join(root, "フォルダA"), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(root, "フォルダA", "動画C.mp4"), []byte(dummyVideo), 0o644); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(root, "memo.txt"), []byte("memo"), 0o644); err != nil {
		t.Fatal(err)
	}

	lib, err := library.New(root)
	if err != nil {
		t.Fatal(err)
	}
	thumbs := thumbnail.NewCache(t.TempDir(), gen, 2)
	ids := index.Open(lib, filepath.Join(t.TempDir(), "index.json"))
	srv := httptest.NewServer(NewHandler(lib, thumbs, ids))
	t.Cleanup(srv.Close)
	return srv
}

func get(t *testing.T, rawURL string, header map[string]string) *http.Response {
	t.Helper()
	req, err := http.NewRequest(http.MethodGet, rawURL, nil)
	if err != nil {
		t.Fatal(err)
	}
	for k, v := range header {
		req.Header.Set(k, v)
	}
	res, err := http.DefaultClient.Do(req)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { res.Body.Close() })
	return res
}

func TestList_ReturnsEntriesAsJSON(t *testing.T) {
	srv := newTestServer(t)

	res := get(t, srv.URL+"/api/list?path="+url.QueryEscape("フォルダA"), nil)

	if res.StatusCode != http.StatusOK {
		t.Fatalf("status = %d, want 200", res.StatusCode)
	}
	if ct := res.Header.Get("Content-Type"); !strings.HasPrefix(ct, "application/json") {
		t.Errorf("Content-Type = %q", ct)
	}
	var body struct {
		Path    string           `json:"path"`
		Entries []map[string]any `json:"entries"`
	}
	if err := json.NewDecoder(res.Body).Decode(&body); err != nil {
		t.Fatal(err)
	}
	if body.Path != "フォルダA" || len(body.Entries) != 1 {
		t.Fatalf("body = %+v", body)
	}
	e := body.Entries[0]
	if e["type"] != "video" || e["name"] != "動画C.mp4" || e["path"] != "フォルダA/動画C.mp4" ||
		e["size"] != float64(len(dummyVideo)) || e["modified"] == nil {
		t.Errorf("entry = %v", e)
	}
}

func TestList_ReturnsRootWhenPathIsOmitted(t *testing.T) {
	srv := newTestServer(t)

	res := get(t, srv.URL+"/api/list", nil)

	var body struct {
		Path    string           `json:"path"`
		Entries []map[string]any `json:"entries"`
	}
	if err := json.NewDecoder(res.Body).Decode(&body); err != nil {
		t.Fatal(err)
	}
	if body.Path != "" || len(body.Entries) != 1 || body.Entries[0]["type"] != "dir" {
		t.Errorf("body = %+v", body)
	}
	if _, ok := body.Entries[0]["size"]; ok {
		t.Errorf("dir entry has size: %v", body.Entries[0])
	}
}

func TestList_ReturnsErrorJSON(t *testing.T) {
	srv := newTestServer(t)
	tests := []struct {
		path       string
		wantStatus int
	}{
		{"../outside", http.StatusForbidden},
		{"missing", http.StatusNotFound},
	}
	for _, tt := range tests {
		t.Run(tt.path, func(t *testing.T) {
			res := get(t, srv.URL+"/api/list?path="+url.QueryEscape(tt.path), nil)

			if res.StatusCode != tt.wantStatus {
				t.Errorf("status = %d, want %d", res.StatusCode, tt.wantStatus)
			}
			var body map[string]string
			if err := json.NewDecoder(res.Body).Decode(&body); err != nil {
				t.Fatal(err)
			}
			if body["error"] == "" {
				t.Errorf("body = %v, want error message", body)
			}
		})
	}
}

func mediaURL(srv *httptest.Server, rel string) string {
	return srv.URL + "/media/" + (&url.URL{Path: rel}).EscapedPath()
}

func TestMedia_ServesWholeVideo(t *testing.T) {
	srv := newTestServer(t)

	res := get(t, mediaURL(srv, "フォルダA/動画C.mp4"), nil)

	if res.StatusCode != http.StatusOK {
		t.Fatalf("status = %d, want 200", res.StatusCode)
	}
	if ct := res.Header.Get("Content-Type"); ct != "video/mp4" {
		t.Errorf("Content-Type = %q, want video/mp4", ct)
	}
	if res.Header.Get("Accept-Ranges") != "bytes" {
		t.Errorf("Accept-Ranges = %q, want bytes", res.Header.Get("Accept-Ranges"))
	}
	if body, _ := io.ReadAll(res.Body); string(body) != dummyVideo {
		t.Errorf("body = %q", body)
	}
}

func TestMedia_ServesPartialContentForRange(t *testing.T) {
	srv := newTestServer(t)

	res := get(t, mediaURL(srv, "フォルダA/動画C.mp4"), map[string]string{"Range": "bytes=4-7"})

	if res.StatusCode != http.StatusPartialContent {
		t.Fatalf("status = %d, want 206", res.StatusCode)
	}
	if cr := res.Header.Get("Content-Range"); cr != "bytes 4-7/16" {
		t.Errorf("Content-Range = %q", cr)
	}
	if body, _ := io.ReadAll(res.Body); string(body) != "4567" {
		t.Errorf("body = %q, want 4567", body)
	}
}

func TestMedia_ReturnsNotFoundForNonVideo(t *testing.T) {
	srv := newTestServer(t)
	for _, rel := range []string{"memo.txt", "フォルダA", "missing.mp4"} {
		t.Run(rel, func(t *testing.T) {
			res := get(t, mediaURL(srv, rel), nil)
			if res.StatusCode != http.StatusNotFound {
				t.Errorf("status = %d, want 404", res.StatusCode)
			}
		})
	}
}

func TestMedia_RejectsEncodedTraversal(t *testing.T) {
	srv := newTestServer(t)

	res := get(t, srv.URL+"/media/%2E%2E%2Foutside.mp4", nil)

	if res.StatusCode != http.StatusForbidden {
		t.Errorf("status = %d, want 403", res.StatusCode)
	}
}

func TestThumbnail_ReturnsJPEG(t *testing.T) {
	srv := newTestServer(t)

	res := get(t, srv.URL+"/api/thumbnail?path="+url.QueryEscape("フォルダA/動画C.mp4"), nil)

	if res.StatusCode != http.StatusOK {
		t.Fatalf("status = %d, want 200", res.StatusCode)
	}
	if ct := res.Header.Get("Content-Type"); ct != "image/jpeg" {
		t.Errorf("Content-Type = %q, want image/jpeg", ct)
	}
	if body, _ := io.ReadAll(res.Body); string(body) != dummyJPEG {
		t.Errorf("body = %q", body)
	}
}

func TestThumbnail_ReturnsErrorJSON(t *testing.T) {
	tests := []struct {
		name       string
		gen        thumbnail.Generator
		path       string
		wantStatus int
	}{
		{"動画でない", stubGenerator{}, "memo.txt", http.StatusNotFound},
		{"存在しない", stubGenerator{}, "missing.mp4", http.StatusNotFound},
		{"公開フォルダの外", stubGenerator{}, "../outside.mp4", http.StatusForbidden},
		{"生成に失敗", stubGenerator{err: errors.New("ffmpeg not found")}, "フォルダA/動画C.mp4", http.StatusInternalServerError},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			srv := newTestServerWithGenerator(t, tt.gen)

			res := get(t, srv.URL+"/api/thumbnail?path="+url.QueryEscape(tt.path), nil)

			if res.StatusCode != tt.wantStatus {
				t.Errorf("status = %d, want %d", res.StatusCode, tt.wantStatus)
			}
			var body map[string]string
			if err := json.NewDecoder(res.Body).Decode(&body); err != nil {
				t.Fatal(err)
			}
			if body["error"] == "" {
				t.Errorf("body = %v, want error message", body)
			}
		})
	}
}

// listedVideoID は フォルダA の動画の識別子を一覧から取り出す。
func listedVideoID(t *testing.T, srv *httptest.Server) string {
	t.Helper()
	res := get(t, srv.URL+"/api/list?path="+url.QueryEscape("フォルダA"), nil)
	var body struct {
		Entries []struct {
			ID string `json:"id"`
		} `json:"entries"`
	}
	if err := json.NewDecoder(res.Body).Decode(&body); err != nil {
		t.Fatal(err)
	}
	if len(body.Entries) != 1 || len(body.Entries[0].ID) != 64 {
		t.Fatalf("body = %+v", body)
	}
	return body.Entries[0].ID
}

func postVideos(t *testing.T, srv *httptest.Server, reqBody string) *http.Response {
	t.Helper()
	res, err := http.Post(srv.URL+"/api/videos", "application/json", strings.NewReader(reqBody))
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { res.Body.Close() })
	return res
}

func TestVideos_ReturnsFoundVideosAsJSON(t *testing.T) {
	srv := newTestServer(t)
	id := listedVideoID(t, srv)

	res := postVideos(t, srv, `{"ids":["unknown","`+id+`"]}`)

	if res.StatusCode != http.StatusOK {
		t.Fatalf("status = %d, want 200", res.StatusCode)
	}
	var body struct {
		Videos []map[string]any `json:"videos"`
	}
	if err := json.NewDecoder(res.Body).Decode(&body); err != nil {
		t.Fatal(err)
	}
	if len(body.Videos) != 1 {
		t.Fatalf("videos = %+v", body.Videos)
	}
	v := body.Videos[0]
	if v["type"] != "video" || v["id"] != id || v["name"] != "動画C.mp4" || v["path"] != "フォルダA/動画C.mp4" ||
		v["size"] != float64(len(dummyVideo)) || v["modified"] == nil {
		t.Errorf("video = %+v", v)
	}
}

func TestVideos_EmptyIDsReturnsEmptyArray(t *testing.T) {
	srv := newTestServer(t)

	res := postVideos(t, srv, `{"ids":[]}`)

	got, err := io.ReadAll(res.Body)
	if err != nil {
		t.Fatal(err)
	}
	if res.StatusCode != http.StatusOK || strings.TrimSpace(string(got)) != `{"videos":[]}` {
		t.Errorf("status = %d, body = %s", res.StatusCode, got)
	}
}

func TestVideos_InvalidJSONReturnsBadRequest(t *testing.T) {
	srv := newTestServer(t)

	res := postVideos(t, srv, `{`)

	if res.StatusCode != http.StatusBadRequest {
		t.Errorf("status = %d, want 400", res.StatusCode)
	}
}
