import 'package:pure_live/modules/live_play/service/commentary_buffer_policy.dart';

/// Serialized, reversible options on an existing native media timeline.
/// This owns only cache options, never pause/seek/open or decoding options.
class NativeSyncBuffer {
  NativeSyncBuffer({required this.read, required this.write, required this.available});
  final Future<String> Function(String) read;
  final Future<void> Function(String, String) write;
  final bool Function() available;
  Map<String, String>? _original;
  Future<void> _tail = Future.value();
  int _seconds = 0;
  bool _closed = false;
  static const keys = ['cache-secs', 'demuxer-readahead-secs', 'demuxer-max-bytes', 'cache-pause-wait'];

  Future<void> _queue(Future<void> Function() work) {
    final next = _tail.then((_) async {
      if (_closed || !available()) return;
      await work();
    });
    _tail = next.then<void>((_) {}, onError: (_, _) {});
    return next;
  }

  Future<void> reserve(Duration delay) => _queue(() async {
    final seconds = CommentaryBufferPolicy.prefetchSeconds(delay);
    if (seconds <= _seconds) return;
    if (_original == null) {
      final original = <String, String>{};
      for (final key in keys) {
        if (_closed || !available()) return;
        original[key] = await read(key).timeout(const Duration(seconds: 2));
      }
      if (_closed || !available()) return;
      _original = original;
    }
    try {
      // cache-on-disk is deliberately unchanged; its payload file may be
      // append-only. max-bytes is not claimed as an on-disk size limit.
      for (final entry in {
        'demuxer-max-bytes': '${CommentaryBufferPolicy.maximumForwardBytes}',
        'cache-secs': '$seconds',
        'demuxer-readahead-secs': '$seconds',
        'cache-pause-wait': '2',
      }.entries) {
        if (_closed || !available()) return;
        await write(entry.key, entry.value).timeout(const Duration(seconds: 2));
      }
      _seconds = seconds;
    } catch (_) {
      // Partial application must not strand ordinary playback with only some
      // of the larger-delay options. Preserve the original error.
      try {
        await _restore();
      } catch (_) {}
      rethrow;
    }
  });

  Future<void> _restore() async {
    final original = _original;
    if (original == null) return;
    Object? firstError;
    for (final entry in original.entries) {
      if (_closed || !available()) return;
      try {
        await write(entry.key, entry.value).timeout(const Duration(seconds: 2));
      } catch (error) {
        firstError ??= error;
      }
    }
    if (firstError != null) throw firstError;
    _original = null;
    _seconds = 0;
  }

  Future<void> restore() => _queue(_restore);
  Future<void> close() async {
    _closed = true;
    await _tail;
    _original = null;
    _seconds = 0;
  }
}
