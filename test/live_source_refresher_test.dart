import 'package:flutter_test/flutter_test.dart';
import 'package:pure_live/common/models/live_room.dart';
import 'package:pure_live/core/interface/live_site.dart';
import 'package:pure_live/model/live_play_quality.dart';
import 'package:pure_live/player/core/live_source_refresher.dart';

void main() {
  test('refresh signs the selected stable quality and keeps its CDN after reordering', () async {
    final site = _LiveSite();
    final source =
        await LiveSourceRefresher(
          siteFor: (_) => site,
          headersFor: (_) async {
            expect(site.requestedQuality?.selectionId, 500);
            return {'Referer': 'fresh-headers'};
          },
        ).resolve(
          room: LiveRoom(roomId: '6657', platform: 'douyu'),
          preferredQuality: LivePlayQuality(quality: '旧高清名称', id: 500),
          preferredQualityIndex: 0,
          preferredLineIndex: 0,
          previousUrl: 'https://cdn-b.example/expired',
        );
    expect(source.qualityIndex, 1);
    expect(source.url, 'https://cdn-b.example/fresh');
    expect(source.headers['Referer'], 'fresh-headers');
    expect(site.detailCalls, 1);
    expect(site.urlCalls, 1);
  });

  test('acknowledged lower quality is reflected and missing lines clamp safely', () async {
    final site = _LiveSite()..appliedQuality = 500;
    final source = await LiveSourceRefresher(siteFor: (_) => site, headersFor: (_) async => {}).resolve(
      room: LiveRoom(roomId: '6657', platform: 'douyu'),
      preferredQuality: LivePlayQuality(quality: '原画', id: 0),
      preferredQualityIndex: 0,
      preferredLineIndex: 8,
      previousUrl: 'https://missing-cdn.example/expired',
    );
    expect(site.requestedQuality?.selectionId, 0);
    expect(source.quality.selectionId, 500);
    expect(source.lineIndex, 1);
  });

  test('offline and recorded rooms never get reopened as a live stream', () async {
    for (final status in [LiveStatus.offline, LiveStatus.replay]) {
      final site = _LiveSite()..status = status;
      await expectLater(
        LiveSourceRefresher(siteFor: (_) => site, headersFor: (_) async => {}).resolve(
          room: LiveRoom(roomId: '6657', platform: 'douyu'),
          preferredQuality: null,
          preferredQualityIndex: 0,
          preferredLineIndex: 0,
          previousUrl: '',
        ),
        throwsA(isA<LiveSourceOffline>()),
      );
      expect(site.urlCalls, 0);
    }
  });

  test('unknown status is retryable rather than reporting a confirmed end', () async {
    final site = _LiveSite()..status = LiveStatus.unknown;
    await expectLater(
      LiveSourceRefresher(siteFor: (_) => site, headersFor: (_) async => {}).resolve(
        room: LiveRoom(roomId: '6657', platform: 'douyu'),
        preferredQuality: null,
        preferredQualityIndex: 0,
        preferredLineIndex: 0,
        previousUrl: '',
      ),
      throwsStateError,
    );
    expect(site.urlCalls, 0);
  });
}

class _LiveSite extends LiveSite implements LivePlayUrlResolver {
  int detailCalls = 0;
  int urlCalls = 0;
  LivePlayQuality? requestedQuality;
  Object? appliedQuality;
  LiveStatus status = LiveStatus.live;

  @override
  Future<LiveRoom> getRoomDetail({required String roomId, required String platform}) async {
    detailCalls++;
    return LiveRoom(
      roomId: roomId,
      platform: platform,
      liveStatus: status,
      status: status == LiveStatus.live,
      isRecord: status == LiveStatus.replay,
    );
  }

  @override
  Future<List<LivePlayQuality>> getPlayQualites({required LiveRoom detail}) async => [
    LivePlayQuality(quality: '原画', id: 0),
    LivePlayQuality(quality: '高清', id: 500),
  ];

  @override
  Future<LivePlayUrlResolution> resolvePlayUrlsRaw({required LiveRoom detail, required LivePlayQuality quality}) async {
    urlCalls++;
    requestedQuality = quality;
    return LivePlayUrlResolution(
      urls: const ['https://cdn-a.example/fresh', 'https://cdn-b.example/fresh'],
      appliedQualityData: appliedQuality ?? quality.selectionId,
    );
  }
}
