import 'dart:convert';

/// Reads embedded JSON without evaluating scripts or stopping at braces inside strings.
class YouTubePage {
  static Map<String, dynamic>? objectAfter(String html, String marker) {
    var searchFrom = 0;
    while (true) {
      final markerIndex = html.indexOf(marker, searchFrom);
      if (markerIndex < 0) return null;
      final start = html.indexOf('{', markerIndex + marker.length);
      if (start < 0) return null;
      var depth = 0;
      var quoted = false;
      var escaped = false;
      for (var end = start; end < html.length; end++) {
        final char = html[end];
        if (quoted) {
          if (escaped) {
            escaped = false;
          } else if (char == r'\') {
            escaped = true;
          } else if (char == '"') {
            quoted = false;
          }
          continue;
        }
        if (char == '"') {
          quoted = true;
          continue;
        }
        if (char == '{') depth++;
        if (char == '}' && --depth == 0) {
          try {
            return jsonDecode(html.substring(start, end + 1)) as Map<String, dynamic>;
          } on FormatException {
            break;
          }
        }
      }
      searchFrom = start + 1;
    }
  }

  static Iterable<Map> renderers(dynamic tree, String key) sync* {
    if (tree is Map) {
      final value = tree[key];
      if (value is Map) yield value;
      for (final child in tree.values) {
        yield* renderers(child, key);
      }
    } else if (tree is List) {
      for (final child in tree) {
        yield* renderers(child, key);
      }
    }
  }

  static String text(dynamic value) {
    if (value is String) return value;
    if (value is! Map) return '';
    if (value['simpleText'] is String) return value['simpleText'];
    return (value['runs'] as List? ?? [])
        .map((run) => run['text'] ?? ((run['emoji']?['shortcuts'] as List?)?.firstOrNull ?? ''))
        .join();
  }

  static String thumbnail(dynamic value) {
    final items = value is Map ? value['thumbnails'] : null;
    return items is List && items.isNotEmpty ? items.last['url']?.toString() ?? '' : '';
  }

  static Map<String, dynamic> context(String html) {
    var offset = 0;
    while (offset < html.length) {
      final next = html.indexOf('ytcfg.set(', offset);
      if (next < 0) break;
      final config = objectAfter(html.substring(next), 'ytcfg.set(');
      if (config?['INNERTUBE_CONTEXT'] is Map) return Map<String, dynamic>.from(config!['INNERTUBE_CONTEXT']);
      offset = next + 10;
    }
    throw StateError('YouTube client context missing; please check network access');
  }
}
