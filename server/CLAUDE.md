# server

Windows 上で動かす Go 製の HTTP サーバー。外付けHDDの公開フォルダにある動画の一覧・配信・サムネイルを提供する。

API 仕様は ../docs/api.md、配置・運用は ../docs/deployment.md を参照する。

## コマンド

開発・テスト・ビルドは Windows の PowerShell で行う。コマンドは server/ で実行する。`*_windows.go` のテストも `go test` でそのまま実行される。

```powershell
go test ./...
```

```powershell
go vet ./...
```

```powershell
gofmt -l .
```

```powershell
go build -o bin/video-streamer-server.exe .
```

## ディレクトリ構成

```
server/
├── main.go               # エントリポイント。設定を読み、HTTP サーバーを起動する
├── config.example.json   # 設定ファイルのひな形
└── internal/
    ├── config/           # 設定ファイルの読み込み
    ├── library/          # 公開フォルダのパスの検証と一覧 (Windows の属性の判定は attr_windows.go)
    ├── thumbnail/        # ffmpeg でのサムネイルの生成とキャッシュ
    ├── index/            # 動画の識別子の計算と、識別子とパスの索引
    └── httpapi/          # HTTP ハンドラー (docs/api.md のエンドポイント)
```

## ルール

- 本番の実行環境は Windows。Windows のパス (区切り文字、ドライブ文字) を前提にしたコードを書く
- 公開フォルダのパスやポート番号はコードに書かず、設定ファイルから読む
- 返してよいのは公開フォルダ配下のファイルだけ。リクエストで渡されたパスは必ず正規化し、公開フォルダの外 (`..` やシンボリックリンク経由を含む) を指す場合は拒否する
- 動画の配信は `http.ServeContent` を使い、Range リクエストに対応させる
- 外部パッケージは標準ライブラリで足りない場合だけ追加する (追加時はユーザーに確認する)
- ffmpeg を使うテストは、ffmpeg がない環境では飛ばす。テスト用の動画はテストの中で ffmpeg のテストパターン (`-f lavfi -i testsrc`) から作る。ffmpeg を使わないテストでは thumbnail.Generator を偽物に差し替える
