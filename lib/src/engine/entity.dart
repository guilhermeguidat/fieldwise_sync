import 'field_rule.dart';

/// Um registro serializado (o `toJson()` da entidade).
typedef Json = Map<String, dynamic>;

/// Entidade sincronizável. [version] detecta conflito; [updatedAt] só desempata
/// o LWW.
abstract interface class Syncable {
  String get id;
  int get version;
  DateTime get updatedAt;
  Json toJson();
}

/// Nome, desserialização e regras por campo de uma entidade. Gerado como
/// `<nome>Entity` para cada classe `@SyncEntity`.
class EntityType<T extends Syncable> {
  final String name;
  final T Function(Json) fromJson;
  final Map<String, FieldRule> rules;

  const EntityType(this.name, this.fromJson, this.rules);
}
