import 'adapter/local_database.dart';
import 'engine/conflict.dart';
import 'outbox/outbox.dart';
import 'transport/sync_transport.dart';

/// Cliente de sincronização de um dispositivo. [edit] funciona offline; [sync]
/// envia as pendências e traz o estado do servidor. Sem `db`, usa
/// [InMemoryDatabase].
class SyncClient {
  final SyncTransport _transport;
  final ILocalDatabase _db;

  SyncClient(this._transport, {ILocalDatabase? db})
    : _db = db ?? InMemoryDatabase();

  T? get<T extends Syncable>(EntityType<T> type, String id) {
    final json = _db.get(type.name, id);
    return json == null ? null : type.fromJson(json);
  }

  List<T> all<T extends Syncable>(EntityType<T> type) =>
      _db.all(type.name).map(type.fromJson).toList();

  /// Mutações na fila, ainda não enviadas.
  int get pending => _db.pendingCount;

  /// Cria ou edita [desired] localmente e o enfileira para envio. Atualize o
  /// `updatedAt` antes: é ele que desempata o LWW.
  void edit<T extends Syncable>(EntityType<T> type, T desired) {
    final before = _db.get(type.name, desired.id);
    final record = desired.toJson();
    _db.saveAndEnqueue(
      Mutation(
        type.name,
        record,
        before?['version'] as int? ?? 0,
        changedFields(before, record),
      ),
    );
  }

  /// Envia o Outbox e puxa o estado do servidor. Cada mutação só sai da fila
  /// após a resposta do servidor; se o envio falhar, a exceção do transporte
  /// sobe e o restante fica para o próximo [sync].
  Future<void> sync() async {
    for (var m = _db.peekOutbox(); m != null; m = _db.peekOutbox()) {
      final resolved = await _transport.push(m);
      _db.put(m.entity, resolved);
      _db.popOutbox();
    }
    for (final e in (await _transport.pull()).entries) {
      for (final r in e.value) {
        _db.put(e.key, r);
      }
    }
  }
}
