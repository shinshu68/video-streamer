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
├── favorites/      # お気に入りの保存、画面、ハートのボタン
└── player/         # 再生画面
```

## ルール

- サーバーとは HTTP (平文) で通信する。network_security_config では IP アドレスの範囲を指定できないため平文通信はアプリ全体で許可し、LAN 内に限る検証は lib/settings/server_address.dart で行う (プライベート IP だけを受け付ける)
- サーバーのアドレスはコードに書かない。設定画面で入力し、端末に保存する
- API のレスポンスの型は docs/api.md に合わせる。仕様にない項目を前提にしない
- テストではサーバーにアクセスせず、`package:http/testing.dart` の MockClient で差し替える
- 主な確認端末は Pixel 6a

## 動作確認

ウィジェットテストと実機 (Pixel 6a) で確かめ、エミュレーターは使わない。エミュレーターでは動画のデコードが重く、再生画面の表示の更新が止まって動画の絵を確かめられず、負荷で adb からの入力も正しく届かないことがあるため。

- 画面の動きや状態の変化は、ウィジェットテストで確かめる
- 実機での確認はユーザーに頼む。見た目・操作の感触・動画の再生など、確かめてほしい点を具体的に挙げる
- 実機へのインストールは、android/ で `flutter devices` を実行して Pixel 6a の ID を確かめ、`flutter run -d <ID>` を実行してもらう
