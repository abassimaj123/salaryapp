import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../salary_engine.dart';

class HistoryEntry {
  final int? id;
  final String flavor;      // 'us' | 'uk' | 'ca'
  final String region;      // state / province / '' for UK
  final DateTime timestamp;
  final SalaryResult result;

  const HistoryEntry({
    this.id,
    required this.flavor,
    required this.region,
    required this.timestamp,
    required this.result,
  });

  Map<String, dynamic> toMap() => {
        if (id != null) 'id': id,
        'flavor': flavor,
        'region': region,
        'timestamp': timestamp.toIso8601String(),
        ...result.toMap(),
      };

  factory HistoryEntry.fromMap(Map<String, dynamic> m) => HistoryEntry(
        id: m['id'] as int?,
        flavor: m['flavor'] as String,
        region: m['region'] as String,
        timestamp: DateTime.parse(m['timestamp'] as String),
        result: SalaryResult.fromMap(m),
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
      version: 1,
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
          effectiveRate REAL  NOT NULL
        )
      '''),
    );
  }

  Future<List<HistoryEntry>> getAll() async {
    final db = await _database;
    final rows = await db.query('history', orderBy: 'timestamp DESC');
    return rows.map(HistoryEntry.fromMap).toList();
  }

  Future<int> count() async {
    final db = await _database;
    final result =
        await db.rawQuery('SELECT COUNT(*) as cnt FROM history');
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
}
