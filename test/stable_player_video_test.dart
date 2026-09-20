import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pure_live/player/interface/unified_player_interface.dart';
import 'package:pure_live/player/widgets/stable_player_video.dart';

void main() {
  testWidgets('offset and overlay rebuilds do not rebind the native video subtree', (tester) async {
    final player = _Player();
    for (var i = 0; i < 25; i++) {
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Column(
            children: [
              Text('offset $i'),
              Expanded(child: StablePlayerVideo(player: player)),
            ],
          ),
        ),
      );
    }
    expect(player.builds, 1);
    expect(find.byKey(const ValueKey('native-video')), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(StablePlayerVideo(player: player));
    expect(player.builds, 2, reason: 'a remount needs a fresh dimensions subscription');
    final replacement = _Player();
    await tester.pumpWidget(StablePlayerVideo(player: replacement));
    expect(replacement.builds, 1);
  });
}

class _Player implements UnifiedPlayer {
  int builds = 0;
  @override
  Widget getVideoWidget(BoxFit fit) {
    builds++;
    return const SizedBox(key: ValueKey('native-video'));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
