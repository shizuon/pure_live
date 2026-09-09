import 'dart:math' as math;
import 'dart:ui';

enum CropHandle {
  topLeft,
  top,
  topRight,
  left,
  center,
  right,
  bottomLeft,
  bottom,
  bottomRight;

  Offset get position => Offset((index % 3) / 2, (index ~/ 3) / 2);
}

/// Session-only coordinates, independent of window size and stream resolution.
class CommentaryOverlayLayout {
  const CommentaryOverlayLayout({
    this.crop = const Rect.fromLTWH(0, 0, 1, 1),
    this.anchor = const Offset(0.95, 0.85),
    this.widthFraction = 0.25,
  });

  final Rect crop;
  // Fraction of the free space, so both edges remain reachable on resize.
  final Offset anchor;
  final double widthFraction;

  CommentaryOverlayLayout copyWith({Rect? crop, Offset? anchor, double? widthFraction}) => CommentaryOverlayLayout(
    crop: crop ?? this.crop,
    anchor: anchor ?? this.anchor,
    widthFraction: widthFraction ?? this.widthFraction,
  );

  static Rect selection(Offset start, Offset end, Size size) {
    Offset normalize(Offset point) =>
        Offset((point.dx / size.width).clamp(0.0, 1.0), (point.dy / size.height).clamp(0.0, 1.0));
    return Rect.fromPoints(normalize(start), normalize(end));
  }

  static bool validCrop(Rect crop) =>
      crop.isFinite &&
      crop.left >= 0 &&
      crop.top >= 0 &&
      crop.right <= 1 &&
      crop.bottom <= 1 &&
      crop.width >= 0.02 &&
      crop.height >= 0.02;

  static Rect adjustCrop(Rect crop, CropHandle handle, Offset delta) {
    if (!validCrop(crop) || !delta.isFinite) return crop;
    if (handle == CropHandle.center) {
      return crop.shift(Offset(delta.dx.clamp(-crop.left, 1 - crop.right), delta.dy.clamp(-crop.top, 1 - crop.bottom)));
    }
    final position = handle.position;
    // Leave a sub-pixel epsilon so subtraction cannot round below validCrop's
    // minimum and hide the handles at the smallest selection size.
    const minimum = 0.020000001;
    return Rect.fromLTRB(
      position.dx == 0 ? (crop.left + delta.dx).clamp(0, math.max(0, crop.right - minimum)) : crop.left,
      position.dy == 0 ? (crop.top + delta.dy).clamp(0, math.max(0, crop.bottom - minimum)) : crop.top,
      position.dx == 1 ? (crop.right + delta.dx).clamp(math.min(1, crop.left + minimum), 1) : crop.right,
      position.dy == 1 ? (crop.bottom + delta.dy).clamp(math.min(1, crop.top + minimum), 1) : crop.bottom,
    );
  }

  Rect bounds(Size viewport, double sourceAspectRatio) {
    final ratio = sourceAspectRatio * crop.width / crop.height;
    final width = math.min(viewport.width * widthFraction, viewport.height * 0.75 * ratio);
    final height = width / ratio;
    return Rect.fromLTWH((viewport.width - width) * anchor.dx, (viewport.height - height) * anchor.dy, width, height);
  }

  CommentaryOverlayLayout move(Offset delta, Size viewport, double sourceAspectRatio) {
    final rect = bounds(viewport, sourceAspectRatio);
    final freeWidth = viewport.width - rect.width;
    final freeHeight = viewport.height - rect.height;
    return copyWith(
      anchor: Offset(
        freeWidth > 0 ? ((rect.left + delta.dx) / freeWidth).clamp(0.0, 1.0) : 0,
        freeHeight > 0 ? ((rect.top + delta.dy) / freeHeight).clamp(0.0, 1.0) : 0,
      ),
    );
  }

  CommentaryOverlayLayout resize(double delta, Size viewport, double sourceAspectRatio) {
    final old = bounds(viewport, sourceAspectRatio);
    final resized = copyWith(widthFraction: ((old.width + delta) / viewport.width).clamp(0.1, 0.8));
    final next = resized.bounds(viewport, sourceAspectRatio);
    // Keep the top-left corner fixed while dragging the bottom-right handle.
    return resized.copyWith(
      anchor: Offset(
        (old.left / math.max(1, viewport.width - next.width)).clamp(0.0, 1.0),
        (old.top / math.max(1, viewport.height - next.height)).clamp(0.0, 1.0),
      ),
    );
  }
}
