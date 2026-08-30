/// Gerador de configuração de conflitos a partir das anotações (`@SyncEntity`
/// + `@Lww`/`@ServerWins`/`@ClientWins`). Roda em tempo de build (source_gen)
/// e emite, para cada entidade anotada, o mapa `<nome>FieldRules`.
///
/// É a peça que torna o OE3 declarativo: a política de conflito mora na
/// entidade; o mapa consumido por `fieldMerge` é gerado, não escrito à mão.
///
// Arquivo de build-time: importa analyzer/build/source_gen (dev_dependencies).
// É o padrão para geradores in-package — daí o ignore abaixo.
// ignore_for_file: depend_on_referenced_packages
library;

import 'package:analyzer/dart/element/element.dart';
import 'package:build/build.dart';
import 'package:source_gen/source_gen.dart';

import 'src/annotations.dart';

Builder syncConfigBuilder(BuilderOptions options) =>
    SharedPartBuilder([SyncConfigGenerator()], 'sync_config');

const _lww = TypeChecker.typeNamed(Lww);
const _serverWins = TypeChecker.typeNamed(ServerWins);
const _clientWins = TypeChecker.typeNamed(ClientWins);

class SyncConfigGenerator extends GeneratorForAnnotation<SyncEntity> {
  @override
  String generateForAnnotatedElement(
    Element element,
    ConstantReader annotation,
    BuildStep buildStep,
  ) {
    if (element is! ClassElement) {
      throw InvalidGenerationSourceError(
        '@SyncEntity só se aplica a classes.',
        element: element,
      );
    }

    final entries = <String>[];
    for (final field in element.fields) {
      if (field.isStatic) continue;
      final rule = _ruleOf(field);
      if (rule != null) entries.add("'${field.name}': FieldRule.$rule");
    }

    final name = '${_lowerFirst(element.name!)}FieldRules';
    return 'const $name = <String, FieldRule>{\n  ${entries.join(',\n  ')}\n};';
  }

  String? _ruleOf(FieldElement field) {
    if (_lww.hasAnnotationOf(field)) return 'lww';
    if (_serverWins.hasAnnotationOf(field)) return 'serverWins';
    if (_clientWins.hasAnnotationOf(field)) return 'clientWins';
    return null;
  }
}

String _lowerFirst(String s) => s[0].toLowerCase() + s.substring(1);
