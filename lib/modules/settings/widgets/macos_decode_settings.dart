import 'package:pure_live/common/index.dart';
import 'package:pure_live/common/services/settings/player_settings_controller.dart';
import 'package:pure_live/player/models/macos_decode_mode.dart';
import 'package:pure_live/player/utils/macos_decoder_status.dart';

class MacosDecodeSettings extends StatefulWidget {
  const MacosDecodeSettings({super.key, required this.settings, required this.readStatus});

  final PlayerSettingsController settings;
  final Future<Map<String, MacosDecoderStatus>> Function() readStatus;

  @override
  State<MacosDecodeSettings> createState() => _MacosDecodeSettingsState();
}

class _MacosDecodeSettingsState extends State<MacosDecodeSettings> {
  Map<String, MacosDecoderStatus>? _status;
  bool _reading = false;

  Future<void> _refresh() async {
    if (_reading) return;
    setState(() => _reading = true);
    try {
      final status = await widget.readStatus();
      if (mounted) setState(() => _status = status);
    } finally {
      if (mounted) setState(() => _reading = false);
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      context.buildGroupTitle(i18n('macos_decode_title')),
      context.buildModernCard([
        Obx(() {
          final selected = widget.settings.macosDecodeMode;
          final active = widget.settings.initializedMacosDecodeMode;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              RadioGroup<MacosDecodeMode>(
                groupValue: selected,
                onChanged: (mode) {
                  if (mode != null) widget.settings.changeMacosDecodeMode(mode);
                },
                child: Column(
                  children: [
                    for (final mode in MacosDecodeMode.values)
                      ListTile(
                        key: ValueKey('decode-${mode.name}'),
                        leading: Radio<MacosDecodeMode>(value: mode),
                        title: Text(i18n(mode.labelKey)),
                        subtitle: Text(i18n('${mode.labelKey}_description')),
                        onTap: () => widget.settings.changeMacosDecodeMode(mode),
                      ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                child: Text(
                  active == null
                      ? i18n('macos_decode_first_start')
                      : i18n(
                          selected == active ? 'macos_decode_active' : 'macos_decode_restart',
                          args: {'mode': i18n(active.labelKey)},
                        ),
                  key: const ValueKey('decode-apply-status'),
                ),
              ),
            ],
          );
        }),
        const Divider(height: 1),
        ListTile(
          title: Text(i18n('macos_decode_status')),
          subtitle: Text(i18n('macos_decode_status_hint')),
          trailing: IconButton(
            key: const ValueKey('decode-read-status'),
            tooltip: i18n('refresh'),
            onPressed: _reading ? null : _refresh,
            icon: _reading
                ? const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.refresh),
          ),
        ),
        if (_status != null)
          for (final entry in _status!.entries)
            ListTile(
              dense: true,
              title: Text(entry.key),
              subtitle: Text(
                [
                  i18n('macos_decode_status_${entry.value.state.name}'),
                  if (entry.value.decoder.isNotEmpty) entry.value.decoder,
                  if (entry.value.codec.isNotEmpty) entry.value.codec,
                ].join(' · '),
              ),
            ),
      ]),
    ],
  );
}
