/// Política de conflito declarada na própria entidade. O `build_runner` gera
/// `<nome>FieldRules` e `<nome>Entity` a partir dela.
///
/// ```dart
/// @SyncEntity()
/// class Product implements Syncable {
///   @Lww() final String name;
///   @ServerWins() final double price;
/// }
/// ```
library;

import 'engine/field_rule.dart';

/// Marca uma classe como sincronizável. [defaultRule] vale para os campos sem
/// anotação.
class SyncEntity {
  final FieldRule defaultRule;
  const SyncEntity({this.defaultRule = FieldRule.lww});
}

/// Campo resolvido por Last Write Wins.
class Lww {
  const Lww();
}

/// Campo em que o servidor vence.
class ServerWins {
  const ServerWins();
}

/// Campo em que o cliente vence.
class ClientWins {
  const ClientWins();
}
