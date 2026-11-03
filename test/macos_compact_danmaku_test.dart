import 'dart:io';

import 'package:flame_barrage/flame_barrage.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:pure_live/common/services/settings/danmaku_settings_controller.dart';
import 'package:pure_live/common/utils/hive_pref_util.dart';
import 'package:pure_live/modules/live_play/widgets/danmaku/compact_danmaku_metrics.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory temp;

  setUpAll(() async {
    temp = await Directory.systemTemp.createTemp('macos-compact-danmaku');
    Hive.init(temp.path);
    await HivePrefUtil.init();
  });
  setUp(() async {
    await HivePrefUtil.clear();
  });
  tearDown(() => debugDefaultTargetPlatformOverride = null);
  tearDownAll(() async {
    await Hive.close();
    await temp.delete(recursive: true);
  });

  test('Mac automatic PiP follows its display, while manual and mobile budgets stay explicit', () {
    final settings = DanmakuSettingsController();
    expect(settings.resolvedDanmakuFps(pip: true, compactDisplayRefreshRate: 120), 120);
    expect(settings.resolvedDanmakuFps(pip: true, compactDisplayRefreshRate: 59.94), 60);
    expect(settings.resolvedDanmakuFps(pip: true, compactDisplayRefreshRate: 0), 60);
    expect(settings.resolvedDanmakuFps(pip: true, compactDisplayRefreshRate: double.nan), 60);
    expect(settings.resolvedDanmakuFps(pip: true), 30);
    settings.pipDanmakuAutoFps.value = false;
    settings.pipDanmakuFps.value = 24;
    expect(settings.resolvedDanmakuFps(pip: true, compactDisplayRefreshRate: 120), 24);
  });

  test('Mac upgrades the old default only once and keeps later user choices', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    final settings = DanmakuSettingsController();
    settings.pipDanmakuFontSize.value = 12;
    settings.onInit();
    expect(settings.pipDanmakuFontSize.value, 14);
    settings.pipDanmakuFontSize.value = 12;
    settings.onInit();
    expect(settings.pipDanmakuFontSize.value, 12);
  });

  test('Mac preserves custom sizes and resets to a readable default', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    final settings = DanmakuSettingsController();
    settings.pipDanmakuFontSize.value = 18;
    settings.onInit();
    expect(settings.pipDanmakuFontSize.value, 18);
    settings.resetPipDanmaku();
    expect(settings.pipDanmakuFontSize.value, 14);
    expect(DanmakuSettingsController.extractConfig({'danmaku': <String, dynamic>{}})['pipDanmakuFontSize'], 14);
  });

  test('Android and Windows retain their existing compact defaults', () {
    for (final platform in [TargetPlatform.android, TargetPlatform.windows]) {
      debugDefaultTargetPlatformOverride = platform;
      final settings = DanmakuSettingsController();
      settings.pipDanmakuFontSize.value = 12;
      settings.onInit();
      expect(settings.pipDanmakuFontSize.value, 12);
      expect(settings.macosPipReadabilityMigration.value, 0);
    }
  });

  test('narrow Mac windows retain readable text without ignoring manual scale', () {
    expect(resolveCompactDanmakuScale(width: 180, autoScale: true, macos: true) * 14, closeTo(11.9, .01));
    expect(resolveCompactDanmakuScale(width: 180, autoScale: true, macos: false), .65);
    expect(resolveCompactDanmakuScale(width: 180, autoScale: false, macos: true), 1);
    expect(resolveCompactDanmakuScale(width: 700, autoScale: true, macos: true), 1);
    expect(resolveCompactDanmakuScale(width: double.infinity, autoScale: true, macos: true), 1);
  });

  testWidgets('120 Hz compact rendering advances on every display frame', (tester) async {
    final controller = BarrageController();
    final settings = DanmakuSettingsController();
    await tester.pumpWidget(
      MaterialApp(
        home: FlameBarrageWidget(
          config: BarrageConfig(fps: settings.resolvedDanmakuFps(pip: true, compactDisplayRefreshRate: 120)),
          emojiAtlas: EmojiAtlas.instance,
          controller: controller,
        ),
      ),
    );
    await tester.pump();
    final engine = controller.engine as BarrageEngine;
    controller.send(const BarrageItem(content: 'smooth compact motion'));
    final before = engine.frameStepCount;
    for (var i = 0; i < 121; i++) {
      await tester.pump(const Duration(microseconds: 8333));
    }
    expect(engine.frameStepCount - before, inInclusiveRange(119, 121));
    await tester.pumpWidget(const SizedBox());
    expect(engine.framePulseActive, isFalse);
  });

  testWidgets('refresh rate alone updates when moving between equal-DPI displays', (tester) async {
    final rates = <double?>[];
    tester.view.display.refreshRate = 120;
    addTearDown(tester.view.display.resetRefreshRate);
    await tester.pumpWidget(
      MaterialApp(
        home: CompactDanmakuDisplay(
          builder: (context, rate) {
            rates.add(rate);
            return const SizedBox();
          },
        ),
      ),
    );
    expect(rates.last, 120);
    tester.view.display.refreshRate = 60;
    await tester.pump();
    expect(rates.last, 60);
    await tester.pumpWidget(const SizedBox());
    tester.view.display.refreshRate = 120;
    await tester.pump();
    expect(tester.takeException(), isNull);
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));
}
