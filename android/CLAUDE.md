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

## ルール

- サーバーとは HTTP (平文) で通信する。Android 9 以降は平文通信が既定で禁止されているため、network_security_config で許可する範囲を LAN 内の通信に絞る
- サーバーのアドレスはコードに書かない (アプリからの指定方法は docs/plan.md の未決事項を参照)
- API のレスポンスの型は docs/api.md に合わせる。仕様にない項目を前提にしない
- 主な確認端末は Pixel 6a
