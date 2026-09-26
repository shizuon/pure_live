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
  final fields = normalizeDouyuCookie(accountCookie).split('; ').where((field) {
    final name = field.split('=').first.toLowerCase();
    return field.isNotEmpty && name != 'dy_did' && name != 'acf_did';
  });
  return ['dy_did=$deviceId', 'acf_did=$deviceId', ...fields].join('; ');
}
