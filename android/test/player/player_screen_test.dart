import 'package:flutter_test/flutter_test.dart';
import 'package:video_streamer/player/player_screen.dart';

void main() {
  test('formatPosition は1時間未満を分:秒、以上を時:分:秒で表す', () {
    expect(formatPosition(Duration.zero), '0:00');
    expect(formatPosition(const Duration(minutes: 2, seconds: 3)), '2:03');
    expect(
      formatPosition(const Duration(hours: 1, minutes: 2, seconds: 3)),
      '1:02:03',
    );
  });
}
