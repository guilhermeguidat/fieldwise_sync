/// Entidade de exemplo da Fase 1 (o "cano fecha" com uma única entidade).
///
/// Dois campos de controle além dos dados de negócio:
/// - [version]: número de versão do registro. É a base da **detecção de
///   conflito** (o cliente informa em que versão baseou a edição; se o
///   servidor já está em outra, houve conflito).
/// - [updatedAt]: instante da última alteração. Usado apenas como
///   **desempate na estratégia LWW** (Last Write Wins), nunca para detectar
///   conflito — relógio de celular não é confiável para isso.
class Product {
  final String id;
  final String name;

  // ponytail: price como double basta para a demo; se precisão monetária
  // virar requisito, trocar por int (centavos).
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
