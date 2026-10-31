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
	"maps"
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

// failureRetryAfter は生成に失敗した動画を、再び生成するまでの時間。
const failureRetryAfter = 10 * time.Minute

// formatVersion はサムネイルの作り方 (位置・大きさなど) の版。作り方を変えたら上げる。
// キャッシュの名前に含め、前の作り方で生成したものを返さないようにする。
const formatVersion = 2

// Cache はサムネイルを dir に保存し、同じ動画の2回目以降はそれを返す。
type Cache struct {
	dir string
	gen Generator
	sem chan struct{}
	now func() time.Time

	mu       sync.Mutex
	inflight map[string]*call
	failures map[string]failure
}

type call struct {
	done chan struct{}
	err  error
}

type failure struct {
	at  time.Time
	err error
}

// NewCache は同時に concurrency 個まで gen を動かす Cache を作る。
func NewCache(dir string, gen Generator, concurrency int) *Cache {
	return &Cache{
		dir:      dir,
		gen:      gen,
		sem:      make(chan struct{}, concurrency),
		now:      time.Now,
		inflight: map[string]*call{},
		failures: map[string]failure{},
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
	if f, ok := c.failures[key]; ok && c.now().Sub(f.at) < failureRetryAfter {
		c.mu.Unlock()
		return "", f.err
	}
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
	cl.err = c.generateFile(ctx, video, path, key)

	c.mu.Lock()
	delete(c.inflight, key)
	c.mu.Unlock()
	close(cl.done)
}

// rememberFailure は key の動画の生成の失敗を覚え、期限の切れた失敗を忘れる。
func (c *Cache) rememberFailure(key string, err error) {
	c.mu.Lock()
	defer c.mu.Unlock()
	now := c.now()
	maps.DeleteFunc(c.failures, func(_ string, f failure) bool {
		return now.Sub(f.at) >= failureRetryAfter
	})
	c.failures[key] = failure{at: now, err: err}
}

func (c *Cache) generateFile(ctx context.Context, video, path, key string) error {
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
		c.rememberFailure(key, err)
		return err
	}
	// 書きかけのファイルをキャッシュとして返さないよう、生成が終わってから正式な名前にする。
	return os.Rename(tmp.Name(), path)
}

// cacheKey は動画を差し替えたときや作り方を変えたときに変わるよう、
// 作り方の版・相対パス・サイズ・更新日時から名前を作る。
func cacheKey(rel string, fi fs.FileInfo) string {
	h := sha256.New()
	h.Write([]byte(strconv.Itoa(formatVersion)))
	h.Write([]byte{0})
	h.Write([]byte(rel))
	h.Write([]byte{0})
	h.Write([]byte(strconv.FormatInt(fi.Size(), 10)))
	h.Write([]byte{0})
	h.Write([]byte(strconv.FormatInt(fi.ModTime().UnixNano(), 10)))
	return hex.EncodeToString(h.Sum(nil))
}
