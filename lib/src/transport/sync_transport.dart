import '../engine/entity.dart';
import '../outbox/outbox.dart';

/// Canal com o servidor: `HttpTransport` ou `FakeServer`.
abstract class SyncTransport {
  /// Envia [m] e devolve o registro resolvido pelo servidor, já com a nova
  /// versão.
  Future<Json> push(Mutation m);

  /// Todos os registros do servidor, por entidade (não é incremental).
  Future<Map<String, List<Json>>> pull();
}
