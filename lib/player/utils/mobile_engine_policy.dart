import 'package:flutter/foundation.dart';

/// BetterPlayer uses AVPlayer on iOS. Reject known unsupported live inputs
/// before native setup; the existing player orchestrator owns fallback.
abstract final class MobileEnginePolicy {
  static bool isKnownUnsupportedAvPlayerSource(String source, TargetPlatform platform) {
    if (platform != TargetPlatform.iOS) return false;
    final uri = Uri.tryParse(source);
    if (uri == null) return false;
    return const {'rtmp', 'rtmps'}.contains(uri.scheme.toLowerCase()) || uri.path.toLowerCase().endsWith('.flv');
  }

  static Map<String, Object> ijkPlayerOptions(TargetPlatform platform, bool hardware) => {
    if (platform == TargetPlatform.android) ...{'mediacodec': hardware ? 1 : 0, 'mediacodec-hevc': hardware ? 1 : 0},
    if (platform == TargetPlatform.iOS) 'videotoolbox': hardware ? 1 : 0,
    'overlay-format': platform == TargetPlatform.iOS ? 'fcc-bgra' : 0x52474238,
  };
}
