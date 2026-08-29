import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pure_live/core/site/huya/huya_site.dart';

void main() {
  HuyaSite capturedTokenSite() =>
      HuyaSite(tokenLoader: (_) async => throw const FormatException('WUP unavailable in deterministic test'));

  test('Huya treats only explicit inactive states as authoritative offline', () {
    expect(HuyaSite.isExplicitOfflineState('OFF'), isTrue);
    expect(HuyaSite.isExplicitOfflineState(' offline '), isTrue);
    expect(HuyaSite.isExplicitOfflineState('CLOSED'), isTrue);
    expect(HuyaSite.isExplicitOfflineState('ON'), isFalse);
    expect(HuyaSite.isExplicitOfflineState(null), isFalse);
  });

  HuyaLineModel line(
    HuyaLineType type,
    String base, {
    String flvAntiCode = 'wsSecret=flv-token&wsTime=6a87f351',
    String hlsAntiCode = 'wsSecret=hls-token&wsTime=6a87f351',
  }) {
    return HuyaLineModel(
      line: base,
      lineType: type,
      flvAntiCode: flvAntiCode,
      hlsAntiCode: hlsAntiCode,
      streamName: 'stream-name',
      cdnType: 'AL',
      presenterUid: 123,
    );
  }

  test('Huya FLV URL uses the FLV token and extension', () async {
    final url = await capturedTokenSite().getPlayUrl(line(HuyaLineType.flv, 'http://al.flv.huya.com/src'), 8000);

    expect(url, startsWith('https://al.flv.huya.com/src/stream-name.flv?'));
    expect(url, contains('wsSecret=flv-token'));
    expect(url, isNot(contains('wsSecret=hls-token')));
    expect(url, contains('&codec=264'));
    expect(url, contains('&ratio=8000'));
  });

  test('Huya HLS URL uses the HLS token and extension', () async {
    final url = await capturedTokenSite().getPlayUrl(line(HuyaLineType.hls, 'http://al.hls.huya.com/src'), 2000);

    expect(url, startsWith('https://al.hls.huya.com/src/stream-name.m3u8?'));
    expect(url, contains('wsSecret=hls-token'));
    expect(url, isNot(contains('wsSecret=flv-token')));
    expect(url, contains('&codec=264'));
    expect(url, contains('&ratio=2000'));
  });

  test('Huya CDN bases use HTTPS without rewriting unrelated hosts', () {
    expect(HuyaSite.secureHuyaCdnBase('http://tx.flv.huya.com/src'), 'https://tx.flv.huya.com/src');
    expect(HuyaSite.secureHuyaCdnBase('http://example.com/src'), 'http://example.com/src');
  });

  test('Huya quality selection replaces a captured ratio instead of keeping stale quality', () async {
    final url = await capturedTokenSite().getPlayUrl(
      line(
        HuyaLineType.hls,
        'https://al.hls.huya.com/src',
        hlsAntiCode: 'wsSecret=hls-token&wsTime=6a87f351&codec=265&ratio=4000',
      ),
      2000,
    );

    expect(RegExp(r'(^|&)codec=').allMatches(Uri.parse(url).query).length, 1);
    expect(RegExp(r'(^|&)ratio=').allMatches(Uri.parse(url).query).length, 1);
    expect(url, contains('&codec=265'));
    expect(url, contains('&ratio=2000'));
    expect(url, isNot(contains('&ratio=4000')));
  });

  test('Huya source quality removes a captured transcode ratio', () async {
    final url = await capturedTokenSite().getPlayUrl(
      line(
        HuyaLineType.flv,
        'https://tx.flv.huya.com/src',
        flvAntiCode: 'wsSecret=flv-token&wsTime=6a87f351&ratio=500',
      ),
      0,
    );

    expect(Uri.parse(url).queryParameters.containsKey('ratio'), isFalse);
  });

  test('Huya exposes only server advertised bitrates and has stable selection ids', () {
    final data = HuyaUrlDataModel(
      url: '',
      uid: '',
      lines: [line(HuyaLineType.flv, 'https://tx.flv.huya.com/src')],
      bitRates: [
        HuyaBitRateModel(name: '蓝光4M', bitRate: 0),
        HuyaBitRateModel(name: '超清', bitRate: 2000),
        HuyaBitRateModel(name: '重复超清', bitRate: 2000),
        HuyaBitRateModel(name: '流畅', bitRate: 500),
      ],
      isXingxiu: false,
    );

    final qualities = HuyaSite.parsePlayQualities(data);

    expect(qualities.map((quality) => quality.quality), ['蓝光4M', '超清', '流畅']);
    expect(qualities.map((quality) => quality.selectionId), [0, 2000, 500]);
  });

  test('Huya does not invent an unsupported transcode when no rate list exists', () {
    final qualities = HuyaSite.parsePlayQualities(
      HuyaUrlDataModel(url: '', uid: '', lines: const [], bitRates: const [], isXingxiu: false),
    );

    expect(qualities, hasLength(1));
    expect(qualities.single.selectionId, 0);
  });

  test('Huya prefers a fresh WUP token and caches concurrent line resolution', () async {
    var requests = 0;
    final site = HuyaSite(
      tokenLoader: (_) async {
        requests++;
        return 'wsSecret=fresh-token&wsTime=7fffffff&codec=265';
      },
    );

    final urls = await Future.wait([
      site.getPlayUrl(line(HuyaLineType.flv, 'http://al.flv.huya.com/src'), 8000),
      site.getPlayUrl(line(HuyaLineType.hls, 'http://al.hls.huya.com/src'), 2000),
    ]);

    expect(requests, 1);
    expect(urls[0], contains('wsSecret=fresh-token'));
    expect(urls[0], contains('&codec=265'));
    expect(urls[0], endsWith('&ratio=8000'));
    expect(urls[1], startsWith('https://al.hls.huya.com/src/stream-name.m3u8?'));
  });

  test('Huya expires its fresh token cache after two minutes', () async {
    var requests = 0;
    var now = DateTime.utc(2026, 8, 29, 12);
    final site = HuyaSite(now: () => now, tokenLoader: (_) async => 'wsSecret=fresh-${++requests}&wsTime=7fffffff');
    final source = line(HuyaLineType.flv, 'http://al.flv.huya.com/src');

    expect(await site.getPlayUrl(source, 0), contains('wsSecret=fresh-1'));
    now = now.add(const Duration(minutes: 1, seconds: 59));
    expect(await site.getPlayUrl(source, 0), contains('wsSecret=fresh-1'));
    now = now.add(const Duration(seconds: 1));
    expect(await site.getPlayUrl(source, 0), contains('wsSecret=fresh-2'));
    expect(requests, 2);
  });

  test('Huya cools down a failed WUP request while page tokens keep working', () async {
    var requests = 0;
    final site = HuyaSite(
      tokenLoader: (_) async {
        requests++;
        throw const FormatException('WUP unavailable');
      },
    );
    final source = line(HuyaLineType.flv, 'http://al.flv.huya.com/src');

    expect(await site.getPlayUrl(source, 8000), contains('wsSecret=flv-token'));
    expect(await site.getPlayUrl(source, 2000), contains('wsSecret=flv-token'));
    expect(requests, 1);
  });

  test('Huya preserves a captured page signature when WUP is unavailable', () async {
    final site = HuyaSite(tokenLoader: (_) async => throw const SocketException('offline'));
    final source = line(
      HuyaLineType.flv,
      'http://al.flv.huya.com/src',
      flvAntiCode: 'wsSecret=page-secret&wsTime=12345678&fm=YWJjX2RlZg%3D%3D&ctype=huya_live&t=100&fs=bgct',
    );

    final url = await site.getPlayUrl(source, 8000);

    expect(url, contains('wsSecret=page-secret'));
    expect(url, contains('wsTime=12345678'));
    expect(url, isNot(contains('seqid=')));
    expect(url, endsWith('&codec=264&ratio=8000'));
  });
}
