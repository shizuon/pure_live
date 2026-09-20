import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pure_live/modules/live_play/widgets/commentary_touch_calibration.dart';
import 'package:pure_live/modules/live_play/widgets/commentary_video_overlay.dart';
import 'package:pure_live/player/interface/unified_player_interface.dart';
import 'package:pure_live/player/widgets/stable_player_video.dart';

void main() {
  testWidgets('phone, tablet split view and landscape show A/B without overflow', (tester) async {
    addTearDown(() => tester.view.resetPhysicalSize());
    addTearDown(() => tester.view.resetDevicePixelRatio());
    tester.view.devicePixelRatio = 1;
    for (final size in const [Size(320, 568), Size(390, 844), Size(844, 390), Size(507, 700), Size(1024, 768)]) {
      tester.view.physicalSize = size;
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(size: size, textScaler: const TextScaler.linear(1.5)),
            child: CommentaryTouchCalibration(
              primary: const ColoredBox(key: ValueKey('A'), color: Colors.red),
              commentary: const ColoredBox(key: ValueKey('B'), color: Colors.blue),
              primaryLabel: '官方比赛直播间',
              commentaryLabel: '玩机器',
              offsetLabel: '+100ms',
              ready: true,
              onAdjust: (_) {},
              onDone: () {},
              onSettings: () {},
            ),
          ),
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull, reason: '$size');
      final a = tester.getRect(find.byKey(const ValueKey('A')));
      final b = tester.getRect(find.byKey(const ValueKey('B')));
      expect(a.overlaps(b), isFalse);
      expect(a.size.shortestSide, greaterThan(70));
      expect(b.size.shortestSide, greaterThan(70));
      expect(a.left, greaterThanOrEqualTo(0));
      expect(b.right, lessThanOrEqualTo(size.width));
      final flex = tester.widget<Flex>(find.byKey(const ValueKey('commentary-touch-videos')));
      expect(flex.direction, size.width > size.height ? Axis.horizontal : Axis.vertical);
      await tester.ensureVisible(find.text('完成校准'));
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('10/100/500ms touch steps adjust B without rebuilding native video', (tester) async {
    final a = _Video();
    final b = _Video();
    final adjustments = <int>[];
    var done = 0;
    var settings = 0;
    Widget page(bool ready, String offset) => MaterialApp(
      home: CommentaryTouchCalibration(
        primary: StablePlayerVideo(player: a),
        commentary: StablePlayerVideo(player: b),
        primaryLabel: 'A',
        commentaryLabel: 'B',
        offsetLabel: offset,
        ready: ready,
        onAdjust: adjustments.add,
        onDone: () => done++,
        onSettings: () => settings++,
      ),
    );
    await tester.pumpWidget(page(true, '0.0s'));
    await tester.tap(find.text('声音延后'));
    await tester.tap(find.text('10ms'));
    await tester.pump();
    await tester.tap(find.text('声音提前'));
    await tester.pumpWidget(page(true, '+90ms'));
    await tester.tap(find.text('500ms'));
    await tester.pump();
    await tester.tap(find.text('声音延后'));
    expect(adjustments, [100, -10, 500]);
    expect(a.builds, 1);
    expect(b.builds, 1);
    await tester.pumpWidget(page(false, '+590ms'));
    await tester.tap(find.text('声音提前'));
    expect(adjustments, hasLength(3));
    await tester.tap(find.text('完成校准'));
    await tester.tap(find.text('画质 / 弹幕 / 更多'));
    expect(done, 1);
    expect(settings, 1);
  });

  testWidgets('mobile crop targets are 48px while desktop remains compact', (tester) async {
    for (final platform in [TargetPlatform.android, TargetPlatform.iOS, TargetPlatform.macOS]) {
      late double size;
      await tester.pumpWidget(
        MaterialApp(
          key: ValueKey(platform),
          theme: ThemeData(platform: platform),
          home: Builder(
            builder: (context) {
              size = commentaryTouchTarget(context, 28);
              return const SizedBox();
            },
          ),
        ),
      );
      expect(size, platform == TargetPlatform.macOS ? 28 : 48);
    }
  });
}

class _Video implements UnifiedPlayer {
  int builds = 0;
  @override
  Widget getVideoWidget(BoxFit fit) {
    builds++;
    return const ColoredBox(color: Colors.black);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
