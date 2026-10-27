// Package thumbnail は動画のサムネイルを生成し、ファイルにキャッシュする。
//
// 返す画像の形は docs/api.md の「サムネイルの取得」に合わせる。
package thumbnail

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"fmt"
	"io/fs"
	"os"
	"path/filepath"
	"strconv"
	"sync"
	"time"
)

// Generator は動画 video から JPEG を生成し、out に書き出す。
type Generator interface {
	Generate(ctx context.Context, video, out string) error
}

// generateTimeout は1本の生成にかける時間の上限。HDD のスリープからの復帰を見込んだ長さにする。
const generateTimeout = 60 * time.Second

// Cache はサムネイルを dir に保存し、同じ動画の2回目以降はそれを返す。
type Cache struct {
	dir string
	gen Generator
	sem chan struct{}

	mu       sync.Mutex
	inflight map[string]*call
}

type call struct {
	done chan struct{}
	err  error
}

// NewCache は同時に concurrency 個まで gen を動かす Cache を作る。
func NewCache(dir string, gen Generator, concurrency int) *Cache {
	return &Cache{
		dir:      dir,
		gen:      gen,
		sem:      make(chan struct{}, concurrency),
		inflight: map[string]*call{},
	}
}

// Path は動画のサムネイルのパスを返す。キャッシュになければ生成する。
// rel は公開フォルダからの相対パス、video は実際のパス、fi は動画のファイルの情報。
func (c *Cache) Path(ctx context.Context, video, rel string, fi fs.FileInfo) (string, error) {
	key := cacheKey(rel, fi)
	path := filepath.Join(c.dir, key+".jpg")
	if _, err := os.Stat(path); err == nil {
		return path, nil
	}

	c.mu.Lock()
	cl, ok := c.inflight[key]
	if !ok {
		cl = &call{done: make(chan struct{})}
		c.inflight[key] = cl
		// 要求したクライアントが切断しても、同じ動画を待つ他の要求のために生成は続ける。
		go c.generate(context.WithoutCancel(ctx), video, path, key, cl)
	}
	c.mu.Unlock()

	select {
	case <-cl.done:
		if cl.err != nil {
			return "", cl.err
		}
		return path, nil
	case <-ctx.Done():
		return "", ctx.Err()
	}
}

func (c *Cache) generate(ctx context.Context, video, path, key string, cl *call) {
	cl.err = c.generateFile(ctx, video, path)

	c.mu.Lock()
	delete(c.inflight, key)
	c.mu.Unlock()
	close(cl.done)
}

func (c *Cache) generateFile(ctx context.Context, video, path string) error {
	c.sem <- struct{}{}
	defer func() { <-c.sem }()

	if err := os.MkdirAll(c.dir, 0o755); err != nil {
		return fmt.Errorf("キャッシュのフォルダを作れません: %w", err)
	}
	tmp, err := os.CreateTemp(c.dir, "tmp-*.jpg")
	if err != nil {
		return fmt.Errorf("一時ファイルを作れません: %w", err)
	}
	tmp.Close()
	defer os.Remove(tmp.Name())

	ctx, cancel := context.WithTimeout(ctx, generateTimeout)
	defer cancel()
	if err := c.gen.Generate(ctx, video, tmp.Name()); err != nil {
		return err
	}
	// 書きかけのファイルをキャッシュとして返さないよう、生成が終わってから正式な名前にする。
	return os.Rename(tmp.Name(), path)
}

// cacheKey は動画を差し替えたら変わるよう、相対パス・サイズ・更新日時から名前を作る。
func cacheKey(rel string, fi fs.FileInfo) string {
	h := sha256.New()
	h.Write([]byte(rel))
	h.Write([]byte{0})
	h.Write([]byte(strconv.FormatInt(fi.Size(), 10)))
	h.Write([]byte{0})
	h.Write([]byte(strconv.FormatInt(fi.ModTime().UnixNano(), 10)))
	return hex.EncodeToString(h.Sum(nil))
}
