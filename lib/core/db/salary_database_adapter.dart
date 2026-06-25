import 'dart:convert';

import 'package:calcwise_core/calcwise_core.dart' show DatabaseAdapter;

import '../salary_engine.dart';
import 'database_service.dart';

/// DatabaseAdapter implementation for SalaryApp.
///
/// Bridges SmartHistoryService (which speaks HistoryEntry / l1_json / l2_json)
/// to SalaryApp's flat sqflite `history` table.
///
/// `app_key` / `screen_id` are always 'salaryapp' / 'calculator' for this app.
/// The `l2` snapshot carries the full SalaryResult fields plus flavor/region so
/// they can be written into the dedicated columns the rest of the app reads.
class SalaryDatabaseAdapter implements DatabaseAdapter {
  static const _appKey = 'salaryapp';
  static const _screenId = 'calculator';

  // ── Insert ──────────────────────────────────────────────────────────────────

  @override
  Future<int> insertRow(Map<String, dynamic> row) async {
    final l2 = jsonDecode(row['l2_json'] as String) as Map<String, dynamic>;
    final savedAt = DateTime.fromMillisecondsSinceEpoch(row['saved_at'] as int);

    // _buildL2() nests salary fields under 'results' and meta under 'inputs'
    final inputs = (l2['inputs'] as Map<String, dynamic>?) ?? {};
    final results = (l2['results'] as Map<String, dynamic>?) ?? l2;

    double d(String k) => (results[k] as num?)?.toDouble() ?? 0.0;

    return DatabaseService.instance.insert(HistoryEntry(
      flavor: (inputs['flavor'] as String?) ?? (l2['flavor'] as String?) ?? '',
      region: (inputs['region'] as String?) ?? (l2['region'] as String?) ?? '',
      timestamp: savedAt,
      result: SalaryResult(
        grossAnnual: d('grossAnnual'),
        federalTax: d('federalTax'),
        ficaTax: d('ficaTax'),
        stateTax: d('stateTax'),
        totalTax: d('totalTax'),
        netAnnual: d('netAnnual'),
        netMonthly: d('netMonthly'),
        netBiWeekly: d('netBiWeekly'),
        netWeekly: d('netWeekly'),
        effectiveRate: d('effectiveRate'),
      ),
      isPinned: (row['is_pinned'] as int?) == 1,
      inputHash: row['result_hash'] as String?,
      pinLabel: row['pin_label'] as String?,
      pinOrder: (row['pin_order'] as int?) ?? 0,
    ));
  }

  // ── Query ────────────────────────────────────────────────────────────────────

  @override
  Future<List<Map<String, dynamic>>> getRows({
    required String appKey,
    String? screenId,
    bool? isPinned,
    int? limit,
  }) async {
    final rows =
        await DatabaseService.instance.getRows(isPinned: isPinned, limit: limit);
    return rows.map(_toAdapterRow).toList();
  }

  @override
  Future<Map<String, dynamic>?> getRowByHash({
    required String appKey,
    required String resultHash,
  }) async {
    final row = await DatabaseService.instance.getByHash(resultHash);
    return row == null ? null : _toAdapterRow(row);
  }

  // ── Update / Delete ──────────────────────────────────────────────────────────

  @override
  Future<int> updateRow(int id, Map<String, dynamic> values) async {
    return DatabaseService.instance.update(id, values);
  }

  @override
  Future<int> deleteRow(int id) async {
    await DatabaseService.instance.delete(id);
    return 1;
  }

  // ── Count / Eviction ─────────────────────────────────────────────────────────

  @override
  Future<int> countRows({required String appKey, bool? isPinned}) async {
    return DatabaseService.instance.countWhere(isPinned: isPinned);
  }

  @override
  Future<List<Map<String, dynamic>>> getOldestAutoSaves({
    required String appKey,
    required int limit,
  }) async {
    final rows =
        await DatabaseService.instance.getOldest(isPinned: false, limit: limit);
    return rows.map(_toAdapterRow).toList();
  }

  @override
  Future<List<Map<String, dynamic>>> getOldestPinned({
    required String appKey,
    required int limit,
  }) async {
    final rows =
        await DatabaseService.instance.getOldest(isPinned: true, limit: limit);
    return rows.map(_toAdapterRow).toList();
  }

  // ── Mapping ──────────────────────────────────────────────────────────────────

  Map<String, dynamic> _toAdapterRow(Map<String, dynamic> row) {
    final savedAt =
        DateTime.tryParse(row['timestamp'] as String? ?? '')?.millisecondsSinceEpoch ??
            0;
    final l1Json = (row['l1_json'] as String?) ?? _buildDefaultL1Json(row);
    return {
      'id': row['id'],
      'app_key': _appKey,
      'screen_id': _screenId,
      'result_hash': (row['input_hash'] as String?) ?? '',
      'l1_json': l1Json,
      'l2_json': _buildL2Json(row),
      'saved_at': savedAt,
      'is_pinned': (row['is_pinned'] as int?) ?? 0,
      'pin_label': row['pin_label'],
      'pin_order': (row['pin_order'] as int?) ?? 0,
    };
  }

  String _buildDefaultL1Json(Map<String, dynamic> row) {
    return jsonEncode({
      'gross': (row['grossAnnual'] as num?)?.toDouble() ?? 0.0,
      'net': (row['netAnnual'] as num?)?.toDouble() ?? 0.0,
      'region': row['region'],
    });
  }

  String _buildL2Json(Map<String, dynamic> row) {
    return jsonEncode({
      'inputs': {
        'flavor': row['flavor'],
        'region': row['region'],
      },
      'results': {
        'grossAnnual': row['grossAnnual'],
        'federalTax': row['federalTax'],
        'ficaTax': row['ficaTax'],
        'stateTax': row['stateTax'],
        'totalTax': row['totalTax'],
        'netAnnual': row['netAnnual'],
        'netMonthly': row['netMonthly'],
        'netBiWeekly': row['netBiWeekly'],
        'netWeekly': row['netWeekly'],
        'effectiveRate': row['effectiveRate'],
      },
    });
  }
}
