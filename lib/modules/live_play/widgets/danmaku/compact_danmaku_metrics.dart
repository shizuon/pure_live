import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// Shared by the live overlay and settings preview. Desktop mini windows need
/// a readable minimum size even when the window is narrowed for a portrait feed.
double resolveCompactDanmakuScale({required double width, required bool autoScale, required bool macos}) {
  if (!autoScale) return 1.0;
  final safeWidth = width.isFinite && width > 0 ? width : 350.0;
  return (safeWidth / 350.0).clamp(macos ? 0.85 : 0.65, 1.0).toDouble();
}

/// Refresh rate is not a MediaQuery field. Observe display metrics directly so
/// moving between equal-DPI monitors still updates the compact renderer budget.
class CompactDanmakuDisplay extends StatefulWidget {
  const CompactDanmakuDisplay({super.key, required this.builder});

  final Widget Function(BuildContext context, double? macosRefreshRate) builder;

  @override
  State<CompactDanmakuDisplay> createState() => _CompactDanmakuDisplayState();
}

class _CompactDanmakuDisplayState extends State<CompactDanmakuDisplay> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeMetrics() {
    if (defaultTargetPlatform == TargetPlatform.macOS) setState(() {});
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(
    context,
    defaultTargetPlatform == TargetPlatform.macOS ? View.of(context).display.refreshRate : null,
  );
}
