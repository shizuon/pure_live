import 'package:flutter/material.dart';

/// Only actual controls take pointer events; the title and gradient let the
/// video surface underneath handle the first two rows of danmaku.
class PlayerTopBarSurface extends StatelessWidget {
  const PlayerTopBarSurface({super.key, required this.title, this.leading = const [], this.actions = const []});

  final Widget title;
  final List<Widget> leading;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.expand,
    children: [
      const IgnorePointer(
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.bottomCenter,
              end: Alignment.topCenter,
              colors: [Colors.transparent, Colors.black45],
            ),
          ),
        ),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Row(
          children: [
            ...leading,
            Expanded(child: IgnorePointer(child: title)),
            ...actions,
          ],
        ),
      ),
    ],
  );
}
