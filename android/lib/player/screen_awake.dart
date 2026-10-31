import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 端末の画面を消灯させないようにする。
abstract interface class ScreenAwake {
  /// [keepOn] が true の間は、端末の画面を消灯させない。
  Future<void> setKeepOn(bool keepOn);
}

/// MainActivity の実装を MethodChannel で呼ぶ [ScreenAwake]。
class MethodChannelScreenAwake implements ScreenAwake {
  static const _channel = MethodChannel('com.shinshu68.video_streamer/screen');

  @override
  Future<void> setKeepOn(bool keepOn) =>
      _channel.invokeMethod('setKeepOn', keepOn);
}

final screenAwakeProvider = Provider<ScreenAwake>(
  (ref) => MethodChannelScreenAwake(),
);
