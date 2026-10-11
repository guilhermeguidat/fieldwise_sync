// Dois dispositivos editam offline o mesmo cliente, em campos diferentes, e
// sincronizam contra o servidor em memória (FakeServer, a especificação
// executável do protocolo). A mesclagem de três vias mantém as duas edições.
//
// Em produção, troque FakeServer por HttpTransport.login(...) e passe
// db: SqliteDatabase('local.db') ao SyncClient.
import 'package:fieldwise_sync/fieldwise_sync.dart';
import 'pdv.dart';

Future<void> main() async {
  final server = FakeServer.withPolicy([customerEntity]);
  final a = SyncClient(server);
  final b = SyncClient(server);
  final agora = DateTime.now().toUtc();

  a.edit(
    customerEntity,
    Customer(
      id: 'c1',
      name: 'Maria Souza',
      phone: '1111',
      creditLimit: 500,
      version: 0,
      updatedAt: agora,
    ),
  );
  await a.sync();
  await b.sync();

  // Offline: A muda o telefone, B muda o nome.
  final ca = a.get(customerEntity, 'c1')!;
  final cb = b.get(customerEntity, 'c1')!;
  a.edit(customerEntity, ca.copyWith(phone: '2222', updatedAt: agora));
  b.edit(
    customerEntity,
    cb.copyWith(name: 'Maria S. Andrade', updatedAt: agora),
  );

  await a.sync();
  await b.sync(); // conflito detectado pela versão; campos distintos: mescla
  await a.sync();

  final maria = a.get(customerEntity, 'c1')!;
  print('${maria.name} · ${maria.phone} · v${maria.version}');
  // Maria S. Andrade · 2222 · v3
}
