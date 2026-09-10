import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../utils/video_output_size_policy.dart';

/// Keeps desktop BGRA textures close to the visible physical viewport.
/// Resizing is debounced so dragging a window does not recreate the texture on
/// every pointer event. This bounded output existed in the last known-good
/// 2.9.8 path and was removed before 3.0.7.
class ViewportSizedVideo extends StatefulWidget {
  const ViewportSizedVideo({
    super.key,
    required this.controller,
    required this.constrainToViewport,
    required this.sourceWidth,
    required this.sourceHeight,
    required this.child,
  });

  final VideoController controller;
  final bool constrainToViewport;
  final Stream<int?> sourceWidth;
  final Stream<int?> sourceHeight;
  final Widget child;

  @override
  State<ViewportSizedVideo> createState() => _ViewportSizedVideoState();
}

class _ViewportSizedVideoState extends State<ViewportSizedVideo> {
  static const _resizeDebounce = Duration(milliseconds: 180);

  StreamSubscription<int?>? _widthSubscription;
  StreamSubscription<int?>? _heightSubscription;
  Timer? _resizeTimer;
  int? _sourceWidth;
  int? _sourceHeight;
  Size? _logicalViewport;
  double _devicePixelRatio = 1;
  Size? _requestedSize;
  bool _hasRequestedSize = false;

  @override
  void initState() {
    super.initState();
    _bindSourceDimensions();
  }

  @override
  void didUpdateWidget(covariant ViewportSizedVideo oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.sourceWidth, widget.sourceWidth) ||
        !identical(oldWidget.sourceHeight, widget.sourceHeight)) {
      unawaited(_cancelSourceSubscriptions());
      _bindSourceDimensions();
    }
    if (!identical(oldWidget.controller, widget.controller)) {
      _hasRequestedSize = false;
      _scheduleResize();
    } else if (oldWidget.constrainToViewport != widget.constrainToViewport) {
      _scheduleResize();
    }
  }

  void _bindSourceDimensions() {
    _widthSubscription = widget.sourceWidth.distinct().listen((value) {
      _sourceWidth = value;
      _scheduleResize();
    });
    _heightSubscription = widget.sourceHeight.distinct().listen((value) {
      _sourceHeight = value;
      _scheduleResize();
    });
  }

  Future<void> _cancelSourceSubscriptions() async {
    final widthSubscription = _widthSubscription;
    final heightSubscription = _heightSubscription;
    _widthSubscription = null;
    _heightSubscription = null;
    await Future.wait<void>([
      if (widthSubscription != null) widthSubscription.cancel(),
      if (heightSubscription != null) heightSubscription.cancel(),
    ]);
  }

  void _scheduleResize() {
    final viewport = _logicalViewport;
    if (viewport == null) return;
    final target = widget.constrainToViewport
        ? calculateVideoOutputSize(
            logicalViewport: viewport,
            devicePixelRatio: _devicePixelRatio,
            sourceWidth: _sourceWidth,
            sourceHeight: _sourceHeight,
          )
        : null;
    // Cancel even when returning to the applied size: an older pending resize
    // must not overwrite it after a quick fullscreen/fit round trip.
    _resizeTimer?.cancel();
    if ((target != null && target.isEmpty) || (_hasRequestedSize && target == _requestedSize)) return;
    _resizeTimer = Timer(_resizeDebounce, () async {
      if (!mounted) return;
      _requestedSize = target;
      _hasRequestedSize = true;
      try {
        // Null removes the explicit size override and follows source changes.
        await widget.controller.setSize(width: target?.width.toInt(), height: target?.height.toInt());
      } catch (_) {
        // The native output can be disposed while a room/window transition is
        // completing. The next mounted output publishes its size again.
      }
    });
  }

  @override
  void dispose() {
    _resizeTimer?.cancel();
    unawaited(_cancelSourceSubscriptions());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final viewport = Size(constraints.maxWidth, constraints.maxHeight);
        final pixelRatio = MediaQuery.devicePixelRatioOf(context);
        if (_logicalViewport != viewport || _devicePixelRatio != pixelRatio) {
          _logicalViewport = viewport;
          _devicePixelRatio = pixelRatio;
          _scheduleResize();
        }
        return widget.child;
      },
    );
  }
}
