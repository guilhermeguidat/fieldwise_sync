import '../annotations.dart';
import '../engine/entity.dart';
import '../engine/field_rule.dart';

part 'order.g.dart';

/// Pedido fechado no checkout. É **só inserção**: nasce no dispositivo, com id
/// gerado ali, e nunca é editado. Não disputa campo com ninguém; o que importa
/// nele é o Outbox: pedido feito sem sinal tem de chegar ao servidor (OE2/OE4).
///
/// Regra da entidade: Server Wins. Se a confirmação de um envio se perder e o
/// pedido for reenviado, o servidor já o tem e a cópia repetida não altera
/// nada. O id gerado no cliente faz o reenvio cair no mesmo registro: entrega
/// ao menos uma vez sem pedido duplicado.
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

/// Item do pedido. O preço unitário é copiado do produto no momento da venda:
/// o pedido registra o que foi cobrado, mesmo que o preço mude depois.
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
