/// Biblioteca de sincronização Offline-First com resolução configurável de
/// conflitos. Núcleo em Dart puro (sem Flutter).
library;

export 'src/annotations.dart';
export 'src/model/product.dart';
export 'src/engine/conflict.dart';
export 'src/outbox/outbox.dart';
export 'src/transport/sync_transport.dart';
export 'src/transport/fake_server.dart';
export 'src/transport/http_transport.dart';
export 'src/sync_client.dart';
