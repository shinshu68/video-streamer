import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/models.dart';
import 'favorites.dart';

/// [entry] のお気に入りを付け外しするハートのボタン。
///
/// 識別子のない動画はお気に入りにできないため、何も出さない。
class FavoriteButton extends ConsumerWidget {
  const FavoriteButton({super.key, required this.entry});

  final Entry entry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final id = entry.id;
    if (id == null) {
      return const SizedBox.shrink();
    }
    final favorites = ref.watch(favoritesProvider).value ?? const [];
    final isFavorite = favorites.any((favorite) => favorite.id == id);
    return IconButton(
      icon: Icon(
        isFavorite ? Icons.favorite : Icons.favorite_border,
        color: isFavorite ? Colors.red : Colors.white,
        shadows: const [Shadow(blurRadius: 4)],
      ),
      tooltip: isFavorite ? 'お気に入りから外す' : 'お気に入りに追加',
      onPressed: () => ref.read(favoritesProvider.notifier).toggle(entry),
    );
  }
}
