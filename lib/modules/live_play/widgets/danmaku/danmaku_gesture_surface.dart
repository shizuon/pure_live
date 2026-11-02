import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

typedef DanmakuActionResolver = VoidCallback? Function(Offset position, {required bool longPress});

/// Resolves moving text on pointer-down, then acts only after the gesture wins.
/// Looking it up in onTap/onLongPress instead can hit a different message after
/// the double-tap/long-press timeout. Drags and double taps must not copy text.
class DanmakuGestureSurface extends StatefulWidget {
  const DanmakuGestureSurface({
    super.key,
    required this.resolveAction,
    required this.child,
    this.onBackgroundTap,
    this.onDoubleTap,
    this.onPanStart,
  });

  final DanmakuActionResolver resolveAction;
  final Widget child;
  final VoidCallback? onBackgroundTap;
  final VoidCallback? onDoubleTap;
  final GestureDragStartCallback? onPanStart;

  @override
  State<DanmakuGestureSurface> createState() => _DanmakuGestureSurfaceState();
}

class _DanmakuGestureSurfaceState extends State<DanmakuGestureSurface> {
  VoidCallback? _tapAction;
  VoidCallback? _longPressAction;
  int? _pointer;

  void _clearActions() {
    _tapAction = null;
    _longPressAction = null;
  }

  @override
  Widget build(BuildContext context) => Listener(
    onPointerDown: (event) {
      _clearActions();
      if (_pointer != null || event.buttons != kPrimaryButton) return;
      _pointer = event.pointer;
      _tapAction = widget.resolveAction(event.position, longPress: false);
      _longPressAction = widget.resolveAction(event.position, longPress: true);
    },
    onPointerUp: (event) {
      if (_pointer == event.pointer) _pointer = null;
      // A single tap can still be waiting for the double-tap timeout here.
    },
    onPointerCancel: (_) {
      _pointer = null;
      _clearActions();
    },
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        final action = _tapAction;
        _clearActions();
        (action ?? widget.onBackgroundTap)?.call();
      },
      onTapCancel: () => _tapAction = null,
      onLongPressStart: (_) {
        final action = _longPressAction;
        _clearActions();
        action?.call();
      },
      onDoubleTap: widget.onDoubleTap == null
          ? null
          : () {
              _clearActions();
              widget.onDoubleTap!();
            },
      onPanStart: widget.onPanStart,
      child: widget.child,
    ),
  );
}
