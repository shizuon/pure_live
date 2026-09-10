import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:pure_live/player/widgets/viewport_sized_video.dart';
import 'package:rxdart/rxdart.dart';

class _VideoController extends Fake implements VideoController {
  final requests = <Size?>[];

  @override
  Future<void> setSize({int? width, int? height}) async {
    requests.add(width == null || height == null ? null : Size(width.toDouble(), height.toDouble()));
  }
}

void main() {
  testWidgets('viewport resizing restores source sizing for crop and cancels stale fullscreen work', (tester) async {
    final controller = _VideoController();
    final width = BehaviorSubject<int?>.seeded(1920);
    final height = BehaviorSubject<int?>.seeded(1080);
    addTearDown(width.close);
    addTearDown(height.close);

    Widget surface({double size = 400, bool constrain = true}) => MediaQuery(
      data: const MediaQueryData(devicePixelRatio: 2),
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: size,
            height: size,
            child: ViewportSizedVideo(
              controller: controller,
              constrainToViewport: constrain,
              sourceWidth: width,
              sourceHeight: height,
              child: const SizedBox.expand(),
            ),
          ),
        ),
      ),
    );

    await tester.pumpWidget(surface());
    await tester.pump();
    expect(controller.requests, isEmpty);
    await tester.pump(const Duration(milliseconds: 180));
    expect(controller.requests, [const Size(800, 450)]);

    // Return before the resize delay: the pending fullscreen request must die.
    await tester.pumpWidget(surface(size: 600));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pumpWidget(surface());
    await tester.pump(const Duration(milliseconds: 180));
    expect(controller.requests, [const Size(800, 450)]);

    await tester.pumpWidget(surface(constrain: false));
    await tester.pump(const Duration(milliseconds: 180));
    expect(controller.requests.last, isNull);
    // No explicit override while cropping; native output follows metadata.
    width.add(3840);
    height.add(2160);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 180));
    expect(controller.requests.length, 2);

    await tester.pumpWidget(surface());
    await tester.pump(const Duration(milliseconds: 180));
    expect(controller.requests.last, const Size(800, 450));
    await tester.pumpWidget(surface(size: 600));
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
    expect(controller.requests.length, 3);
    expect(width.hasListener, isFalse);
    expect(height.hasListener, isFalse);
  });
}
