import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api/models.dart';
import '../api/providers.dart';

/// お気に入りの1件。[name] はサーバーで見つからなくなったときの表示に使う。
class Favorite {
  const Favorite({required this.id, required this.name});

  factory Favorite.fromJson(Map<String, dynamic> json) {
    return Favorite(id: json['id'] as String, name: json['name'] as String);
  }

  final String id;
  final String name;

  Map<String, dynamic> toJson() => {'id': id, 'name': name};
}

/// お気に入りを端末に保存する。
abstract interface class FavoritesStorage {
  Future<List<Favorite>> load();
  Future<void> save(List<Favorite> favorites);
}

class SharedPreferencesFavoritesStorage implements FavoritesStorage {
  static const _key = 'favorites';

  final _prefs = SharedPreferencesAsync();

  @override
  Future<List<Favorite>> load() async {
    final saved = await _prefs.getStringList(_key) ?? [];
    return [
      for (final json in saved)
        Favorite.fromJson(jsonDecode(json) as Map<String, dynamic>),
    ];
  }

  @override
  Future<void> save(List<Favorite> favorites) {
    return _prefs.setStringList(_key, [
      for (final favorite in favorites) jsonEncode(favorite.toJson()),
    ]);
  }
}

final favoritesStorageProvider = Provider<FavoritesStorage>(
  (ref) => SharedPreferencesFavoritesStorage(),
);

/// お気に入りの一覧。新しく付けたものが先。
final favoritesProvider =
    AsyncNotifierProvider<FavoritesNotifier, List<Favorite>>(
      FavoritesNotifier.new,
    );

class FavoritesNotifier extends AsyncNotifier<List<Favorite>> {
  @override
  Future<List<Favorite>> build() {
    return ref.read(favoritesStorageProvider).load();
  }

  /// [entry] がお気に入りなら外し、そうでなければ先頭に加える。
  Future<void> toggle(Entry entry) async {
    final id = entry.id!;
    final current = await future;
    if (current.any((favorite) => favorite.id == id)) {
      await remove(id);
    } else {
      await _update([Favorite(id: id, name: entry.name), ...current]);
    }
  }

  Future<void> remove(String id) async {
    final current = await future;
    await _update([
      for (final favorite in current)
        if (favorite.id != id) favorite,
    ]);
  }

  Future<void> _update(List<Favorite> favorites) async {
    state = AsyncData(favorites);
    await ref.read(favoritesStorageProvider).save(favorites);
  }
}

/// お気に入りのうち、サーバーで見つかった動画。キーは識別子。
final favoriteVideosProvider = FutureProvider.autoDispose<Map<String, Entry>>((
  ref,
) async {
  final favorites = await ref.watch(favoritesProvider.future);
  if (favorites.isEmpty) {
    return {};
  }
  final videos = await ref.watch(apiClientProvider).videos([
    for (final favorite in favorites) favorite.id,
  ]);
  return {for (final video in videos) video.id!: video};
});
