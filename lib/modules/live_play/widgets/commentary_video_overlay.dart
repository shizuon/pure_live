import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:pure_live/get/get.dart' show Obx;
import 'package:rxdart/rxdart.dart';
import 'package:pure_live/modules/live_play/controllers/commentary_sync_controller.dart';
import 'package:pure_live/modules/live_play/states/commentary_overlay_layout.dart';
import 'package:pure_live/player/interface/unified_player_interface.dart';

/// Shares B's existing player. Preview, crop editor and overlay never render it
/// simultaneously (important for native video output sizing on Windows/macOS).
class CommentaryVideoOverlay extends StatelessWidget {
  const CommentaryVideoOverlay({
    super.key,
    required this.sync,
    required this.controlsVisible,
    required this.controlsLocked,
    required this.onInteraction,
  });

  final CommentarySyncController sync;
  final bool controlsVisible;
  final bool controlsLocked;
  final VoidCallback onInteraction;

  @override
  Widget build(BuildContext context) => Obx(() {
    final state = sync.state.value;
    final player = sync.companionPreviewPlayer;
    if (!state.isEngaged ||
        state.previewVisible ||
        player == null ||
        (!state.overlayEditing && !state.overlayEnabled)) {
      return const SizedBox.shrink();
    }
    return Positioned.fill(
      child: _SourceSizedOverlay(
        key: ObjectKey(player),
        player: player,
        sync: sync,
        controlsVisible: controlsVisible,
        controlsLocked: controlsLocked,
        onInteraction: onInteraction,
      ),
    );
  });
}

class _SourceSizedOverlay extends StatefulWidget {
  const _SourceSizedOverlay({
    super.key,
    required this.player,
    required this.sync,
    required this.controlsVisible,
    required this.controlsLocked,
    required this.onInteraction,
  });
  final UnifiedPlayer player;
  final CommentarySyncController sync;
  final bool controlsVisible;
  final bool controlsLocked;
  final VoidCallback onInteraction;

  @override
  State<_SourceSizedOverlay> createState() => _SourceSizedOverlayState();
}

class _SourceSizedOverlayState extends State<_SourceSizedOverlay> {
  late final video = widget.player.getVideoWidget(BoxFit.contain);
  late final sizes = CombineLatestStream.combine2(
    widget.player.width,
    widget.player.height,
    (int? width, int? height) => (width: width, height: height),
  );

  @override
  Widget build(BuildContext context) => StreamBuilder(
    stream: sizes,
    builder: (context, snapshot) {
      final width = snapshot.data?.width ?? 0;
      final height = snapshot.data?.height ?? 0;
      final ready = width > 0 && height > 0;
      final ratio = ready ? width / height : 16 / 9;
      return Obx(() {
        final state = widget.sync.state.value;
        if (state.overlayEditing) {
          return _CropEditor(
            aspectRatio: ratio,
            ready: ready && state.isActive,
            initialCrop: state.overlayLayout.crop,
            video: state.isActive ? video : const SizedBox.shrink(),
            onCancel: widget.sync.cancelOverlayCrop,
            onConfirm: widget.sync.confirmOverlayCrop,
          );
        }
        return LayoutBuilder(
          builder: (context, constraints) {
            final viewport = constraints.biggest;
            if (viewport.isEmpty) return const SizedBox.shrink();
            final layout = state.overlayLayout;
            final bounds = layout.bounds(viewport, ratio);
            final editing = widget.controlsVisible && !widget.controlsLocked;
            return Stack(
              children: [
                Positioned.fromRect(
                  rect: bounds,
                  child: MouseRegion(
                    cursor: editing ? SystemMouseCursors.move : MouseCursor.defer,
                    child: GestureDetector(
                      key: const ValueKey('commentary-overlay-move'),
                      behavior: HitTestBehavior.opaque,
                      dragStartBehavior: DragStartBehavior.down,
                      onTap: widget.onInteraction,
                      onPanUpdate: editing
                          ? (event) {
                              widget.onInteraction();
                              widget.sync.updateOverlayLayout(
                                widget.sync.state.value.overlayLayout.move(event.delta, viewport, ratio),
                              );
                            }
                          : null,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          // Lay out the whole source at its true aspect ratio, then
                          // translate it behind a hard clip; never stretch the face.
                          if (state.isActive)
                            ClipRect(
                              child: OverflowBox(
                                alignment: Alignment.topLeft,
                                minWidth: bounds.width / layout.crop.width,
                                maxWidth: bounds.width / layout.crop.width,
                                minHeight: bounds.height / layout.crop.height,
                                maxHeight: bounds.height / layout.crop.height,
                                child: Transform.translate(
                                  offset: Offset(
                                    -layout.crop.left * bounds.width / layout.crop.width,
                                    -layout.crop.top * bounds.height / layout.crop.height,
                                  ),
                                  child: IgnorePointer(child: video),
                                ),
                              ),
                            ),
                          if (!ready || !state.isActive)
                            const ColoredBox(
                              color: Colors.black87,
                              child: Center(
                                child: Text('B 画面暂不可用', style: TextStyle(color: Colors.white)),
                              ),
                            ),
                          if (editing) ...[
                            IgnorePointer(
                              child: DecoratedBox(
                                decoration: BoxDecoration(border: Border.all(color: Colors.white70, width: 2)),
                              ),
                            ),
                            Positioned(
                              top: 0,
                              right: 0,
                              child: ConstrainedBox(
                                constraints: BoxConstraints(maxWidth: bounds.width),
                                child: FittedBox(
                                  fit: BoxFit.scaleDown,
                                  child: ColoredBox(
                                    color: Colors.black54,
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        IconButton(
                                          tooltip: '重新选区',
                                          onPressed: widget.sync.beginOverlayCrop,
                                          icon: const Icon(Icons.crop, color: Colors.white, size: 18),
                                        ),
                                        IconButton(
                                          tooltip: '关闭画面覆盖（保留 B 声音）',
                                          onPressed: widget.sync.disableOverlay,
                                          icon: const Icon(Icons.close, color: Colors.white, size: 18),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            Positioned(
                              right: 0,
                              bottom: 0,
                              child: MouseRegion(
                                cursor: SystemMouseCursors.resizeDownRight,
                                child: GestureDetector(
                                  key: const ValueKey('commentary-overlay-resize'),
                                  behavior: HitTestBehavior.opaque,
                                  dragStartBehavior: DragStartBehavior.down,
                                  onPanUpdate: (event) {
                                    widget.onInteraction();
                                    widget.sync.updateOverlayLayout(
                                      widget.sync.state.value.overlayLayout.resize(event.delta.dx, viewport, ratio),
                                    );
                                  },
                                  child: const SizedBox(
                                    width: 32,
                                    height: 32,
                                    child: ColoredBox(
                                      color: Colors.black54,
                                      child: Icon(Icons.open_in_full, color: Colors.white, size: 18),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        );
      });
    },
  );
}

class _CropEditor extends StatefulWidget {
  const _CropEditor({
    required this.aspectRatio,
    required this.ready,
    required this.initialCrop,
    required this.video,
    required this.onCancel,
    required this.onConfirm,
  });
  final double aspectRatio;
  final bool ready;
  final Rect initialCrop;
  final Widget video;
  final VoidCallback onCancel;
  final ValueChanged<Rect> onConfirm;

  @override
  State<_CropEditor> createState() => _CropEditorState();
}

class _CropEditorState extends State<_CropEditor> {
  late Rect crop = widget.initialCrop;
  Offset? start;

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.black87,
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          const Text('框选 B 画面中要覆盖的区域（例如主播的脸）', style: TextStyle(color: Colors.white)),
          const SizedBox(height: 8),
          Expanded(
            child: Center(
              child: AspectRatio(
                aspectRatio: widget.aspectRatio,
                child: LayoutBuilder(
                  builder: (context, constraints) => GestureDetector(
                    key: const ValueKey('commentary-crop-selection'),
                    behavior: HitTestBehavior.opaque,
                    dragStartBehavior: DragStartBehavior.down,
                    onPanStart: widget.ready ? (event) => start = event.localPosition : null,
                    onPanUpdate: widget.ready
                        ? (event) {
                            final origin = start;
                            if (origin != null) {
                              setState(() {
                                crop = CommentaryOverlayLayout.selection(
                                  origin,
                                  event.localPosition,
                                  constraints.biggest,
                                );
                              });
                            }
                          }
                        : null,
                    onPanEnd: (_) => start = null,
                    onPanCancel: () => start = null,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        IgnorePointer(child: widget.video),
                        IgnorePointer(child: CustomPaint(painter: _CropPainter(crop))),
                        if (!widget.ready)
                          const Center(
                            child: Text('等待 B 视频尺寸…', style: TextStyle(color: Colors.white)),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          Wrap(
            spacing: 12,
            alignment: WrapAlignment.center,
            children: [
              TextButton(onPressed: widget.onCancel, child: const Text('取消')),
              TextButton(
                onPressed: () => setState(() => crop = const Rect.fromLTWH(0, 0, 1, 1)),
                child: const Text('整个画面'),
              ),
              FilledButton(
                onPressed: widget.ready && CommentaryOverlayLayout.validCrop(crop)
                    ? () => widget.onConfirm(crop)
                    : null,
                child: const Text('覆盖到 A 画面'),
              ),
            ],
          ),
        ],
      ),
    ),
  );
}

class _CropPainter extends CustomPainter {
  const _CropPainter(this.crop);
  final Rect crop;
  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromLTWH(
      crop.left * size.width,
      crop.top * size.height,
      crop.width * size.width,
      crop.height * size.height,
    );
    final mask = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(Offset.zero & size)
      ..addRect(rect);
    canvas.drawPath(mask, Paint()..color = Colors.black54);
    canvas.drawRect(
      rect,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(_CropPainter oldDelegate) => oldDelegate.crop != crop;
}
