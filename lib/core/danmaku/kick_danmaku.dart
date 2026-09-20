import 'dart:convert';
import 'dart:async';
import 'dart:math';

import 'package:dio/dio.dart';
import 'package:pure_live/common/models/live_message.dart';
import 'package:pure_live/core/common/http_client.dart';
import 'package:pure_live/core/common/web_socket_util.dart';
import 'package:pure_live/core/interface/live_danmaku.dart';

class KickDanmaku extends LiveDanmaku {
  WebScoketUtils? _socket;
  CancelToken? _cancel;
  int _generation = 0;
  Timer? _retryTimer;
  @override
  int get heartbeatTime => 30000;

  @override
  Future<void> start(dynamic args) async {
    await stop();
    final generation = _generation;
    final cancel = _cancel = CancelToken();
    if (args is! Map || args['channelId'] == null || args['chatroomId'] == null) {
      throw StateError('Kick chatroom metadata missing');
    }
    if (!RegExp(r'^\d+$').hasMatch(args['channelId'].toString()) ||
        !RegExp(r'^\d+$').hasMatch(args['chatroomId'].toString())) {
      throw ArgumentError('Invalid Kick chatroom');
    }
    await _connect(args, generation, cancel);
  }

  Future<dynamic> connectionConfig(Map args, CancelToken cancel, String clientId) => HttpClient.instance.postJson(
    'https://web.kick.com/api/v1/realtime/channels/${args['channelId']}/chat/connection',
    cancel: cancel,
    data: {
      'client': {'id': clientId, 'type': 'web'},
      'capabilities': {
        'accepted_providers': [
          {'provider': 'pusher'},
        ],
      },
    },
    header: {'User-Agent': 'Mozilla/5.0', 'Origin': 'https://kick.com', 'Referer': 'https://kick.com/'},
  );

  Future<void> _connect(Map args, int generation, CancelToken cancel) async {
    try {
      final random = Random.secure();
      final clientId = List.generate(16, (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
      final config = await connectionConfig(args, cancel, clientId);
      if (generation != _generation) return;
      final connections = config['data']?['connections'] as List? ?? [];
      final pusher = connections.where((entry) => entry['provider'] == 'pusher').firstOrNull;
      final key = pusher?['credentials']?['app_key']?.toString() ?? '';
      final cluster = pusher?['credentials']?['cluster']?.toString() ?? '';
      if (!RegExp(r'^[a-zA-Z0-9]+$').hasMatch(key) || !RegExp(r'^[a-z0-9-]+$').hasMatch(cluster)) {
        throw StateError('Kick public chat transport unavailable');
      }
      final channel = 'chatrooms.${args['chatroomId']}.v2';
      final socket = WebScoketUtils(
        url: 'wss://ws-$cluster.pusher.com/app/$key?protocol=7&client=js&version=8.4.0&flash=false',
        heartBeatTime: heartbeatTime,
        onHeartBeat: heartbeat,
        onMessage: (raw) {
          if (generation != _generation) return;
          try {
            final packet = jsonDecode(raw is String ? raw : utf8.decode(raw as List<int>));
            final event = packet['event'];
            if (event == 'pusher:connection_established') {
              _socket?.sendMessage(
                jsonEncode({
                  'event': 'pusher:subscribe',
                  'data': {'auth': '', 'channel': channel},
                }),
              );
            } else if (event == 'pusher_internal:subscription_succeeded' && packet['channel'] == channel) {
              markConnected();
              onReady?.call();
            } else if (event == 'pusher:ping') {
              _socket?.sendMessage(jsonEncode({'event': 'pusher:pong', 'data': {}}));
            } else if (event == 'pusher:error') {
              markDisconnected();
              _socket?.reconnect();
            } else if (packet['channel'] == channel) {
              final message = parseMessage(packet);
              if (message != null) onMessage?.call(message);
            }
          } on FormatException {
            /* Ignore non-chat frames. */
          }
        },
        onReconnect: () {
          if (generation == _generation) {
            markDisconnected();
            onClose?.call('Kick 弹幕断开，正在尝试重连（15秒后）');
          }
        },
        onClose: (_) {
          if (generation == _generation) {
            markDisconnected();
            onClose?.call('Kick 弹幕连接断开');
          }
        },
      );
      _socket = socket;
      await socket.connect();
    } catch (_) {
      if (generation != _generation) return;
      markDisconnected();
      onClose?.call('Kick 弹幕断开，正在尝试重连（15秒后）');
      _retryTimer?.cancel();
      _retryTimer = Timer(const Duration(seconds: 15), () {
        if (generation == _generation) unawaited(_connect(args, generation, cancel));
      });
    }
  }

  static LiveMessage? parseMessage(Map packet) {
    if (packet['event'] != r'App\Events\ChatMessageEvent') return null;
    final raw = packet['data'];
    final data = raw is String ? jsonDecode(raw) : raw;
    if (data is! Map || data['content'] is! String) return null;
    final sender = data['sender'] as Map? ?? {};
    final hex = sender['identity']?['color']?.toString().replaceFirst('#', '') ?? '';
    return LiveMessage(
      type: LiveMessageType.chat,
      userName: sender['username']?.toString() ?? '',
      userId: sender['id']?.toString() ?? '',
      message: data['content'],
      messageId: data['id']?.toString() ?? '',
      sentAt: DateTime.tryParse(data['created_at']?.toString() ?? ''),
      color: LiveMessageColor.numberToColor(int.tryParse(hex, radix: 16) ?? 0xFFFFFF),
    );
  }

  @override
  void heartbeat() => _socket?.sendMessage(jsonEncode({'event': 'pusher:ping', 'data': {}}));

  @override
  Future<void> stop() async {
    _generation++;
    _retryTimer?.cancel();
    _retryTimer = null;
    _cancel?.cancel();
    _cancel = null;
    final socket = _socket;
    _socket = null;
    markDisconnected();
    await socket?.close();
  }
}
