import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:video_player/video_player.dart';

import '../api/models.dart';
import '../api/providers.dart';

/// [entry] の動画を配信 URL から再生する画面。
class PlayerScreen extends ConsumerStatefulWidget {
  const PlayerScreen({super.key, required this.entry});

  final Entry entry;

  @override
  ConsumerState<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends ConsumerState<PlayerScreen> {
  static const _skip = Duration(seconds: 10);

  late final VideoPlayerController _controller;
  late final Future<void> _initialized;

  @override
  void initState() {
    super.initState();
    final uri = ref.read(apiClientProvider).mediaUri(widget.entry.path);
    _controller = VideoPlayerController.networkUrl(uri);
    _initialized = _controller.initialize().then((_) => _controller.play());
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _seekBy(Duration offset) {
    final value = _controller.value;
    var target = value.position + offset;
    if (target < Duration.zero) {
      target = Duration.zero;
    } else if (target > value.duration) {
      target = value.duration;
    }
    _controller.seekTo(target);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text(widget.entry.name),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
      ),
      body: FutureBuilder(
        future: _initialized,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return const _Message('動画を再生できません');
          }
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          return ValueListenableBuilder(
            valueListenable: _controller,
            builder: (context, value, _) {
              if (value.hasError) {
                return const _Message('再生中にエラーが発生しました');
              }
              return Column(
                children: [
                  Expanded(
                    child: Center(
                      child: AspectRatio(
                        aspectRatio: value.aspectRatio,
                        child: VideoPlayer(_controller),
                      ),
                    ),
                  ),
                  VideoProgressIndicator(
                    _controller,
                    allowScrubbing: true,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                  ),
                  _Controls(
                    value: value,
                    onPlayPause: value.isPlaying
                        ? _controller.pause
                        : _controller.play,
                    onBack: () => _seekBy(-_skip),
                    onForward: () => _seekBy(_skip),
                  ),
                ],
              );
            },
          );
        },
      ),
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
