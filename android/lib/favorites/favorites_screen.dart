import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/models.dart';
import '../api/providers.dart';
import '../browse/browse_screen.dart';
import '../player/player_screen.dart';
import 'favorites.dart';

/// お気に入りの動画の一覧画面。サーバーで見つからない動画は末尾に出す。
class FavoritesScreen extends ConsumerWidget {
  const FavoritesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final favorites = ref.watch(favoritesProvider).value ?? const <Favorite>[];
    final videos = ref.watch(favoriteVideosProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('お気に入り')),
      body: videos.when(
        skipLoadingOnReload: true,
        data: (found) => _FavoriteList(favorites: favorites, found: found),
        error: (error, _) => ErrorView(
          message: errorMessage(error),
          onRetry: () => ref.invalidate(favoriteVideosProvider),
        ),
        loading: () => const Center(child: CircularProgressIndicator()),
      ),
    );
  }
}

class _FavoriteList extends ConsumerWidget {
  const _FavoriteList({required this.favorites, required this.found});

  final List<Favorite> favorites;
  final Map<String, Entry> found;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (favorites.isEmpty) {
      return const Center(child: Text('お気に入りはありません'));
    }
    final videos = [for (final favorite in favorites) ?found[favorite.id]];
    final missing = [
      for (final favorite in favorites)
        if (!found.containsKey(favorite.id)) favorite,
    ];
    final client = ref.watch(apiClientProvider);
    return ListView(
      children: [
        for (final (i, video) in videos.indexed)
          VideoTile(
            entry: video,
            thumbnail: NetworkImage(client.thumbnailUri(video.path).toString()),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute<void>(
                builder: (_) => PlayerScreen(entries: videos, initialIndex: i),
              ),
            ),
          ),
        for (final favorite in missing) _MissingTile(favorite: favorite),
      ],
    );
  }
}

class _MissingTile extends ConsumerWidget {
  const _MissingTile({required this.favorite});

  final Favorite favorite;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Opacity(
      opacity: 0.5,
      child: ListTile(
        title: Text(favorite.name),
        subtitle: const Text('見つかりません'),
        trailing: IconButton(
          icon: const Icon(Icons.delete_outline),
          tooltip: 'お気に入りから外す',
          onPressed: () =>
              ref.read(favoritesProvider.notifier).remove(favorite.id),
        ),
      ),
    );
  }
}
