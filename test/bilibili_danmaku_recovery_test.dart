import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pure_live/core/danmaku/bilibili_danmaku.dart';
import 'package:pure_live/core/site/bilibili/bilibili_site.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:web_socket_channel/io.dart';

BiliBiliDanmakuArgs args({
  String token = 'initial',
  int room = 123,
  int uid = 0,
  Future<BiliBiliDanmakuArgs?> Function()? refresh,
}) => BiliBiliDanmakuArgs(
  roomId: room,
  token: token,
  serverUrls: ['wss://one.test/sub', 'wss://two.test/sub'],
  buvid: 'fixture',
  uid: uid,
  cookie: '',
  refresh: refresh,
);

Uint8List packet(Map<String, dynamic> body, int operation) {
  final payload = utf8.encode(jsonEncode(body));
  final data = Uint8List(16 + payload.length);
  final header = ByteData.sublistView(data);
  header.setUint32(0, data.length);
  header.setUint16(4, 16);
  header.setUint32(8, operation);
  header.setUint32(12, 1);
  data.setRange(16, data.length, payload);
  return data;
}

Map _join(_Channel channel) => jsonDecode(utf8.decode(channel.output.sent.first.sublist(16))) as Map;

class _Channel implements WebSocketChannel {
  final input = StreamController<dynamic>();
  final output = _Sink();
  @override
  Stream<dynamic> get stream => input.stream;
  @override
  WebSocketSink get sink => output;
  @override
  Future<void> get ready => Future.value();
  @override
  int? get closeCode => null;
  @override
  String? get closeReason => null;
  @override
  String? get protocol => null;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Sink implements WebSocketSink {
  final sent = <List<int>>[];
  bool closed = false;
  @override
  void add(dynamic data) {
    if (!closed) sent.add(List<int>.from(data as List));
  }

  @override
  Future<void> close([int? code, String? reason]) async {
    closed = true;
  }

  @override
  Future<void> get done => Future.value();
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test('initial empty credentials keep retrying beyond three failures then authenticate', () {
    fakeAsync((clock) {
      var refreshes = 0, ready = 0;
      final channels = <_Channel>[];
      final notices = <String>[];
      late Future<BiliBiliDanmakuArgs?> Function() refresh;
      refresh = () async {
        refreshes++;
        if (refreshes <= 4) throw StateError('API unavailable');
        return args(token: 'fresh', refresh: refresh);
      };
      final engine =
          BiliBiliDanmaku(
              connector: (_, {connectTimeout, protocols, headers}) {
                final c = _Channel();
                channels.add(c);
                return c;
              },
            )
            ..onClose = notices.add
            ..onReady = () => ready++;
      var started = false;
      unawaited(engine.start(args(token: '', refresh: refresh)).then((_) => started = true));
      clock.flushMicrotasks();
      expect(started, isTrue);
      for (var i = 0; i < 4; i++) {
        clock.elapse(const Duration(seconds: 15));
      }
      expect(refreshes, 5);
      expect(channels, hasLength(1));
      expect(_join(channels.single)['key'], 'fresh');
      expect(engine.isConnected, isFalse);
      channels.single.input.add(packet({'code': 0}, 8));
      clock.flushMicrotasks();
      expect(engine.isConnected, isTrue);
      expect(ready, 1);
      expect(notices, everyElement(contains('正在尝试重连')));
      unawaited(engine.stop());
      clock.flushMicrotasks();
      clock.elapse(const Duration(minutes: 2));
      expect(refreshes, 5);
    });
  });
  test('repeated auth rejection refreshes once per 15s and does not exhaust lifetime budget', () {
    fakeAsync((clock) {
      final channels = <_Channel>[];
      final endpoints = <String>[];
      var refreshes = 0;
      late Future<BiliBiliDanmakuArgs?> Function() refresh;
      refresh = () async => args(token: 'new-${++refreshes}', refresh: refresh);
      final engine = BiliBiliDanmaku(
        connector: (url, {connectTimeout, protocols, headers}) {
          endpoints.add(url);
          final c = _Channel();
          channels.add(c);
          return c;
        },
      );
      unawaited(engine.start(args(refresh: refresh)));
      clock.flushMicrotasks();
      for (var i = 0; i < 5; i++) {
        channels.last.input.add(packet({'code': -101}, 8));
        clock.flushMicrotasks();
        expect(channels.last.output.closed, isTrue);
        clock.elapse(const Duration(seconds: 14));
        expect(refreshes, i);
        clock.elapse(const Duration(seconds: 1));
        expect(refreshes, i + 1);
      }
      expect(channels, hasLength(6));
      expect(endpoints.take(2), ['wss://one.test/sub', 'wss://two.test/sub']);
      channels.last.input.add(packet({'code': 0}, 8));
      clock.flushMicrotasks();
      expect(engine.isConnected, isTrue);
      unawaited(engine.stop());
      clock.flushMicrotasks();
    });
  });
  test('auth timeout refreshes and a late old ACK cannot mark new session connected', () {
    fakeAsync((clock) {
      final channels = <_Channel>[];
      var refreshes = 0;
      final engine = BiliBiliDanmaku(
        connector: (_, {connectTimeout, protocols, headers}) {
          final c = _Channel();
          channels.add(c);
          return c;
        },
      );
      unawaited(
        engine.start(
          args(
            refresh: () async {
              refreshes++;
              return args(token: 'fresh');
            },
          ),
        ),
      );
      clock.flushMicrotasks();
      clock.elapse(const Duration(seconds: 8));
      channels.first.input.add(packet({'code': 0}, 8));
      clock.flushMicrotasks();
      expect(engine.isConnected, isFalse);
      clock.elapse(const Duration(seconds: 15));
      expect(refreshes, 1);
      expect(channels, hasLength(2));
      unawaited(engine.stop());
      clock.flushMicrotasks();
    });
  });
  test('old discovery completing after room replacement cannot overwrite it', () {
    fakeAsync((clock) {
      final pending = Completer<BiliBiliDanmakuArgs?>();
      final channels = <_Channel>[];
      final engine = BiliBiliDanmaku(
        connector: (_, {connectTimeout, protocols, headers}) {
          final c = _Channel();
          channels.add(c);
          return c;
        },
      );
      unawaited(engine.start(args(token: '', refresh: () => pending.future)));
      clock.flushMicrotasks();
      unawaited(engine.start(args(room: 456, token: 'replacement')));
      clock.flushMicrotasks();
      pending.complete(args(room: 123, token: 'late'));
      clock.flushMicrotasks();
      expect(channels, hasLength(1));
      expect(_join(channels.single)['roomid'], 456);
      expect(engine.danmakuArgs.roomId, 456);
      unawaited(engine.stop());
      clock.flushMicrotasks();
    });
  });
  test('failed real handshake cannot strand credential recovery', () {
    fakeAsync((clock) {
      var tries = 0, refreshes = 0;
      final success = _Channel();
      final engine = BiliBiliDanmaku(
        connector: (_, {connectTimeout, protocols, headers}) {
          tries++;
          return tries == 1 ? IOWebSocketChannel(Future.error(StateError('handshake'))) : success;
        },
      );
      unawaited(
        engine.start(
          args(
            refresh: () async {
              refreshes++;
              return args(token: 'new');
            },
          ),
        ),
      );
      clock.flushMicrotasks();
      clock.elapse(const Duration(seconds: 15));
      clock.flushMicrotasks();
      expect(tries, 2);
      expect(refreshes, 1);
      unawaited(engine.stop());
      clock.flushMicrotasks();
    });
  });
  test('hung credential discovery releases retry after timeout; stop fences late completion', () {
    fakeAsync((clock) {
      var attempts = 0;
      final pending = Completer<BiliBiliDanmakuArgs?>();
      final engine = BiliBiliDanmaku();
      unawaited(
        engine.start(
          args(
            token: '',
            refresh: () {
              attempts++;
              return pending.future;
            },
          ),
        ),
      );
      clock.flushMicrotasks();
      clock.elapse(const Duration(seconds: 27));
      expect(attempts, 1, reason: 'timeout does not spawn overlapping HTTP discovery');
      unawaited(engine.stop());
      clock.flushMicrotasks();
      pending.complete(args());
      clock.flushMicrotasks();
      clock.elapse(const Duration(minutes: 1));
      expect(engine.webScoketUtils, isNull);
      expect(engine.isConnected, isFalse);
    });
  });
  test('auth payload and message ACK use required protocol fields', () {
    final sent = <List<int>>[];
    final engine = BiliBiliDanmaku(packetSender: sent.add);
    final payload = engine.buildJoinPayload(args());
    expect(payload['support_ack'], isTrue);
    expect(payload['scene'], 'room');
    expect(payload['queue_uuid'], matches(RegExp(r'^[0-9a-f]{8}$')));
    engine.decodeMessage(packet({'cmd': 'NOTICE', 'p_is_ack': true, 'msg_id': '1', 'p_msg_type': 2}, 5));
    expect(ByteData.sublistView(Uint8List.fromList(sent.single)).getUint32(8), 24);
    expect(jsonDecode(utf8.decode(sent.single.sublist(16))), {'cmd': 'NOTICE', 'msg_id': '1', 'p_msg_type': 2});
    engine.decodeMessage(packet({'cmd': 'NOTICE', 'p_is_ack': true}, 5));
    expect(sent, hasLength(1));
  });
  test('UID is bound to session Cookie rather than old profile state', () {
    expect(BiliBiliSite.resolveDanmakuUid('SESSDATA=token; DedeUserID=42'), 42);
    expect(BiliBiliSite.resolveDanmakuUid('DedeUserID=42; buvid3=guest'), 0);
    expect(BiliBiliSite.resolveDanmakuUid('SESSDATA=token'), 0);
  });
}
