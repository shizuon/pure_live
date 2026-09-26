import 'dart:async';

import 'package:pure_live/common/index.dart';
import 'package:pure_live/core/common/http_client.dart';
import 'package:pure_live/common/services/settings/bilibili_account_service.dart';

enum QRStatus { loading, unscanned, scanned, expired, failed }

class BiliBiliQRLoginController extends GetxController {
  @override
  void onInit() {
    loadQRCode();
    super.onInit();
  }

  Timer? timer;
  int _generation = 0;
  bool _closed = false;
  bool _polling = false;

  var qrcodeUrl = "".obs;
  var qrcodeKey = "";

  /// 二维码状态
  /// - [0] 加载中
  /// - [1] 未扫描
  /// - [2] 已扫描，待确认
  /// - [3] 二维码已经失效
  /// - [4] 登录失败
  Rx<QRStatus> qrStatus = QRStatus.loading.obs;

  void loadQRCode() async {
    final generation = ++_generation;
    timer?.cancel();
    qrcodeKey = '';
    try {
      qrStatus.value = QRStatus.loading;

      var result = await HttpClient.instance.getJson(
        "https://passport.bilibili.com/x/passport-login/web/qrcode/generate",
      );
      if (_closed || generation != _generation) return;
      if (result["code"] != 0) {
        throw result["message"];
      }
      qrcodeKey = result["data"]["qrcode_key"];
      qrcodeUrl.value = result["data"]["url"];
      qrStatus.value = QRStatus.unscanned;
      startPoll();
    } catch (e) {
      if (_closed || generation != _generation) return;
      ToastUtil.show(i18n('qr_load_failed'));
      qrStatus.value = QRStatus.failed;
    }
  }

  void startPoll() {
    timer?.cancel();
    timer = Timer.periodic(const Duration(seconds: 3), (timer) {
      pollQRStatus();
    });
  }

  void pollQRStatus() async {
    if (_closed || _polling || qrcodeKey.isEmpty) return;
    _polling = true;
    final generation = _generation;
    final key = qrcodeKey;
    try {
      var response = await HttpClient.instance.get(
        "https://passport.bilibili.com/x/passport-login/web/qrcode/poll",
        queryParameters: {"qrcode_key": key},
      );
      if (_closed || generation != _generation || key != qrcodeKey) return;
      if (response.data["code"] != 0) {
        throw response.data["message"];
      }
      var data = response.data["data"];
      var code = data["code"];
      if (code == 0) {
        timer?.cancel();
        var cookies = <String>[];
        response.headers["set-cookie"]?.forEach((element) {
          var cookie = element.split(";")[0];
          cookies.add(cookie);
        });
        if (cookies.isNotEmpty) {
          var cookieStr = cookies.join(";");
          BiliBiliAccountService.instance.setCookie(cookieStr);
          await BiliBiliAccountService.instance.loadUserInfo();
          if (!_closed && generation == _generation && Get.currentRoute == RoutePath.kBiliBiliQRLogin) {
            Get.back();
          }
        } else {
          qrStatus.value = QRStatus.failed;
        }
      } else if (code == 86038) {
        qrStatus.value = QRStatus.expired;
        qrcodeKey = "";
        timer?.cancel();
      } else if (code == 86090) {
        qrStatus.value = QRStatus.scanned;
      }
    } catch (e) {
      if (!_closed && generation == _generation) {
        qrStatus.value = QRStatus.failed;
        timer?.cancel();
      }
    } finally {
      _polling = false;
    }
  }

  @override
  void onClose() {
    _closed = true;
    _generation++;
    timer?.cancel();
    super.onClose();
  }
}
