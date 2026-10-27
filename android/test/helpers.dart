import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:video_streamer/settings/server_address.dart';

/// 端末に保存する代わりにメモリに持つストレージ。
class InMemoryServerAddressStorage implements ServerAddressStorage {
  InMemoryServerAddressStorage([this.saved]);

  String? saved;

  @override
  Future<String?> load() async => saved;

  @override
  Future<void> save(String address) async => saved = address;
}

/// テスト用の ProviderScope。自動の再試行はタイマーが残るため止める。
Widget testScope({required List<Override> overrides, required Widget child}) {
  return ProviderScope(
    overrides: overrides,
    retry: (_, _) => null,
    child: child,
  );
}
