import 'field_rule.dart';

/// Representação de um registro no protocolo: o `toJson()` da entidade.
///
/// O motor, o Outbox, os adapters e o transporte trabalham sobre [Json], e não
/// sobre classes concretas: é o que permite N entidades sem que nenhuma dessas
/// camadas conheça `Product`, `Customer` ou `Order`.
typedef Json = Map<String, dynamic>;

/// Contrato mínimo de uma entidade sincronizável. Os três campos de controle
/// são do protocolo (ADR 0001): [version] detecta conflito, [updatedAt] só
/// desempata o LWW.
abstract interface class Syncable {
  String get id;
  int get version;
  DateTime get updatedAt;
  Json toJson();
}

/// Descritor de uma entidade: o nome que viaja no protocolo, como reconstruir
/// o objeto a partir do JSON e a política de conflito resolvida por campo.
///
/// Não é escrito à mão: o gerador emite um `const <nome>Entity` para cada
/// classe `@SyncEntity` (ver `builder.dart`).
class EntityType<T extends Syncable> {
  final String name;
  final T Function(Json) fromJson;
  final Map<String, FieldRule> rules;

  const EntityType(this.name, this.fromJson, this.rules);
}
