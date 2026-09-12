import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:pure_live/common/services/settings/player_settings_controller.dart';
import 'package:pure_live/common/services/settings/font_settings_controller.dart';
import 'package:pure_live/common/services/settings/proxy_settings_controller.dart';
import 'package:pure_live/common/services/settings_service.dart';
import 'package:pure_live/common/utils/hive_pref_util.dart';
import 'package:pure_live/get/get.dart';
import 'package:pure_live/modules/settings/widgets/macos_decode_settings.dart';
import 'package:pure_live/player/adapters/media_kit_adapter.dart';
import 'package:pure_live/player/models/macos_decode_mode.dart';
import 'package:pure_live/player/utils/macos_decoder_status.dart';

class _NativeProperties {
  final values = <String, String>{};
  Future<void> setProperty(String key, String value) async => values[key] = value;
}

// Persistence is covered by the real Hive tests above. Widget fake time should
// only drive UI state, not leave a disk write waiting on a different clock.
class _WidgetSettings extends PlayerSettingsController {
  _WidgetSettings() : super(decodeSession: MacosDecodeSession());
  final RxString _mode = MacosDecodeMode.software.name.obs;
  @override
  RxString get macosDecodeModeName => _mode;
}

class _TestSettingsService extends SettingsService {
  final _player = PlayerSettingsController(decodeSession: MacosDecodeSession());
  final _font = FontSettingsController();
  final _proxy = ProxySettingsController();
  @override
  PlayerSettingsController get player => _player;
  @override
  FontSettingsController get font => _font;
  @override
  ProxySettingsController get proxy => _proxy;
  @override
  // ignore: must_call_super -- Do not start IPTV/network/font services in a decoder fixture.
  void onInit() {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('pure_live_decode_settings_');
    Hive.init(directory.path);
    await HivePrefUtil.init();
  });
  tearDown(() async {
    Get.deleteAll(force: true);
    Get.reset();
    await Hive.close();
    await directory.delete(recursive: true);
  });

  test('old and invalid backups retain software, not legacy auto hardware', () {
    for (final value in [null, true, 'auto', 'unknown']) {
      final config = PlayerSettingsController.extractConfig({
        'player': {'enableCodec': true, 'macosDecodeMode': value},
      });
      expect(config['macosDecodeMode'], 'software');
    }
  });

  test('selection persists and exports; import and reset never change a running session', () async {
    final session = MacosDecodeSession();
    final settings = PlayerSettingsController(decodeSession: session);
    expect(settings.initializedMacosDecodeMode, isNull);
    settings.changeMacosDecodeMode(MacosDecodeMode.hardwareOnly);
    expect(settings.activeMacosDecodeMode, MacosDecodeMode.hardwareOnly);
    settings.changeMacosDecodeMode(MacosDecodeMode.hardwareCompatible);
    expect(settings.activeMacosDecodeMode, MacosDecodeMode.hardwareOnly);
    expect(settings.toJson()['macosDecodeMode'], 'hardwareCompatible');
    await Hive.box('app_settings').flush();
    final recreated = PlayerSettingsController(decodeSession: session);
    expect(recreated.macosDecodeMode, MacosDecodeMode.hardwareCompatible);
    expect(recreated.activeMacosDecodeMode, MacosDecodeMode.hardwareOnly);
    final restarted = PlayerSettingsController(decodeSession: MacosDecodeSession());
    expect(restarted.activeMacosDecodeMode, MacosDecodeMode.hardwareCompatible);
    settings.fromJson({'macosDecodeMode': 'software'});
    expect(settings.macosDecodeMode, MacosDecodeMode.software);
    expect(settings.activeMacosDecodeMode, MacosDecodeMode.hardwareOnly);
    settings.changeMacosDecodeMode(MacosDecodeMode.hardwareCompatible);
    settings.resetMpvPlayerSettings();
    expect(settings.macosDecodeMode, MacosDecodeMode.software);
    expect(settings.activeMacosDecodeMode, MacosDecodeMode.hardwareOnly);
    await Hive.box('app_settings').flush();
  });

  for (final mode in MacosDecodeMode.values) {
    test('shared native policy applies $mode without overriding audio or other platforms', () async {
      final settings = Get.put<SettingsService>(_TestSettingsService()).player;
      settings.changeMacosDecodeMode(mode);
      settings.customPlayerOutput.value = true;
      settings.audioOutputDriver.value = 'auto';
      settings.videoHardwareDecoder.value = 'wrong-legacy-value';
      settings.playerCompatMode.value = true;
      final native = _NativeProperties();
      await MediaKitAdapter.applyNativeLiveProperties(native);
      expect(native.values['ao'], 'auto');
      expect(native.values['hwdec-software-fallback'], Platform.isMacOS ? mode.softwareFallback : '1');
      if (Platform.isMacOS) {
        expect(native.values['hwdec'], mode.hwdec);
        settings.changeMacosDecodeMode(MacosDecodeMode.software);
        final nextPlayer = _NativeProperties();
        await MediaKitAdapter.applyNativeLiveProperties(nextPlayer);
        expect(nextPlayer.values['hwdec'], mode.hwdec); // B retains A's session policy.
      } else {
        expect(native.values.containsKey('hwdec'), isFalse);
      }
      await Hive.box('app_settings').flush();
    });
  }

  testWidgets('three choices show pending restart; diagnostics are read only on request', (tester) async {
    Get.testMode = true;
    Get.put<SettingsService>(_TestSettingsService());
    final settings = _WidgetSettings();
    expect(settings.activeMacosDecodeMode, MacosDecodeMode.software);
    var reads = 0;
    await tester.pumpWidget(
      GetMaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: MacosDecodeSettings(
              settings: settings,
              readStatus: () async {
                reads++;
                return {
                  'A': const MacosDecoderStatus(MacosDecoderState.hardware, decoder: 'videotoolbox'),
                  'B': const MacosDecoderStatus(MacosDecoderState.audioOnly),
                };
              },
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    for (final mode in MacosDecodeMode.values) {
      expect(find.byKey(ValueKey('decode-${mode.name}')), findsOneWidget);
    }
    await tester.tap(find.byKey(const ValueKey('decode-hardwareOnly')));
    await tester.pump();
    expect(settings.macosDecodeMode, MacosDecodeMode.hardwareOnly);
    expect(settings.activeMacosDecodeMode, MacosDecodeMode.software);
    expect(find.text('macos_decode_restart'), findsOneWidget);
    expect(reads, 0);
    await tester.ensureVisible(find.byKey(const ValueKey('decode-read-status')));
    await tester.tap(find.byKey(const ValueKey('decode-read-status')));
    await tester.pumpAndSettle();
    expect(reads, 1);
    expect(find.textContaining('videotoolbox'), findsOneWidget);
    expect(find.text('macos_decode_status_audioOnly'), findsOneWidget);
    await tester.pump(const Duration(seconds: 30));
    expect(reads, 1);
    await tester.pumpWidget(const SizedBox());
  });
}
