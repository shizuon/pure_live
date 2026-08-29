import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:pure_live/common/services/utils/settings_upgrade_migration.dart';

Map<String, dynamic> room(String id, {String title = ''}) => {
  'platform': 'bilibili',
  'roomId': id,
  'title': title,
  'tagIds': <String>[],
};

void main() {
  group('Windows settings upgrade migration', () {
    test('converts legacy lists and unions follows from previous installs', () {
      final current = <String, dynamic>{
        'favoriteRooms': [jsonEncode(room('1', title: 'current')), jsonEncode(room('2'))],
        'historyRooms': [jsonEncode(room('1'))],
        'danmakuArea': 0.8,
        'audienceMetricMigration': 2,
      };
      final previousInstall = <String, dynamic>{
        'favoriteRooms': jsonEncode({
          'list': [room('1', title: 'previous'), room('3')],
        }),
        'historyRooms': jsonEncode({
          'list': [room('2'), room('3')],
        }),
        'danmakuArea': 0.45,
        'themeColorSwitch': 'blue',
      };

      final merged = SettingsUpgradeMigration.mergeRawSettings(current, [
        previousInstall,
      ], preferRichestSourceScalars: true);
      final favorites = (jsonDecode(merged['favoriteRooms'] as String) as Map)['list'] as List;
      final history = (jsonDecode(merged['historyRooms'] as String) as Map)['list'] as List;

      expect(favorites.map((item) => item['roomId']), ['1', '2', '3']);
      expect(favorites.first['title'], 'current');
      expect(history.map((item) => item['roomId']), ['1', '2', '3']);
      expect(merged['danmakuArea'], 0.45);
      expect(merged['themeColorSwitch'], 'blue');
      expect(merged['audienceMetricMigration'], 2);
    });

    test('unions block lists and tolerates damaged collection values', () {
      final merged = SettingsUpgradeMigration.mergeRawSettings(
        {
          'shieldList': ['广告'],
          'favoriteAreas': '{damaged',
        },
        [
          {
            'shieldList': ['广告', '剧透'],
            'blockedDanmakuUsers': ['user-a'],
            'favoriteAreas': jsonEncode({
              'list': [
                {'platform': 'huya', 'areaId': 'game'},
              ],
            }),
          },
        ],
      );

      expect(merged['shieldList'], ['广告', '剧透']);
      expect(merged['blockedDanmakuUsers'], ['user-a']);
      final areas = (jsonDecode(merged['favoriteAreas'] as String) as Map)['list'] as List;
      expect(areas, hasLength(1));
    });

    test('never revives stale volume scalars from a previous install', () {
      final merged = SettingsUpgradeMigration.mergeRawSettings(
        {
          'favoriteRooms': [jsonEncode(room('1'))],
          'globalVolumeMute': false,
          'defaultDesktopVolume': 0.8,
          'defaultMobileVolume': 0.4,
          'roomVolumes': '{"room":0.7}',
        },
        [
          {
            'favoriteRooms': jsonEncode({
              'list': [room('2')],
            }),
            'globalVolumeMute': true,
            'defaultDesktopVolume': 0.0,
            'defaultMobileVolume': 0.0,
            'roomVolumes': '{}',
          },
        ],
        preferRichestSourceScalars: true,
      );

      expect(merged['globalVolumeMute'], isFalse);
      expect(merged['defaultDesktopVolume'], 0.8);
      expect(merged['defaultMobileVolume'], 0.4);
      expect(merged['roomVolumes'], '{"room":0.7}');
    });

    test('does not silently truncate a configured unlimited history during upgrade', () {
      final rooms = List.generate(75, (index) => room('$index'));
      final merged = SettingsUpgradeMigration.mergeRawSettings(
        {
          'historyLimit': 0,
          'historyRooms': jsonEncode({'list': rooms.take(40).toList()}),
        },
        [
          {
            'historyLimit': 0,
            'historyRooms': jsonEncode({'list': rooms.skip(40).toList()}),
          },
        ],
      );
      final history = (jsonDecode(merged['historyRooms'] as String) as Map)['list'] as List;

      expect(history, hasLength(75));
      expect(merged['historyLimit'], 0);
    });

    test('imports a legacy Hive file once and persists the source ledger', () async {
      final root = await Directory.systemTemp.createTemp('pure_live_upgrade_test_');
      final targetDirectory = Directory('${root.path}/target')..createSync();
      final sourceDirectory = Directory('${root.path}/source')..createSync();
      final workingDirectory = Directory('${root.path}/working');

      try {
        Hive.init(sourceDirectory.path);
        final source = await Hive.openBox<dynamic>('app_settings');
        await source.put(
          'favoriteRooms',
          jsonEncode({
            'list': [room('2'), room('3')],
          }),
        );
        await source.close();

        Hive.init(targetDirectory.path);
        final target = await Hive.openBox<dynamic>('app_settings');
        await target.put('favoriteRooms', [jsonEncode(room('1')), jsonEncode(room('2'))]);

        final first = await SettingsUpgradeMigration.migrate(
          target: target,
          legacyHiveFiles: ['${sourceDirectory.path}/app_settings.hive'],
          workingDirectory: workingDirectory,
        );
        final second = await SettingsUpgradeMigration.migrate(
          target: target,
          legacyHiveFiles: ['${sourceDirectory.path}/app_settings.hive'],
          workingDirectory: workingDirectory,
        );

        expect(first.importedSources, 1);
        expect(first.favoriteCount, 3);
        expect(second.importedSources, 0);
        expect(second.favoriteCount, 3);
        await target.close();
      } finally {
        await Hive.close();
        await root.delete(recursive: true);
      }
    });

    test('repairs the pre-v5 all-zero global mute trap once', () async {
      final root = await Directory.systemTemp.createTemp('pure_live_volume_upgrade_test_');
      try {
        Hive.init(root.path);
        final target = await Hive.openBox<dynamic>('app_settings');
        await target.putAll({
          'settingsUpgradeSchema': 4,
          'globalVolumeMute': true,
          'defaultDesktopVolume': 0.0,
          'defaultMobileVolume': 0.0,
        });

        await SettingsUpgradeMigration.migrate(
          target: target,
          legacyHiveFiles: const [],
          workingDirectory: Directory('${root.path}/working'),
        );

        expect(target.get('globalVolumeMute'), isFalse);
        expect(target.get('defaultDesktopVolume'), 1.0);
        expect(target.get('defaultMobileVolume'), 0.5);
        expect(target.get('settingsUpgradeSchema'), SettingsUpgradeMigration.schemaVersion);
        await target.close();
      } finally {
        await Hive.close();
        await root.delete(recursive: true);
      }
    });
  });
}
