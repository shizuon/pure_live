import 'dart:io';
import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:brotli/brotli.dart';
import 'package:web_socket_channel/io.dart';

import '../common/binary_writer.dart';

import 'package:pure_live/core/common/core_log.dart';
import 'package:pure_live/common/models/live_message.dart';
import 'package:pure_live/core/common/convert_helper.dart';
import 'package:pure_live/core/common/web_socket_util.dart';
import 'package:pure_live/core/interface/live_danmaku.dart';

class BiliBiliDanmakuArgs {
  final int roomId;
  final String token;
  final String buvid;
  final List<String> serverUrls;
  final int uid;
  final String cookie;
  final Map<String, dynamic> headers;
  final Future<BiliBiliDanmakuArgs?> Function()? refresh;
  BiliBiliDanmakuArgs({
    required this.roomId,
    required this.token,
    required this.serverUrls,
    required this.buvid,
    required this.uid,
    required this.cookie,
    this.headers = const {},
    this.refresh,
  });
  @override
  String toString() {
    return json.encode({
      "roomId": roomId,
      "hasToken": token.isNotEmpty,
      "serverUrls": serverUrls,
      "hasBuvid": buvid.isNotEmpty,
      "uid": uid,
      "hasCookie": cookie.isNotEmpty,
    });
  }
}

class BiliBiliDanmaku implements LiveDanmaku {
  BiliBiliDanmaku({
    this.connector,
    this.packetSender,
    this.retryDelay = const Duration(seconds: 15),
    this.discoveryTimeout = const Duration(seconds: 12),
    this.authTimeout = const Duration(seconds: 8),
  });
  final WebSocketConnector? connector;
  final void Function(List<int>)? packetSender;
  final Duration retryDelay;
  final Duration discoveryTimeout;
  final Duration authTimeout;
  @override
  int heartbeatTime = 30 * 1000;
  bool _connected = false;

  @override
  bool get isConnected => _connected;

  @override
  void markConnected() {
    _connected = true;
  }

  @override
  void markDisconnected() {
    _connected = false;
  }

  @override
  Function(LiveMessage msg)? onMessage;
  @override
  Function(String msg)? onClose;
  @override
  Function()? onReady;

  // String serverUrl = "wss://broadcastlv.chat.bilibili.com/sub";

  WebScoketUtils? webScoketUtils;
  late BiliBiliDanmakuArgs danmakuArgs;
  bool _stopped = false;
  Timer? _authTimer;
  Timer? _retryTimer;
  int _generation = 0;
  int _attempt = 0;
  int _endpointIndex = 0;
  Future<BiliBiliDanmakuArgs?>? _pendingRefresh;

  bool _owns(int generation, int attempt) => !_stopped && generation == _generation && attempt == _attempt;

  @override
  Future start(dynamic args) async {
    final generation = ++_generation;
    _attempt++;
    _retryTimer?.cancel();
    _retryTimer = null;
    _authTimer?.cancel();
    final previous = webScoketUtils;
    webScoketUtils = null;
    danmakuArgs = args as BiliBiliDanmakuArgs;
    _stopped = false;
    _endpointIndex = 0;
    _pendingRefresh = null;
    markDisconnected();
    await previous?.close();
    if (_stopped || generation != _generation) return;
    // Own discovery beyond this method. The page's 20s startup timeout must
    // not terminate a recoverable token/API failure and cancel all retries.
    unawaited(_connect(generation, refresh: danmakuArgs.token.isEmpty));
  }

  Future<void> _connect(int generation, {required bool refresh}) async {
    final attempt = ++_attempt;
    if (!_owns(generation, attempt)) return;
    try {
      var args = danmakuArgs;
      if (refresh && args.refresh != null) {
        // A timeout fences a result but does not cancel its HTTP requests.
        // Reuse the in-flight discovery on subsequent timers instead of
        // accumulating parallel discovery requests while an endpoint hangs.
        var pending = _pendingRefresh;
        if (pending == null) {
          final operation = Future<BiliBiliDanmakuArgs?>.sync(args.refresh!);
          _pendingRefresh = pending = operation;
          unawaited(
            operation.then<void>(
              (_) {
                if (identical(_pendingRefresh, operation)) _pendingRefresh = null;
              },
              onError: (Object _, StackTrace __) {
                if (identical(_pendingRefresh, operation)) _pendingRefresh = null;
              },
            ),
          );
        }
        final updated = await pending.timeout(discoveryTimeout);
        if (!_owns(generation, attempt)) return;
        if (updated == null || updated.roomId != args.roomId || updated.token.isEmpty) {
          throw StateError('Invalid refreshed danmaku credentials');
        }
        args = updated;
        danmakuArgs = updated;
      }
      if (args.token.isEmpty) throw StateError('Missing danmaku token');
      final endpoints = args.serverUrls.isEmpty ? const ['wss://broadcastlv.chat.bilibili.com/sub'] : args.serverUrls;
      final socket = WebScoketUtils(
        url: endpoints[_endpointIndex % endpoints.length],
        headers: args.headers.isNotEmpty ? args.headers : (args.cookie.isEmpty ? null : {"cookie": args.cookie}),
        heartBeatTime: heartbeatTime,
        connector:
            connector ??
            (url, {connectTimeout, protocols, headers}) =>
                IOWebSocketChannel.connect(url, connectTimeout: connectTimeout, protocols: protocols, headers: headers),
        onMessage: (e) {
          if (_owns(generation, attempt) && e is List<int>) decodeMessage(e);
        },
        onReady: () {
          if (!_owns(generation, attempt)) return;
          _authTimer?.cancel();
          _authTimer = Timer(authTimeout, () {
            if (_owns(generation, attempt) && !isConnected) _scheduleRetry(generation, attempt);
          });
          joinRoom(args);
        },
        onHeartBeat: () {
          if (_owns(generation, attempt) && isConnected) heartbeat();
        },
        onClose: (e) {
          if (_owns(generation, attempt)) _scheduleRetry(generation, attempt);
        },
      );
      // No second retry loop inside the transport. Failure delegates to this
      // owner, which refreshes token + UID + headers together on every retry.
      socket.maxReconnectTime = 0;
      webScoketUtils = socket;
      await socket.connect().timeout(const Duration(seconds: 12));
    } catch (_) {
      if (_owns(generation, attempt)) _scheduleRetry(generation, attempt);
    }
  }

  void _scheduleRetry(int generation, int attempt) {
    if (!_owns(generation, attempt)) return;
    _attempt++; // Reject buffered packets and late handshake/auth callbacks.
    _endpointIndex++;
    _authTimer?.cancel();
    _authTimer = null;
    markDisconnected();
    final old = webScoketUtils;
    webScoketUtils = null;
    unawaited(old?.close() ?? Future<void>.value());
    _retryTimer?.cancel();
    _retryTimer = Timer(retryDelay, () {
      _retryTimer = null;
      if (!_stopped && generation == _generation) unawaited(_connect(generation, refresh: true));
    });
    // Existing page controller treats this as transient and retains ownership.
    onClose?.call("与服务器断开连接，正在尝试重连（15秒后）");
  }

  Map<String, dynamic> buildJoinPayload(BiliBiliDanmakuArgs args) => {
    'uid': args.uid,
    'roomid': args.roomId,
    'protover': 3,
    'buvid': args.buvid,
    'support_ack': true,
    'queue_uuid': List.generate(8, (_) => Random.secure().nextInt(16).toRadixString(16)).join(),
    'scene': 'room',
    'platform': 'web',
    'type': 2,
    'key': args.token,
  };

  void _sendPacket(List<int> data) {
    if (packetSender != null) {
      packetSender!(data);
    } else {
      webScoketUtils?.sendMessage(data);
    }
  }

  void joinRoom(BiliBiliDanmakuArgs args) {
    _sendPacket(encodeData(json.encode(buildJoinPayload(args)), 7));
  }

  @override
  void heartbeat() {
    _sendPacket(encodeData("", 2));
  }

  @override
  Future stop() async {
    _stopped = true;
    _generation++;
    _pendingRefresh = null;
    _attempt++;
    _retryTimer?.cancel();
    _retryTimer = null;
    _authTimer?.cancel();
    _authTimer = null;
    markDisconnected();
    onMessage = null;
    onClose = null;
    onReady = null;
    final previous = webScoketUtils;
    webScoketUtils = null;
    await previous?.close();
  }

  List<int> encodeData(String msg, int action) {
    var data = utf8.encode(msg);
    //头部长度固定16
    var length = data.length + 16;
    var buffer = Uint8List(length);

    var writer = BinaryWriter([]);

    //数据包长度
    writer.writeInt(buffer.length, 4);
    //数据包头部长度,固定16
    writer.writeInt(16, 2);

    //协议版本，0=JSON,1=Int32,2=Buffer
    writer.writeInt(0, 2);

    //操作类型
    writer.writeInt(action, 4);

    //数据包头部长度,固定1

    writer.writeInt(1, 4);

    writer.writeBytes(data);

    return writer.buffer;
  }

  void decodeMessage(List<int> data) {
    if (_stopped) return;
    try {
      _decodePacketStream(data, depth: 0);
    } catch (e) {
      CoreLog.error(e);
    }
  }

  /// A WebSocket message can contain multiple Bilibili packets. Compressed
  /// notification packets contain another complete packet stream, rather than
  /// plain JSON. Parsing the 16-byte frames recursively keeps packet-length
  /// bytes away from the JSON decoder and prevents valid DANMU_MSG events from
  /// being dropped.
  void _decodePacketStream(List<int> data, {required int depth}) {
    if (depth > 8) {
      throw const FormatException('Bilibili danmaku packet nesting is too deep');
    }

    var offset = 0;
    while (offset + 16 <= data.length) {
      final packetLength = readInt(data, offset, 4);
      final headerLength = readInt(data, offset + 4, 2);
      final protocolVersion = readInt(data, offset + 6, 2);
      final operation = readInt(data, offset + 8, 4);

      if (headerLength < 16 || packetLength < headerLength || offset + packetLength > data.length) {
        throw FormatException(
          'Invalid Bilibili danmaku frame: offset=$offset, packet=$packetLength, header=$headerLength, total=${data.length}',
        );
      }

      final body = data.sublist(offset + headerLength, offset + packetLength);
      final previousAttempt = _attempt;
      _decodePacket(protocolVersion, operation, body, depth: depth);
      if (_stopped || previousAttempt != _attempt) return;
      offset += packetLength;
    }

    if (offset != data.length) {
      throw FormatException('Incomplete Bilibili danmaku frame: parsed=$offset, total=${data.length}');
    }
  }

  void _decodePacket(int protocolVersion, int operation, List<int> body, {required int depth}) {
    if (operation == 3) {
      if (body.length < 4) return;
      final online = readInt(body, 0, 4);
      onMessage?.call(
        LiveMessage(
          type: LiveMessageType.online,
          data: LiveAudienceUpdate(kind: LiveAudienceMetricKind.popularity, value: online),
          color: LiveMessageColor.white,
          message: "",
          userName: "",
        ),
      );
      return;
    }

    if (operation == 5) {
      if (protocolVersion == 2 || protocolVersion == 3) {
        final decoded = protocolVersion == 2 ? zlib.decode(body) : brotli.decode(body);
        _decodePacketStream(decoded, depth: depth + 1);
      } else {
        final text = utf8.decode(body, allowMalformed: true).trim();
        if (text.isNotEmpty) parseMessage(text);
      }
      return;
    }

    if (operation == 8) {
      // The transport is usable only after Bilibili acknowledges auth.
      final text = utf8.decode(body, allowMalformed: true).trim();
      final dynamic decoded = text.isEmpty ? const <String, dynamic>{'code': -1} : json.decode(text);
      final auth = decoded is Map ? decoded : const <String, dynamic>{};
      final code = int.tryParse(auth['code']?.toString() ?? '') ?? -1;
      if (code == 0 && !isConnected) {
        _authTimer?.cancel();
        markConnected();
        heartbeat();
        onReady?.call();
      } else if (code != 0) {
        _authTimer?.cancel();
        markDisconnected();
        _scheduleRetry(_generation, _attempt);
      }
    }
  }

  void parseMessage(String jsonMessage) {
    try {
      var obj = json.decode(jsonMessage);
      if (obj is Map && obj['p_is_ack'] == true) {
        final id = obj['msg_id']?.toString().trim() ?? '';
        final cmd = obj['cmd']?.toString().trim() ?? '';
        final type = int.tryParse(obj['p_msg_type']?.toString() ?? '');
        if (id.isNotEmpty && cmd.isNotEmpty && type != null) {
          _sendPacket(encodeData(json.encode({'msg_id': id, 'cmd': cmd, 'p_msg_type': type}), 24));
        }
      }
      var cmd = obj["cmd"].toString();
      if (cmd.contains("DANMU_MSG")) {
        if (obj["info"] != null && obj["info"].length != 0) {
          var message = obj["info"][1].toString();
          var color = asT<int?>(obj["info"][0][3]) ?? 0;
          if (obj["info"][2] != null && obj["info"][2].length != 0) {
            final metadata = obj["info"][0] is List ? obj["info"][0] as List : const <dynamic>[];
            final username = _preferredBilibiliUserName(obj, metadata, obj["info"][2][1]?.toString() ?? '');
            final rawTimestamp = metadata.length > 4 ? int.tryParse(metadata[4]?.toString() ?? '') : null;
            final rawNonce = metadata.length > 5 ? metadata[5]?.toString() ?? '' : '';
            final sentAt = rawTimestamp == null
                ? null
                : DateTime.fromMillisecondsSinceEpoch(rawTimestamp > 100000000000 ? rawTimestamp : rawTimestamp * 1000);
            var liveMsg = LiveMessage(
              type: LiveMessageType.chat,
              userName: username,
              userId: obj["info"][2][0]?.toString() ?? '',
              message: message,
              color: color == 0 ? LiveMessageColor.white : LiveMessageColor.numberToColor(color),
              messageId: rawNonce.isEmpty ? '' : 'bilibili:$rawNonce',
              sentAt: sentAt,
            );
            onMessage?.call(liveMsg);
          }
        }
      } else if (cmd == "WATCHED_CHANGE") {
        final value = int.tryParse(obj["data"]?["num"]?.toString() ?? '');
        if (value != null && value >= 0) {
          onMessage?.call(
            LiveMessage(
              type: LiveMessageType.online,
              data: LiveAudienceUpdate(kind: LiveAudienceMetricKind.totalViewers, value: value),
              color: LiveMessageColor.white,
              message: "",
              userName: "",
            ),
          );
        }
      } else if (cmd == "SUPER_CHAT_MESSAGE") {
        if (obj["data"] == null) {
          return;
        }
        LiveSuperChatMessage sc = LiveSuperChatMessage(
          backgroundBottomColor: obj["data"]["background_bottom_color"].toString(),
          backgroundColor: obj["data"]["background_color"].toString(),
          endTime: DateTime.fromMillisecondsSinceEpoch(obj["data"]["end_time"] * 1000),
          face: "${obj["data"]["user_info"]["face"]}@200w.jpg",
          message: obj["data"]["message"].toString(),
          price: obj["data"]["price"],
          startTime: DateTime.fromMillisecondsSinceEpoch(obj["data"]["start_time"] * 1000),
          userName: obj["data"]["user_info"]["uname"].toString(),
        );
        var liveMsg = LiveMessage(
          type: LiveMessageType.superChat,
          userName: "SUPER_CHAT_MESSAGE",
          message: "SUPER_CHAT_MESSAGE",
          color: LiveMessageColor.white,
          data: sc,
        );
        onMessage?.call(liveMsg);
      }
    } catch (e) {
      CoreLog.error(e);
    }
  }

  String _preferredBilibiliUserName(dynamic packet, List<dynamic> metadata, String legacyName) {
    dynamic richInfo;
    if (metadata.length > 15) richInfo = metadata[15];
    if (richInfo is String && richInfo.trimLeft().startsWith('{')) {
      try {
        richInfo = json.decode(richInfo);
      } catch (_) {
        richInfo = null;
      }
    }

    String readName(dynamic root) {
      if (root is! Map) return '';
      final user = root['user'] is Map ? root['user'] : root;
      if (user is! Map) return '';
      final base = user['base'];
      if (base is! Map) return '';
      final name = base['name']?.toString().trim() ?? '';
      if (name.isNotEmpty) return name;
      final origin = base['origin_info'];
      return origin is Map ? origin['name']?.toString().trim() ?? '' : '';
    }

    // Current packets include a richer user object in info[0][15]. Logged-in
    // sessions may expose a complete name there even when the legacy slot is
    // masked. Guest sessions currently mask both locations and omit the uid.
    dynamic packetUserInfo;
    dynamic packetDataUserInfo;
    if (packet is Map) {
      packetUserInfo = packet['uinfo'];
      final data = packet['data'];
      if (data is Map) packetDataUserInfo = data['uinfo'];
    }
    final candidates = <String>[];
    for (final candidate in [richInfo, packetUserInfo, packetDataUserInfo]) {
      final name = readName(candidate);
      if (name.isNotEmpty) candidates.add(name);
    }
    final masked = RegExp(r'\*{2,}|＊{2,}');
    for (final candidate in [...candidates, legacyName]) {
      if (candidate.isNotEmpty && !masked.hasMatch(candidate)) return candidate;
    }
    return candidates.isNotEmpty ? candidates.first : legacyName;
  }

  int readInt(List<int> buffer, int start, int len) {
    var bytes = Uint8List.fromList(buffer.getRange(start, start + len).toList());
    var byteBuffer = bytes.buffer;
    var data = ByteData.view(byteBuffer);
    var result = 0;

    if (len == 1) {
      result = data.getUint8(0);
    }
    if (len == 2) {
      result = data.getUint16(0, Endian.big);
    }
    if (len == 4) {
      result = data.getUint32(0, Endian.big);
    }
    if (len == 8) {
      result = data.getInt64(0, Endian.big);
    }

    return result;
  }
}
