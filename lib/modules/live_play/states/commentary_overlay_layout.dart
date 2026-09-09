import 'dart:math' as math;
import 'dart:ui';

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
