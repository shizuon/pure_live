/// Bounded low-latency buffer budget for non-seekable live streams.
///
/// These are mpv packet-cache limits, not an unconditional media byte budget:
/// with MediaKit's disk cache enabled, payload is stored in a file and these
/// bounds chiefly constrain metadata. `cache-secs` may also override the
/// smaller readahead value. Do not infer retained seconds from 32 MiB alone.
abstract final class LiveBufferPolicy {
  static const int forwardBytes = 32 * 1024 * 1024;
  static const int backBytes = 4 * 1024 * 1024;
  static const int readaheadSeconds = 2;
}
