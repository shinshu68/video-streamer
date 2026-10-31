import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:video_streamer/api/models.dart';
import 'package:video_streamer/favorites/favorites.dart';

import '../helpers.dart';

const entryA = Entry(
  type: EntryType.video,
  id: 'A',
  name: '動画A.mp4',
  path: '動画A.mp4',
);
const entryB = Entry(
  type: EntryType.video,
  id: 'B',
  name: '動画B.mp4',
  path: '動画B.mp4',
);

ProviderContainer containerWith(FavoritesStorage storage) {
  final container = ProviderContainer(
    overrides: [favoritesStorageProvider.overrideWithValue(storage)],
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  test('付けたお気に入りは先頭に入り、保存される', () async {
    final storage = InMemoryFavoritesStorage();
    final notifier = containerWith(storage).read(favoritesProvider.notifier);

    await notifier.toggle(entryA);
    await notifier.toggle(entryB);

    expect(storage.saved.map((f) => f.id), ['B', 'A']);
    expect(storage.saved.first.name, '動画B.mp4');
  });

  test('お気に入りの動画でもう一度切り替えると外れる', () async {
    final storage = InMemoryFavoritesStorage([
      const Favorite(id: 'A', name: '動画A.mp4'),
      const Favorite(id: 'B', name: '動画B.mp4'),
    ]);
    final notifier = containerWith(storage).read(favoritesProvider.notifier);

    await notifier.toggle(entryA);

    expect(storage.saved.map((f) => f.id), ['B']);
  });

  test('Favorite は JSON に変換して元に戻せる', () {
    final favorite = Favorite.fromJson(
      const Favorite(id: 'A', name: '動画A.mp4').toJson(),
    );

    expect(favorite.id, 'A');
    expect(favorite.name, '動画A.mp4');
  });
}
