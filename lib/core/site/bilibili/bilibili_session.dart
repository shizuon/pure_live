/// Strict Cookie field parsing shared by HTTP discovery and socket identity.
/// No value is decoded/re-encoded: percent-encoded SESSDATA must stay intact.
Map<String, String> parseBilibiliCookie(String cookie) {
  final result = <String, String>{};
  for (final field in cookie.split(';')) {
    final separator = field.indexOf('=');
    if (separator <= 0) continue;
    final key = field.substring(0, separator).trim();
    final value = field.substring(separator + 1).trim();
    if (key.isEmpty || key.contains(RegExp(r'[\s\x00-\x1f\x7f]')) || value.contains(RegExp(r'[\x00-\x1f\x7f]'))) {
      continue;
    }
    result[key] = value;
  }
  return result;
}

class BilibiliSessionExpired implements Exception {
  const BilibiliSessionExpired();
  @override
  String toString() => 'B站登录会话失效或身份不一致，请重新登录后刷新直播间';
}

/// Safe to show in status text: never carries raw HTTP/WS response payloads.
class BilibiliDiscoveryFailure implements Exception {
  const BilibiliDiscoveryFailure(this.stage, {this.code});
  final String stage;
  final int? code;
  @override
  String toString() => code == null ? stage : '$stage（code=$code）';
}
