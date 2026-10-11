import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../models/vehicle_scan.dart';

/// Local SQLite persistence for scans.
class DatabaseService {
  DatabaseService._();
  static final DatabaseService instance = DatabaseService._();

  Database? _db;

  Future<Database> get _database async => _db ??= await _open();

  Future<Database> _open() async {
    final path = p.join(await getDatabasesPath(), 'vehicle_scans.db');
    return openDatabase(
      path,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE scans (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            raw_data TEXT NOT NULL,
            vin TEXT NOT NULL,
            spec_code TEXT NOT NULL,
            fuel_type TEXT NOT NULL,
            scanned_at TEXT NOT NULL
          )
        ''');
        await db.execute('CREATE INDEX idx_scans_vin ON scans(vin)');
        await db.execute('CREATE INDEX idx_scans_time ON scans(scanned_at)');
      },
    );
  }

  Future<int> insert(VehicleScan scan) async {
    final db = await _database;
    return db.insert('scans', scan.toMap()..remove('id'));
  }

  Future<void> update(VehicleScan scan) async {
    final db = await _database;
    await db.update('scans', scan.toMap(), where: 'id = ?', whereArgs: [scan.id]);
  }

  Future<void> delete(int id) async {
    final db = await _database;
    await db.delete('scans', where: 'id = ?', whereArgs: [id]);
  }

  /// Newest first. [query] matches VIN, spec code or raw data; [fuel] is exact.
  Future<List<VehicleScan>> all({String query = '', String? fuel}) async {
    final db = await _database;
    final where = <String>[];
    final args = <Object?>[];
    final q = query.trim();
    if (q.isNotEmpty) {
      where.add('(vin LIKE ? OR spec_code LIKE ? OR raw_data LIKE ?)');
      args.addAll(['%$q%', '%$q%', '%$q%']);
    }
    if (fuel != null && fuel.isNotEmpty) {
      where.add('fuel_type = ?');
      args.add(fuel);
    }
    final rows = await db.query(
      'scans',
      where: where.isEmpty ? null : where.join(' AND '),
      whereArgs: args.isEmpty ? null : args,
      orderBy: 'scanned_at DESC',
    );
    return rows.map(VehicleScan.fromMap).toList();
  }

  Future<List<VehicleScan>> recent({int limit = 8}) async {
    final db = await _database;
    final rows = await db.query('scans', orderBy: 'scanned_at DESC', limit: limit);
    return rows.map(VehicleScan.fromMap).toList();
  }

  Future<int> count() async {
    final db = await _database;
    return Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM scans')) ?? 0;
  }

  /// Fuel type -> number of scans, biggest first.
  Future<Map<String, int>> fuelCounts() async {
    final db = await _database;
    final rows = await db.rawQuery(
      'SELECT fuel_type, COUNT(*) AS c FROM scans GROUP BY fuel_type ORDER BY c DESC',
    );
    return {
      for (final r in rows)
        ((r['fuel_type'] as String).isEmpty ? 'Unknown' : r['fuel_type'] as String):
            r['c'] as int,
    };
  }

  /// True if another saved scan already has this VIN.
  Future<bool> vinExists(String vin, {int? excludeId}) async {
    final db = await _database;
    final rows = await db.query(
      'scans',
      columns: ['id'],
      where: excludeId == null ? 'vin = ?' : 'vin = ? AND id != ?',
      whereArgs: excludeId == null ? [vin] : [vin, excludeId],
      limit: 1,
    );
    return rows.isNotEmpty;
  }
}
