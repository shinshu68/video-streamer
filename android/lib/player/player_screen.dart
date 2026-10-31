import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:video_player/video_player.dart';

import '../api/models.dart';
import '../api/providers.dart';
import '../favorites/favorite_button.dart';

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
class PlayerScreen extends StatefulWidget {
  const PlayerScreen({
    super.key,
    required this.entries,
    required this.initialIndex,
  });

  final List<Entry> entries;
  final int initialIndex;

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  late final _pageController = PageController(initialPage: widget.initialIndex);
  late int _current = widget.initialIndex;
  bool? _fullscreen;

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

  @override
  Widget build(BuildContext context) {
    final fullscreen = _fullscreen!;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: fullscreen
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
  });

  final Entry entry;
  final bool active;
  final bool fullscreen;

  @override
  ConsumerState<_VideoPage> createState() => _VideoPageState();
}

class _VideoPageState extends ConsumerState<_VideoPage> {
  static const _skip = Duration(seconds: 10);

  VideoPlayerController? _controller;
  Future<void>? _initialized;

  @override
  void initState() {
    super.initState();
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
    _controller?.dispose();
    super.dispose();
  }

  void _start() {
    final controller = ref.read(videoControllerFactoryProvider)(
      widget.entry.path,
    );
    _controller = controller;
    _initialized = controller.initialize().then((_) => controller.play());
  }

  void _stop() {
    _controller?.dispose();
    _controller = null;
    _initialized = null;
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
            final progress = VideoProgressIndicator(
              controller,
              allowScrubbing: true,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            );
            final controls = _Controls(
              value: value,
              onPlayPause: value.isPlaying ? controller.pause : controller.play,
              onBack: () => _seekBy(-_skip),
              onForward: () => _seekBy(_skip),
            );
            if (widget.fullscreen) {
              return _FullscreenLayout(
                title: widget.entry.name,
                isPlaying: value.isPlaying,
                video: video,
                favorite: FavoriteButton(entry: widget.entry),
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
                        child: FavoriteButton(entry: widget.entry),
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
    required this.favorite,
    required this.progress,
    required this.controls,
  });

  static const hideAfter = Duration(seconds: 3);

  final String title;
  final bool isPlaying;
  final Widget video;
  final Widget favorite;
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
                          child: widget.favorite,
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
