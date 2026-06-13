import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:calcwise_core/calcwise_core.dart';

class _MemoryAdapter implements DatabaseAdapter {
  final List<Map<String, dynamic>> _rows = [];
  int _nextId = 1;
  int get rowCount => _rows.length;

  @override
  Future<int> insertRow(Map<String, dynamic> row) async {
    final id = _nextId++;
    _rows.add({...row, 'id': id});
    return id;
  }

  @override
  Future<List<Map<String, dynamic>>> getRows({
    required String appKey,
    String? screenId,
    bool? isPinned,
    int? limit,
  }) async {
    var result = _rows.where((r) {
      if (r['app_key'] != appKey) return false;
      if (screenId != null && r['screen_id'] != screenId) return false;
      if (isPinned != null) return ((r['is_pinned'] as int) == 1) == isPinned;
      return true;
    }).toList();
    result.sort((a, b) {
      final aPin = a['is_pinned'] as int;
      final bPin = b['is_pinned'] as int;
      if (aPin != bPin) return bPin.compareTo(aPin);
      return (b['saved_at'] as int).compareTo(a['saved_at'] as int);
    });
    if (limit != null && result.length > limit) result = result.sublist(0, limit);
    return result;
  }

  @override
  Future<Map<String, dynamic>?> getRowByHash({required String appKey, required String resultHash}) async {
    try { return _rows.firstWhere((r) => r['app_key'] == appKey && r['result_hash'] == resultHash); }
    catch (_) { return null; }
  }

  @override
  Future<int> updateRow(int id, Map<String, dynamic> values) async {
    final idx = _rows.indexWhere((r) => r['id'] == id);
    if (idx < 0) return 0;
    _rows[idx] = {..._rows[idx], ...values};
    return 1;
  }

  @override
  Future<int> deleteRow(int id) async {
    final before = _rows.length;
    _rows.removeWhere((r) => r['id'] == id);
    return before - _rows.length;
  }

  @override
  Future<int> countRows({required String appKey, bool? isPinned}) async =>
      _rows.where((r) {
        if (r['app_key'] != appKey) return false;
        if (isPinned != null) return ((r['is_pinned'] as int) == 1) == isPinned;
        return true;
      }).length;

  @override
  Future<List<Map<String, dynamic>>> getOldestAutoSaves({required String appKey, required int limit}) async {
    final rows = _rows.where((r) => r['app_key'] == appKey && (r['is_pinned'] as int) == 0).toList()
      ..sort((a, b) => (a['saved_at'] as int).compareTo(b['saved_at'] as int));
    return rows.take(limit).toList();
  }

  @override
  Future<List<Map<String, dynamic>>> getOldestPinned({required String appKey, required int limit}) async {
    final rows = _rows.where((r) => r['app_key'] == appKey && (r['is_pinned'] as int) == 1).toList()
      ..sort((a, b) => (a['saved_at'] as int).compareTo(b['saved_at'] as int));
    return rows.take(limit).toList();
  }
}

Future<void> _pump() async {
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
}

void main() {
  late _MemoryAdapter adapter;
  late CalcwiseFreemium freemium;
  late SmartHistoryService svc;

  // SalaryApp has 3 flavors (ca/uk/us) but all use appKey='salaryapp'
  // screenId='calculator' for the main salary screen
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    adapter = _MemoryAdapter();
    freemium = CalcwiseFreemium(appKey: 'salaryapp');
    await freemium.initialize();
    svc = SmartHistoryService(
      db: adapter,
      freemium: freemium,
      overrideSaveDebounce: Duration.zero,
    );
  });

  tearDown(() => svc.dispose());

  group('SalaryApp — save → history scenarios', () {
    test('scenario: calculate net salary → entry appears in history', () async {
      // GIVEN: typical salary inputs (mirrors calculator_screen._buildL1/_buildL2)
      const grossAnnual = 85000.0;
      const netAnnual = 62400.0;
      const region = 'ON';          // CA flavor — Ontario
      const effectiveRate = 26.6;
      const totalTax = 22600.0;

      final inputHash = ResultHasher.hashMixed({
        'gross': ResultHasher.roundTo(grossAnnual, 1000),
        'region': region,
      });

      // WHEN: auto-save triggered (mirrors calculator_screen._scheduleAutoSave)
      var savedCalled = false;
      svc.scheduleAutoSave(
        appKey: 'salaryapp',
        screenId: 'calculator',
        inputHash: inputHash,
        l1: {
          'gross': grossAnnual,
          'net': netAnnual,
          'region': region,
          'effective_rate': effectiveRate,
          'total_tax': totalTax,
        },
        l2: {
          'inputs': {
            'gross': grossAnnual,
            'flavor': 'ca',
            'region': region,
          },
          'results': {
            'netAnnual': netAnnual,
            'totalTax': totalTax,
            'effectiveRate': effectiveRate,
            'netMonthly': netAnnual / 12,
          },
        },
        onSaved: () => savedCalled = true,
      );
      await _pump();

      // THEN
      final history = await svc.getHistory('salaryapp');
      expect(history, isNotEmpty,
          reason: 'History must contain the salary entry');
      expect(history.first.l1['gross'], grossAnnual);
      expect(savedCalled, isTrue,
          reason: 'onSaved must fire — anti-regression for history refresh race condition');
    });

    test('scenario: two different salary levels → both entries in history', () async {
      final salaries = [65000.0, 120000.0];
      for (var i = 0; i < 2; i++) {
        final gross = salaries[i];
        svc.scheduleAutoSave(
          appKey: 'salaryapp',
          screenId: 'calculator',
          inputHash: 'hash-salary-$i',
          l1: {'gross': gross, 'net': gross * 0.72, 'region': 'ON', 'effective_rate': 28.0},
          l2: {
            'inputs': {'gross': gross, 'flavor': 'ca', 'region': 'ON'},
            'results': {'netAnnual': gross * 0.72, 'effectiveRate': 28.0},
          },
        );
        await _pump();
      }
      final history = await svc.getHistory('salaryapp');
      expect(history.length, 2);
    });

    test('scenario: same salary twice → only one history entry', () async {
      const hash = 'same-hash-salaryapp';
      for (var i = 0; i < 3; i++) {
        svc.scheduleAutoSave(
          appKey: 'salaryapp',
          screenId: 'calculator',
          inputHash: hash,
          l1: {'gross': 75000.0, 'net': 54000.0, 'region': 'BC', 'effective_rate': 28.0},
          l2: {
            'inputs': {'gross': 75000.0, 'flavor': 'ca', 'region': 'BC'},
            'results': {'netAnnual': 54000.0},
          },
        );
        await _pump();
      }
      expect(adapter.rowCount, 1,
          reason: 'Identical inputs must not create duplicates');
    });

    test('scenario: pinned salary scenario survives ring buffer eviction', () async {
      await svc.saveScenario(
        appKey: 'salaryapp',
        screenId: 'calculator',
        inputHash: 'pinned-salary-scenario',
        l1: {'gross': 200000.0, 'net': 128000.0, 'region': 'QC', 'effective_rate': 36.0, 'total_tax': 72000.0},
        l2: {
          'inputs': {'gross': 200000.0, 'flavor': 'ca', 'region': 'QC'},
          'results': {'netAnnual': 128000.0, 'effectiveRate': 36.0},
        },
        label: 'Director comp package',
      );
      for (var i = 0; i < MonetizationConfig.freeRingBufferSize + 2; i++) {
        svc.scheduleAutoSave(
          appKey: 'salaryapp',
          screenId: 'calculator',
          inputHash: 'auto-salary-$i',
          l1: {'gross': i * 10000.0, 'net': i * 7200.0, 'region': 'ON'},
          l2: {'inputs': {'gross': i * 10000.0, 'flavor': 'ca'}, 'results': <String, dynamic>{}},
        );
        await _pump();
      }
      final pinned = await svc.getPinned('salaryapp');
      expect(pinned, isNotEmpty,
          reason: 'Pinned salary scenario must survive ring buffer eviction');
      expect(pinned.first.l1['gross'], 200000.0);
    });
  });
}
