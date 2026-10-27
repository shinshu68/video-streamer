import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../api/api_client.dart';
import '../api/models.dart';
import '../api/providers.dart';
import '../player/player_screen.dart';
import '../settings/settings_screen.dart';

/// 公開フォルダの [path] にあるフォルダと動画の一覧画面。ルートは空文字列。
class BrowseScreen extends ConsumerWidget {
  const BrowseScreen({super.key, required this.path});

  final String path;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final result = ref.watch(listProvider(path));
    return Scaffold(
      appBar: AppBar(
        title: Text(path.isEmpty ? 'ライブラリ' : path.split('/').last),
        actions: [
          if (path.isEmpty)
            IconButton(
              icon: const Icon(Icons.settings),
              tooltip: 'サーバーの設定',
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute<void>(builder: (_) => const SettingsScreen()),
              ),
            ),
        ],
      ),
      body: result.when(
        data: (list) => RefreshIndicator(
          onRefresh: () => ref.refresh(listProvider(path).future),
          child: _EntryList(entries: list.entries),
        ),
        error: (error, _) => _ErrorView(
          message: errorMessage(error),
          onRetry: () => ref.invalidate(listProvider(path)),
        ),
        loading: () => const Center(child: CircularProgressIndicator()),
      ),
    );
  }
}

/// 一覧の取得に失敗したときに画面に出すメッセージ。
String errorMessage(Object error) {
  return switch (error) {
    ApiException(statusCode: 404) => 'フォルダが見つかりません',
    ApiException(statusCode: 403) => 'このフォルダは開けません',
    ApiException(:final statusCode) => 'サーバーでエラーが発生しました ($statusCode)',
    TimeoutException() => 'サーバーから応答がありません',
    http.ClientException() => 'サーバーに接続できません',
    _ => 'エラーが発生しました',
  };
}

class _EntryList extends StatelessWidget {
  const _EntryList({required this.entries});

  final List<Entry> entries;

  @override
  Widget build(BuildContext context) {
    if (entries.isEmpty) {
      // RefreshIndicator で引っ張って更新できるよう、空でもスクロールできる形にする。
      return ListView(
        children: const [
          Padding(
            padding: EdgeInsets.all(32),
            child: Center(child: Text('このフォルダには動画がありません')),
          ),
        ],
      );
    }
    return ListView.builder(
      itemCount: entries.length,
      itemBuilder: (context, i) => _EntryTile(entry: entries[i]),
    );
  }
}

class _EntryTile extends StatelessWidget {
  const _EntryTile({required this.entry});

  final Entry entry;

  @override
  Widget build(BuildContext context) {
    return switch (entry.type) {
      EntryType.dir => ListTile(
        leading: const Icon(Icons.folder),
        title: Text(entry.name),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute<void>(
            builder: (_) => BrowseScreen(path: entry.path),
          ),
        ),
      ),
      EntryType.video => ListTile(
        leading: const Icon(Icons.movie),
        title: Text(entry.name),
        subtitle: Text(_videoDetail(entry)),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute<void>(builder: (_) => PlayerScreen(entry: entry)),
        ),
      ),
    };
  }
}

String _videoDetail(Entry entry) {
  final parts = <String>[
    if (entry.size case final size?) formatSize(size),
    if (entry.modified case final modified?) formatDate(modified.toLocal()),
  ];
  return parts.join(' ・ ');
}

/// バイト数を `1.5 GB` のような表記にする。
String formatSize(int bytes) {
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  var value = bytes.toDouble();
  var unit = 0;
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit++;
  }
  return unit == 0 ? '$bytes B' : '${value.toStringAsFixed(1)} ${units[unit]}';
}

/// 日付を `2026/10/25` のような表記にする。
String formatDate(DateTime date) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${date.year}/${two(date.month)}/${two(date.day)}';
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(message),
          const SizedBox(height: 16),
          OutlinedButton(onPressed: onRetry, child: const Text('再読み込み')),
        ],
      ),
    );
  }
}
