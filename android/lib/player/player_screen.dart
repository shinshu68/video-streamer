import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:video_player/video_player.dart';

import '../api/models.dart';
import '../api/providers.dart';
import '../favorites/favorite_button.dart';
import 'picture_in_picture.dart';

/// 動画の相対パスから、配信 URL を再生するコントローラーを作る関数。
final videoControllerFactoryProvider =
    Provider<VideoPlayerController Function(String path)>((ref) {
      final client = ref.watch(apiClientProvider);
      return (path) => VideoPlayerController.networkUrl(client.mediaUri(path));
    });

/// [entries] の動画を、[initialIndex] の動画から配信 URL で再生する画面。
///
/// 縦向きでは上下のスワイプで前後の動画に切り替える。
/// 端末を横向きにすると全画面になり、ステータスバーとナビゲーションバーを隠す。
/// ピクチャーインピクチャーの小窓では動画だけを出す。
class PlayerScreen extends ConsumerStatefulWidget {
  const PlayerScreen({
    super.key,
    required this.entries,
    required this.initialIndex,
  });

  final List<Entry> entries;
  final int initialIndex;

  @override
  ConsumerState<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends ConsumerState<PlayerScreen> {
  late final _pageController = PageController(initialPage: widget.initialIndex);
  late int _current = widget.initialIndex;
  bool? _fullscreen;
  bool _pictureInPicture = false;
  late final StreamSubscription<bool> _modeChanges;
  late final StreamSubscription<PictureInPictureAction> _actions;

  @override
  void initState() {
    super.initState();
    final pictureInPicture = ref.read(pictureInPictureProvider);
    _modeChanges = pictureInPicture.modeChanges.listen(
      (active) => setState(() => _pictureInPicture = active),
    );
    _actions = pictureInPicture.actions.listen(_onPictureInPictureAction);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final fullscreen =
        MediaQuery.orientationOf(context) == Orientation.landscape;
    if (fullscreen != _fullscreen) {
      _fullscreen = fullscreen;
      SystemChrome.setEnabledSystemUIMode(
        fullscreen ? SystemUiMode.immersiveSticky : SystemUiMode.edgeToEdge,
      );
    }
  }

  @override
  void dispose() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    _modeChanges.cancel();
    _actions.cancel();
    _pageController.dispose();
    super.dispose();
  }

  // onPageChanged はスワイプの途中で呼ばれるため、止まってから切り替える。
  // 途中で切り替えると、指を戻したときに元の動画を読み込み直すことになる。
  bool _onScrollEnd(ScrollEndNotification notification) {
    if (notification.depth == 0) {
      final page = _pageController.page!.round();
      if (page != _current) {
        setState(() => _current = page);
      }
    }
    return false;
  }

  void _onPictureInPictureAction(PictureInPictureAction action) {
    final page = switch (action) {
      PictureInPictureAction.previous => _current - 1,
      PictureInPictureAction.next => _current + 1,
      PictureInPictureAction.playPause => _current,
    };
    if (page != _current && page >= 0 && page < widget.entries.length) {
      _pageController.jumpToPage(page);
    }
  }

  @override
  Widget build(BuildContext context) {
    final fullscreen = _fullscreen!;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: fullscreen || _pictureInPicture
          ? null
          : AppBar(
              title: Text(widget.entries[_current].name),
              backgroundColor: Colors.black,
              foregroundColor: Colors.white,
            ),
      body: NotificationListener<ScrollEndNotification>(
        onNotification: _onScrollEnd,
        child: PageView.builder(
          controller: _pageController,
          scrollDirection: Axis.vertical,
          // 全画面では、上下の端からのスワイプがシステム UI を出す操作と重なる。
          physics: fullscreen ? const NeverScrollableScrollPhysics() : null,
          itemCount: widget.entries.length,
          itemBuilder: (context, i) => _VideoPage(
            entry: widget.entries[i],
            active: i == _current,
            fullscreen: fullscreen,
            pictureInPicture: _pictureInPicture,
            hasPrevious: i > 0,
            hasNext: i < widget.entries.length - 1,
          ),
        ),
      ),
    );
  }
}

/// [entry] の動画のページ。[active] の間だけ動画を読み込んで再生する。
class _VideoPage extends ConsumerStatefulWidget {
  const _VideoPage({
    required this.entry,
    required this.active,
    required this.fullscreen,
    required this.pictureInPicture,
    required this.hasPrevious,
    required this.hasNext,
  });

  final Entry entry;
  final bool active;
  final bool fullscreen;
  final bool pictureInPicture;
  final bool hasPrevious;
  final bool hasNext;

  @override
  ConsumerState<_VideoPage> createState() => _VideoPageState();
}

class _VideoPageState extends ConsumerState<_VideoPage> {
  static const _skip = Duration(seconds: 10);

  VideoPlayerController? _controller;
  Future<void>? _initialized;
  PictureInPictureState? _sentState;
  late final StreamSubscription<PictureInPictureAction> _actions;

  @override
  void initState() {
    super.initState();
    _actions = ref
        .read(pictureInPictureProvider)
        .actions
        .where((action) => action == PictureInPictureAction.playPause)
        .listen((_) => _togglePlayPause());
    if (widget.active) {
      _start();
    }
  }

  @override
  void didUpdateWidget(_VideoPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active != oldWidget.active) {
      widget.active ? _start() : _stop();
    }
  }

  @override
  void dispose() {
    _actions.cancel();
    _controller?.dispose();
    super.dispose();
  }

  void _start() {
    final controller = ref.read(videoControllerFactoryProvider)(
      widget.entry.path,
    );
    _controller = controller;
    controller.addListener(_updatePictureInPicture);
    _updatePictureInPicture();
    _initialized = controller.initialize().then((_) => controller.play());
  }

  void _stop() {
    _controller?.dispose();
    _controller = null;
    _initialized = null;
  }

  void _togglePlayPause() {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
      return;
    }
    controller.value.isPlaying ? controller.pause() : controller.play();
  }

  PictureInPictureState _pictureInPictureState() {
    final value = _controller!.value;
    return (
      size: value.size,
      isPlaying: value.isPlaying,
      hasPrevious: widget.hasPrevious,
      hasNext: widget.hasNext,
    );
  }

  void _enterPictureInPicture() {
    final state = _pictureInPictureState();
    _sentState = state;
    ref.read(pictureInPictureProvider).enter(state);
  }

  void _updatePictureInPicture() {
    if (!widget.pictureInPicture) {
      return;
    }
    final state = _pictureInPictureState();
    if (state != _sentState) {
      _sentState = state;
      ref.read(pictureInPictureProvider).update(state);
    }
  }

  void _seekBy(Duration offset) {
    final controller = _controller!;
    final value = controller.value;
    var target = value.position + offset;
    if (target < Duration.zero) {
      target = Duration.zero;
    } else if (target > value.duration) {
      target = value.duration;
    }
    controller.seekTo(target);
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    if (controller == null) {
      return const SizedBox.expand();
    }
    return FutureBuilder(
      future: _initialized,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return const _Message('動画を再生できません');
        }
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        return ValueListenableBuilder(
          valueListenable: controller,
          builder: (context, value, _) {
            if (value.hasError) {
              return const _Message('再生中にエラーが発生しました');
            }
            final video = Center(
              child: AspectRatio(
                aspectRatio: value.aspectRatio,
                child: VideoPlayer(controller),
              ),
            );
            if (widget.pictureInPicture) {
              return video;
            }
            final favoriteButton = FavoriteButton(entry: widget.entry);
            final pictureInPictureButton = _PictureInPictureButton(
              onPressed: _enterPictureInPicture,
            );
            final progress = VideoProgressIndicator(
              controller,
              allowScrubbing: true,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            );
            final controls = _Controls(
              value: value,
              onPlayPause: _togglePlayPause,
              onBack: () => _seekBy(-_skip),
              onForward: () => _seekBy(_skip),
            );
            if (widget.fullscreen) {
              return _FullscreenLayout(
                title: widget.entry.name,
                isPlaying: value.isPlaying,
                video: video,
                actions: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [favoriteButton, pictureInPictureButton],
                ),
                progress: progress,
                controls: controls,
              );
            }
            return Column(
              children: [
                Expanded(
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      video,
                      Positioned(
                        right: 8,
                        bottom: 8,
                        child: Column(
                          children: [favoriteButton, pictureInPictureButton],
                        ),
                      ),
                    ],
                  ),
                ),
                progress,
                controls,
              ],
            );
          },
        );
      },
    );
  }
}

/// 動画を画面いっぱいに出し、タップしたときだけ操作を重ねて出すレイアウト。
///
/// 再生中は、最後に触れてから [hideAfter] たつと操作を隠す。
class _FullscreenLayout extends StatefulWidget {
  const _FullscreenLayout({
    required this.title,
    required this.isPlaying,
    required this.video,
    required this.actions,
    required this.progress,
    required this.controls,
  });

  static const hideAfter = Duration(seconds: 3);

  final String title;
  final bool isPlaying;
  final Widget video;
  final Widget actions;
  final Widget progress;
  final Widget controls;

  @override
  State<_FullscreenLayout> createState() => _FullscreenLayoutState();
}

class _FullscreenLayoutState extends State<_FullscreenLayout> {
  bool _overlayVisible = false;
  Timer? _hideTimer;

  @override
  void didUpdateWidget(_FullscreenLayout oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isPlaying && !oldWidget.isPlaying && _overlayVisible) {
      _scheduleHide();
    }
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    super.dispose();
  }

  void _toggleOverlay() {
    setState(() => _overlayVisible = !_overlayVisible);
    if (_overlayVisible) {
      _scheduleHide();
    } else {
      _hideTimer?.cancel();
    }
  }

  void _scheduleHide() {
    _hideTimer?.cancel();
    _hideTimer = Timer(_FullscreenLayout.hideAfter, () {
      if (widget.isPlaying) {
        setState(() => _overlayVisible = false);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _toggleOverlay,
          child: widget.video,
        ),
        if (_overlayVisible)
          Listener(
            onPointerDown: (_) => _scheduleHide(),
            child: SafeArea(
              child: Column(
                children: [
                  ColoredBox(
                    color: Colors.black54,
                    child: Row(
                      children: [
                        const BackButton(color: Colors.white),
                        Expanded(
                          child: Text(
                            widget.title,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Spacer(),
                  ColoredBox(
                    color: Colors.black54,
                    child: Column(
                      children: [
                        Align(
                          alignment: Alignment.centerRight,
                          child: widget.actions,
                        ),
                        widget.progress,
                        widget.controls,
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

/// ピクチャーインピクチャーの小窓に入るボタン。対応していない端末では何も出さない。
class _PictureInPictureButton extends ConsumerWidget {
  const _PictureInPictureButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (ref.watch(pictureInPictureSupportedProvider).value != true) {
      return const SizedBox.shrink();
    }
    return IconButton(
      icon: const Icon(
        Icons.picture_in_picture_alt,
        color: Colors.white,
        // 明るい動画に重ねても見えるようにする。
        shadows: [Shadow(blurRadius: 4)],
      ),
      tooltip: 'ピクチャーインピクチャー',
      onPressed: onPressed,
    );
  }
}

class _Controls extends StatelessWidget {
  const _Controls({
    required this.value,
    required this.onPlayPause,
    required this.onBack,
    required this.onForward,
  });

  final VideoPlayerValue value;
  final VoidCallback onPlayPause;
  final VoidCallback onBack;
  final VoidCallback onForward;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: IconTheme(
        data: const IconThemeData(color: Colors.white),
        child: Row(
          children: [
            const SizedBox(width: 16),
            Text(
              '${formatPosition(value.position)} / ${formatPosition(value.duration)}',
              style: const TextStyle(color: Colors.white),
            ),
            const Spacer(),
            IconButton(
              icon: const Icon(Icons.replay_10),
              tooltip: '10秒戻る',
              onPressed: onBack,
            ),
            IconButton(
              icon: Icon(value.isPlaying ? Icons.pause : Icons.play_arrow),
              tooltip: value.isPlaying ? '一時停止' : '再生',
              iconSize: 40,
              onPressed: onPlayPause,
            ),
            IconButton(
              icon: const Icon(Icons.forward_10),
              tooltip: '10秒進む',
              onPressed: onForward,
            ),
            const SizedBox(width: 8),
          ],
        ),
      ),
    );
  }
}

/// 再生位置を `1:02:03` や `2:03` のような表記にする。
String formatPosition(Duration d) {
  String two(int n) => n.toString().padLeft(2, '0');
  final minutes = d.inMinutes.remainder(60);
  final seconds = two(d.inSeconds.remainder(60));
  return d.inHours > 0
      ? '${d.inHours}:${two(minutes)}:$seconds'
      : '$minutes:$seconds';
}

class _Message extends StatelessWidget {
  const _Message(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(text, style: const TextStyle(color: Colors.white)),
    );
  }
}
