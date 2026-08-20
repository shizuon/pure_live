import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('macOS release disables Impeller wide-gamut texture composition', () {
    final plist = File('macos/Runner/Info.plist').readAsStringSync();
    expect(
      plist,
      contains(RegExp(r'<key>FLTEnableImpeller</key>\s*<false/>')),
      reason: 'media_kit SDR textures must be composed on the stable sRGB/BGRA8 Flutter surface',
    );
  });
}
