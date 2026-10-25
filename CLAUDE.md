# video-streamer

同一 LAN 内の Windows PC の外付けHDDに保存した動画 (主に mp4) を、Android アプリからストリーミング再生するためのモノレポ。

docs/plan.md を起点に、docs/ 配下の各ドキュメントを参照する。

## 技術スタック

- server/: Go (Windows 上で動かす HTTP サーバー)
- android/: Flutter (Android アプリ)

## ディレクトリ構成

```
video-streamer/
├── CLAUDE.md
├── docs/
│   ├── plan.md          # 概要と目次
│   ├── api.md           # サーバーとアプリの間の API 仕様
│   ├── architecture.md  # 全体構成とデータの流れ
│   └── deployment.md    # Windows 上での配置・運用
├── server/              # 詳細は server/CLAUDE.md
└── android/             # 詳細は android/CLAUDE.md
```

## コマンド

ビルド・テスト・実行のコマンドは server/CLAUDE.md と android/CLAUDE.md にそれぞれ記載する。

## プロジェクト固有のルール

- docs/api.md をサーバーとアプリの間の唯一の正とする。API を変更するときは「docs/api.md → server/ → android/」の順に、1つのブランチで直す
- server/ と android/ の両方にまたがる変更でも、コミットは server/ と android/ で分ける
- テストやサンプルに実際の動画ファイルを置かない。必要な場合はテストの中で小さなダミーファイルを生成する
