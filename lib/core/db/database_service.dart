import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../salary_engine.dart';

class HistoryEntry {
  final int? id;
  final String flavor; // 'us' | 'uk' | 'ca'
  final String region; // state / province / '' for UK
  final DateTime timestamp;
  final SalaryResult result;

  // ── SmartHistory ring-buffer / Save Scenario fields ──────────────────────
  final bool isPinned;
  final String? inputHash;
  final String? pinLabel;
  final int pinOrder;

  const HistoryEntry({
    this.id,
    required this.flavor,
    required this.region,
    required this.timestamp,
    required this.result,
    this.isPinned = false,
    this.inputHash,
    this.pinLabel,
    this.pinOrder = 0,
  });

  Map<String, dynamic> toMap() => {
        if (id != null) 'id': id,
        'flavor': flavor,
        'region': region,
        'timestamp': timestamp.toIso8601String(),
        'is_pinned': isPinned ? 1 : 0,
        'input_hash': inputHash,
        'pin_label': pinLabel,
        'pin_order': pinOrder,
        ...result.toMap(),
      };

  factory HistoryEntry.fromMap(Map<String, dynamic> m) => HistoryEntry(
        id: m['id'] as int?,
        flavor: m['flavor'] as String,
        region: m['region'] as String,
        timestamp: DateTime.parse(m['timestamp'] as String),
        result: SalaryResult.fromMap(m),
        isPinned: (m['is_pinned'] as int?) == 1,
        inputHash: m['input_hash'] as String?,
        pinLabel: m['pin_label'] as String?,
        pinOrder: (m['pin_order'] as int?) ?? 0,
      );
}

class DatabaseService {
  DatabaseService._();
  static final instance = DatabaseService._();

  Database? _db;

  Future<Database> get _database async {
    _db ??= await _open();
    return _db!;
  }

  Future<Database> _open() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'salary_history.db');
    return openDatabase(
      path,
      version: 2,
      onUpgrade: (db, oldVersion, newVersion) async {
        // v2 — SmartHistory ring buffer + Save Scenario columns
        if (oldVersion < 2) {
          await db.execute(
              'ALTER TABLE history ADD COLUMN is_pinned INTEGER NOT NULL DEFAULT 0');
          await db.execute('ALTER TABLE history ADD COLUMN input_hash TEXT');
          await db.execute('ALTER TABLE history ADD COLUMN pin_label TEXT');
          await db.execute(
              'ALTER TABLE history ADD COLUMN pin_order INTEGER NOT NULL DEFAULT 0');
          await db.execute('ALTER TABLE history ADD COLUMN l1_json TEXT');
        }
      },
      onCreate: (db, _) => db.execute('''
        CREATE TABLE history (
          id          INTEGER PRIMARY KEY AUTOINCREMENT,
          flavor      TEXT    NOT NULL,
          region      TEXT    NOT NULL,
          timestamp   TEXT    NOT NULL,
          grossAnnual REAL    NOT NULL,
          federalTax  REAL    NOT NULL,
          ficaTax     REAL    NOT NULL,
          stateTax    REAL    NOT NULL,
          totalTax    REAL    NOT NULL,
          netAnnual   REAL    NOT NULL,
          netMonthly  REAL    NOT NULL,
          netBiWeekly REAL    NOT NULL,
          netWeekly   REAL    NOT NULL,
          effectiveRate REAL  NOT NULL,
          is_pinned   INTEGER NOT NULL DEFAULT 0,
          input_hash  TEXT,
          pin_label   TEXT,
          pin_order   INTEGER NOT NULL DEFAULT 0,
          l1_json     TEXT
        )
      '''),
    );
  }

  Future<List<HistoryEntry>> getAll() async {
    final db = await _database;
    final rows = await db.query('history',
        orderBy: 'is_pinned DESC, pin_order DESC, timestamp DESC');
    return rows.map(HistoryEntry.fromMap).toList();
  }

  Future<int> count() async {
    final db = await _database;
    final result = await db.rawQuery('SELECT COUNT(*) as cnt FROM history');
    return (result.first['cnt'] as int?) ?? 0;
  }

  Future<int> insert(HistoryEntry entry) async {
    final db = await _database;
    return db.insert('history', entry.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> delete(int id) async {
    final db = await _database;
    await db.delete('history', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> clearAll() async {
    final db = await _database;
    await db.delete('history');
  }

  // ── SmartHistory helpers ───────────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> getRows({bool? isPinned, int? limit}) async {
    final db = await _database;
    return db.query(
      'history',
      where: isPinned == null ? null : 'is_pinned = ?',
      whereArgs: isPinned == null ? null : [isPinned ? 1 : 0],
      orderBy: 'is_pinned DESC, pin_order DESC, timestamp DESC',
      limit: limit,
    );
  }

  Future<Map<String, dynamic>?> getByHash(String hash) async {
    final db = await _database;
    final rows = await db.query('history',
        where: 'input_hash = ?', whereArgs: [hash], limit: 1);
    return rows.isEmpty ? null : rows.first;
  }

  Future<int> update(int id, Map<String, dynamic> values) async {
    final db = await _database;
    return db.update('history', values, where: 'id = ?', whereArgs: [id]);
  }

  Future<int> countWhere({bool? isPinned}) async {
    final db = await _database;
    final result = await db.rawQuery(
      isPinned == null
          ? 'SELECT COUNT(*) as cnt FROM history'
          : 'SELECT COUNT(*) as cnt FROM history WHERE is_pinned = ?',
      isPinned == null ? null : [isPinned ? 1 : 0],
    );
    return (result.first['cnt'] as int?) ?? 0;
  }

  Future<List<Map<String, dynamic>>> getOldest(
      {required bool isPinned, required int limit}) async {
    final db = await _database;
    return db.query(
      'history',
      where: 'is_pinned = ?',
      whereArgs: [isPinned ? 1 : 0],
      orderBy: 'timestamp ASC',
      limit: limit,
    );
  }
}
