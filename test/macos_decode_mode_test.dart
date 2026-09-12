import 'package:flutter_test/flutter_test.dart';
import 'package:pure_live/player/models/macos_decode_mode.dart';
import 'package:pure_live/player/utils/macos_decoder_status.dart';

void main() {
  test('three modes keep decoding separate from rendering and fallback', () {
    for (final (mode, hwdec, hardwareOutput, fallback) in [
      (MacosDecodeMode.software, 'no', false, '1'),
      (MacosDecodeMode.hardwareOnly, 'videotoolbox', true, 'no'),
      (MacosDecodeMode.hardwareCompatible, 'videotoolbox-copy', false, '1'),
    ]) {
      final config = mode.configuration(width: 640, height: 360);
      expect(config.hwdec, hwdec);
      expect(config.vo, 'libmpv');
      expect(config.enableHardwareAcceleration, hardwareOutput);
      expect(config.width, 640);
      expect(config.height, 360);
      expect(mode.softwareFallback, fallback);
      expect(MacosDecodeMode.parse(mode.name), mode);
    }
  });

  test('unknown and legacy modes safely default to software', () {
    for (final value in [null, true, 1, 'auto', 'broken']) {
      expect(MacosDecodeMode.parse(value), MacosDecodeMode.software);
    }
  });

  test('audio-only skips native queries and is not mistaken for failed hardware', () async {
    final status = await MacosDecoderStatus.read((_) => throw StateError('must not read'), videoEnabled: false);
    expect(status.state, MacosDecoderState.audioOnly);
  });

  test('reports actual decoder, including compatible mode software fallback', () async {
    for (final decoder in ['no', 'videotoolbox', 'videotoolbox-copy']) {
      final properties = {'hwdec-current': decoder, 'video-format': 'h264', 'video-out-params/w': '1920', 'vid': '1'};
      final status = await MacosDecoderStatus.read((key) async => properties[key]!, videoEnabled: true);
      expect(status.decoder, decoder);
      expect(status.codec, 'h264');
      expect(status.state, decoder == 'no' ? MacosDecoderState.software : MacosDecoderState.hardware);
    }
  });

  test('startup, no-video and disposed-native snapshots are not misreported as software', () async {
    final properties = {'hwdec-current': 'no', 'video-format': 'h264', 'video-out-params/w': '', 'vid': 'auto'};
    expect(
      (await MacosDecoderStatus.read((key) async => properties[key]!, videoEnabled: true)).state,
      MacosDecoderState.waiting,
    );
    properties['vid'] = 'no';
    expect(
      (await MacosDecoderStatus.read((key) async => properties[key]!, videoEnabled: true)).state,
      MacosDecoderState.audioOnly,
    );
    expect(
      (await MacosDecoderStatus.read((_) async => throw StateError('disposed'), videoEnabled: true)).state,
      MacosDecoderState.unavailable,
    );
  });
}
