import 'package:fieldwise_sync/fieldwise_sync.dart';

part 'product.g.dart';

/// Produto do catálogo. O `build_runner` gera [productFieldRules] e
/// [productEntity] em `product.g.dart`.
@SyncEntity()
class Product implements Syncable {
  @override
  final String id;

  @Lww()
  final String name;

  /// Preço tabelado: o cliente não sobrescreve.
  // Em produção, prefira centavos (int) a double.
  @ServerWins()
  final double price;

  @override
  final int version;
  @override
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

  @override
  Json toJson() => {
    'id': id,
    'name': name,
    'price': price,
    'version': version,
    'updatedAt': updatedAt.toUtc().toIso8601String(),
  };

  factory Product.fromJson(Json j) => Product(
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
