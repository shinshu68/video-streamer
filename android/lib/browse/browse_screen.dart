import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../api/api_client.dart';
import '../api/models.dart';
import '../api/providers.dart';
import '../favorites/favorites_screen.dart';
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
          IconButton(
            icon: const Icon(Icons.favorite),
            tooltip: 'お気に入り',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute<void>(builder: (_) => const FavoritesScreen()),
            ),
          ),
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
          // 失敗は listProvider の状態になり ErrorView で表示されるため、受け取るだけでよい。
          onRefresh: () => ref
              .refresh(listProvider(path).future)
              .then<void>((_) {}, onError: (_) {}),
          child: _EntryList(entries: list.entries),
        ),
        error: (error, _) => ErrorView(
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
    final videos = [
      for (final entry in entries)
        if (entry.type == EntryType.video) entry,
    ];
    return ListView.builder(
      itemCount: entries.length,
      itemBuilder: (context, i) =>
          _EntryTile(entry: entries[i], videos: videos),
    );
  }
}

class _EntryTile extends ConsumerWidget {
  const _EntryTile({required this.entry, required this.videos});

  final Entry entry;

  /// 再生画面で前後に切り替える、同じフォルダの動画。
  final List<Entry> videos;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return switch (entry.type) {
      EntryType.dir => ListTile(
        leading: const _LeadingBox(child: Icon(Icons.folder)),
        title: Text(entry.name),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute<void>(
            builder: (_) => BrowseScreen(path: entry.path),
          ),
        ),
      ),
      EntryType.video => VideoTile(
        entry: entry,
        thumbnail: NetworkImage(
          ref.watch(apiClientProvider).thumbnailUri(entry.path).toString(),
        ),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute<void>(
            builder: (_) => PlayerScreen(
              entries: videos,
              initialIndex: videos.indexOf(entry),
            ),
          ),
        ),
      ),
    };
  }
}

/// 動画の行。サムネイル、名前、サイズと更新日時を並べる。
///
/// 縦長のサムネイルのときは、その分だけ行を高くする。
// ListTile は先頭の部品の高さを 56 までに抑えるため、縦長の枠が収まらない。
// 余白と文字のスタイルは ListTile の2行の表示に合わせている。
class VideoTile extends StatelessWidget {
  const VideoTile({
    super.key,
    required this.entry,
    required this.thumbnail,
    required this.onTap,
  });

  final Entry entry;
  final ImageProvider thumbnail;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 72),
        child: Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(16, 8, 24, 8),
          child: Row(
            children: [
              Thumbnail(image: thumbnail),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(entry.name, style: theme.textTheme.bodyLarge),
                    Text(
                      _videoDetail(entry),
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 一覧の行の先頭に置く枠。幅は横長のサムネイルにそろえ、行の文字の位置をそろえる。
class _LeadingBox extends StatelessWidget {
  const _LeadingBox({this.height = _thumbnailShortSide, required this.child});

  final double height;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: _thumbnailLongSide,
      height: height,
      child: Center(child: child),
    );
  }
}

const _thumbnailLongSide = 96.0;
const _thumbnailShortSide = 54.0;

/// [image] のサムネイル。縦長の画像は縦長の枠で出す。
///
/// 取得中や取得できないときは、横長の枠に動画のアイコンを出す。
class Thumbnail extends StatefulWidget {
  const Thumbnail({super.key, required this.image});

  final ImageProvider image;

  @override
  State<Thumbnail> createState() => _ThumbnailState();
}

// 縦横比で枠を決めるため、Image ではなく画像を自分で取得して RawImage で描く。
// Image の frameBuilder には読み込んだ画像の大きさが渡されない。
class _ThumbnailState extends State<Thumbnail> {
  ImageStream? _stream;
  ImageInfo? _info;
  late final _listener = ImageStreamListener(_onImage, onError: (_, _) {});

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _resolve();
  }

  @override
  void didUpdateWidget(Thumbnail oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.image != oldWidget.image) {
      _resolve();
    }
  }

  @override
  void dispose() {
    _stream?.removeListener(_listener);
    _info?.dispose();
    super.dispose();
  }

  void _resolve() {
    final stream = widget.image.resolve(createLocalImageConfiguration(context));
    if (stream.key == _stream?.key) {
      return;
    }
    _stream?.removeListener(_listener);
    _info?.dispose();
    _info = null;
    _stream = stream..addListener(_listener);
  }

  void _onImage(ImageInfo info, bool _) {
    setState(() {
      _info?.dispose();
      _info = info;
    });
  }

  @override
  Widget build(BuildContext context) {
    final image = _info?.image;
    if (image == null) {
      return const _LeadingBox(child: Icon(Icons.movie));
    }
    final portrait = image.height > image.width;
    final (width, height) = portrait
        ? (_thumbnailShortSide, _thumbnailLongSide)
        : (_thumbnailLongSide, _thumbnailShortSide);
    return _LeadingBox(
      height: height,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: RawImage(
          image: image,
          width: width,
          height: height,
          fit: BoxFit.cover,
        ),
      ),
    );
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

/// 取得に失敗したことを伝え、再読み込みできるようにする表示。
class ErrorView extends StatelessWidget {
  const ErrorView({super.key, required this.message, required this.onRetry});

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
