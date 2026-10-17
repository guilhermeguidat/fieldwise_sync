import 'package:fieldwise_sync/fieldwise_sync.dart';

part 'order.g.dart';

/// Pedido: só inserção, com id gerado no dispositivo. Server Wins faz um
/// reenvio (resposta perdida) cair no mesmo registro sem alterá-lo, então não
/// há pedido duplicado.
@SyncEntity(defaultRule: FieldRule.serverWins)
class Order implements Syncable {
  @override
  final String id;
  final String customerId;

  /// Usuário (vendedor) que fechou a venda.
  final String seller;
  final List<OrderItem> items;

  @override
  final int version;
  @override
  final DateTime updatedAt;

  const Order({
    required this.id,
    required this.customerId,
    required this.seller,
    required this.items,
    required this.version,
    required this.updatedAt,
  });

  double get total => items.fold(0, (sum, i) => sum + i.quantity * i.unitPrice);

  @override
  Json toJson() => {
    'id': id,
    'customerId': customerId,
    'seller': seller,
    'items': [for (final i in items) i.toJson()],
    'version': version,
    'updatedAt': updatedAt.toUtc().toIso8601String(),
  };

  factory Order.fromJson(Json j) => Order(
    id: j['id'] as String,
    customerId: j['customerId'] as String,
    seller: j['seller'] as String,
    items: [for (final i in j['items'] as List) OrderItem.fromJson(i as Json)],
    version: j['version'] as int,
    updatedAt: DateTime.parse(j['updatedAt'] as String),
  );

  @override
  String toString() =>
      'Order($id, $customerId, ${items.length} itens, v$version)';
}

/// Item do pedido, com o preço cobrado no momento da venda.
class OrderItem {
  final String productId;
  final int quantity;
  final double unitPrice;

  const OrderItem({
    required this.productId,
    required this.quantity,
    required this.unitPrice,
  });

  Json toJson() => {
    'productId': productId,
    'quantity': quantity,
    'unitPrice': unitPrice,
  };

  factory OrderItem.fromJson(Json j) => OrderItem(
    productId: j['productId'] as String,
    quantity: j['quantity'] as int,
    unitPrice: (j['unitPrice'] as num).toDouble(),
  );
}
