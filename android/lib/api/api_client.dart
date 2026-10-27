import 'dart:convert';

import 'package:http/http.dart' as http;

import 'models.dart';

/// サーバーがエラーのステータスコードを返したことを表す。
class ApiException implements Exception {
  const ApiException(this.statusCode);

  final int statusCode;

  @override
  String toString() => 'ApiException($statusCode)';
}

/// docs/api.md のエンドポイントを呼び出すクライアント。
class ApiClient {
  ApiClient(this.baseUri, {http.Client? httpClient})
    : _http = httpClient ?? http.Client();

  /// 外付けHDDがスリープから復帰するまで待てる長さにする。
  static const timeout = Duration(seconds: 30);

  final Uri baseUri;
  final http.Client _http;

  /// `path` のフォルダの一覧を取得する。ルートは空文字列。
  Future<ListResult> list(String path) async {
    final uri = baseUri.replace(
      path: '/api/list',
      queryParameters: path.isEmpty ? null : {'path': path},
    );
    final res = await _http.get(uri).timeout(timeout);
    if (res.statusCode != 200) {
      throw ApiException(res.statusCode);
    }
    return ListResult.fromJson(
      jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>,
    );
  }

  /// `path` の動画の配信 URL を返す。
  Uri mediaUri(String path) {
    return baseUri.replace(pathSegments: ['media', ...path.split('/')]);
  }

  void close() => _http.close();
}
