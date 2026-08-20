import 'dart:async';

import 'package:pure_live/common/index.dart';
import 'package:pure_live/common/widgets/common_avatar.dart';
import 'package:pure_live/modules/live_play/controllers/danmaku_controller.dart';
import 'package:pure_live/modules/live_play/controllers/live_play_controller.dart';
import 'package:pure_live/modules/live_play/states/commentary_sync_state.dart';
import 'package:pure_live/modules/live_play/widgets/video_player/video_controller.dart';
import 'package:pure_live/plugins/event_bus.dart';
import 'package:pure_live/recorder/models/record_status.dart';

class CommentarySyncButton extends StatelessWidget {
  const CommentarySyncButton({super.key, required this.controller});

  final VideoController controller;

  @override
  Widget build(BuildContext context) {
    final sync = GlobalPlayerService.instance.commentarySyncController;
    return Obx(() {
      final engaged = sync.state.value.isEngaged;
      return IconButton(
        visualDensity: VisualDensity.compact,
        tooltip: engaged ? i18n('commentary_sync_settings') : i18n('commentary_choose_source'),
        color: engaged ? Theme.of(context).colorScheme.primary : Colors.white,
        icon: Icon(engaged ? Icons.record_voice_over : Icons.spatial_audio_off, size: 21),
        onPressed: () {
          controller.enableController();
          if (controller.isAudioOnly) {
            ToastUtil.show(i18n('commentary_audio_only_conflict'));
            return;
          }
          if (!engaged && _isRecording(controller.room)) {
            ToastUtil.show(i18n('commentary_stop_recording_first'));
            return;
          }
          if (engaged) {
            Get.dialog(CommentarySyncDialog(controller: controller));
          } else {
            showCommentarySourceDialog(controller);
          }
        },
      );
    });
  }
}

bool _isRecording(LiveRoom room) {
  final tasks = Get.find<LivePlayController>().recorderController.tasks;
  final task = tasks.firstWhereOrNull((item) => item.platform == room.platform && item.roomId == room.roomId);
  return task?.status == RecordStatus.running ||
      task?.status == RecordStatus.reconnecting ||
      task?.status == RecordStatus.preparing;
}

class CommentarySyncBadge extends StatelessWidget {
  const CommentarySyncBadge({super.key, required this.controller});

  final VideoController controller;

  @override
  Widget build(BuildContext context) {
    final sync = GlobalPlayerService.instance.commentarySyncController;
    final danmaku = Get.find<LivePlayController>().danmakuController;
    return Obx(() {
      final state = sync.state.value;
      if (!state.isEngaged) return const SizedBox.shrink();
      final danmakuRoom = danmaku.selectedSource.value == CommentaryDanmakuSource.commentary
          ? state.audioRoom
          : state.videoRoom;
      final label = switch (state.status) {
        CommentarySyncStatus.loading => i18n('commentary_connecting'),
        CommentarySyncStatus.calibrating => i18n('commentary_calibrating'),
        CommentarySyncStatus.reconnecting => i18n('commentary_reconnecting'),
        CommentarySyncStatus.error => i18n('commentary_failed'),
        _ =>
          '${i18n('commentary_video')}: ${state.videoRoom?.nick ?? '-'}  ·  '
              '${i18n('commentary_audio')}: ${state.audioRoom?.nick ?? '-'}  ·  '
              '${i18n('commentary_danmaku')}: ${danmakuRoom?.nick ?? '-'}  ·  '
              '${formatCommentaryOffset(state.offsetMs)}',
      };
      return Positioned(
        top: 58,
        left: 16,
        right: 16,
        child: Align(
          alignment: Alignment.topCenter,
          child: GestureDetector(
            onTap: () => Get.dialog(CommentarySyncDialog(controller: controller)),
            child: Container(
              constraints: const BoxConstraints(maxWidth: 620),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: BoxDecoration(
                color: state.status == CommentarySyncStatus.error
                    ? Colors.red.shade800
                    : Colors.black.withValues(alpha: 0.72),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: Colors.white24),
              ),
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white),
              ),
            ),
          ),
        ),
      );
    });
  }
}

class CommentarySyncDialog extends StatelessWidget {
  const CommentarySyncDialog({super.key, required this.controller});

  final VideoController controller;

  @override
  Widget build(BuildContext context) {
    final sync = GlobalPlayerService.instance.commentarySyncController;
    final liveController = Get.find<LivePlayController>();
    final danmaku = liveController.danmakuController;
    return Obx(() {
      final state = sync.state.value;
      final selectedDanmaku = danmaku.selectedSource.value;
      final commentaryDanmakuSupported = danmaku.supportsRoom(state.audioRoom);
      return AlertDialog(
        title: Text(i18n('commentary_sync_settings')),
        content: SizedBox(
          width: 430,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('${i18n('commentary_video')}: ${state.videoRoom?.nick ?? '-'}'),
              const SizedBox(height: 4),
              Text('${i18n('commentary_audio')}: ${state.audioRoom?.nick ?? '-'}'),
              const SizedBox(height: 14),
              Text(i18n('commentary_danmaku_source'), style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  ChoiceChip(
                    label: Text('A · ${state.videoRoom?.nick ?? i18n('commentary_video')}'),
                    selected: selectedDanmaku == CommentaryDanmakuSource.video,
                    onSelected: (_) async {
                      final switched = await danmaku.selectSource(CommentaryDanmakuSource.video);
                      if (!switched) {
                        ToastUtil.show(i18n('commentary_danmaku_switch_failed'));
                      }
                    },
                  ),
                  ChoiceChip(
                    label: Text('B · ${state.audioRoom?.nick ?? i18n('commentary_audio')}'),
                    selected: selectedDanmaku == CommentaryDanmakuSource.commentary,
                    onSelected: commentaryDanmakuSupported
                        ? (_) async {
                            final switched = await danmaku.selectSource(CommentaryDanmakuSource.commentary);
                            if (!switched) {
                              ToastUtil.show(i18n('commentary_danmaku_switch_failed'));
                            }
                          }
                        : null,
                  ),
                ],
              ),
              if (selectedDanmaku == CommentaryDanmakuSource.commentary) ...[
                const SizedBox(height: 8),
                Text(
                  i18n(
                    'commentary_danmaku_delay_help',
                    args: {'delay': formatCommentaryOffset(danmaku.effectiveDelayMs.value)},
                  ),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
              const SizedBox(height: 16),
              Center(
                child: Text(
                  formatCommentaryOffset(state.offsetMs),
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton(
                    onPressed: state.isActive ? () => sync.adjustOffset(-10) : null,
                    child: Text('${i18n('commentary_advance')} 10ms'),
                  ),
                  OutlinedButton(
                    onPressed: state.isActive ? () => sync.adjustOffset(-500) : null,
                    child: Text('${i18n('commentary_advance')} 500ms'),
                  ),
                  OutlinedButton(
                    onPressed: state.isActive ? () => sync.adjustOffset(-100) : null,
                    child: Text('${i18n('commentary_advance')} 100ms'),
                  ),
                  OutlinedButton(
                    onPressed: state.isActive ? () => sync.adjustOffset(100) : null,
                    child: Text('${i18n('commentary_delay')} 100ms'),
                  ),
                  OutlinedButton(
                    onPressed: state.isActive ? () => sync.adjustOffset(10) : null,
                    child: Text('${i18n('commentary_delay')} 10ms'),
                  ),
                  OutlinedButton(
                    onPressed: state.isActive ? () => sync.adjustOffset(500) : null,
                    child: Text('${i18n('commentary_delay')} 500ms'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                i18n('commentary_offset_help'),
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall,
              ),
              if (state.message != null) ...[
                const SizedBox(height: 12),
                Text(state.message!, textAlign: TextAlign.center),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: state.isActive
                ? () {
                    sync.showCalibrationPreview();
                    Navigator.pop(context);
                  }
                : null,
            child: Text(i18n('commentary_show_calibration')),
          ),
          TextButton(
            onPressed: () async {
              await danmaku.selectSource(CommentaryDanmakuSource.video);
              if (!context.mounted) return;
              Navigator.pop(context);
              showCommentarySourceDialog(controller);
            },
            child: Text(i18n('commentary_change_source')),
          ),
          TextButton(onPressed: () => sync.resetOffset(), child: Text(i18n('commentary_reset_offset'))),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              await sync.resync();
            },
            child: Text(i18n('commentary_resync')),
          ),
          TextButton(
            onPressed: () async {
              await danmaku.selectSource(CommentaryDanmakuSource.video);
              await sync.exit();
              if (context.mounted) Navigator.pop(context);
            },
            child: Text(i18n('commentary_exit')),
          ),
        ],
      );
    });
  }
}

class CommentaryCalibrationPreview extends StatelessWidget {
  const CommentaryCalibrationPreview({super.key, required this.controller});

  final VideoController controller;

  @override
  Widget build(BuildContext context) {
    final sync = GlobalPlayerService.instance.commentarySyncController;
    return Obx(() {
      final state = sync.state.value;
      if (!state.isEngaged || !state.previewVisible) {
        return const SizedBox.shrink();
      }
      final previewPlayer = sync.companionPreviewPlayer;
      final screenWidth = MediaQuery.sizeOf(context).width;
      final previewWidth = (screenWidth * 0.34).clamp(300.0, 460.0);
      return Positioned(
        top: 96,
        right: 16,
        width: previewWidth,
        child: Material(
          color: Colors.black,
          elevation: 16,
          borderRadius: BorderRadius.circular(10),
          clipBehavior: Clip.antiAlias,
          child: DecoratedBox(
            decoration: BoxDecoration(
              border: Border.all(color: Colors.white54),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  height: 38,
                  padding: const EdgeInsets.only(left: 12, right: 4),
                  color: Colors.black87,
                  child: Row(
                    children: [
                      const Icon(Icons.picture_in_picture_alt, color: Colors.white, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '${i18n('commentary_preview_title')} · ${state.audioRoom?.nick ?? '-'}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                        ),
                      ),
                      TextButton(
                        onPressed: sync.finishCalibrationPreview,
                        child: Text(i18n('commentary_finish_calibration')),
                      ),
                    ],
                  ),
                ),
                AspectRatio(
                  aspectRatio: 16 / 9,
                  child: ColoredBox(
                    color: Colors.black,
                    child:
                        previewPlayer?.getVideoWidget(BoxFit.contain) ??
                        Center(
                          child: Text(
                            i18n('commentary_preview_loading'),
                            style: const TextStyle(color: Colors.white70),
                          ),
                        ),
                  ),
                ),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
                  color: Colors.black87,
                  child: Column(
                    children: [
                      Text(
                        '${i18n('commentary_preview_help')}  ·  ${formatCommentaryOffset(state.offsetMs)}',
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.white70),
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        alignment: WrapAlignment.center,
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          _PreviewOffsetButton(
                            label: '-10ms',
                            enabled: state.isActive,
                            onPressed: () => sync.adjustOffset(-10),
                          ),
                          _PreviewOffsetButton(
                            label: '-500ms',
                            enabled: state.isActive,
                            onPressed: () => sync.adjustOffset(-500),
                          ),
                          _PreviewOffsetButton(
                            label: '-100ms',
                            enabled: state.isActive,
                            onPressed: () => sync.adjustOffset(-100),
                          ),
                          _PreviewOffsetButton(
                            label: '+100ms',
                            enabled: state.isActive,
                            onPressed: () => sync.adjustOffset(100),
                          ),
                          _PreviewOffsetButton(
                            label: '+10ms',
                            enabled: state.isActive,
                            onPressed: () => sync.adjustOffset(10),
                          ),
                          _PreviewOffsetButton(
                            label: '+500ms',
                            enabled: state.isActive,
                            onPressed: () => sync.adjustOffset(500),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    });
  }
}

class _PreviewOffsetButton extends StatelessWidget {
  const _PreviewOffsetButton({required this.label, required this.enabled, required this.onPressed});

  final String label;
  final bool enabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      style: OutlinedButton.styleFrom(
        foregroundColor: Colors.white,
        visualDensity: VisualDensity.compact,
        side: const BorderSide(color: Colors.white38),
      ),
      onPressed: enabled ? onPressed : null,
      child: Text(label),
    );
  }
}

Future<void> showCommentarySourceDialog(VideoController controller) async {
  final selected = await Get.dialog<LiveRoom>(CommentarySourceDialog(videoRoom: controller.room));
  if (selected == null) return;
  final sync = GlobalPlayerService.instance.commentarySyncController;
  if (sync.isEngaged) {
    await Get.find<LivePlayController>().danmakuController.selectSource(CommentaryDanmakuSource.video);
  }
  await sync.activate(videoRoom: controller.room, audioRoom: selected);
  if (sync.state.value.status == CommentarySyncStatus.error) {
    ToastUtil.show(i18n('commentary_failed'));
  }
}

class CommentarySourceDialog extends StatefulWidget {
  const CommentarySourceDialog({super.key, required this.videoRoom});

  final LiveRoom videoRoom;

  @override
  State<CommentarySourceDialog> createState() => _CommentarySourceDialogState();
}

class _CommentarySourceDialogState extends State<CommentarySourceDialog> {
  StreamSubscription<dynamic>? _refreshSubscription;

  List<LiveRoom> get _rooms {
    final rooms = SettingsService.to.fav.favoriteRooms.v
        .where((room) => room.liveStatus == LiveStatus.live && !_isSameRoom(room, widget.videoRoom))
        .toList();
    rooms.sort((a, b) => _watching(b).compareTo(_watching(a)));
    return rooms;
  }

  int _watching(LiveRoom room) => int.tryParse(room.watching ?? '') ?? 0;

  bool _isSameRoom(LiveRoom first, LiveRoom second) =>
      first.platform == second.platform && first.roomId == second.roomId;

  @override
  void initState() {
    super.initState();
    _refreshSubscription = EventBus.instance.listen('refresh_favorite_finish', (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _refreshSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final rooms = _rooms;
    return AlertDialog(
      title: Text(i18n('commentary_choose_source')),
      content: SizedBox(
        width: 480,
        height: 430,
        child: rooms.isEmpty
            ? AppStatusView(type: AppStatusType.empty, title: i18n('commentary_no_online_favorites'), subtitle: '')
            : ListView.builder(
                itemCount: rooms.length,
                itemBuilder: (context, index) {
                  final room = rooms[index];
                  return ListTile(
                    leading: CommonAvatar(avatarUrl: room.avatar, fallbackName: room.nick, dense: true),
                    title: Text(room.title ?? '', maxLines: 1, overflow: TextOverflow.ellipsis),
                    subtitle: Text('${room.nick ?? ''} · ${room.platform?.toUpperCase() ?? ''}'),
                    trailing: Text(readableCount(room.watching ?? '0')),
                    onTap: () => Navigator.pop(context, room),
                  );
                },
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => EventBus.instance.emit('refresh_favorite_rooms', true),
          child: Text(i18n('refresh')),
        ),
        TextButton(onPressed: () => Navigator.pop(context), child: Text(i18n('cancel'))),
      ],
    );
  }
}

String formatCommentaryOffset(int offsetMs) {
  final seconds = offsetMs / 1000;
  final prefix = offsetMs > 0 ? '+' : '';
  return '$prefix${seconds.toStringAsFixed(1)}s';
}
