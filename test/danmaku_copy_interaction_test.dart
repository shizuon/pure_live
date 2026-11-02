import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:flame_barrage/flame_barrage.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:pure_live/common/models/live_message.dart';
import 'package:pure_live/common/services/settings/danmaku_settings_controller.dart';
import 'package:pure_live/common/services/settings/font_settings_controller.dart';
import 'package:pure_live/common/services/settings_service.dart';
import 'package:pure_live/common/utils/hive_pref_util.dart';
import 'package:pure_live/get/get.dart';
import 'package:pure_live/modules/live_play/widgets/danmaku/danmaku_gesture_surface.dart';
import 'package:pure_live/modules/live_play/widgets/danmaku/danmaku_list_view.dart';
import 'package:pure_live/modules/live_play/widgets/danmaku/danmaku_message_actions.dart';
import 'package:pure_live/modules/live_play/widgets/video_player/player_top_bar_surface.dart';
import 'package:pure_live/modules/live_play/widgets/video_player/video_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Settings extends SettingsService {
  @override
  final danmaku = DanmakuSettingsController();
  @override
  final font = FontSettingsController();

  @override
  // ignore: must_call_super
  void onInit() {}
}

class _Video extends Fake implements VideoController {
  @override
  final hideDanmaku = false.obs;
  @override
  final danmakuSpeed = 100.0.obs;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory hiveDirectory;
  final copied = <String>[];
  final message = LiveMessage(
    type: LiveMessageType.chat,
    userName: 'do-not-copy-this-name',
    message: '正文: 保留冒号\nhello 🎉',
    color: LiveMessageColor.white,
  );

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
    hiveDirectory = await Directory.systemTemp.createTemp('pure-live-copy-test-');
    Hive.init(hiveDirectory.path);
    await HivePrefUtil.init();
  });

  setUp(() async {
    copied.clear();
    await HivePrefUtil.clear();
    Get.testMode = true;
    Get.reset();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') copied.add((call.arguments as Map)['text'] as String);
        return null;
      },
    );
  });

  tearDown(() {
    Get.reset();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      null,
    );
  });

  tearDownAll(() async {
    await Hive.close();
    await hiveDirectory.delete(recursive: true);
  });

  Widget app(Widget child) => MaterialApp(home: Scaffold(body: child));

  testWidgets('main and compact message callbacks copy the original body only', (tester) async {
    final main = BarrageController();
    final compact = BarrageController();
    final emitted = <BarrageItem>[];
    main.onAddDanmaku = (item) => emitted.add(item as BarrageItem);
    compact.onAddDanmaku = (item) => emitted.add(item as BarrageItem);
    final settings = _Settings();
    settings.danmaku.enableDanmakuDisplay.value = true;
    settings.danmaku.enablePipDanmaku.value = true;
    final manager = DanmakuManager(
      controller: main,
      pipController: compact,
      settingsService: settings,
      videoController: _Video(),
    );
    addTearDown(manager.dispose);
    manager.sendDanmaku(message, true, true);
    expect(emitted, hasLength(2));
    for (final item in emitted) {
      item.onTapUp!();
      await tester.pump();
    }
    expect(copied, [message.message, message.message]);
    main.detach();
    compact.detach();
  });

  testWidgets('sidebar single click copies only the body', (tester) async {
    Get.put<SettingsService>(_Settings());
    await tester.pumpWidget(
      GetMaterialApp(
        home: Scaffold(body: DanmakuItem(danmaku: message)),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byType(Text));
    await tester.pump();
    expect(copied, [message.message]);
  });

  testWidgets('message action menu copies only the body', (tester) async {
    await tester.pumpWidget(
      app(
        Builder(
          builder: (context) =>
              TextButton(onPressed: () => DanmakuMessageActions.show(context, message), child: const Text('open')),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.copy_all_rounded));
    await tester.pumpAndSettle();
    expect(copied, [message.message]);
  });

  testWidgets('first two rows remain clickable through the top title and gradient', (tester) async {
    final rows = <int>[];
    var controls = 0;
    var background = 0;
    await tester.pumpWidget(
      app(
        SizedBox(
          width: 600,
          height: 200,
          child: Stack(
            children: [
              Positioned.fill(
                child: DanmakuGestureSurface(
                  resolveAction: (point, {required longPress}) =>
                      point.dy < 48 ? () => rows.add(point.dy < 24 ? 0 : 1) : null,
                  onBackgroundTap: () => background++,
                  child: const SizedBox.expand(),
                ),
              ),
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                height: 56,
                child: PlayerTopBarSurface(
                  title: const Column(children: [Text('visible room title'), Text('current programme')]),
                  actions: [
                    IconButton(
                      key: const ValueKey('control'),
                      onPressed: () => controls++,
                      icon: const Icon(Icons.volume_up),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.tapAt(const Offset(120, 12));
    await tester.tapAt(const Offset(120, 36));
    await tester.tapAt(const Offset(2, 36)); // Gradient/padding, outside title.
    await tester.tap(find.byKey(const ValueKey('control')));
    await tester.tapAt(const Offset(120, 100));
    expect(rows, [0, 1, 1]);
    expect(controls, 1);
    expect(background, 1);
  });

  testWidgets('single click retains the message under pointer down while text moves', (tester) async {
    var current = 'first';
    final actions = <String>[];
    await tester.pumpWidget(
      app(
        DanmakuGestureSurface(
          resolveAction: (point, {required longPress}) {
            final selected = current;
            return () => actions.add(selected);
          },
          onDoubleTap: () => actions.add('fullscreen'),
          child: const SizedBox.expand(),
        ),
      ),
    );
    final gesture = await tester.startGesture(const Offset(100, 20));
    current = 'another message';
    await tester.pump(const Duration(milliseconds: 150));
    await gesture.up();
    expect(actions, isEmpty);
    await tester.pump(const Duration(milliseconds: 350));
    expect(actions, ['first']);
  });

  testWidgets('long press retains the selected message and never copies', (tester) async {
    var current = 'first';
    final actions = <String>[];
    await tester.pumpWidget(
      app(
        DanmakuGestureSurface(
          resolveAction: (point, {required longPress}) {
            final selected = current;
            return () => actions.add('${longPress ? 'menu' : 'copy'}:$selected');
          },
          onDoubleTap: () {},
          child: const SizedBox.expand(),
        ),
      ),
    );
    final gesture = await tester.startGesture(const Offset(100, 20));
    current = 'later';
    await tester.pump(const Duration(milliseconds: 600));
    await gesture.up();
    await tester.pump(const Duration(milliseconds: 400));
    expect(actions, ['menu:first']);
  });

  testWidgets('double tap, drag and pointer cancel never copy', (tester) async {
    var copies = 0;
    var doubles = 0;
    var drags = 0;
    await tester.pumpWidget(
      app(
        DanmakuGestureSurface(
          resolveAction: (point, {required longPress}) =>
              () => copies++,
          onDoubleTap: () => doubles++,
          onPanStart: (_) => drags++,
          child: const SizedBox.expand(),
        ),
      ),
    );
    await tester.tapAt(const Offset(100, 20));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tapAt(const Offset(100, 20));
    await tester.pump(const Duration(milliseconds: 400));
    expect(doubles, 1);
    final drag = await tester.startGesture(const Offset(100, 20));
    await drag.moveBy(const Offset(0, 60));
    await drag.up();
    await tester.pump(const Duration(milliseconds: 400));
    expect(drags, 1);
    final cancel = await tester.startGesture(const Offset(100, 20));
    await cancel.cancel();
    await tester.pump(const Duration(milliseconds: 400));
    expect(copies, 0);
  });

  testWidgets('engine snapshots survive movement but not clear or detach', (tester) async {
    final controller = BarrageController();
    var taps = 0;
    await tester.pumpWidget(
      app(
        Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: 400,
            height: 200,
            child: FlameBarrageWidget(
              config: const BarrageConfig(
                safeArea: false,
                baseSpeed: 400,
                fontSize: 16,
                trackHeight: 24,
                emitInterval: .01,
              ),
              emojiAtlas: EmojiAtlas.instance,
              controller: controller,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    final engine = controller.engine as BarrageEngine;
    addTearDown(engine.clear);
    controller.send(BarrageItem(content: 'A', onTapUp: () => taps++));
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    Offset? hit;
    for (var y = 0; y < 48 && hit == null; y += 2) {
      for (var x = 0; x < 400 && hit == null; x += 2) {
        if (controller.actionAt(x.toDouble(), y.toDouble(), longPress: false) != null)
          hit = Offset(x.toDouble(), y.toDouble());
      }
    }
    expect(hit, isNotNull);
    final action = controller.actionAt(hit!.dx, hit.dy, longPress: false)!;
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(controller.actionAt(hit.dx, hit.dy, longPress: false), isNull);
    action();
    expect(taps, 1);
    controller.clear();
    action();
    expect(taps, 1);
    controller.detach();
    action();
    expect(taps, 1);
  });
}
