import 'package:fieldwise_sync/fieldwise_sync.dart';

part 'customer.g.dart';

/// Cliente do PDV. Dois vendedores podem atualizar o mesmo cadastro em campo,
/// cada um com o que ouviu do cliente: é a entidade em que a mesclagem por
/// campo mais aparece (um muda o telefone, outro o nome, nada se perde).
@SyncEntity()
class Customer implements Syncable {
  @override
  final String id;

  /// Dados de contato: em colisão real, vence a edição mais recente.
  @Lww()
  final String name;

  @Lww()
  final String phone;

  /// Limite de crédito: decisão da retaguarda, vendedor não sobrescreve.
  @ServerWins()
  final double creditLimit;

  @override
  final int version;
  @override
  final DateTime updatedAt;

  const Customer({
    required this.id,
    required this.name,
    required this.phone,
    required this.creditLimit,
    required this.version,
    required this.updatedAt,
  });

  Customer copyWith({
    String? name,
    String? phone,
    double? creditLimit,
    DateTime? updatedAt,
  }) => Customer(
    id: id,
    name: name ?? this.name,
    phone: phone ?? this.phone,
    creditLimit: creditLimit ?? this.creditLimit,
    version: version,
    updatedAt: updatedAt ?? this.updatedAt,
  );

  @override
  Json toJson() => {
    'id': id,
    'name': name,
    'phone': phone,
    'creditLimit': creditLimit,
    'version': version,
    'updatedAt': updatedAt.toUtc().toIso8601String(),
  };

  factory Customer.fromJson(Json j) => Customer(
    id: j['id'] as String,
    name: j['name'] as String,
    phone: j['phone'] as String,
    creditLimit: (j['creditLimit'] as num).toDouble(),
    version: j['version'] as int,
    updatedAt: DateTime.parse(j['updatedAt'] as String),
  );

  @override
  String toString() => 'Customer($id, "$name", $phone, v$version)';
}
