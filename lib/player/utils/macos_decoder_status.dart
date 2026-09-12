import 'dart:async';

enum MacosDecoderState { inactive, audioOnly, waiting, software, hardware, unavailable }

class MacosDecoderStatus {
  const MacosDecoderStatus(this.state, {this.decoder = '', this.codec = ''});

  final MacosDecoderState state;
  final String decoder;
  final String codec;

  static Future<MacosDecoderStatus> read(
    Future<String> Function(String) readProperty, {
    required bool videoEnabled,
  }) async {
    if (!videoEnabled) return const MacosDecoderStatus(MacosDecoderState.audioOnly);
    try {
      final values = await Future.wait([
        readProperty('hwdec-current'),
        readProperty('video-format'),
        readProperty('video-out-params/w'),
        readProperty('vid'),
      ]);
      if (values[3] == 'no') return const MacosDecoderStatus(MacosDecoderState.audioOnly);
      // Do not classify mpv's transient `no` before a decoded video exists.
      if ((int.tryParse(values[2]) ?? 0) <= 0 || values[0].isEmpty || values[1].isEmpty) {
        return const MacosDecoderStatus(MacosDecoderState.waiting);
      }
      return MacosDecoderStatus(
        values[0] == 'no' ? MacosDecoderState.software : MacosDecoderState.hardware,
        decoder: values[0],
        codec: values[1],
      );
    } catch (_) {
      return const MacosDecoderStatus(MacosDecoderState.unavailable);
    }
  }
}

/// mpv's `hwdec-software-fallback=no` prevents *runtime* fallback, but initial
/// unsupported codecs may still open a software decoder. Refuse to continue
/// that playback in strict mode. Property-change driven, not frame polling.
class MacosHardwareDecodeGuard {
  MacosHardwareDecodeGuard({required this.native, required this.pause, required this.onRejected});

  final dynamic native;
  final Future<void> Function() pause;
  final void Function() onRejected;
  static const _properties = ['hwdec-current', 'video-out-params'];
  final List<String> _observed = [];
  Timer? _checkTimer;
  bool _disposed = false;
  bool _videoEnabled = false;
  bool rejected = false;
  int _generation = 0;

  Future<void> attach() async {
    try {
      for (final property in _properties) {
        await native.observeProperty(property, (String _) async => scheduleCheck());
        _observed.add(property);
      }
    } catch (_) {
      await dispose();
      rethrow;
    }
  }

  void suspend() {
    _generation++;
    _videoEnabled = false;
    rejected = false;
    _checkTimer?.cancel();
    _checkTimer = null;
  }

  void activate({required bool videoEnabled}) {
    suspend();
    _videoEnabled = videoEnabled;
    scheduleCheck();
  }

  void scheduleCheck() {
    if (_disposed || !_videoEnabled || rejected || _checkTimer != null) return;
    final generation = _generation;
    // Also leaves the native event callback before sending a pause command.
    _checkTimer = Timer(const Duration(milliseconds: 150), () async {
      _checkTimer = null;
      final status = await MacosDecoderStatus.read(
        (property) async => await native.getProperty(property) as String,
        videoEnabled: true,
      );
      if (_disposed || generation != _generation || !_videoEnabled || rejected) return;
      if (status.state != MacosDecoderState.software) return;
      rejected = true;
      try {
        await pause();
      } catch (_) {
        // A native teardown may already be in progress. Still report the
        // rejected decoder, but never leak an unhandled timer Future.
      } finally {
        if (!_disposed && generation == _generation) onRejected();
      }
    });
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    suspend();
    for (final property in _observed) {
      try {
        await native.unobserveProperty(property);
      } catch (_) {
        // Disposing the native player also removes its property observers.
        // One failed unobserve must not prevent the remaining native teardown.
      }
    }
    _observed.clear();
  }
}
