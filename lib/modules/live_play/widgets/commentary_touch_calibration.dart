import 'package:flutter/material.dart';

/// Uses the room's available area, rather than opening another player route.
/// The supplied video widgets stay mounted while offsets and steps change.
class CommentaryTouchCalibration extends StatefulWidget {
  const CommentaryTouchCalibration({
    super.key,
    required this.primary,
    required this.commentary,
    required this.primaryLabel,
    required this.commentaryLabel,
    required this.offsetLabel,
    required this.ready,
    required this.onAdjust,
    required this.onDone,
    required this.onSettings,
  });

  final Widget primary;
  final Widget commentary;
  final String primaryLabel;
  final String commentaryLabel;
  final String offsetLabel;
  final bool ready;
  final ValueChanged<int> onAdjust;
  final VoidCallback onDone;
  final VoidCallback onSettings;

  @override
  State<CommentaryTouchCalibration> createState() => _CommentaryTouchCalibrationState();
}

class _CommentaryTouchCalibrationState extends State<CommentaryTouchCalibration> {
  int step = 100;

  Widget _pane(String label, Widget video) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Padding(
        padding: const EdgeInsets.all(4),
        child: Text(
          label,
          maxLines: 1,
          textAlign: TextAlign.center,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: Colors.white),
        ),
      ),
      Expanded(child: video),
    ],
  );

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.black,
    child: SafeArea(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final horizontal = constraints.maxWidth > constraints.maxHeight;
          return Column(
            children: [
              Expanded(
                child: Flex(
                  key: const ValueKey('commentary-touch-videos'),
                  direction: horizontal ? Axis.horizontal : Axis.vertical,
                  children: [
                    Expanded(child: _pane('A · ${widget.primaryLabel}', widget.primary)),
                    Expanded(child: _pane('B · ${widget.commentaryLabel}', widget.commentary)),
                  ],
                ),
              ),
              // Wrap and scroll accommodate large system text and split view.
              ConstrainedBox(
                constraints: BoxConstraints(maxHeight: constraints.maxHeight * .48),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('B 声音偏移 ${widget.offsetLabel}', style: const TextStyle(color: Colors.white)),
                      Wrap(
                        spacing: 8,
                        alignment: WrapAlignment.center,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          for (final value in const [10, 100, 500])
                            ChoiceChip(
                              label: Text('${value}ms'),
                              selected: step == value,
                              onSelected: (_) => setState(() => step = value),
                            ),
                          FilledButton(
                            key: const ValueKey('commentary-touch-advance'),
                            onPressed: widget.ready ? () => widget.onAdjust(-step) : null,
                            child: const Text('声音提前'),
                          ),
                          FilledButton(
                            key: const ValueKey('commentary-touch-delay'),
                            onPressed: widget.ready ? () => widget.onAdjust(step) : null,
                            child: const Text('声音延后'),
                          ),
                          TextButton(onPressed: widget.onSettings, child: const Text('画质 / 弹幕 / 更多')),
                          TextButton(onPressed: widget.onDone, child: const Text('完成校准')),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    ),
  );
}
