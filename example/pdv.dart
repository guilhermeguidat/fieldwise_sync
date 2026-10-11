/// Domínio de demonstração (Ponto de Venda): `Product`, `Customer` e `Order`
/// anotados com a política de conflito. Não faz parte do motor; mostra como
/// declarar as próprias entidades e serve aos testes e aos experimentos.
///
/// O app de demonstração (`app_pdv`, fora do pacote) declara o mesmo domínio;
/// `test/generated_config_test.dart` confere que as duas políticas coincidem.
library;

export 'pdv/customer.dart';
export 'pdv/order.dart';
export 'pdv/product.dart';
