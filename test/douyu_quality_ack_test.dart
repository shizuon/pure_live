import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pure_live/common/models/live_room.dart';
import 'package:pure_live/core/common/http_client.dart';
import 'package:pure_live/core/interface/live_site.dart';
import 'package:pure_live/core/site/douyu/douyu_site.dart';
import 'package:pure_live/model/live_play_quality.dart';
import 'package:pure_live/modules/live_play/controllers/player_controller.dart';
import 'package:pure_live/modules/live_play/service/stream_source_resolver.dart';

void main() {
  final room = LiveRoom(roomId: '123', platform: 'douyu');
  final quality = LivePlayQuality(quality: '原画1080P60', id: 0, data: DouyuPlayData(0, ['main', 'backup']));
  final low = LivePlayQuality(quality: '蓝光4M', id: 4, data: DouyuPlayData(4, ['main', 'backup']));
  late Dio previous;
  late Dio fixture;
  late Map<String, Object?> rates;
  late List<Map<String, String>> requests;
  late Set<String> failures;
  setUp(() {
    previous = HttpClient.instance.dio;
    rates = {'main': 4, 'backup': '4'};
    requests = [];
    failures = {};
    fixture = Dio()
      ..interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            if (options.path.endsWith('/getEncryption')) {
              handler.resolve(
                Response(
                  requestOptions: options,
                  data: {
                    'data': {
                      'key': 'fixture',
                      'rand_str': 'fixture',
                      'enc_data': 'fixture',
                      'enc_time': 1,
                      'expire_at': DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600,
                    },
                  },
                ),
              );
              return;
            }
            final form = Uri.splitQueryString(options.data as String);
            requests.add(form);
            final cdn = form['cdn']!;
            handler.resolve(
              Response(
                requestOptions: options,
                data: {
                  'error': failures.contains(cdn) ? 102 : 0,
                  'data': {'rate': rates[cdn], 'rtmp_url': 'https://$cdn.example.test/live', 'rtmp_live': 'stream.flv'},
                },
              ),
            );
          },
        ),
      );
    HttpClient.instance.dio = fixture;
  });
  tearDown(() {
    HttpClient.instance.dio = previous;
    fixture.close(force: true);
  });

  test('source request acknowledged as 4M updates visible selection', () async {
    final result = await DouyuSite().resolvePlayUrls(detail: room, quality: quality);
    expect(result.appliedQualityData, 4);
    expect(result.urls, hasLength(2));
    expect(requests.map((r) => r['rate']), ['0', '0']);
    expect(
      resolveAppliedQualityIndex(
        qualities: result.withAcknowledgedQuality([quality, low]),
        requestedIndex: 0,
        appliedQualityData: result.appliedQualityData,
      ),
      1,
    );
  });
  test('source-confirmed CDN wins over a downgraded first line', () async {
    rates['backup'] = 0;
    final result = await DouyuSite().resolvePlayUrls(detail: room, quality: quality);
    expect(result.appliedQualityData, 0);
    expect(result.urls, ['https://backup.example.test/live/stream.flv']);
  });
  test('single-line recording cursor keeps acknowledgement and resolves only that CDN', () async {
    final result = await DouyuSite().resolvePlayUrlAtRaw(detail: room, quality: quality, lineIndex: 1);
    expect(result.appliedQualityData, 4);
    expect(requests, hasLength(1));
    expect(requests.single['cdn'], 'backup');
  });
  test('missing, fractional and negative acknowledgements never display requested 60fps', () async {
    for (final raw in [null, 0.5, -1, 'invalid']) {
      rates = {'main': raw, 'backup': raw};
      final result = await DouyuSite().resolvePlayUrls(detail: room, quality: quality);
      final menu = result.withAcknowledgedQuality([quality, low]);
      final index = resolveAppliedQualityIndex(
        qualities: menu,
        requestedIndex: 0,
        appliedQualityData: result.appliedQualityData,
      );
      expect(index, 2);
      expect(menu[index].quality, isNot(quality.quality));
    }
  });
  test('B candidates carry the actual quality, without eager loading another tier', () async {
    final cursor = StreamSourceResolver.buildCandidates(
      room: room,
      qualities: [quality, low],
      headers: {},
      preferredOrder: [quality, low],
      getPlayUrls: (_) async => throw StateError('legacy path must not be used'),
      resolvePlayUrls: (q) => DouyuSite().resolvePlayUrls(detail: room, quality: q),
    );
    final candidate = await cursor.next();
    expect(candidate!.quality.selectionId, 4);
    expect(requests, hasLength(2));
    cursor.cancel();
    expect(await cursor.next(), isNull);
  });
  test('failed CDN retains bounded retries and other same-quality lines', () async {
    failures.add('main');
    final result = await DouyuSite().resolvePlayUrls(detail: room, quality: quality);
    expect(result.urls, ['https://backup.example.test/live/stream.flv']);
    expect(requests.where((r) => r['cdn'] == 'main'), hasLength(2));
  });
}
