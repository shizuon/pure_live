import 'dart:async';
import 'dart:io';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:pure_live/common/services/settings_service.dart';
import 'package:pure_live/common/services/settings/window_size_controller.dart';
import 'package:pure_live/common/utils/hive_pref_util.dart';
import 'package:pure_live/get/get.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('pure_live_settings_registration_');
    Hive.init(directory.path);
    await HivePrefUtil.init();
  });
  tearDown(() async {
    Get.deleteAll(force: true);
    Get.reset();
    await Hive.close();
    await directory.delete(recursive: true);
  });

  test('settings lookup and fenix recreation do not enqueue a second ready callback', () {
    fakeAsync((async) {
      final delayedReady = <Duration>[];
      runZoned(
        () {
          final settings = Get.put(SettingsService());
          expect(Get.isPrepared<WindowSizeController>(), isTrue);
          final first = settings.window;
          expect(first.initialized, isTrue);
          expect(settings.window, same(first));
          Get.delete<WindowSizeController>();
          final next = settings.window;
          expect(next, isNot(same(first)));
          expect(next.initialized, isTrue);
          async.elapse(const Duration(seconds: 1));
          expect(delayedReady, isEmpty);
        },
        zoneSpecification: ZoneSpecification(
          createTimer: (self, parent, zone, duration, callback) {
            if (duration == const Duration(milliseconds: 200)) delayedReady.add(duration);
            return parent.createTimer(zone, duration, callback);
          },
        ),
      );
    });
  });
}
