import '../model/product.dart';
import '../outbox/outbox.dart';

/// Contrato de comunicação com o servidor. O [SyncClient] fala só com esta
/// interface — não sabe se por trás há um servidor HTTP real ou um fake em
/// memória. Isso é o que permite testar toda a lógica de sync em Dart puro,
/// sem emulador nem rede (ver FakeServer nos testes).
abstract class SyncTransport {
  /// Envia uma mutação e recebe de volta o estado **resolvido** pelo servidor
  /// (após detecção + resolução de conflito e renumeração da versão).
  Future<Product> push(Mutation m);

  /// Puxa o estado atual do servidor (a fonte da verdade).
  ///
  /// ponytail: puxa o conjunto inteiro; quando a base crescer, trocar por
  /// pull incremental (a partir de um cursor "since").
  Future<List<Product>> pull();
}
