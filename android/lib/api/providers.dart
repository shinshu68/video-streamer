import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../settings/server_address.dart';
import 'api_client.dart';
import 'models.dart';

/// 保存されているサーバーに接続するクライアント。アドレスの設定後にだけ読む。
final apiClientProvider = Provider<ApiClient>((ref) {
  final baseUri = ref.watch(serverAddressProvider).requireValue;
  if (baseUri == null) {
    throw StateError('サーバーのアドレスが設定されていません');
  }
  final client = ApiClient(baseUri);
  ref.onDispose(client.close);
  return client;
});

/// フォルダの相対パスごとの一覧。
final listProvider = FutureProvider.autoDispose.family<ListResult, String>(
  (ref, path) => ref.watch(apiClientProvider).list(path),
);
