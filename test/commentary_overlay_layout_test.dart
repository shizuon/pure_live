import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:pure_live/modules/live_play/states/commentary_overlay_layout.dart';
import 'package:pure_live/modules/live_play/states/commentary_sync_state.dart';

void main() {
  test('nine crop handles resize or translate inside the source', () {
    const crop = Rect.fromLTRB(0.2, 0.2, 0.7, 0.8);
    for (final handle in CropHandle.values) {
      for (final delta in [const Offset(-10, -10), const Offset(10, 10)]) {
        final result = CommentaryOverlayLayout.adjustCrop(crop, handle, delta);
        expect(result.left, greaterThanOrEqualTo(0));
        expect(result.top, greaterThanOrEqualTo(0));
        expect(result.right, lessThanOrEqualTo(1));
        expect(result.bottom, lessThanOrEqualTo(1));
        expect(result.width, greaterThanOrEqualTo(0.02 - 1e-9));
        expect(result.height, greaterThanOrEqualTo(0.02 - 1e-9));
        if (handle == CropHandle.center) {
          expect(result.width, closeTo(crop.width, 1e-9));
          expect(result.height, closeTo(crop.height, 1e-9));
        }
      }
    }
    final resized = CommentaryOverlayLayout.adjustCrop(crop, CropHandle.right, const Offset(0.1, 0.1));
    expect(resized.right, closeTo(0.8, 1e-9));
    expect(resized.left, crop.left);
    expect(resized.top, crop.top);
    expect(resized.bottom, crop.bottom);
  });
  test('crop accepts reverse drags and clamps to source, not letterbox', () {
    final crop = CommentaryOverlayLayout.selection(
      const Offset(800, 450),
      const Offset(-40, 180),
      const Size(800, 450),
    );
    expect(crop, const Rect.fromLTRB(0, 0.4, 1, 1));
    expect(CommentaryOverlayLayout.validCrop(crop), isTrue);
    expect(CommentaryOverlayLayout.validCrop(Rect.zero), isFalse);
    expect(CommentaryOverlayLayout.validCrop(const Rect.fromLTWH(-0.1, 0, 1, 1)), isFalse);
  });

  test('overlay preserves crop aspect and stays bounded on drag/fullscreen/resize', () {
    const layout = CommentaryOverlayLayout(crop: Rect.fromLTWH(0.6, 0.2, 0.3, 0.5));
    for (final viewport in [const Size(320, 180), const Size(1920, 1080), const Size(300, 700)]) {
      final moved = layout.move(const Offset(10000, -10000), viewport, 16 / 9);
      final rect = moved.bounds(viewport, 16 / 9);
      expect(rect.left, closeTo(viewport.width - rect.width, 0.001));
      expect(rect.top, 0);
      expect(rect.width / rect.height, closeTo(16 / 9 * 0.3 / 0.5, 0.001));
      for (final delta in [-10000.0, 10000.0]) {
        final resized = moved.resize(delta, viewport, 16 / 9).bounds(viewport, 16 / 9);
        expect(resized.left, greaterThanOrEqualTo(0));
        expect(resized.top, greaterThanOrEqualTo(0));
        expect(resized.right, lessThanOrEqualTo(viewport.width + 0.001));
        expect(resized.bottom, lessThanOrEqualTo(viewport.height + 0.001));
      }
    }
  });

  test('video is required by preview, crop editor OR enabled overlay', () {
    const state = CommentarySyncState();
    expect(state.needsCompanionVideo, isFalse);
    expect(state.copyWith(previewVisible: true).needsCompanionVideo, isTrue);
    expect(state.copyWith(overlayEditing: true).needsCompanionVideo, isTrue);
    expect(state.copyWith(overlayEnabled: true).needsCompanionVideo, isTrue);
    expect(state.copyWith(overlayEnabled: true).copyWith(previewVisible: false).needsCompanionVideo, isTrue);
  });
}
