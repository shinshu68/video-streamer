import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:video_player/video_player.dart';
import 'package:video_streamer/favorites/favorites.dart';
import 'package:video_streamer/player/picture_in_picture.dart';
import 'package:video_streamer/player/screen_awake.dart';
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

/// 端末の小窓の代わりに、送られた状態を記録し、通知をテストから送れるようにする。
class FakePictureInPicture implements PictureInPicture {
  FakePictureInPicture({this.supported = true});

  final bool supported;
  final entered = <PictureInPictureState>[];
  final updated = <PictureInPictureState>[];
  bool autoEnterDisabled = false;

  final _modeChanges = StreamController<bool>.broadcast(sync: true);
  final _actions = StreamController<PictureInPictureAction>.broadcast(
    sync: true,
  );

  void changeMode(bool active) => _modeChanges.add(active);

  void sendAction(PictureInPictureAction action) => _actions.add(action);

  @override
  Stream<bool> get modeChanges => _modeChanges.stream;

  @override
  Stream<PictureInPictureAction> get actions => _actions.stream;

  @override
  Future<bool> isSupported() async => supported;

  @override
  Future<void> enter(PictureInPictureState state) async => entered.add(state);

  @override
  Future<void> update(PictureInPictureState state) async => updated.add(state);

  @override
  Future<void> disableAutoEnter() async => autoEnterDisabled = true;
}

/// 端末の代わりに、画面を消灯させない状態かを記録する。
class FakeScreenAwake implements ScreenAwake {
  bool keepOn = false;

  @override
  Future<void> setKeepOn(bool keepOn) async => this.keepOn = keepOn;
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

  /// 実際のコントローラーの dispose は非同期で、終わるまでの間に通知が届くことがある。
  bool notifiesWhileDisposing = false;

  bool _playWhenReady = false;

  /// 実機と同じく、バッファリング中は isPlaying を false にする。
  void startBuffering() =>
      value = value.copyWith(isPlaying: false, isBuffering: true);

  void endBuffering() =>
      value = value.copyWith(isPlaying: _playWhenReady, isBuffering: false);

  @override
  int get playerId => VideoPlayerController.kUninitializedPlayerId;

  @override
  Future<void> initialize() async {
    value = value.copyWith(isInitialized: true, size: const Size(1920, 1080));
  }

  @override
  Future<void> play() async {
    _playWhenReady = true;
    value = value.copyWith(isPlaying: true);
  }

  @override
  Future<void> pause() async {
    _playWhenReady = false;
    value = value.copyWith(isPlaying: false);
  }

  @override
  Future<void> seekTo(Duration position) async =>
      value = value.copyWith(position: position);

  @override
  Future<void> dispose() async {
    disposed = true;
    if (notifiesWhileDisposing) {
      await null;
      value = value.copyWith(position: const Duration(seconds: 1));
    }
    super.dispose();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
