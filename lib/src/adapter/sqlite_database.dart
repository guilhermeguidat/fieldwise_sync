import 'dart:convert';

import 'package:sqlite3/sqlite3.dart';

import '../model/product.dart';
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
      CREATE TABLE IF NOT EXISTS products (
        id   TEXT PRIMARY KEY,
        json TEXT NOT NULL
      );
      CREATE TABLE IF NOT EXISTS outbox (
        seq          INTEGER PRIMARY KEY AUTOINCREMENT,
        product_json TEXT    NOT NULL,
        base_version INTEGER NOT NULL
      );
    ''');
  }

  SqliteDatabase.inMemory() : this(':memory:');

  @override
  Product? get(String id) {
    final rows = _db.select('SELECT json FROM products WHERE id = ?', [id]);
    return rows.isEmpty ? null : _decode(rows.first['json'] as String);
  }

  @override
  List<Product> all() => _db
      .select('SELECT json FROM products')
      .map((r) => _decode(r['json'] as String))
      .toList();

  @override
  void put(Product p) => _db.execute(
    'INSERT OR REPLACE INTO products (id, json) VALUES (?, ?)',
    [p.id, jsonEncode(p.toJson())],
  );

  @override
  void enqueue(Mutation m) => _db.execute(
    'INSERT INTO outbox (product_json, base_version) VALUES (?, ?)',
    [jsonEncode(m.product.toJson()), m.baseVersion],
  );

  @override
  Mutation? peekOutbox() {
    final rows = _db.select(
      'SELECT product_json, base_version FROM outbox ORDER BY seq LIMIT 1',
    );
    if (rows.isEmpty) return null;
    final r = rows.first;
    return Mutation(
      _decode(r['product_json'] as String),
      r['base_version'] as int,
    );
  }

  @override
  void popOutbox() => _db.execute(
    'DELETE FROM outbox WHERE seq = (SELECT MIN(seq) FROM outbox)',
  );

  @override
  int get pendingCount =>
      _db.select('SELECT COUNT(*) AS n FROM outbox').first['n'] as int;

  void close() => _db.dispose();

  static Product _decode(String json) =>
      Product.fromJson(jsonDecode(json) as Map<String, dynamic>);
}
