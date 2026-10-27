# android

Flutter 製の Android アプリ。server/ の API から動画の一覧を取得し、配信 URL をストリーミング再生する。

API 仕様は ../docs/api.md、画面構成とデータの流れは ../docs/architecture.md を参照する。

## コマンド

```fish
flutter pub get
```

```fish
flutter analyze
```

```fish
flutter test
```

```fish
flutter run
```

```fish
flutter build apk
```

## ディレクトリ構成

機能ごとに分ける。状態管理は Riverpod (flutter_riverpod 3.x)。

```
lib/
├── main.dart       # ProviderScope と、アドレスの設定有無で最初の画面を切り替える
├── api/            # API クライアント、レスポンスの型、一覧の Provider
├── settings/       # サーバーのアドレスの検証・保存と設定画面
├── browse/         # 一覧画面
└── player/         # 再生画面
```

## ルール

- サーバーとは HTTP (平文) で通信する。network_security_config では IP アドレスの範囲を指定できないため平文通信はアプリ全体で許可し、LAN 内に限る検証は lib/settings/server_address.dart で行う (プライベート IP だけを受け付ける)
- サーバーのアドレスはコードに書かない。設定画面で入力し、端末に保存する
- API のレスポンスの型は docs/api.md に合わせる。仕様にない項目を前提にしない
- テストではサーバーにアクセスせず、`package:http/testing.dart` の MockClient で差し替える
- 主な確認端末は Pixel 6a

## 動作確認

確認用のエミュレーターは `Pixel_6a_API_37` (Android 17) とする。

- Windows で server/ を起動し、アプリの設定画面に `10.0.2.2:<ポート>` を入力する (エミュレーターからホストの PC を指すアドレス)
- 確認用の動画は実際の動画を使わず、pub cache にある video_player のサンプル (`video_player-<バージョン>/example/assets/Butterfly-209.mp4`) を一時フォルダにコピーして使う
- `adb shell screencap` は古い画面を返すことがあるため、スクリーンショットは `adb emu screenrecord screenshot <保存先のフォルダ>` で撮る
- エミュレーターでは再生画面の間だけ画面の更新が止まり、動画の絵を目で確かめられない。再生位置やボタンの状態は `adb shell uiautomator dump` のビュー階層で確かめる (値は操作1回分遅れて更新されることがある)。絵が出ることは実機で確かめる
