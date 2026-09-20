import '../annotations.dart';
import '../engine/field_rule.dart';

part 'product.g.dart';

/// Entidade de exemplo da Fase 1 (o "cano fecha" com uma única entidade).
///
/// A política de conflito é declarada por anotação em cada campo (OE3): o
/// gerador (source_gen) lê essas anotações e emite [productFieldRules] no
/// arquivo `product.g.dart`, consumido por `fieldMerge`.
///
/// Dois campos de controle além dos dados de negócio:
/// - [version]: número de versão do registro. É a base da **detecção de
///   conflito** (o cliente informa em que versão baseou a edição; se o
///   servidor já está em outra, houve conflito).
/// - [updatedAt]: instante da última alteração. Usado apenas como
///   **desempate na estratégia LWW** (Last Write Wins), nunca para detectar
///   conflito — relógio de celular não é confiável para isso.
@SyncEntity()
class Product {
  final String id;

  /// Nome do produto: em conflito, vence a edição mais recente.
  @Lww()
  final String name;

  // ponytail: price como double basta para a demo; se precisão monetária
  // virar requisito, trocar por int (centavos).
  /// Preço: autoridade do servidor (preço tabelado não é sobrescrito pelo cliente).
  @ServerWins()
  final double price;

  final int version;
  final DateTime updatedAt;

  const Product({
    required this.id,
    required this.name,
    required this.price,
    required this.version,
    required this.updatedAt,
  });

  Product copyWith({
    String? name,
    double? price,
    int? version,
    DateTime? updatedAt,
  }) {
    return Product(
      id: id,
      name: name ?? this.name,
      price: price ?? this.price,
      version: version ?? this.version,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'price': price,
    'version': version,
    'updatedAt': updatedAt.toUtc().toIso8601String(),
  };

  factory Product.fromJson(Map<String, dynamic> j) => Product(
    id: j['id'] as String,
    name: j['name'] as String,
    price: (j['price'] as num).toDouble(),
    version: j['version'] as int,
    updatedAt: DateTime.parse(j['updatedAt'] as String),
  );

  @override
  String toString() =>
      'Product($id, "$name", $price, v$version, ${updatedAt.toIso8601String()})';
}
