import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:video_player/video_player.dart';
import 'package:video_streamer/favorites/favorites.dart';
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

/// 端末に保存する代わりにメモリに持つストレージ。
class InMemoryFavoritesStorage implements FavoritesStorage {
  InMemoryFavoritesStorage([this.saved = const []]);

  List<Favorite> saved;

  @override
  Future<List<Favorite>> load() async => saved;

  @override
  Future<void> save(List<Favorite> favorites) async => saved = favorites;
}

/// テスト用の ProviderScope。自動の再試行はタイマーが残るため止める。
Widget testScope({required List<Override> overrides, required Widget child}) {
  return ProviderScope(
    overrides: overrides,
    retry: (_, _) => null,
    child: child,
  );
}

/// プラットフォームの再生機能を使わずに、再生中の状態だけを持つコントローラー。
class FakeVideoPlayerController extends ValueNotifier<VideoPlayerValue>
    implements VideoPlayerController {
  FakeVideoPlayerController(this.path)
    : super(VideoPlayerValue(duration: const Duration(minutes: 1)));

  /// 再生する動画の相対パス。
  final String path;

  bool disposed = false;

  @override
  int get playerId => VideoPlayerController.kUninitializedPlayerId;

  @override
  Future<void> initialize() async {
    value = value.copyWith(isInitialized: true, size: const Size(1920, 1080));
  }

  @override
  Future<void> play() async => value = value.copyWith(isPlaying: true);

  @override
  Future<void> pause() async => value = value.copyWith(isPlaying: false);

  @override
  Future<void> seekTo(Duration position) async =>
      value = value.copyWith(position: position);

  @override
  Future<void> dispose() async {
    disposed = true;
    super.dispose();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
