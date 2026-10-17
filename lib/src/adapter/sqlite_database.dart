import 'dart:convert';

import 'package:sqlite3/sqlite3.dart';

import '../engine/entity.dart';
import '../outbox/outbox.dart';
import 'local_database.dart';

/// [ILocalDatabase] sobre SQLite, via pacote `sqlite3` (FFI, sem Flutter). Num
/// app Flutter, adicione `sqlite3_flutter_libs` para o binário nativo.
/// Cada registro é guardado como JSON numa coluna de texto.
class SqliteDatabase implements ILocalDatabase {
  final Database _db;

  /// [path] é o arquivo do banco; `':memory:'` para um banco volátil.
  SqliteDatabase(String path) : _db = sqlite3.open(path) {
    _db.execute('''
      CREATE TABLE IF NOT EXISTS records (
        entity TEXT NOT NULL,
        id     TEXT NOT NULL,
        json   TEXT NOT NULL,
        PRIMARY KEY (entity, id)
      );
      CREATE TABLE IF NOT EXISTS outbox (
        seq      INTEGER PRIMARY KEY AUTOINCREMENT,
        mutation TEXT NOT NULL
      );
    ''');
  }

  SqliteDatabase.inMemory() : this(':memory:');

  @override
  Json? get(String entity, String id) {
    final rows = _db.select(
      'SELECT json FROM records WHERE entity = ? AND id = ?',
      [entity, id],
    );
    return rows.isEmpty ? null : _decode(rows.first['json']);
  }

  @override
  List<Json> all(String entity) => [
    for (final r in _db.select('SELECT json FROM records WHERE entity = ?', [
      entity,
    ]))
      _decode(r['json']),
  ];

  @override
  void put(String entity, Json record) => _db.execute(
    'INSERT OR REPLACE INTO records (entity, id, json) VALUES (?, ?, ?)',
    [entity, record['id'], jsonEncode(record)],
  );

  @override
  void saveAndEnqueue(Mutation m) {
    _db.execute('BEGIN');
    try {
      put(m.entity, m.record);
      _db.execute('INSERT INTO outbox (mutation) VALUES (?)', [
        jsonEncode(m.toJson()),
      ]);
      _db.execute('COMMIT');
    } catch (_) {
      _db.execute('ROLLBACK');
      rethrow;
    }
  }

  @override
  Mutation? peekOutbox() {
    final rows = _db.select('SELECT mutation FROM outbox ORDER BY seq LIMIT 1');
    return rows.isEmpty
        ? null
        : Mutation.fromJson(_decode(rows.first['mutation']));
  }

  @override
  void popOutbox() => _db.execute(
    'DELETE FROM outbox WHERE seq = (SELECT MIN(seq) FROM outbox)',
  );

  @override
  int get pendingCount =>
      _db.select('SELECT COUNT(*) AS n FROM outbox').first['n'] as int;

  void close() => _db.dispose();

  static Json _decode(Object? json) => jsonDecode(json as String) as Json;
}
