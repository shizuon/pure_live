/// Normalize an explicitly supplied browser Cookie header, not a Set-Cookie
/// response or a whole request. Never include this value in diagnostic output.
String normalizeDouyuCookie(String value) {
  final input = value
      .replaceAll(RegExp(r'[\x00-\x1f\x7f]'), '')
      .trim()
      .replaceFirst(RegExp(r'^Cookie:\s*', caseSensitive: false), '');
  final fields = <String, String>{};
  for (final piece in input.split(';')) {
    final separator = piece.indexOf('=');
    if (separator <= 0) continue;
    final name = piece.substring(0, separator).trim();
    if (!RegExp(r"^[A-Za-z0-9_!#$%&'*+.^`|~-]+$").hasMatch(name)) continue;
    fields[name] = piece.substring(separator + 1).trim();
  }
  return fields.entries.map((field) => '${field.key}=${field.value}').join('; ');
}

String buildDouyuCookieHeader(String accountCookie, String deviceId) {
  final fields = douyuCookieFields(accountCookie)..remove('LTP0');
  if (fields['dy_did']?.isNotEmpty != true) fields['dy_did'] = deviceId;
  if (fields['acf_did']?.isNotEmpty != true) fields['acf_did'] = deviceId;
  return fields.entries.map((e) => '${e.key}=${e.value}').join('; ');
}

Map<String, String> douyuCookieFields(String value) => {
  for (final field in normalizeDouyuCookie(value).split('; '))
    if (field.contains('=')) field.substring(0, field.indexOf('=')): field.substring(field.indexOf('=') + 1),
};

String douyuCookieDeviceId(String cookie, String fallback) {
  final fields = douyuCookieFields(cookie);
  for (final key in ['dy_did', 'acf_did']) {
    final value = fields[key];
    if (value != null && value.isNotEmpty) return value;
  }
  return fallback;
}
