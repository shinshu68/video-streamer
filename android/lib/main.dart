import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'browse/browse_screen.dart';
import 'settings/server_address.dart';
import 'settings/settings_screen.dart';

void main() {
  runApp(
    // Riverpod 3 は失敗した Provider を自動で再試行するが、サーバーが止まっているときに
    // 読み込み中の表示が続かないよう、再試行は画面の「再読み込み」に任せる。
    ProviderScope(retry: (_, _) => null, child: const VideoStreamerApp()),
  );
}

class VideoStreamerApp extends StatelessWidget {
  const VideoStreamerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Video Streamer',
      theme: ThemeData(colorSchemeSeed: Colors.indigo),
      darkTheme: ThemeData(
        colorSchemeSeed: Colors.indigo,
        brightness: Brightness.dark,
      ),
      home: const _Home(),
    );
  }
}

/// アドレスが未設定なら設定画面、設定済みならルートの一覧画面を出す。
class _Home extends ConsumerWidget {
  const _Home();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ref
        .watch(serverAddressProvider)
        .when(
          data: (uri) => uri == null
              ? const SettingsScreen()
              : const BrowseScreen(path: ''),
          error: (_, _) => const SettingsScreen(),
          loading: () =>
              const Scaffold(body: Center(child: CircularProgressIndicator())),
        );
  }
}
