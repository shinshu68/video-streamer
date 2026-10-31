import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 小窓の表示に使う再生の状態。[size] が 0 の間は縦横比を変えない。
typedef PictureInPictureState = ({
  Size size,
  bool isPlaying,
  bool hasPrevious,
  bool hasNext,
});

/// 小窓のボタンの操作。
enum PictureInPictureAction { previous, playPause, next }

/// ピクチャーインピクチャーの小窓を扱う。
abstract interface class PictureInPicture {
  /// 小窓に入り始めたか、小窓から戻ったかを通知する。
  ///
  /// Android 15 より前の端末では、小窓に入りきったときに通知する。
  Stream<bool> get modeChanges;

  /// 小窓のボタンの操作を通知する。
  Stream<PictureInPictureAction> get actions;

  /// この端末で小窓を使えるかを返す。
  Future<bool> isSupported();

  /// [state] の内容で小窓に入る。
  Future<void> enter(PictureInPictureState state);

  /// [state] を伝える。再生中はホームに戻ったときに自動で小窓に入り、
  /// 小窓の表示中はその内容に反映する。
  Future<void> update(PictureInPictureState state);

  /// ホームに戻ったときに自動で小窓に入らないようにする。
  Future<void> disableAutoEnter();
}

/// MainActivity の実装を MethodChannel で呼ぶ [PictureInPicture]。
class MethodChannelPictureInPicture implements PictureInPicture {
  MethodChannelPictureInPicture() {
    _channel.setMethodCallHandler(_onMethodCall);
  }

  static const _channel = MethodChannel(
    'com.shinshu68.video_streamer/picture_in_picture',
  );

  final _modeChanges = StreamController<bool>.broadcast();
  final _actions = StreamController<PictureInPictureAction>.broadcast();

  @override
  Stream<bool> get modeChanges => _modeChanges.stream;

  @override
  Stream<PictureInPictureAction> get actions => _actions.stream;

  @override
  Future<bool> isSupported() async =>
      await _channel.invokeMethod<bool>('isSupported') ?? false;

  @override
  Future<void> enter(PictureInPictureState state) =>
      _channel.invokeMethod('enter', _arguments(state));

  @override
  Future<void> update(PictureInPictureState state) =>
      _channel.invokeMethod('update', _arguments(state));

  @override
  Future<void> disableAutoEnter() => _channel.invokeMethod('disableAutoEnter');

  Map<String, Object> _arguments(PictureInPictureState state) => {
    'width': state.size.width.round(),
    'height': state.size.height.round(),
    'isPlaying': state.isPlaying,
    'hasPrevious': state.hasPrevious,
    'hasNext': state.hasNext,
  };

  Future<void> _onMethodCall(MethodCall call) async {
    switch (call.method) {
      case 'onModeChanged':
        _modeChanges.add(call.arguments as bool);
      case 'onAction':
        _actions.add(
          PictureInPictureAction.values.byName(call.arguments as String),
        );
    }
  }
}

final pictureInPictureProvider = Provider<PictureInPicture>(
  (ref) => MethodChannelPictureInPicture(),
);

final pictureInPictureSupportedProvider = FutureProvider<bool>(
  (ref) => ref.watch(pictureInPictureProvider).isSupported(),
);
