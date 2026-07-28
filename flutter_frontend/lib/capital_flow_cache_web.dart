import 'dart:convert';

import 'package:web/web.dart' as web;

const _cacheKey = 'ekt.capital-flow.cache.v1';

void saveCapitalFlowCache(Map<String, dynamic> payload) {
  try {
    final current = _readCache();
    final records = <String, Map<String, dynamic>>{};

    for (final raw in (current?['items'] as List<dynamic>?) ?? const []) {
      final item = Map<String, dynamic>.from(raw as Map);
      records[_recordKey(item)] = item;
    }
    for (final raw in (payload['items'] as List<dynamic>?) ?? const []) {
      final item = Map<String, dynamic>.from(raw as Map);
      records[_recordKey(item)] = item;
    }

    final items = records.values.toList()
      ..sort((a, b) => '${a['reference_date']}|${a['investor_type']}'
          .compareTo('${b['reference_date']}|${b['investor_type']}'));

    web.window.localStorage.setItem(
      _cacheKey,
      jsonEncode({
        'items': items,
        'notice': payload['notice'],
        'last_updated': payload['last_updated'],
        'cached_at': DateTime.now().toIso8601String(),
      }),
    );
  } catch (_) {
    // Browser storage is a convenience fallback; server persistence is primary.
  }
}

Map<String, dynamic>? loadCapitalFlowCache(String dateFrom, String dateTo) {
  try {
    final cache = _readCache();
    if (cache == null) return null;

    final items = ((cache['items'] as List<dynamic>?) ?? const [])
        .map((raw) => Map<String, dynamic>.from(raw as Map))
        .where((item) {
      final date = '${item['reference_date'] ?? ''}';
      return date.compareTo(dateFrom) >= 0 && date.compareTo(dateTo) <= 0;
    }).toList();
    if (items.isEmpty) return null;

    return {
      'ok': true,
      'items': items,
      'notice': cache['notice'],
      'last_updated': cache['last_updated'],
      'cached_at': cache['cached_at'],
    };
  } catch (_) {
    return null;
  }
}

Map<String, dynamic>? _readCache() {
  final raw = web.window.localStorage.getItem(_cacheKey);
  if (raw == null || raw.isEmpty) return null;
  return Map<String, dynamic>.from(jsonDecode(raw) as Map);
}

String _recordKey(Map<String, dynamic> item) =>
    '${item['reference_date']}|${item['investor_type']}';
