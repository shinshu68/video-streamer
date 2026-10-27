import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:video_streamer/api/api_client.dart';
import 'package:video_streamer/api/models.dart';

final baseUri = Uri.parse('http://192.168.0.10:8765');

http.Response jsonResponse(Object body, {int status = 200}) {
  return http.Response.bytes(
    utf8.encode(jsonEncode(body)),
    status,
    headers: {'content-type': 'application/json; charset=utf-8'},
  );
}

void main() {
  group('list', () {
    test('フォルダのパスをクエリに付けて一覧を取得し、型に変換する', () async {
      late Uri requested;
      final client = ApiClient(
        baseUri,
        httpClient: MockClient((req) async {
          requested = req.url;
          return jsonResponse({
            'path': 'フォルダA',
            'entries': [
              {'type': 'dir', 'name': 'サブフォルダB', 'path': 'フォルダA/サブフォルダB'},
              {
                'type': 'video',
                'name': '動画C.mp4',
                'path': 'フォルダA/動画C.mp4',
                'size': 123456789,
                'modified': '2026-10-25T12:00:00+09:00',
              },
            ],
          });
        }),
      );

      final result = await client.list('フォルダA');

      expect(requested.path, '/api/list');
      expect(requested.queryParameters, {'path': 'フォルダA'});
      expect(result.path, 'フォルダA');
      final [dir, video] = result.entries;
      expect(dir.type, EntryType.dir);
      expect(dir.path, 'フォルダA/サブフォルダB');
      expect(dir.size, isNull);
      expect(video.type, EntryType.video);
      expect(video.name, '動画C.mp4');
      expect(video.size, 123456789);
      expect(video.modified, DateTime.utc(2026, 10, 25, 3));
    });

    test('ルートを取得するときは path を付けない', () async {
      late Uri requested;
      final client = ApiClient(
        baseUri,
        httpClient: MockClient((req) async {
          requested = req.url;
          return jsonResponse({'path': '', 'entries': []});
        }),
      );

      final result = await client.list('');

      expect(requested.toString(), 'http://192.168.0.10:8765/api/list');
      expect(result.entries, isEmpty);
    });

    test('エラーのステータスコードは ApiException にする', () async {
      final client = ApiClient(
        baseUri,
        httpClient: MockClient(
          (_) async => jsonResponse({'error': 'Not Found'}, status: 404),
        ),
      );

      await expectLater(
        client.list('missing'),
        throwsA(
          isA<ApiException>().having((e) => e.statusCode, 'statusCode', 404),
        ),
      );
    });
  });

  test('mediaUri はパスの各要素を URL エンコードする', () {
    final client = ApiClient(
      baseUri,
      httpClient: MockClient((_) async => http.Response('', 200)),
    );

    final uri = client.mediaUri('フォルダA/動画 C#1.mp4');

    expect(
      uri.toString(),
      'http://192.168.0.10:8765/media/%E3%83%95%E3%82%A9%E3%83%AB%E3%83%80A/'
      '%E5%8B%95%E7%94%BB%20C%231.mp4',
    );
  });
}
