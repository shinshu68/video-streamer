import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 入力されたサーバーのアドレス (`192.168.0.10:8765` など) を検証し、ベース URL を返す。
///
/// 受け付けるのはプライベート IP (10/8・172.16/12・192.168/16) と明示したポートだけ。
/// 不正な場合は、画面に出す理由をメッセージに持つ [FormatException] を投げる。
Uri parseServerAddress(String input) {
  var text = input.trim();
  if (text.startsWith('http://')) {
    text = text.substring('http://'.length);
  }
  if (text.endsWith('/')) {
    text = text.substring(0, text.length - 1);
  }

  final parts = text.split(':');
  if (parts.length != 2) {
    throw const FormatException('「IP アドレス:ポート番号」の形で入力してください');
  }
  final host = parts[0];
  if (!_isPrivateIPv4(host)) {
    throw const FormatException('LAN 内の IP アドレス (192.168.x.x など) を入力してください');
  }
  final port = int.tryParse(parts[1]);
  if (port == null || port < 1 || port > 65535) {
    throw const FormatException('ポート番号は 1〜65535 で入力してください');
  }
  return Uri(scheme: 'http', host: host, port: port);
}

bool _isPrivateIPv4(String host) {
  final octets = host.split('.');
  if (octets.length != 4) {
    return false;
  }
  final values = <int>[];
  for (final octet in octets) {
    final value = int.tryParse(octet);
    if (value == null || value < 0 || value > 255 || '$value' != octet) {
      return false;
    }
    values.add(value);
  }
  final [a, b, _, _] = values;
  return a == 10 || (a == 172 && b >= 16 && b <= 31) || (a == 192 && b == 168);
}

/// サーバーのアドレスを端末に保存する。
abstract interface class ServerAddressStorage {
  Future<String?> load();
  Future<void> save(String address);
}

class SharedPreferencesServerAddressStorage implements ServerAddressStorage {
  static const _key = 'server_address';

  final _prefs = SharedPreferencesAsync();

  @override
  Future<String?> load() => _prefs.getString(_key);

  @override
  Future<void> save(String address) => _prefs.setString(_key, address);
}

final serverAddressStorageProvider = Provider<ServerAddressStorage>(
  (ref) => SharedPreferencesServerAddressStorage(),
);

/// 保存されているサーバーのベース URL。未設定なら null。
final serverAddressProvider =
    AsyncNotifierProvider<ServerAddressNotifier, Uri?>(
      ServerAddressNotifier.new,
    );

class ServerAddressNotifier extends AsyncNotifier<Uri?> {
  @override
  Future<Uri?> build() async {
    final saved = await ref.read(serverAddressStorageProvider).load();
    if (saved == null) {
      return null;
    }
    try {
      return parseServerAddress(saved);
    } on FormatException {
      return null;
    }
  }

  /// [input] を検証して保存する。不正な場合は [FormatException] を投げ、何も保存しない。
  Future<void> save(String input) async {
    final uri = parseServerAddress(input);
    await ref
        .read(serverAddressStorageProvider)
        .save('${uri.host}:${uri.port}');
    state = AsyncData(uri);
  }
}
