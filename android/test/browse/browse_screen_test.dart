import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:video_streamer/api/api_client.dart';
import 'package:video_streamer/api/models.dart';
import 'package:video_streamer/api/providers.dart';
import 'package:video_streamer/browse/browse_screen.dart';
import 'package:video_streamer/favorites/favorites.dart';
import 'package:video_streamer/favorites/favorites_screen.dart';
import 'package:video_streamer/player/player_screen.dart';

import '../helpers.dart';

/// フォルダの相対パスごとのレスポンスを返す偽のサーバー。
ApiClient fakeServer(Map<String, Object> listings) {
  return ApiClient(
    Uri.parse('http://192.168.0.10:8765'),
    httpClient: MockClient((req) async {
      final path = req.url.queryParameters['path'] ?? '';
      final listing = listings[path];
      if (listing == null) {
        return http.Response('{"error":"Not Found"}', 404);
      }
      return http.Response.bytes(utf8.encode(jsonEncode(listing)), 200);
    }),
  );
}

Future<void> pumpBrowse(
  WidgetTester tester,
  ApiClient client, {
  String path = '',
}) async {
  await tester.pumpWidget(
    testScope(
      overrides: [
        apiClientProvider.overrideWithValue(client),
        favoritesStorageProvider.overrideWithValue(InMemoryFavoritesStorage()),
        videoControllerFactoryProvider.overrideWithValue(
          FakeVideoPlayerController.new,
        ),
      ],
      child: MaterialApp(home: BrowseScreen(path: path)),
    ),
  );
  await tester.pumpAndSettle();
}

/// [width]×[height] の PNG 画像。
Future<MemoryImage> pngImage(int width, int height) async {
  final recorder = ui.PictureRecorder();
  Canvas(
    recorder,
  ).drawRect(Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()), Paint());
  final image = await recorder.endRecording().toImage(width, height);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  return MemoryImage(data!.buffer.asUint8List());
}

/// [image] をサムネイルにした動画の行を置き、画像を読み込み終えるまで進める。
Future<void> pumpVideoTile(WidgetTester tester, ImageProvider image) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Column(
          children: [
            VideoTile(
              entry: const Entry(
                type: EntryType.video,
                name: '動画C.mp4',
                path: '動画C.mp4',
              ),
              thumbnail: image,
              onTap: () {},
            ),
          ],
        ),
      ),
    ),
  );
  await tester.runAsync(
    () => precacheImage(image, tester.element(find.byType(Thumbnail))),
  );
  await tester.pump();
}

void main() {
  testWidgets('フォルダと動画を一覧に表示する', (tester) async {
    await pumpBrowse(
      tester,
      fakeServer({
        '': {
          'path': '',
          'entries': [
            {'type': 'dir', 'name': 'フォルダA', 'path': 'フォルダA'},
            {
              'type': 'video',
              'name': '動画C.mp4',
              'path': '動画C.mp4',
              'size': 1610612736,
              'modified': '2026-10-25T12:00:00+09:00',
            },
          ],
        },
      }),
    );

    expect(find.text('ライブラリ'), findsOneWidget);
    expect(find.text('フォルダA'), findsOneWidget);
    expect(find.text('動画C.mp4'), findsOneWidget);
    expect(find.textContaining('1.5 GB'), findsOneWidget);
    expect(find.byIcon(Icons.settings), findsOneWidget);
  });

  testWidgets('動画の行はサムネイルを取得し、取得できなければアイコンを出す', (tester) async {
    await pumpBrowse(
      tester,
      fakeServer({
        '': {
          'path': '',
          'entries': [
            {'type': 'dir', 'name': 'フォルダA', 'path': 'フォルダA'},
            {
              'type': 'video',
              'name': '動画C.mp4',
              'path': 'フォルダA/動画C.mp4',
              'size': 1,
              'modified': '2026-10-25T12:00:00+09:00',
            },
          ],
        },
      }),
    );

    final thumbnail = tester.widget<Thumbnail>(find.byType(Thumbnail));
    final url = Uri.parse((thumbnail.image as NetworkImage).url);
    expect(url.path, '/api/thumbnail');
    expect(url.queryParameters, {'path': 'フォルダA/動画C.mp4'});
    // テスト環境では画像の取得が失敗するため、代わりのアイコンになる。
    expect(find.byIcon(Icons.movie), findsOneWidget);
    expect(find.byIcon(Icons.folder), findsOneWidget);
  });

  testWidgets('横長のサムネイルは横長の枠で出す', (tester) async {
    final image = (await tester.runAsync(() => pngImage(320, 180)))!;
    await pumpVideoTile(tester, image);

    expect(tester.getSize(find.byType(RawImage)), const Size(96, 54));
  });

  testWidgets('縦長のサムネイルは縦長の枠で出し、行をその分高くする', (tester) async {
    final image = (await tester.runAsync(() => pngImage(180, 320)))!;
    await pumpVideoTile(tester, image);

    expect(tester.getSize(find.byType(RawImage)), const Size(54, 96));
    expect(tester.getSize(find.byType(VideoTile)).height, greaterThan(96));
  });

  testWidgets('フォルダをタップするとその中の一覧を開く', (tester) async {
    await pumpBrowse(
      tester,
      fakeServer({
        '': {
          'path': '',
          'entries': [
            {'type': 'dir', 'name': 'フォルダA', 'path': 'フォルダA'},
          ],
        },
        'フォルダA': {
          'path': 'フォルダA',
          'entries': [
            {'type': 'dir', 'name': 'サブフォルダB', 'path': 'フォルダA/サブフォルダB'},
          ],
        },
      }),
    );

    await tester.tap(find.text('フォルダA'));
    await tester.pumpAndSettle();

    expect(find.text('サブフォルダB'), findsOneWidget);
    expect(find.byIcon(Icons.settings), findsNothing);
  });

  testWidgets('動画をタップすると、同じフォルダの動画を前後に切り替えられる再生画面を開く', (tester) async {
    Map<String, Object> video(String name) => {
      'type': 'video',
      'name': name,
      'path': name,
      'size': 1,
      'modified': '2026-10-25T12:00:00+09:00',
    };
    await pumpBrowse(
      tester,
      fakeServer({
        '': {
          'path': '',
          'entries': [
            video('動画A.mp4'),
            {'type': 'dir', 'name': 'フォルダB', 'path': 'フォルダB'},
            video('動画C.mp4'),
            video('動画D.mp4'),
          ],
        },
      }),
    );

    await tester.tap(find.text('動画C.mp4'));
    await tester.pumpAndSettle();

    final player = tester.widget<PlayerScreen>(find.byType(PlayerScreen));
    expect(player.entries.map((e) => e.name), [
      '動画A.mp4',
      '動画C.mp4',
      '動画D.mp4',
    ]);
    expect(player.initialIndex, 1);
  });

  testWidgets('サブフォルダの一覧からもお気に入りの画面を開ける', (tester) async {
    await pumpBrowse(
      tester,
      fakeServer({
        'フォルダA': {'path': 'フォルダA', 'entries': []},
      }),
      path: 'フォルダA',
    );

    await tester.tap(find.byTooltip('お気に入り'));
    await tester.pumpAndSettle();

    expect(find.byType(FavoritesScreen), findsOneWidget);
  });

  testWidgets('空のフォルダではその旨を表示する', (tester) async {
    await pumpBrowse(
      tester,
      fakeServer({
        'フォルダA': {'path': 'フォルダA', 'entries': []},
      }),
      path: 'フォルダA',
    );

    expect(find.text('このフォルダには動画がありません'), findsOneWidget);
  });

  testWidgets('取得に失敗したらメッセージを出し、再読み込みで取り直す', (tester) async {
    var fail = true;
    final client = ApiClient(
      Uri.parse('http://192.168.0.10:8765'),
      httpClient: MockClient((_) async {
        if (fail) {
          throw http.ClientException('connection refused');
        }
        return http.Response('{"path":"","entries":[]}', 200);
      }),
    );
    await pumpBrowse(tester, client);

    expect(find.text('サーバーに接続できません'), findsOneWidget);

    fail = false;
    await tester.tap(find.text('再読み込み'));
    await tester.pumpAndSettle();

    expect(find.text('このフォルダには動画がありません'), findsOneWidget);
  });

  test('errorMessage はステータスコードごとに理由を返す', () {
    expect(errorMessage(const ApiException(404)), 'フォルダが見つかりません');
    expect(errorMessage(const ApiException(403)), 'このフォルダは開けません');
    expect(errorMessage(const ApiException(500)), contains('500'));
  });

  test('formatSize は単位を繰り上げて小数1桁で表す', () {
    expect(formatSize(512), '512 B');
    expect(formatSize(1536), '1.5 KB');
    expect(formatSize(1610612736), '1.5 GB');
  });
}
