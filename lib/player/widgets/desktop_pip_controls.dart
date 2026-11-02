import 'package:flutter/material.dart';

/// A separate hit-test layer lets hidden controls release the entire video
/// surface for dragging and double-click restoration, including the centre.
class DesktopPipControls extends StatelessWidget {
  const DesktopPipControls({
    super.key,
    required this.visible,
    required this.playing,
    required this.danmakuEnabled,
    required this.onTogglePlayback,
    required this.onToggleDanmaku,
    required this.onRestore,
    required this.restoreLabel,
    required this.danmakuLabel,
  });

  final bool visible, playing, danmakuEnabled;
  final VoidCallback onTogglePlayback, onToggleDanmaku, onRestore;
  final String restoreLabel, danmakuLabel;

  @override
  Widget build(BuildContext context) => IgnorePointer(
    ignoring: !visible,
    child: AnimatedOpacity(
      opacity: visible ? 1 : 0,
      duration: const Duration(milliseconds: 160),
      child: Stack(
        fit: StackFit.expand,
        children: [
          Center(
            child: IconButton(
              key: const ValueKey('desktop-pip-playback'),
              iconSize: 40,
              style: IconButton.styleFrom(backgroundColor: Colors.black54),
              icon: Icon(playing ? Icons.pause_circle_filled : Icons.play_circle_filled, color: Colors.white),
              onPressed: onTogglePlayback,
            ),
          ),
          Positioned(
            top: 6,
            left: 6,
            child: IconButton(
              key: const ValueKey('desktop-pip-danmaku'),
              tooltip: danmakuLabel,
              style: IconButton.styleFrom(backgroundColor: Colors.black54),
              icon: Icon(danmakuEnabled ? Icons.subtitles : Icons.subtitles_off, color: Colors.white),
              onPressed: onToggleDanmaku,
            ),
          ),
          Positioned(
            top: 6,
            right: 6,
            child: IconButton(
              key: const ValueKey('desktop-pip-restore'),
              tooltip: restoreLabel,
              style: IconButton.styleFrom(backgroundColor: Colors.black54),
              icon: const Icon(Icons.picture_in_picture_alt, color: Colors.white),
              onPressed: onRestore,
            ),
          ),
        ],
      ),
    ),
  );
}
