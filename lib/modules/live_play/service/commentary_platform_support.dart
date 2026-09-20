import 'dart:io';

/// Explicit platform allow-list for the dual-stream commentary feature.
///
/// macOS is the validated release target. Windows and iOS/iPadOS reuse the
/// same MediaKit/Dart implementation. Android and iOS are migration test
/// targets: native dual-decoder and background behavior still need sampling.
abstract final class CommentaryPlatformSupport {
  static bool get isSupported =>
      supports(macOS: Platform.isMacOS, windows: Platform.isWindows, iOS: Platform.isIOS, android: Platform.isAndroid);

  static bool get hasDesktopShortcuts => Platform.isMacOS || Platform.isWindows;

  static bool supports({required bool macOS, required bool windows, required bool iOS, bool android = false}) {
    return macOS || windows || iOS || android;
  }
}
