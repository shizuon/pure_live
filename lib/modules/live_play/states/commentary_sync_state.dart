import 'package:pure_live/common/models/live_room.dart';
import 'package:pure_live/model/live_play_quality.dart';

import 'commentary_overlay_layout.dart';

enum CommentarySyncStatus { inactive, loading, calibrating, active, reconnecting, error }

class CommentarySyncState {
  const CommentarySyncState({
    this.status = CommentarySyncStatus.inactive,
    this.videoRoom,
    this.audioRoom,
    this.offsetMs = 0,
    this.outputVolume = 1,
    this.previewVisible = false,
    this.overlayEnabled = false,
    this.overlayEditing = false,
    this.overlayLayout = const CommentaryOverlayLayout(),
    this.message,
    this.qualities = const [],
    this.qualityId,
    this.qualityLabel,
  });

  final CommentarySyncStatus status;
  final LiveRoom? videoRoom;
  final LiveRoom? audioRoom;
  final int offsetMs;
  final double outputVolume;
  final bool previewVisible;
  final bool overlayEnabled;
  final bool overlayEditing;
  final CommentaryOverlayLayout overlayLayout;
  bool get needsCompanionVideo => previewVisible || overlayEnabled || overlayEditing;
  final String? message;
  final List<LivePlayQuality> qualities;
  final String? qualityId;
  final String? qualityLabel;

  bool get isEngaged => status != CommentarySyncStatus.inactive;
  bool get isActive => status == CommentarySyncStatus.active || status == CommentarySyncStatus.calibrating;
  bool get isBusy =>
      status == CommentarySyncStatus.loading ||
      status == CommentarySyncStatus.calibrating ||
      status == CommentarySyncStatus.reconnecting;

  CommentarySyncState copyWith({
    CommentarySyncStatus? status,
    LiveRoom? videoRoom,
    LiveRoom? audioRoom,
    int? offsetMs,
    double? outputVolume,
    bool? previewVisible,
    bool? overlayEnabled,
    bool? overlayEditing,
    CommentaryOverlayLayout? overlayLayout,
    String? message,
    bool clearMessage = false,
    List<LivePlayQuality>? qualities,
    String? qualityId,
    String? qualityLabel,
  }) {
    return CommentarySyncState(
      status: status ?? this.status,
      videoRoom: videoRoom ?? this.videoRoom,
      audioRoom: audioRoom ?? this.audioRoom,
      offsetMs: offsetMs ?? this.offsetMs,
      outputVolume: outputVolume ?? this.outputVolume,
      previewVisible: previewVisible ?? this.previewVisible,
      overlayEnabled: overlayEnabled ?? this.overlayEnabled,
      overlayEditing: overlayEditing ?? this.overlayEditing,
      overlayLayout: overlayLayout ?? this.overlayLayout,
      message: clearMessage ? null : message ?? this.message,
      qualities: qualities ?? this.qualities,
      qualityId: qualityId ?? this.qualityId,
      qualityLabel: qualityLabel ?? this.qualityLabel,
    );
  }
}
