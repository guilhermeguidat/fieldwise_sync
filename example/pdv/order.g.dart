// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'order.dart';

// **************************************************************************
// SyncConfigGenerator
// **************************************************************************

const orderFieldRules = <String, FieldRule>{
  'customerId': FieldRule.serverWins,
  'seller': FieldRule.serverWins,
  'items': FieldRule.serverWins,
};

const orderEntity = EntityType<Order>('Order', Order.fromJson, orderFieldRules);
