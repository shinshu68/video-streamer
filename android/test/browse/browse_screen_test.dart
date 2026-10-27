import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:video_streamer/api/api_client.dart';
import 'package:video_streamer/api/providers.dart';
import 'package:video_streamer/browse/browse_screen.dart';

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
      overrides: [apiClientProvider.overrideWithValue(client)],
      child: MaterialApp(home: BrowseScreen(path: path)),
    ),
  );
  await tester.pumpAndSettle();
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
