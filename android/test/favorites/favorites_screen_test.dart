import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:video_streamer/api/api_client.dart';
import 'package:video_streamer/api/providers.dart';
import 'package:video_streamer/favorites/favorites.dart';
import 'package:video_streamer/favorites/favorites_screen.dart';
import 'package:video_streamer/player/picture_in_picture.dart';
import 'package:video_streamer/player/player_screen.dart';

import '../helpers.dart';

Map<String, Object> video(String id) => {
  'type': 'video',
  'id': id,
  'name': '動画$id.mp4',
  'path': '動画$id.mp4',
  'size': 1,
  'modified': '2026-10-25T12:00:00+09:00',
};

const favoriteA = Favorite(id: 'A', name: '動画A.mp4');
const favoriteB = Favorite(id: 'B', name: '動画B.mp4');
const favoriteC = Favorite(id: 'C', name: '動画C.mp4');

/// [found] の識別子だけを見つけるサーバーで、お気に入りの画面を開く。
Future<void> pumpFavorites(
  WidgetTester tester, {
  required InMemoryFavoritesStorage storage,
  required Set<String> found,
  bool fail = false,
}) async {
  final client = ApiClient(
    Uri.parse('http://192.168.0.10:8765'),
    httpClient: MockClient((req) async {
      if (fail) {
        return http.Response('{"error":"Internal Server Error"}', 500);
      }
      final ids = jsonDecode(req.body)['ids'] as List<dynamic>;
      return http.Response.bytes(
        utf8.encode(
          jsonEncode({
            'videos': [
              for (final id in ids)
                if (found.contains(id)) video(id as String),
            ],
          }),
        ),
        200,
      );
    }),
  );
  await tester.pumpWidget(
    testScope(
      overrides: [
        apiClientProvider.overrideWithValue(client),
        favoritesStorageProvider.overrideWithValue(storage),
        pictureInPictureProvider.overrideWithValue(FakePictureInPicture()),
        videoControllerFactoryProvider.overrideWithValue(
          FakeVideoPlayerController.new,
        ),
      ],
      child: const MaterialApp(home: FavoritesScreen()),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('お気に入りがなければその旨を表示する', (tester) async {
    await pumpFavorites(tester, storage: InMemoryFavoritesStorage(), found: {});

    expect(find.text('お気に入りはありません'), findsOneWidget);
  });

  testWidgets('保存された順に動画を並べ、選んだ動画から再生する', (tester) async {
    await pumpFavorites(
      tester,
      storage: InMemoryFavoritesStorage([favoriteB, favoriteA]),
      found: {'A', 'B'},
    );

    expect(
      tester.getTopLeft(find.text('動画B.mp4')).dy,
      lessThan(tester.getTopLeft(find.text('動画A.mp4')).dy),
    );

    await tester.tap(find.text('動画A.mp4'));
    await tester.pumpAndSettle();

    final player = tester.widget<PlayerScreen>(find.byType(PlayerScreen));
    expect(player.entries.map((e) => e.name), ['動画B.mp4', '動画A.mp4']);
    expect(player.initialIndex, 1);
  });

  testWidgets('見つからない動画は末尾に出し、再生の切り替えには含めない', (tester) async {
    await pumpFavorites(
      tester,
      storage: InMemoryFavoritesStorage([favoriteA, favoriteB, favoriteC]),
      found: {'B', 'C'},
    );

    expect(find.text('見つかりません'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('動画C.mp4')).dy,
      lessThan(tester.getTopLeft(find.text('動画A.mp4')).dy),
    );

    await tester.tap(find.text('動画B.mp4'));
    await tester.pumpAndSettle();

    final player = tester.widget<PlayerScreen>(find.byType(PlayerScreen));
    expect(player.entries.map((e) => e.name), ['動画B.mp4', '動画C.mp4']);
  });

  testWidgets('見つからない動画はボタンでお気に入りから外せる', (tester) async {
    final storage = InMemoryFavoritesStorage([favoriteA, favoriteB]);
    await pumpFavorites(tester, storage: storage, found: {'B'});

    await tester.tap(find.byTooltip('お気に入りから外す'));
    await tester.pumpAndSettle();

    expect(find.text('見つかりません'), findsNothing);
    expect(storage.saved.map((f) => f.id), ['B']);
  });

  testWidgets('取得に失敗したら、見つからない扱いにせずメッセージを出す', (tester) async {
    final storage = InMemoryFavoritesStorage([favoriteA]);
    await pumpFavorites(tester, storage: storage, found: {}, fail: true);

    expect(find.text('見つかりません'), findsNothing);
    expect(find.text('再読み込み'), findsOneWidget);
    expect(storage.saved.map((f) => f.id), ['A']);
  });
}
