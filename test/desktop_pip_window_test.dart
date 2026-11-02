import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:pure_live/get/get.dart';
import 'package:pure_live/common/services/settings/player_settings_controller.dart';
import 'package:pure_live/common/services/settings/window_size_controller.dart';
import 'package:pure_live/common/services/settings_service.dart';
import 'package:pure_live/common/utils/hive_pref_util.dart';
import 'package:pure_live/player/utils/desktop_fullscreen_transition.dart';
import 'package:pure_live/player/utils/window_helper.dart';
import 'package:pure_live/player/widgets/desktop_pip_controls.dart';
import 'package:pure_live/modules/live_play/widgets/video_player/video_controller_panel.dart';
import 'package:window_manager/window_manager.dart';

class _Settings extends SettingsService {
  @override
  // ignore: must_call_super -- deterministic fixture, no background services.
  void onInit() {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('window_manager');
  const screens = MethodChannel('dev.leanflutter.plugins/screen_retriever');
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late Directory temp;
  late Rect bounds;
  late bool alwaysOnTop, maximized, allSpaces, buttonsVisible, fullscreen;
  late List<MethodCall> calls;
  var failNextBounds = false;
  Completer<void>? resizeGate;
  const normalBounds = Rect.fromLTWH(80, 100, 1000, 620);
  final display = {
    'id': 'main',
    'size': {'width': 1920.0, 'height': 1080.0},
    'visiblePosition': {'dx': 0.0, 'dy': 24.0},
    'visibleSize': {'width': 1920.0, 'height': 1016.0},
  };

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('desktop-pip');
    Hive.init(temp.path);
    await HivePrefUtil.init();
    Get.testMode = true;
    Get.put(PlayerSettingsController());
    Get.put(WindowSizeController());
    Get.put<SettingsService>(_Settings());
    bounds = normalBounds;
    alwaysOnTop = false;
    maximized = false;
    allSpaces = false;
    buttonsVisible = true;
    fullscreen = false;
    failNextBounds = false;
    resizeGate = null;
    calls = [];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      final args = call.arguments as Map? ?? {};
      switch (call.method) {
        case 'isAlwaysOnTop':
          return alwaysOnTop;
        case 'isMaximized':
          return maximized;
        case 'isVisibleOnAllWorkspaces':
          return allSpaces;
        case 'isFullScreen':
          return fullscreen;
        case 'setAlwaysOnTop':
          alwaysOnTop = args['isAlwaysOnTop'];
        case 'setVisibleOnAllWorkspaces':
          allSpaces = args['visible'];
        case 'setTitleBarStyle':
          buttonsVisible = args['windowButtonVisibility'];
        case 'setFullScreen':
          fullscreen = args['isFullScreen'];
        case 'unmaximize':
          maximized = false;
          bounds = normalBounds;
        case 'maximize':
          maximized = true;
        case 'getBounds':
          return {'x': bounds.left, 'y': bounds.top, 'width': bounds.width, 'height': bounds.height};
        case 'setBounds':
          await resizeGate?.future;
          if (failNextBounds) {
            failNextBounds = false;
            throw PlatformException(code: 'fixture-resize-failure');
          }
          bounds = Rect.fromLTWH(
            args['x'] ?? bounds.left,
            args['y'] ?? bounds.top,
            args['width'] ?? bounds.width,
            args['height'] ?? bounds.height,
          );
      }
      return null;
    });
    messenger.setMockMethodCallHandler(
      screens,
      (call) async => call.method == 'getAllDisplays'
          ? {
              'displays': [display],
            }
          : display,
    );
  });
  tearDown(() async {
    messenger.setMockMethodCallHandler(channel, null);
    messenger.setMockMethodCallHandler(screens, null);
    Get.reset();
    await Hive.close();
    await temp.delete(recursive: true);
  });

  for (final macos in [false, true]) {
    test('${macos ? 'Mac' : 'Windows'} mini player restores geometry, stacking and native chrome', () async {
      final helper = WindowHelper.forTesting(macos);
      await helper.enterPiP(16 / 9);
      expect(helper.currentMode, WindowLayoutMode.pip);
      expect(alwaysOnTop, isTrue);
      expect(bounds.width, 360);
      expect(bounds.height, closeTo(202.5, .01));
      if (macos) {
        expect(allSpaces, isTrue);
        expect(buttonsVisible, isFalse);
        expect(
          calls.where((c) => c.method == 'setVisibleOnAllWorkspaces').last.arguments['visibleOnFullScreen'],
          isTrue,
        );
      }
      await helper.exitPiP();
      expect(helper.currentMode, WindowLayoutMode.normal);
      expect(bounds, normalBounds);
      expect(alwaysOnTop, isFalse);
      expect(allSpaces, isFalse);
      expect(buttonsVisible, isTrue);
      expect(calls.where((c) => c.method == 'setMinimumSize').last.arguments['width'], 400);
    });
  }

  test('repeated clicks do not overwrite the main-window snapshot', () async {
    final helper = WindowHelper.forTesting();
    await Future.wait([helper.enterPiP(16 / 9), helper.enterPiP(16 / 9)]);
    await Future.wait([helper.exitPiP(), helper.exitPiP()]);
    expect(bounds, normalBounds);
    expect(helper.currentMode, WindowLayoutMode.normal);
  });

  test('preserves an existing topmost and maximized normal window', () async {
    alwaysOnTop = true;
    maximized = true;
    bounds = const Rect.fromLTWH(0, 24, 1920, 1016);
    final helper = WindowHelper.forTesting();
    await helper.enterPiP(9 / 16);
    expect(maximized, isFalse);
    expect(bounds.height, 380);
    await helper.exitPiP();
    expect(maximized, isTrue);
    expect(alwaysOnTop, isTrue);
    expect(bounds, normalBounds);
  });

  test('a native entry failure rolls back size, chrome and topmost state', () async {
    final helper = WindowHelper.forTesting(true);
    failNextBounds = true;
    await expectLater(helper.enterPiP(16 / 9), throwsA(isA<PlatformException>()));
    expect(bounds, normalBounds);
    expect(alwaysOnTop, isFalse);
    expect(allSpaces, isFalse);
    expect(buttonsVisible, isTrue);
    expect(helper.currentMode, WindowLayoutMode.normal);
    expect(helper.isTransitioning, isFalse);
    await helper.enterPiP(16 / 9);
    await helper.exitPiP();
    expect(bounds, normalBounds);
  });

  test('exit during entry waits until entry completes and restores once', () async {
    final helper = WindowHelper.forTesting();
    resizeGate = Completer<void>();
    final enter = helper.enterPiP(16 / 9);
    final exit = helper.exitPiP();
    resizeGate!.complete();
    await enter;
    await exit;
    expect(bounds, normalBounds);
    expect(helper.currentMode, WindowLayoutMode.normal);
  });

  test('Mac full-screen transition waits for its native completion event', () async {
    fullscreen = true;
    var complete = false;
    final before = windowManager.listeners.length;
    final future = setDesktopFullScreen(false, waitForEvent: true).then((_) => complete = true);
    // Drain just the method-channel microtasks, not a guessed animation delay.
    await Future<void>.delayed(Duration.zero);
    expect(complete, isFalse);
    expect(windowManager.listeners.length, before + 1);
    for (final listener in windowManager.listeners) {
      listener.onWindowEvent('leave-full-screen');
    }
    await future;
    expect(complete, isTrue);
    expect(windowManager.listeners.length, before);
  });

  test('Mac PiP button is available in normal and full-screen playback', () {
    for (final fullscreen in [false, true]) {
      expect(
        resolveTopActionTrailingSlots(fullscreen: fullscreen, android: false, windows: false, macos: true),
        contains(TopActionTrailingSlot.pip),
      );
    }
    expect(
      resolveTopActionTrailingSlots(fullscreen: false, android: false, windows: false),
      isNot(contains(TopActionTrailingSlot.pip)),
    );
  });

  testWidgets('hidden controls pass input to video; visible controls toggle chat and restore', (tester) async {
    var underlying = 0, toggled = 0, restored = 0;
    Widget surface(bool visible) => MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 360,
          height: 203,
          child: Stack(
            fit: StackFit.expand,
            children: [
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => underlying++,
                child: const ColoredBox(color: Colors.black),
              ),
              DesktopPipControls(
                visible: visible,
                playing: true,
                danmakuEnabled: true,
                onTogglePlayback: () {},
                onToggleDanmaku: () => toggled++,
                onRestore: () => restored++,
                restoreLabel: 'Restore',
                danmakuLabel: 'Chat',
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpWidget(surface(false));
    await tester.tapAt(const Offset(180, 100));
    expect(underlying, 1);
    await tester.pumpWidget(surface(true));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('desktop-pip-danmaku')));
    await tester.tap(find.byKey(const ValueKey('desktop-pip-restore')));
    expect(toggled, 1);
    expect(restored, 1);
    expect(tester.takeException(), isNull);
  });
}
