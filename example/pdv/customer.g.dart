// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'customer.dart';

// **************************************************************************
// SyncConfigGenerator
// **************************************************************************

const customerFieldRules = <String, FieldRule>{
  'name': FieldRule.lww,
  'phone': FieldRule.lww,
  'creditLimit': FieldRule.serverWins,
};

const customerEntity = EntityType<Customer>(
  'Customer',
  Customer.fromJson,
  customerFieldRules,
);
