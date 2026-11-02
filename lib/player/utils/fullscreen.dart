import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:pure_live/common/index.dart';
import 'package:pure_live/player/utils/window_helper.dart';
import 'package:pure_live/common/global/platform_utils.dart';
import 'package:pure_live/player/utils/desktop_fullscreen_transition.dart';
import 'package:pure_live/modules/live_play/controllers/player_state.dart';
import 'package:pure_live/modules/live_play/controllers/live_play_controller.dart';

@visibleForTesting
bool supportsOrientationLockForLogicalDisplay(Size logicalDisplaySize) {
  return logicalDisplaySize.shortestSide < 600;
}

@immutable
class WindowPresentationSnapshot {
  const WindowPresentationSnapshot({required this.fullscreen, required this.widescreen});

  factory WindowPresentationSnapshot.capture(GlobalPlayerState state) {
    return WindowPresentationSnapshot(fullscreen: state.isFullscreen.value, widescreen: state.isWindowFullscreen.value);
  }

  final bool fullscreen;
  final bool widescreen;
}

class WindowService {
  static final WindowService _instance = WindowService._internal();
  factory WindowService() => _instance;
  WindowService._internal();

  WindowPresentationSnapshot? _presentationBeforePip;

  bool _canApplyMobileOrientationLock() {
    if (!Platform.isAndroid) return true;
    final views = WidgetsBinding.instance.platformDispatcher.views;
    if (views.isEmpty) return true;
    final display = views.first.display;
    final logicalSize = Size(
      display.size.width / display.devicePixelRatio,
      display.size.height / display.devicePixelRatio,
    );
    return supportsOrientationLockForLogicalDisplay(logicalSize);
  }

  bool _nativeFullscreenBeforePip = false;

  Future<void> enterDesktopPiP(double videoRatio) async {
    if (!PlatformUtils.supportsDesktopPip || WindowHelper.instance.currentMode == WindowLayoutMode.pip) return;
    final state = GlobalPlayerState.to;
    _presentationBeforePip = WindowPresentationSnapshot.capture(state);
    _nativeFullscreenBeforePip = await windowManager.isFullScreen();
    try {
      if (_nativeFullscreenBeforePip) await doExitWindowFullScreen();
      await WindowHelper.instance.enterPiP(videoRatio);
    } catch (_) {
      await _restorePresentation();
      rethrow;
    }
  }

  Future<void> exitDesktopPiP() async {
    if (!PlatformUtils.supportsDesktopPip) return;
    await WindowHelper.instance.exitPiP();
    await _restorePresentation();
  }

  Future<void> _restorePresentation() async {
    final state = GlobalPlayerState.to;
    final presentation = _presentationBeforePip;
    if (presentation == null) return;
    if (_nativeFullscreenBeforePip || presentation.fullscreen) await doEnterWindowFullScreen();
    state.isFullscreen.value = presentation.fullscreen;
    state.isWindowFullscreen.value = !presentation.fullscreen && presentation.widescreen;
    if (Get.isRegistered<LivePlayController>()) {
      final controller = Get.find<LivePlayController>();
      if (presentation.fullscreen) {
        controller.setFullScreen();
      } else if (presentation.widescreen) {
        controller.setWidescreen();
      } else {
        controller.setNormalScreen();
      }
    }
    _presentationBeforePip = null;
    _nativeFullscreenBeforePip = false;
  }

  //横屏
  Future<void> landScape() async {
    dynamic document;
    try {
      if (kIsWeb) {
        await document.documentElement?.requestFullscreen();
      } else if (Platform.isAndroid || Platform.isIOS) {
        if (!_canApplyMobileOrientationLock()) return;
        await SystemChrome.setPreferredOrientations([
          DeviceOrientation.landscapeLeft,
          DeviceOrientation.landscapeRight,
        ]);
      } else if (Platform.isMacOS || Platform.isWindows || Platform.isLinux) {
        await doEnterWindowFullScreen();
      }
    } catch (exception, stacktrace) {
      debugPrint(exception.toString());
      debugPrint(stacktrace.toString());
    }
  }

  //竖屏
  Future<void> verticalScreen() async {
    if (!_canApplyMobileOrientationLock()) return;
    await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  }

  Future<void> followSystemOrientation() async {
    if (!(Platform.isAndroid || Platform.isIOS)) return;
    await SystemChrome.setPreferredOrientations(const <DeviceOrientation>[]);
  }

  Future<void> doEnterFullScreen() async {
    if (Platform.isAndroid || Platform.isIOS) {
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    } else {
      await doEnterWindowFullScreen();
    }
  }

  //退出全屏显示
  Future<void> doExitFullScreen() async {
    dynamic document;
    try {
      if (kIsWeb) {
        document.exitFullscreen();
      } else if (Platform.isAndroid || Platform.isIOS) {
        await SystemChrome.setEnabledSystemUIMode(SystemUiMode.manual, overlays: SystemUiOverlay.values);
        await Future.microtask(() {});
        SystemChrome.setSystemUIOverlayStyle(
          const SystemUiOverlayStyle(statusBarIconBrightness: Brightness.dark, statusBarBrightness: Brightness.light),
        );
        await SystemChrome.setPreferredOrientations(const <DeviceOrientation>[]);
      } else if (Platform.isMacOS || Platform.isWindows || Platform.isLinux) {
        await doExitWindowFullScreen();
      }
    } catch (exception, stacktrace) {
      debugPrint(exception.toString());
      debugPrint(stacktrace.toString());
    }
  }

  Future<void> doExitWindowFullScreen() async {
    if (Platform.isMacOS || Platform.isWindows || Platform.isLinux) {
      await setDesktopFullScreen(false, waitForEvent: Platform.isMacOS);
    }
  }

  Future<void> doEnterWindowFullScreen({bool enableEscListener = true, VoidCallback? onEsc}) async {
    if (Platform.isMacOS || Platform.isWindows || Platform.isLinux) {
      await setDesktopFullScreen(true, waitForEvent: Platform.isMacOS);
    }
  }
}
