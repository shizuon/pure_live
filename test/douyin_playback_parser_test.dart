import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:pure_live/core/site/douyin/douyin_site.dart';

void main() {
  group('Douyin quality parsing', () {
    test('joins legacy pull URL maps by sdk key rather than JSON position', () {
      final qualities = DouyinSite.parseStreamQualities({
        'live_core_sdk_data': {
          'pull_data': {
            'stream_data': '',
            'options': {
              'qualities': [
                {'name': '高清', 'sdk_key': 'HD1', 'v_bit_rate': 2000000},
                {'name': '流畅', 'sdk_key': 'SD2', 'v_bit_rate': 500000},
              ],
            },
          },
        },
        // Deliberately reverse insertion order. Positional pairing used to
        // attach these URLs to the opposite quality.
        'flv_pull_url': {'SD2': 'https://cdn.test/sd2.flv', 'HD1': 'https://cdn.test/hd1.flv'},
        'hls_pull_url_map': {'HD1': 'https://cdn.test/hd1.m3u8', 'SD2': 'https://cdn.test/sd2.m3u8'},
      });

      expect(qualities.map((quality) => quality.quality), ['高清', '流畅']);
      expect(qualities.first.selectionId, 'hd1');
      expect(qualities.first.data, ['https://cdn.test/hd1.flv', 'https://cdn.test/hd1.m3u8']);
      expect(qualities.last.data, ['https://cdn.test/sd2.flv', 'https://cdn.test/sd2.m3u8']);
    });

    test('parses modern stream_data and excludes advertised choices without URLs', () {
      final streamData = jsonEncode({
        'data': {
          'origin': {
            'main': {'flv': 'https://cdn.test/source.flv'},
          },
          'hd': {
            'main': {'flv': 'https://cdn.test/hd.flv', 'hls': 'https://cdn.test/hd.m3u8'},
          },
        },
      });
      final qualities = DouyinSite.parseStreamQualities({
        'live_core_sdk_data': {
          'pull_data': {
            'stream_data': streamData,
            'options': {
              'qualities': [
                {'name': '原画', 'sdk_key': 'origin'},
                {'name': '高清', 'sdk_key': 'HD'},
                {'name': '失效项', 'sdk_key': 'missing'},
              ],
            },
          },
        },
      });

      expect(qualities.map((quality) => quality.quality), ['原画', '高清']);
      expect(qualities.map((quality) => quality.selectionId), ['origin', 'hd']);
    });

    test('retains main and backup routes in each quality and deduplicates legacy URLs', () {
      final qualities = DouyinSite.parseStreamQualities({
        'live_core_sdk_data': {
          'pull_data': {
            'stream_data': jsonEncode({
              'data': {
                'origin': {
                  'main': {'flv': 'https://main.test/source.flv', 'hls': 'https://main.test/source.m3u8'},
                  'backup': {'flv': 'https://backup.test/source.flv', 'hls': 'https://backup.test/source.m3u8'},
                },
                'hd': {
                  'backup': {'flv': 'https://backup.test/hd.flv'},
                },
              },
            }),
          },
        },
        'flv_pull_url': {'origin': 'https://main.test/source.flv'},
      });

      expect(qualities.map((quality) => quality.selectionId), ['origin', 'hd']);
      expect(qualities.first.data, [
        'https://main.test/source.flv',
        'https://main.test/source.m3u8',
        'https://backup.test/source.flv',
        'https://backup.test/source.m3u8',
      ]);
      expect(qualities.last.data, ['https://backup.test/hd.flv']);
    });

    test('merges modern and legacy aliases without dropping alternate CDN routes', () {
      final qualities = DouyinSite.parseStreamQualities({
        'live_core_sdk_data': {
          'pull_data': {
            'options': {
              'qualities': [
                {'name': '旧原画', 'sdk_key': 'ORIGION'},
                {'name': '原画', 'sdk_key': 'origin'},
              ],
            },
            'stream_data': jsonEncode({
              'data': {
                'origin': {
                  'main': {'flv': 'https://main.test/source.flv'},
                  'backup': {'flv': 'https://backup.test/source.flv'},
                },
                'uhd': {
                  'main': {'flv': 'https://main.test/uhd.flv'},
                },
              },
            }),
          },
        },
        'flv_pull_url': {'ORIGION': 'https://main.test/source.flv', 'FULL_HD1': 'https://main.test/uhd.flv'},
        'hls_pull_url_map': {'ORIGION': 'https://legacy.test/source.m3u8', 'FULL_HD1': 'https://legacy.test/uhd.m3u8'},
      });

      expect(qualities.map((quality) => quality.selectionId), ['origin', 'uhd']);
      expect(qualities.map((quality) => quality.quality), ['原画', '蓝光']);
      expect(qualities.first.data, [
        'https://main.test/source.flv',
        'https://backup.test/source.flv',
        'https://legacy.test/source.m3u8',
      ]);
      expect(qualities.last.data, ['https://main.test/uhd.flv', 'https://legacy.test/uhd.m3u8']);
    });

    test('keeps one official top tier when FULL_HD1 points at origin', () {
      final qualities = DouyinSite.parseStreamQualities({
        'live_core_sdk_data': {
          'pull_data': {
            'options': {
              'qualities': [
                {'name': '蓝光', 'sdk_key': 'origin'},
              ],
            },
            'stream_data': jsonEncode({
              'data': {
                'origin': {
                  'main': {'flv': 'https://main.test/source.flv'},
                  'backup': {'flv': 'https://backup.test/source.flv'},
                },
              },
            }),
          },
        },
        'flv_pull_url': {'FULL_HD1': 'https://main.test/source.flv'},
        'hls_pull_url_map': {'FULL_HD1': 'https://legacy.test/source.m3u8'},
      });

      expect(qualities, hasLength(1));
      expect(qualities.single.selectionId, 'origin');
      expect(qualities.single.quality, '蓝光');
      expect(qualities.single.data, [
        'https://main.test/source.flv',
        'https://backup.test/source.flv',
        'https://legacy.test/source.m3u8',
      ]);
    });

    test('keeps audio-only streams out of video quality choices', () {
      final qualities = DouyinSite.parseStreamQualities({
        'live_core_sdk_data': {
          'pull_data': {
            'stream_data': jsonEncode({
              'data': {
                'origin': {
                  'main': {'flv': 'https://cdn.test/source.flv'},
                },
                'audio': {
                  'main': {'flv': 'https://cdn.test/audio.flv', 'hls': 'https://cdn.test/audio.m3u8'},
                },
                'ao': {
                  'main': {'flv': 'https://cdn.test/ao.flv', 'hls': 'https://cdn.test/ao.m3u8'},
                },
              },
            }),
          },
        },
        'flv_pull_url': {'AUDIO': 'https://cdn.test/legacy-audio.flv'},
      });

      expect(qualities.map((quality) => quality.selectionId), ['origin']);
    });

    test('localizes SDK labels and ranks semantic tiers before instantaneous bitrate', () {
      final streamData = jsonEncode({
        'data': {
          'origin': {
            'main': {'flv': 'https://cdn.test/source.flv'},
          },
          'hd': {
            'main': {'flv': 'https://cdn.test/hd.flv'},
          },
          'sd': {
            'main': {'flv': 'https://cdn.test/sd.flv'},
          },
          'ld': {
            'main': {'flv': 'https://cdn.test/ld.flv'},
          },
        },
      });
      final qualities = DouyinSite.parseStreamQualities({
        'live_core_sdk_data': {
          'pull_data': {
            'stream_data': streamData,
            'options': {
              'qualities': [
                // A source stream may report a lower instantaneous bitrate
                // than a transcoded tier. sdk_key/level is the hierarchy.
                {'name': 'origin', 'sdk_key': 'origin', 'level': 4, 'v_bit_rate': 1200000},
                {'name': 'HD', 'sdk_key': 'HD', 'level': 3, 'v_bit_rate': 3000000},
                {'name': 'SD', 'sdk_key': 'SD', 'level': 2, 'v_bit_rate': 1500000},
                {'name': 'LD', 'sdk_key': 'LD', 'level': 1, 'v_bit_rate': 600000},
              ],
            },
          },
        },
      });

      expect(qualities.map((quality) => quality.quality), ['原画', '超清', '高清', '标清']);
      expect(qualities.map((quality) => quality.selectionId), ['origin', 'hd', 'sd', 'ld']);
    });

    test('covers legacy quality keys, sdk metadata and duplicate source aliases', () {
      final sharedSource = 'https://cdn.test/source.flv';
      final streamData = jsonEncode({
        'data': {
          'origin': {
            'main': {'flv': sharedSource},
          },
          'FULL_HD1': {
            'main': {'flv': 'https://cdn.test/blue.flv'},
          },
          'HD1': {
            'main': {'flv': 'https://cdn.test/super.flv'},
          },
          'SD2': {
            'main': {'flv': 'https://cdn.test/high.flv'},
          },
          'SD1': {
            'main': {'flv': 'https://cdn.test/standard.flv'},
          },
          'MD': {
            'main': {
              'flv': 'https://cdn.test/smooth.flv',
              'sdk_params': jsonEncode({'vbitrate': 300000, 'resolution': '360x640'}),
            },
          },
          'ORIGION': {
            'main': {'flv': sharedSource},
          },
        },
      });

      final qualities = DouyinSite.parseStreamQualities({
        'live_core_sdk_data': {
          'pull_data': {'stream_data': streamData},
        },
      });

      expect(qualities.map((quality) => quality.quality), ['原画', '蓝光', '超清', '高清', '标清', '流畅']);
      expect(qualities.map((quality) => quality.selectionId), ['origin', 'full_hd1', 'hd1', 'sd2', 'sd1', 'md']);
      expect(qualities.last.sort, 1000000);
    });
  });
}
