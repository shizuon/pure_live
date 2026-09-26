import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pure_live/core/common/http_client.dart';
import 'package:pure_live/core/interface/live_site.dart';
import 'package:pure_live/core/site/yy/yy_site.dart';
import 'package:pure_live/core/site/twitch/twitch_site.dart';
import 'package:pure_live/core/site/kuaishou/kuaishou_site.dart';
import 'package:pure_live/core/site/bilibili/bilibili_site.dart';
import 'package:pure_live/common/models/live_room.dart';
import 'package:pure_live/model/live_play_quality.dart';
import 'package:pure_live/modules/live_play/controllers/player_controller.dart';
import 'package:pure_live/modules/live_play/service/stream_source_resolver.dart';

class _YyFallback extends YYSite {
  @override
  Map<String, String> getHeaders() => {};
  @override
  Future<Map<String, dynamic>> getLiveStreamObj({required LiveRoom detail, required String qn}) async =>
      throw StateError('primary unavailable');
}

void main() {
  test('YY fallback labels actual resolution and B receives it', () async {
    final previous = HttpClient.instance.dio;
    final dio = Dio()
      ..interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            handler.resolve(
              Response(
                requestOptions: options,
                data: '{"code":0,"width":640,"height":360,"hls":"https://example.test/low.m3u8"}',
              ),
            );
          },
        ),
      );
    HttpClient.instance.dio = dio;
    try {
      final quality = LivePlayQuality(quality: '原画', id: 'original', data: 'original', sort: 8000);
      final room = LiveRoom(roomId: '123', platform: 'yy');
      final result = await _YyFallback().resolvePlayUrls(detail: room, quality: quality);
      final menu = result.withAcknowledgedQuality([quality]);
      expect(menu, hasLength(2));
      expect(menu.last.quality, '360P · HLS');
      expect(
        resolveAppliedQualityIndex(qualities: menu, requestedIndex: 0, appliedQualityData: result.appliedQualityData),
        1,
      );
      final cursor = StreamSourceResolver.buildCandidates(
        room: room,
        qualities: [quality],
        headers: {},
        getPlayUrls: (_) async => [],
        resolvePlayUrls: (_) async => result,
      );
      expect((await cursor.next())!.quality.quality, '360P · HLS');
      cursor.cancel();
      final noSize = YYSite.mobileHlsResolution({'hls': 'https://example.test/a'}, rate: '4000');
      expect(noSize.unlistedQuality!.quality, 'quality_unconfirmed');
    } finally {
      HttpClient.instance.dio = previous;
      dio.close(force: true);
    }
  });

  test('Bilibili acknowledgement outside old menu never displays requested source', () {
    final result = BiliBiliSite.parsePlayUrlResolution({
      'code': 0,
      'data': {
        'playurl_info': {
          'playurl': {
            'stream': [
              {
                'protocol_name': 'http_stream',
                'format': [
                  {
                    'format_name': 'flv',
                    'codec': [
                      {
                        'codec_name': 'avc',
                        'current_qn': 250,
                        'base_url': '/low.flv',
                        'url_info': [
                          {'host': 'https://example.test', 'extra': ''},
                        ],
                      },
                    ],
                  },
                ],
              },
            ],
          },
        },
      },
    }, requestedQualityData: 10000);
    final menu = result.withAcknowledgedQuality([LivePlayQuality(quality: '原画', id: 10000)]);
    final index = resolveAppliedQualityIndex(
      qualities: menu,
      requestedIndex: 0,
      appliedQualityData: result.appliedQualityData,
    );
    expect(index, 1);
    expect(menu[index].quality, '超清');
  });

  test('HLS lacks resolution: report bandwidth, not guessed 1080p', () {
    final q = TwitchSite.parseMasterPlaylist('''
#EXTM3U
#EXT-X-STREAM-INF:BANDWIDTH=6000000,CODECS="avc1.640028,mp4a.40.2"
video.m3u8
''', masterUri: Uri.parse('https://example.test/master.m3u8'));
    expect(q.single.quality, '6.00 Mbps');
  });
  test('HLS separates codec, audio group and exact frame rate but still deduplicates CDN', () {
    const rows = [
      'BANDWIDTH=6000000,RESOLUTION=1920x1080,FRAME-RATE=60,CODECS="avc1",AUDIO="a"',
      'BANDWIDTH=6000000,RESOLUTION=1920x1080,FRAME-RATE=60,CODECS="hvc1",AUDIO="a"',
      'BANDWIDTH=6000000,RESOLUTION=1920x1080,FRAME-RATE=59.94,CODECS="avc1",AUDIO="a"',
      'BANDWIDTH=6000000,RESOLUTION=1920x1080,FRAME-RATE=60,CODECS="avc1",AUDIO="b"',
      'BANDWIDTH=6000000,RESOLUTION=1920x1080,FRAME-RATE=60,CODECS="avc1",AUDIO="a"',
    ];
    final text = '#EXTM3U\n${rows.indexed.map((e) => '#EXT-X-STREAM-INF:${e.$2}\n${e.$1}.m3u8').join('\n')}';
    final q = TwitchSite.parseMasterPlaylist(text, masterUri: Uri.parse('https://example.test/m.m3u8'));
    expect(q, hasLength(4));
    expect(q.where((e) => (e.data as List).length == 2), hasLength(1));
  });

  test('Kuaishou retains HEVC-exclusive source but uses AVC within matching tier', () {
    final q = KuaishowSite.parsePlayQualities({
      'h264': {
        'representation': [
          {'name': '高清', 'level': 1, 'bitrate': 2000, 'url': 'https://example.test/avc.flv'},
        ],
      },
      'hevc': {
        'representation': [
          {'name': '高清', 'level': 1, 'bitrate': 1000, 'url': 'https://example.test/hevc-low.flv'},
          {'name': '原画', 'level': 4, 'url': 'https://example.test/source.flv'},
        ],
      },
    });
    expect(q.map((e) => e.quality), ['原画', '高清']);
    expect(q.last.data, ['https://example.test/avc.flv']);
  });
}
