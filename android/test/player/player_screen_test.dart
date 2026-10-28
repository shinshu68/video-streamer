import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:video_player/video_player.dart';
import 'package:video_streamer/api/models.dart';
import 'package:video_streamer/player/player_screen.dart';

import '../helpers.dart';

/// プラットフォームの再生機能を使わずに、再生中の状態だけを持つコントローラー。
class FakeVideoPlayerController extends ValueNotifier<VideoPlayerValue>
    implements VideoPlayerController {
  FakeVideoPlayerController()
    : super(VideoPlayerValue(duration: const Duration(minutes: 1)));

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
  Future<void> dispose() async => super.dispose();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

const portrait = Size(1080, 2400);
const landscape = Size(2400, 1080);

/// 再生画面を [size] の画面で開き、送られたシステム UI のモードを記録する。
Future<List<String>> pumpPlayer(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  addTearDown(tester.view.reset);
  final systemUiModes = <String>[];
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    SystemChannels.platform,
    (call) async {
      if (call.method == 'SystemChrome.setEnabledSystemUIMode') {
        systemUiModes.add(call.arguments as String);
      }
      return null;
    },
  );
  await tester.pumpWidget(
    testScope(
      overrides: [
        videoControllerFactoryProvider.overrideWithValue(
          (_) => FakeVideoPlayerController(),
        ),
      ],
      child: const MaterialApp(
        home: PlayerScreen(
          entry: Entry(type: EntryType.video, name: '動画A.mp4', path: '動画A.mp4'),
        ),
      ),
    ),
  );
  await tester.pump();
  return systemUiModes;
}

Future<void> rotate(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  await tester.pump();
}

Future<void> tapScreenCenter(WidgetTester tester) async {
  await tester.tapAt(tester.getCenter(find.byType(Scaffold)));
  await tester.pump();
}

void main() {
  test('formatPosition は1時間未満を分:秒、以上を時:分:秒で表す', () {
    expect(formatPosition(Duration.zero), '0:00');
    expect(formatPosition(const Duration(minutes: 2, seconds: 3)), '2:03');
    expect(
      formatPosition(const Duration(hours: 1, minutes: 2, seconds: 3)),
      '1:02:03',
    );
  });

  testWidgets('縦向きではタイトルバーと操作を常に出し、システム UI を隠さない', (tester) async {
    final modes = await pumpPlayer(tester, portrait);

    expect(find.byType(AppBar), findsOneWidget);
    expect(find.byTooltip('一時停止'), findsOneWidget);
    expect(modes.last, 'SystemUiMode.edgeToEdge');
  });

  testWidgets('横向きではタイトルバーと操作を隠して全画面にし、システム UI を隠す', (tester) async {
    final modes = await pumpPlayer(tester, landscape);

    expect(find.byType(AppBar), findsNothing);
    expect(find.byTooltip('一時停止'), findsNothing);
    expect(modes.last, 'SystemUiMode.immersiveSticky');
  });

  testWidgets('横向きでは画面をタップすると操作を出し、もう一度タップすると隠す', (tester) async {
    await pumpPlayer(tester, landscape);

    await tapScreenCenter(tester);
    expect(find.text('動画A.mp4'), findsOneWidget);
    expect(find.byTooltip('一時停止'), findsOneWidget);

    await tapScreenCenter(tester);
    expect(find.byTooltip('一時停止'), findsNothing);
  });

  testWidgets('横向きで再生中は、最後に触れてから3秒で操作を隠す', (tester) async {
    await pumpPlayer(tester, landscape);
    await tapScreenCenter(tester);

    await tester.pump(const Duration(seconds: 2));
    await tester.tap(find.byTooltip('10秒進む'));
    await tester.pump(const Duration(seconds: 2));
    expect(find.byTooltip('一時停止'), findsOneWidget);

    await tester.pump(const Duration(seconds: 1));
    expect(find.byTooltip('一時停止'), findsNothing);
  });

  testWidgets('横向きで一時停止中は操作を隠さず、再生を再開すると3秒で隠す', (tester) async {
    await pumpPlayer(tester, landscape);
    await tapScreenCenter(tester);

    await tester.tap(find.byTooltip('一時停止'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 5));
    expect(find.byTooltip('再生'), findsOneWidget);

    await tester.tap(find.byTooltip('再生'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 3));
    expect(find.byTooltip('一時停止'), findsNothing);
  });

  testWidgets('向きを変えるとレイアウトとシステム UI を切り替える', (tester) async {
    final modes = await pumpPlayer(tester, portrait);

    await rotate(tester, landscape);
    expect(find.byType(AppBar), findsNothing);
    expect(modes.last, 'SystemUiMode.immersiveSticky');

    await rotate(tester, portrait);
    expect(find.byType(AppBar), findsOneWidget);
    expect(modes.last, 'SystemUiMode.edgeToEdge');
  });

  testWidgets('横向きのまま画面を離れるとシステム UI を元に戻す', (tester) async {
    final modes = await pumpPlayer(tester, landscape);

    await tester.pumpWidget(const SizedBox());
    expect(modes.last, 'SystemUiMode.edgeToEdge');
  });
}
