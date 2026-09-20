import 'dart:async';

import 'package:dio/dio.dart';
import 'package:pure_live/common/models/live_message.dart';
import 'package:pure_live/core/common/http_client.dart';
import 'package:pure_live/core/interface/live_danmaku.dart';
import 'package:pure_live/core/site/youtube/youtube_page.dart';
import 'package:pure_live/core/site/youtube/youtube_site.dart';

/// YouTube chat uses server-paced HTTP continuations rather than a WebSocket.
class YouTubeDanmaku extends LiveDanmaku {
  Timer? _timer;
  CancelToken? _cancel;
  int _generation = 0;
  final _seen = <String>{};
  Map<String, dynamic> _context = {};
  String? _continuation;
  String _videoId = '';

  Future<String> watch(String videoId, CancelToken cancel) => HttpClient.instance.getText(
    'https://www.youtube.com/watch',
    queryParameters: {'v': videoId},
    header: YouTubeSite.headers,
    cancel: cancel,
  );

  Future<dynamic> poll(String continuation, CancelToken cancel) => HttpClient.instance.postJson(
    'https://www.youtube.com/youtubei/v1/live_chat/get_live_chat',
    data: {'context': _context, 'continuation': continuation},
    header: YouTubeSite.headers,
    cancel: cancel,
  );

  @override
  Future<void> start(dynamic args) async {
    await stop();
    final generation = _generation;
    final cancel = _cancel = CancelToken();
    final videoId = args?.toString() ?? '';
    if (!RegExp(r'^[\w-]{11}$').hasMatch(videoId)) throw ArgumentError('Invalid YouTube chat video');
    _videoId = videoId;
    await _open(generation, cancel);
  }

  Future<void> _open(int generation, CancelToken cancel) async {
    try {
      final html = await watch(_videoId, cancel);
      if (generation != _generation) return;
      _context = YouTubePage.context(html);
      final initial = YouTubePage.objectAfter(html, 'var ytInitialData =');
      final chat = YouTubePage.renderers(initial, 'liveChatRenderer').firstOrNull;
      final next = continuationData(chat);
      if (next == null) {
        markDisconnected();
        onClose?.call('此 YouTube 直播未开放公开聊天');
        return;
      }
      _continuation = next.token;
      // Subscription is ready only after the first successful continuation.
      await _poll(generation, cancel);
    } catch (_) {
      if (generation != _generation) return;
      _retry(generation, cancel);
    }
  }

  Future<void> _poll(int generation, CancelToken cancel) async {
    try {
      final result = await poll(_continuation!, cancel);
      if (generation != _generation) return;
      final chat = result['continuationContents']?['liveChatContinuation'];
      if (chat is! Map) throw StateError('YouTube chat continuation missing');
      if (!isConnected) {
        markConnected();
        onReady?.call();
      }
      if (generation != _generation) return;
      for (final message in parseMessages(chat)) {
        if (generation != _generation) return;
        if (message.messageId.isNotEmpty && !_seen.add(message.messageId)) continue;
        if (_seen.length > 2000) _seen.remove(_seen.first);
        onMessage?.call(message);
      }
      if (generation != _generation) return;
      final next = continuationData(chat);
      if (next == null) {
        markDisconnected();
        onClose?.call('YouTube 直播聊天已结束');
        return;
      }
      _continuation = next.token;
      _timer = Timer(Duration(milliseconds: next.delayMs), () => unawaited(_poll(generation, cancel)));
    } catch (_) {
      if (generation != _generation) return;
      _retry(generation, cancel);
    }
  }

  void _retry(int generation, CancelToken cancel) {
    markDisconnected();
    onClose?.call('YouTube 弹幕断开，正在尝试重连（15秒后）');
    _timer?.cancel();
    _timer = Timer(const Duration(seconds: 15), () {
      if (generation == _generation) unawaited(_open(generation, cancel));
    });
  }

  static ({String token, int delayMs})? continuationData(dynamic chat) {
    if (chat is! Map) return null;
    for (final entry in chat['continuations'] as List? ?? []) {
      for (final key in ['timedContinuationData', 'invalidationContinuationData', 'reloadContinuationData']) {
        final value = entry[key];
        final token = value?['continuation'];
        if (token is String && token.isNotEmpty) {
          final timeout = value['timeoutMs'];
          return (token: token, delayMs: (timeout is num ? timeout.toInt() : 3000).clamp(1000, 30000));
        }
      }
    }
    return null;
  }

  static List<LiveMessage> parseMessages(dynamic chat) {
    final messages = <LiveMessage>[];
    for (final type in ['liveChatTextMessageRenderer', 'liveChatPaidMessageRenderer']) {
      for (final item in YouTubePage.renderers(chat, type)) {
        final content = YouTubePage.text(item['message']);
        if (content.isEmpty) continue;
        final micros = int.tryParse(item['timestampUsec']?.toString() ?? '');
        messages.add(
          LiveMessage(
            type: LiveMessageType.chat,
            userName: YouTubePage.text(item['authorName']),
            userId: item['authorExternalChannelId']?.toString() ?? '',
            message: content,
            messageId: item['id']?.toString() ?? '',
            color: LiveMessageColor.white,
            sentAt: micros == null ? null : DateTime.fromMicrosecondsSinceEpoch(micros),
          ),
        );
      }
    }
    return messages;
  }

  @override
  Future<void> stop() async {
    _generation++;
    _timer?.cancel();
    _timer = null;
    _cancel?.cancel();
    _cancel = null;
    _continuation = null;
    _context = {};
    _seen.clear();
    markDisconnected();
  }
}
