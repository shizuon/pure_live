import 'dart:io';

/// Explicit platform allow-list for the dual-stream commentary feature.
///
/// macOS is the validated release target. Windows and iOS/iPadOS reuse the
/// same MediaKit/Dart implementation and are enabled for migration testing;
/// Android remains excluded until its two-decoder and Surface lifecycle path
/// has been tested separately.
abstract final class CommentaryPlatformSupport {
  static bool get isSupported => supports(macOS: Platform.isMacOS, windows: Platform.isWindows, iOS: Platform.isIOS);

  static bool get hasDesktopShortcuts => Platform.isMacOS || Platform.isWindows;

  static bool supports({required bool macOS, required bool windows, required bool iOS}) {
    return macOS || windows || iOS;
  }
}
