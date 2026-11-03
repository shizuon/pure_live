import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';

/// Actions for the message under the pointer at press time, before tap versus
/// double-tap/long-press recognition lets the scrolling text move away.
class DanmakuPointerTarget {
  const DanmakuPointerTarget({this.onTap, this.onLongPress});

  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
}

class DanmakuGestureSurface extends StatefulWidget {
  const DanmakuGestureSurface({
    super.key,
    required this.captureTarget,
    required this.onBackgroundTap,
    required this.onDoubleTap,
    required this.child,
  });

  final DanmakuPointerTarget? Function(Offset globalPosition) captureTarget;
  final VoidCallback onBackgroundTap;
  final VoidCallback onDoubleTap;
  final Widget child;

  @override
  State<DanmakuGestureSurface> createState() => _DanmakuGestureSurfaceState();
}

class _DanmakuGestureSurfaceState extends State<DanmakuGestureSurface> {
  VoidCallback? _tap;
  VoidCallback? _longPress;
  VoidCallback? _secondaryTap;

  void _capture(PointerDownEvent event) {
    if (event.buttons != kPrimaryButton && event.buttons != kSecondaryButton) return;
    final target = widget.captureTarget(event.position);
    if (event.buttons == kSecondaryButton) {
      _secondaryTap = target?.onTap;
    } else {
      _tap = target?.onTap;
      _longPress = target?.onLongPress;
    }
  }

  void _clearPrimary() {
    _tap = null;
    _longPress = null;
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: _capture,
      onPointerCancel: (_) {
        _clearPrimary();
        _secondaryTap = null;
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          final action = _tap;
          _clearPrimary();
          (action ?? widget.onBackgroundTap)();
        },
        // Losing the tap arena to a long press must keep its separate target.
        onTapCancel: () => _tap = null,
        onLongPressStart: (_) {
          final action = _longPress;
          _clearPrimary();
          action?.call();
        },
        onLongPressCancel: () => _longPress = null,
        onSecondaryTap: () {
          final action = _secondaryTap;
          _secondaryTap = null;
          action?.call();
        },
        onSecondaryTapCancel: () => _secondaryTap = null,
        onDoubleTap: () {
          _clearPrimary();
          widget.onDoubleTap();
        },
        child: widget.child,
      ),
    );
  }
}
