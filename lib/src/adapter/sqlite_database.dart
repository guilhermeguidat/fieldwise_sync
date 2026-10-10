import 'dart:convert';

import 'package:sqlite3/sqlite3.dart';

import '../engine/entity.dart';
import '../outbox/outbox.dart';
import 'local_database.dart';

/// Adapter SQLite de [ILocalDatabase] — a implementação concreta prometida no
/// pré-projeto. É o que roda no dispositivo: réplica local e Outbox
/// sobrevivem a fechar o app.
///
/// Usa o pacote `sqlite3` (binding Dart puro, via FFI), e não `sqflite`, para
/// que o adapter seja testável em `dart test` sem emulador. O motor de banco é
/// o mesmo SQLite; só muda o binding.
///
/// ponytail: registros guardados como JSON numa coluna, não uma coluna por
/// campo. O adapter é sobre persistência, não sobre consulta; se o app
/// precisar filtrar por campo no SQL, aí sim vira esquema por coluna.
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
  void enqueue(Mutation m) => _db.execute(
    'INSERT INTO outbox (mutation) VALUES (?)',
    [jsonEncode(m.toJson())],
  );

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
