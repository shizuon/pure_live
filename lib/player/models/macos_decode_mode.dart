import 'package:media_kit_video/media_kit_video.dart';

/// Decoder and renderer are separate choices. Copy-back retains the SW
/// renderer used by the macOS HDR/window-flicker workaround.
enum MacosDecodeMode {
  software,
  hardwareOnly,
  hardwareCompatible;

  static MacosDecodeMode parse(Object? value) => values.where((mode) => mode.name == value).firstOrNull ?? software;

  String get hwdec => switch (this) {
    software => 'no',
    hardwareOnly => 'videotoolbox',
    hardwareCompatible => 'videotoolbox-copy',
  };

  bool get hardwareOutput => this == hardwareOnly;
  String get softwareFallback => this == hardwareOnly ? 'no' : '1';
  String get labelKey => 'macos_decode_$name';

  VideoControllerConfiguration configuration({int? width, int? height}) => VideoControllerConfiguration(
    vo: 'libmpv',
    hwdec: hwdec,
    enableHardwareAcceleration: hardwareOutput,
    androidAttachSurfaceAfterVideoParameters: false,
    width: width,
    height: height,
  );
}

/// Outlives GetX's fenix settings controllers and any individual player pool.
/// Only a new application process starts a new production decode session.
class MacosDecodeSession {
  static final application = MacosDecodeSession();

  MacosDecodeMode? _active;
  MacosDecodeMode? get initializedMode => _active;
  MacosDecodeMode activate(MacosDecodeMode selected) => _active ??= selected;
}
