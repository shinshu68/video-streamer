import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:video_streamer/api/models.dart';
import 'package:video_streamer/favorites/favorites.dart';
import 'package:video_streamer/player/picture_in_picture.dart';
import 'package:video_streamer/player/player_screen.dart';
import 'package:video_streamer/player/screen_awake.dart';

import '../helpers.dart';

const portrait = Size(1080, 2400);
const landscape = Size(2400, 1080);

const videos = [
  Entry(type: EntryType.video, id: 'A', name: '動画A.mp4', path: '動画A.mp4'),
  Entry(type: EntryType.video, id: 'B', name: '動画B.mp4', path: '動画B.mp4'),
  Entry(type: EntryType.video, id: 'C', name: '動画C.mp4', path: '動画C.mp4'),
];

/// [videos] の [initialIndex] 番目から再生画面を [size] の画面で開き、
/// 送られたシステム UI のモードを記録する。作ったコントローラーは [controllers] に入れる。
Future<List<String>> pumpPlayer(
  WidgetTester tester,
  Size size, {
  int initialIndex = 0,
  List<FakeVideoPlayerController>? controllers,
  FavoritesStorage? favorites,
  PictureInPicture? pictureInPicture,
  ScreenAwake? screenAwake,
}) async {
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
        favoritesStorageProvider.overrideWithValue(
          favorites ?? InMemoryFavoritesStorage(),
        ),
        pictureInPictureProvider.overrideWithValue(
          pictureInPicture ?? FakePictureInPicture(),
        ),
        screenAwakeProvider.overrideWithValue(screenAwake ?? FakeScreenAwake()),
        videoControllerFactoryProvider.overrideWithValue((path) {
          final controller = FakeVideoPlayerController(path);
          controllers?.add(controller);
          return controller;
        }),
      ],
      child: MaterialApp(
        home: PlayerScreen(entries: videos, initialIndex: initialIndex),
      ),
    ),
  );
  await tester.pump();
  return systemUiModes;
}

Future<void> swipe(WidgetTester tester, double dy) async {
  await tester.fling(find.byType(PageView), Offset(0, dy), 1000);
  await tester.pumpAndSettle();
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

  testWidgets('上にスワイプすると次の動画を再生し、前の動画を破棄する', (tester) async {
    final controllers = <FakeVideoPlayerController>[];
    await pumpPlayer(tester, portrait, controllers: controllers);

    await swipe(tester, -300);

    expect(find.text('動画B.mp4'), findsOneWidget);
    expect(controllers.map((c) => c.path), ['動画A.mp4', '動画B.mp4']);
    expect(controllers[0].disposed, isTrue);
    expect(controllers[1].value.isPlaying, isTrue);
  });

  testWidgets('下にスワイプすると前の動画を再生する', (tester) async {
    final controllers = <FakeVideoPlayerController>[];
    await pumpPlayer(
      tester,
      portrait,
      initialIndex: 1,
      controllers: controllers,
    );

    await swipe(tester, 300);

    expect(find.text('動画A.mp4'), findsOneWidget);
    expect(controllers.last.path, '動画A.mp4');
  });

  testWidgets('先頭より前、末尾より後には切り替えない', (tester) async {
    final controllers = <FakeVideoPlayerController>[];
    await pumpPlayer(tester, portrait, controllers: controllers);
    await swipe(tester, 300);
    expect(find.text('動画A.mp4'), findsOneWidget);

    await swipe(tester, -300);
    await swipe(tester, -300);
    await swipe(tester, -300);
    expect(find.text('動画C.mp4'), findsOneWidget);
    expect(controllers.map((c) => c.path), ['動画A.mp4', '動画B.mp4', '動画C.mp4']);
  });

  testWidgets('縦向きではハートのボタンでお気に入りを付け外しする', (tester) async {
    final storage = InMemoryFavoritesStorage();
    await pumpPlayer(tester, portrait, favorites: storage);

    await tester.tap(find.byTooltip('お気に入りに追加'));
    await tester.pump();
    expect(storage.saved.map((f) => f.id), ['A']);

    await tester.tap(find.byTooltip('お気に入りから外す'));
    await tester.pump();
    expect(storage.saved, isEmpty);
  });

  testWidgets('ハートのボタンは切り替えた先の動画を対象にする', (tester) async {
    final storage = InMemoryFavoritesStorage();
    await pumpPlayer(tester, portrait, favorites: storage);

    await swipe(tester, -300);
    await tester.tap(find.byTooltip('お気に入りに追加'));
    await tester.pump();

    expect(storage.saved.map((f) => f.id), ['B']);
  });

  testWidgets('横向きでは操作を出したときだけハートのボタンを出す', (tester) async {
    await pumpPlayer(tester, landscape);
    expect(find.byTooltip('お気に入りに追加'), findsNothing);

    await tapScreenCenter(tester);

    expect(find.byTooltip('お気に入りに追加'), findsOneWidget);
  });

  testWidgets('識別子のない動画にはハートのボタンを出さない', (tester) async {
    await tester.pumpWidget(
      testScope(
        overrides: [
          pictureInPictureProvider.overrideWithValue(FakePictureInPicture()),
          screenAwakeProvider.overrideWithValue(FakeScreenAwake()),
          videoControllerFactoryProvider.overrideWithValue(
            FakeVideoPlayerController.new,
          ),
        ],
        child: const MaterialApp(
          home: PlayerScreen(
            entries: [
              Entry(type: EntryType.video, name: '動画A.mp4', path: '動画A.mp4'),
            ],
            initialIndex: 0,
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.byTooltip('お気に入りに追加'), findsNothing);
  });

  testWidgets('横向きではスワイプしても切り替えない', (tester) async {
    final controllers = <FakeVideoPlayerController>[];
    await pumpPlayer(tester, landscape, controllers: controllers);

    await tester.fling(find.byType(PageView), const Offset(0, -300), 1000);
    await tester.pump();
    await rotate(tester, portrait);

    expect(find.text('動画A.mp4'), findsOneWidget);
    expect(controllers.map((c) => c.path), ['動画A.mp4']);
  });

  group('画面の消灯', () {
    testWidgets('再生中は消灯させず、一時停止すると元に戻す', (tester) async {
      final screen = FakeScreenAwake();
      await pumpPlayer(tester, portrait, screenAwake: screen);
      await tester.pump();
      expect(screen.keepOn, isTrue);

      await tester.tap(find.byTooltip('一時停止'));
      await tester.pump();
      expect(screen.keepOn, isFalse);

      await tester.tap(find.byTooltip('再生'));
      await tester.pump();
      expect(screen.keepOn, isTrue);
    });

    testWidgets('再生画面を離れると元に戻す', (tester) async {
      final screen = FakeScreenAwake();
      await pumpPlayer(tester, portrait, screenAwake: screen);
      await tester.pump();

      await tester.pumpWidget(const SizedBox());

      expect(screen.keepOn, isFalse);
    });

    testWidgets('次の動画に切り替えても再生中は消灯させない', (tester) async {
      final screen = FakeScreenAwake();
      await pumpPlayer(tester, portrait, screenAwake: screen);
      await tester.pump();

      await swipe(tester, -300);

      expect(screen.keepOn, isTrue);
    });
  });

  group('ピクチャーインピクチャー', () {
    const button = 'ピクチャーインピクチャー';

    /// 再生画面をボタンから小窓に入った状態にする。
    Future<void> enter(WidgetTester tester, FakePictureInPicture pip) async {
      await tester.tap(find.byTooltip(button));
      pip.changeMode(true);
      await tester.pump();
    }

    testWidgets('縦向きではハートの隣のボタンで、再生の状態を添えて小窓に入る', (tester) async {
      final pip = FakePictureInPicture();
      await pumpPlayer(tester, portrait, pictureInPicture: pip);
      await tester.pump();

      await tester.tap(find.byTooltip(button));

      final state = pip.entered.single;
      expect(state.size, const Size(1920, 1080));
      expect(state.isPlaying, isTrue);
      expect(state.hasPrevious, isFalse);
      expect(state.hasNext, isTrue);
    });

    testWidgets('縦向きではボタンをハートの下に並べる', (tester) async {
      await pumpPlayer(tester, portrait);
      await tester.pump();

      expect(
        tester.getCenter(find.byTooltip(button)).dy,
        greaterThan(tester.getCenter(find.byTooltip('お気に入りに追加')).dy),
      );
    });

    testWidgets('横向きではボタンをハートの右に並べる', (tester) async {
      await pumpPlayer(tester, landscape);
      await tapScreenCenter(tester);
      await tester.pump();

      final pictureInPicture = tester.getCenter(find.byTooltip(button));
      final favorite = tester.getCenter(find.byTooltip('お気に入りに追加'));
      expect(pictureInPicture.dx, greaterThan(favorite.dx));
      expect(pictureInPicture.dy, favorite.dy);
    });

    testWidgets('再生中か一時停止中かを小窓に入る前から伝える', (tester) async {
      final pip = FakePictureInPicture();
      await pumpPlayer(tester, portrait, pictureInPicture: pip);
      await tester.pump();
      await tester.pump();
      expect(pip.updated.last.isPlaying, isTrue);

      await tester.tap(find.byTooltip('一時停止'));
      await tester.pump();
      await tester.pump();
      expect(pip.updated.last.isPlaying, isFalse);
    });

    testWidgets('再生画面を離れると自動で小窓に入らないようにする', (tester) async {
      final pip = FakePictureInPicture();
      await pumpPlayer(tester, portrait, pictureInPicture: pip);
      expect(pip.autoEnterDisabled, isFalse);

      await tester.pumpWidget(const SizedBox());

      expect(pip.autoEnterDisabled, isTrue);
    });

    testWidgets('横向きでは操作を出したときだけボタンを出す', (tester) async {
      await pumpPlayer(tester, landscape);
      await tester.pump();
      expect(find.byTooltip(button), findsNothing);

      await tapScreenCenter(tester);
      await tester.pump();
      expect(find.byTooltip(button), findsOneWidget);
    });

    testWidgets('対応していない端末ではボタンを出さない', (tester) async {
      await pumpPlayer(
        tester,
        portrait,
        pictureInPicture: FakePictureInPicture(supported: false),
      );
      await tester.pump();

      expect(find.byTooltip(button), findsNothing);
    });

    testWidgets('小窓の中では動画だけを出し、戻ると元の画面に戻る', (tester) async {
      final pip = FakePictureInPicture();
      await pumpPlayer(tester, portrait, pictureInPicture: pip);
      await tester.pump();

      await enter(tester, pip);
      expect(find.byType(AppBar), findsNothing);
      expect(find.byTooltip('一時停止'), findsNothing);
      expect(find.byTooltip(button), findsNothing);

      pip.changeMode(false);
      await tester.pump();
      expect(find.byType(AppBar), findsOneWidget);
      expect(find.byTooltip('一時停止'), findsOneWidget);
    });

    testWidgets('小窓の再生ボタンで一時停止と再開を切り替え、状態を小窓に反映する', (tester) async {
      final pip = FakePictureInPicture();
      final controllers = <FakeVideoPlayerController>[];
      await pumpPlayer(
        tester,
        portrait,
        controllers: controllers,
        pictureInPicture: pip,
      );
      await tester.pump();
      await enter(tester, pip);

      pip.sendAction(PictureInPictureAction.playPause);
      await tester.pump();
      expect(controllers.single.value.isPlaying, isFalse);
      expect(pip.updated.last.isPlaying, isFalse);

      pip.sendAction(PictureInPictureAction.playPause);
      await tester.pump();
      expect(controllers.single.value.isPlaying, isTrue);
      expect(pip.updated.last.isPlaying, isTrue);
    });

    testWidgets('再生の状態が変わらない間は小窓に送り直さない', (tester) async {
      final pip = FakePictureInPicture();
      final controllers = <FakeVideoPlayerController>[];
      await pumpPlayer(
        tester,
        portrait,
        controllers: controllers,
        pictureInPicture: pip,
      );
      await tester.pump();
      await enter(tester, pip);
      await tester.pump();
      final sent = pip.updated.length;

      await controllers.single.seekTo(const Duration(seconds: 5));
      await tester.pump();

      expect(pip.updated, hasLength(sent));
    });

    testWidgets('小窓の次へと前へで動画を切り替え、端の動画ではボタンの状態を反映する', (tester) async {
      final pip = FakePictureInPicture();
      final controllers = <FakeVideoPlayerController>[];
      await pumpPlayer(
        tester,
        portrait,
        initialIndex: 1,
        controllers: controllers,
        pictureInPicture: pip,
      );
      await tester.pump();
      await enter(tester, pip);

      pip.sendAction(PictureInPictureAction.next);
      await tester.pump();
      await tester.pump();
      expect(controllers.last.path, '動画C.mp4');
      expect(controllers.first.disposed, isTrue);
      expect(controllers.last.value.isPlaying, isTrue);
      expect(pip.updated.last.hasPrevious, isTrue);
      expect(pip.updated.last.hasNext, isFalse);

      pip.sendAction(PictureInPictureAction.previous);
      await tester.pump();
      await tester.pump();
      expect(controllers.last.path, '動画B.mp4');
    });

    testWidgets('端の動画では小窓の前へで切り替えない', (tester) async {
      final pip = FakePictureInPicture();
      final controllers = <FakeVideoPlayerController>[];
      await pumpPlayer(
        tester,
        portrait,
        controllers: controllers,
        pictureInPicture: pip,
      );
      await tester.pump();
      await enter(tester, pip);

      pip.sendAction(PictureInPictureAction.previous);
      await tester.pump();

      expect(controllers.map((c) => c.path), ['動画A.mp4']);
    });
  });
}
