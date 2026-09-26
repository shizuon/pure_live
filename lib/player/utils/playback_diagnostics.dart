/// On-demand native snapshot. No URLs, cookies, media titles or background
/// polling. Counters are cumulative for the current native media session,
/// not a measurement of Flutter/screen presentation FPS.
class PlaybackDiagnostics {
  const PlaybackDiagnostics(this.values);
  final Map<String, String?> values;
  static const properties = [
    'time-pos',
    'demuxer-cache-duration',
    'paused-for-cache',
    'pause',
    'eof-reached',
    'speed',
    'decoder-frame-drop-count',
    'frame-drop-count',
  ];

  static Future<PlaybackDiagnostics> read(
    Future<String> Function(String) readProperty, {
    Duration timeout = const Duration(seconds: 2),
  }) async {
    final entries = await Future.wait(
      properties.map((key) async {
        try {
          final value = (await readProperty(key).timeout(timeout)).trim();
          if (['paused-for-cache', 'pause', 'eof-reached'].contains(key)) {
            return MapEntry(key, value == 'yes' || value == 'no' ? value : null);
          }
          final number = double.tryParse(value);
          return MapEntry(key, number != null && number.isFinite && number >= 0 ? value : null);
        } catch (_) {
          return MapEntry<String, String?>(key, null);
        }
      }),
    );
    return PlaybackDiagnostics(Map.unmodifiable(Map.fromEntries(entries)));
  }

  String number(String key, {int digits = 2}) {
    final value = double.tryParse(values[key] ?? '');
    return value == null ? '—' : value.toStringAsFixed(digits);
  }
}
