import 'package:flame_barrage/flame_barrage.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pure_live/common/models/live_message.dart';
import 'package:pure_live/modules/live_play/widgets/danmaku/danmaku_gesture_surface.dart';
import 'package:pure_live/modules/live_play/widgets/danmaku/danmaku_message_actions.dart';

void main() {
  for (final buttons in [kPrimaryButton, kSecondaryButton]) {
    testWidgets('${buttons == kPrimaryButton ? 'left' : 'right'} click captures a moving message at pointer down', (
      tester,
    ) async {
      final harness = await _mount(tester);
      final point = harness.messagePoint();
      final gesture = await tester.startGesture(point, kind: PointerDeviceKind.mouse, buttons: buttons);
      await _advance(tester, 12);
      // The original implementation hits this now-empty position after the
      // tap/double-tap decision. The captured message must remain actionable.
      expect(harness.itemAt(point), isNull);
      await gesture.up();
      await _advance(tester, 24);
      expect(harness.events, ['tap:first']);
    });
  }

  testWidgets('double click on a message only toggles fullscreen', (tester) async {
    final harness = await _mount(tester);
    final point = harness.messagePoint();
    await tester.tapAt(point, kind: PointerDeviceKind.mouse);
    await tester.pump(const Duration(milliseconds: 70));
    await tester.tapAt(point, kind: PointerDeviceKind.mouse);
    await _advance(tester, 24);
    expect(harness.events, ['fullscreen']);
  });

  testWidgets('long press keeps its target even after the text scrolls away', (tester) async {
    final harness = await _mount(tester);
    final point = harness.messagePoint();
    final gesture = await tester.startGesture(point);
    await _advance(tester, 40);
    expect(harness.itemAt(point), isNull);
    await gesture.up();
    await _advance(tester, 24);
    expect(harness.events, ['long:first']);
  });

  testWidgets('vertical drag cancels the message menu and keeps volume gestures', (tester) async {
    final harness = await _mount(tester);
    final point = harness.messagePoint();
    final gesture = await tester.startGesture(point);
    await gesture.moveBy(const Offset(0, 40));
    await tester.pump(const Duration(milliseconds: 40));
    await gesture.moveBy(const Offset(0, 30));
    await gesture.up();
    await _advance(tester, 40);
    expect(harness.events, isNotEmpty);
    expect(harness.events.every((event) => event == 'drag'), isTrue);
  });

  testWidgets('cancelled pointer never opens a menu', (tester) async {
    final harness = await _mount(tester);
    final gesture = await tester.startGesture(harness.messagePoint());
    await gesture.cancel();
    await _advance(tester, 40);
    expect(harness.events, isEmpty);
  });

  testWidgets('empty clicks reveal controls and right clicks on empty space do nothing', (tester) async {
    final harness = await _mount(tester);
    final point = harness.origin + const Offset(80, 180);
    await tester.tapAt(point, kind: PointerDeviceKind.mouse);
    await _advance(tester, 24);
    expect(harness.events, ['controls']);
    final right = await tester.startGesture(point, kind: PointerDeviceKind.mouse, buttons: kSecondaryButton);
    await right.up();
    await _advance(tester, 24);
    expect(harness.events, ['controls']);
  });

  testWidgets('message without enabled actions falls through to playback controls', (tester) async {
    final harness = await _mount(tester, interactive: false);
    await tester.tapAt(harness.messagePoint(), kind: PointerDeviceKind.mouse);
    await _advance(tester, 24);
    expect(harness.events, ['controls']);
  });

  testWidgets('right click opens the real action sheet and copies the captured message', (tester) async {
    String? clipboard;
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') clipboard = (call.arguments as Map)['text'] as String;
      return null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(SystemChannels.platform, null));
    final harness = await _mount(tester, showMenu: true);
    final gesture = await tester.startGesture(
      harness.messagePoint(),
      kind: PointerDeviceKind.mouse,
      buttons: kSecondaryButton,
    );
    await _advance(tester, 12);
    await gesture.up();
    await tester.pumpAndSettle();
    expect(find.text('viewer: first'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.copy_all_rounded));
    await tester.pumpAndSettle();
    expect(clipboard, 'viewer: first');
  });
}

Future<void> _advance(WidgetTester tester, int frames) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(microseconds: 16667));
  }
}

class _Harness {
  final controller = BarrageController();
  final surfaceKey = GlobalKey();
  final events = <String>[];

  RenderBox get box => surfaceKey.currentContext!.findRenderObject()! as RenderBox;
  Offset get origin => box.localToGlobal(Offset.zero);

  BarrageItem? itemAt(Offset global) {
    final local = box.globalToLocal(global);
    return controller.itemAt(local.dx, local.dy);
  }

  Offset messagePoint() {
    // Pick the trailing edge of the real painted item so that it has definitely
    // vacated this pixel before recognition completes. No private entry access.
    for (var x = 398.0; x >= 0; x -= 2) {
      for (var y = 2.0; y < 80; y += 2) {
        if (controller.itemAt(x, y) != null) return origin + Offset(x, y);
      }
    }
    throw StateError('Expected a visible scrolling message');
  }
}

Future<_Harness> _mount(WidgetTester tester, {bool interactive = true, bool showMenu = false}) async {
  final harness = _Harness();
  late BuildContext menuContext;
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 400,
            height: 200,
            child: Builder(
              builder: (context) {
                menuContext = context;
                return Stack(
                  fit: StackFit.expand,
                  children: [
                    FlameBarrageWidget(
                      key: harness.surfaceKey,
                      config: const BarrageConfig(
                        safeArea: false,
                        fontSize: 20,
                        baseSpeed: 240,
                        emitInterval: .01,
                        fps: 60,
                      ),
                      emojiAtlas: EmojiAtlas.instance,
                      controller: harness.controller,
                    ),
                    DanmakuGestureSurface(
                      captureTarget: (point) {
                        final item = harness.itemAt(point);
                        return item == null
                            ? null
                            : DanmakuPointerTarget(onTap: item.onTapUp, onLongPress: item.onLongTapDown);
                      },
                      onBackgroundTap: () => harness.events.add('controls'),
                      onDoubleTap: () => harness.events.add('fullscreen'),
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onVerticalDragUpdate: (_) => harness.events.add('drag'),
                        child: const SizedBox.expand(),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  harness.controller.send(
    BarrageItem(
      content: 'first',
      onTapUp: !interactive
          ? null
          : () {
              harness.events.add('tap:first');
              if (showMenu) {
                harness.controller.pause();
                DanmakuMessageActions.show(
                  menuContext,
                  LiveMessage(
                    type: LiveMessageType.chat,
                    userName: 'viewer',
                    message: 'first',
                    color: LiveMessageColor(255, 255, 255),
                    isLocal: true,
                  ),
                );
              }
            },
      onLongTapDown: !interactive ? null : () => harness.events.add('long:first'),
    ),
  );
  await _advance(tester, 30);
  addTearDown(harness.controller.clear);
  return harness;
}
