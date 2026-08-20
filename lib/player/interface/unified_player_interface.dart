import '../models/player_state.dart';
import 'package:flutter/material.dart';
import '../models/player_exception.dart';
import 'package:pure_live/common/models/live_room.dart';
import 'package:pure_live/player/models/player_engine.dart';




import '../core/live_audio_control_delegate.dart';

abstract class UnifiedPlayer implements LiveAudioControlDelegate {
  Future<void> init({bool audioOnly = false});
  PlayerEngine get engine;

  /// 设置数据源
  /// [url] 当前播放地址
  /// [playUrls] 备用地址列表
  /// [headers] HTTP 请求头
  Future<void> setDataSource(
    String url,
    List<String> playUrls,
    Map<String, String> headers, {
    LiveRoom? room,
    bool audioOnly = false,
    bool startMuted = false,
    bool force = false,
  });

  @override
  Future<void> play();

  @override
  Future<void> pause();

  @override
  Future<void> stop();

  // 不销毁播放器
  Future<void> softStop();

  /// Enables or disables video decoding/rendering without replacing the
  /// player or reopening the current live stream. Surface-backed adapters must
  /// serialize this with their surface lifecycle.
  Future<void> setAudioOnly(bool audioOnly);

  // 真正释放播放器
  Future<void> hardDispose();

  @override
  Future<void> setVolume(double volume);

  /// 获取渲染组件
  /// [fitIndex] 对应 BoxFit 的索引
  /// [controls] 覆盖在视频上的 UI 控制层
  Widget getVideoWidget(BoxFit boxfit);

  bool get isInitialized;

  bool get isPlayingNow;

  bool get isReusable;

  // --- 状态流 ---

  Stream<PlayerState> get onStateChanged;

  Stream<bool> get onPlaying;

  Stream<PlayerException> get onError;

  Stream<bool> get onLoading;

  Stream<bool> get onComplete;

  Stream<int?> get width;

  Stream<int?> get height;
}
