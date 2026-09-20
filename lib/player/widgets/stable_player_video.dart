import 'package:flutter/widgets.dart';

import '../interface/unified_player_interface.dart';

/// Creates the adapter's video subtree once per mounted presentation. Offset
/// labels/overlay handles can rebuild without replacing its dimension stream.
/// A new mount creates a fresh subtree, never reusing a disposed subscription.
class StablePlayerVideo extends StatefulWidget {
  const StablePlayerVideo({super.key, required this.player, this.fit = BoxFit.contain});
  final UnifiedPlayer player;
  final BoxFit fit;
  @override
  State<StablePlayerVideo> createState() => _StablePlayerVideoState();
}

class _StablePlayerVideoState extends State<StablePlayerVideo> {
  late Widget _video = widget.player.getVideoWidget(widget.fit);
  @override
  void didUpdateWidget(StablePlayerVideo oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.player, widget.player) || oldWidget.fit != widget.fit) {
      _video = widget.player.getVideoWidget(widget.fit);
    }
  }

  @override
  Widget build(BuildContext context) => _video;
}
