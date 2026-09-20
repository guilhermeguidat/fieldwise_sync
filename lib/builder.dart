/// Geradores de configuração de conflitos a partir das anotações (`@SyncEntity`
/// + `@Lww`/`@ServerWins`/`@ClientWins`). Rodam em tempo de build (source_gen).
///
/// Dois artefatos saem das MESMAS anotações (ADR 0002 — fonte única):
/// - [SyncConfigGenerator]: o mapa Dart `<nome>FieldRules` em `*.g.dart`,
///   consumido por `fieldMerge` (motor de referência / FakeServer);
/// - [SyncConfigJsonBuilder]: `lib/sync_config.json`, a mesma política em
///   formato agnóstico, lida pelo servidor (Spring) na inicialização.
///
/// É a peça que torna o OE3 declarativo ponta a ponta: a política mora na
/// entidade; nem o mapa Dart nem a config do servidor são escritos à mão.
///
// Arquivo de build-time: importa analyzer/build/source_gen (dev_dependencies).
// É o padrão para geradores in-package — daí o ignore abaixo.
// ignore_for_file: depend_on_referenced_packages
library;

import 'dart:convert';

import 'package:analyzer/dart/element/element.dart';
import 'package:build/build.dart';
import 'package:glob/glob.dart';
import 'package:source_gen/source_gen.dart';

import 'src/annotations.dart';

Builder syncConfigBuilder(BuilderOptions options) =>
    SharedPartBuilder([SyncConfigGenerator()], 'sync_config');

Builder syncConfigJsonBuilder(BuilderOptions options) =>
    SyncConfigJsonBuilder();

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

    final entries = [
      for (final e in _rulesOf(element).entries)
        "'${e.key}': FieldRule.${e.value}",
    ];
    final name = '${_lowerFirst(element.name!)}FieldRules';
    return 'const $name = <String, FieldRule>{\n  ${entries.join(',\n  ')}\n};';
  }
}

/// Agrega todas as classes `@SyncEntity` do pacote num único
/// `lib/sync_config.json`:
/// `{ "default": "LWW", "entities": { "Classe": { "campo": "REGRA" } } }`.
/// Campos sem anotação não entram (o servidor usa `default`, o mesmo
/// fallback do `fieldMerge`).
class SyncConfigJsonBuilder implements Builder {
  static const _entity = TypeChecker.typeNamed(SyncEntity);

  @override
  Map<String, List<String>> get buildExtensions => const {
    r'$lib$': ['sync_config.json'],
  };

  @override
  Future<void> build(BuildStep buildStep) async {
    final entities = <String, Map<String, String>>{};
    await for (final asset in buildStep.findAssets(Glob('lib/**.dart'))) {
      if (!await buildStep.resolver.isLibrary(asset)) continue;
      final lib = await buildStep.resolver.libraryFor(asset);
      for (final a in LibraryReader(lib).annotatedWith(_entity)) {
        final cls = a.element as ClassElement;
        entities[cls.name!] = _rulesOf(
          cls,
        ).map((field, rule) => MapEntry(field, _snakeUpper(rule)));
      }
    }
    const encoder = JsonEncoder.withIndent('  ');
    await buildStep.writeAsString(
      AssetId(buildStep.inputId.package, 'lib/sync_config.json'),
      '${encoder.convert({'default': 'LWW', 'entities': entities})}\n',
    );
  }
}

/// `campo -> regra` para os campos anotados de uma classe. Compartilhado
/// pelos dois geradores: é a única leitura das anotações.
Map<String, String> _rulesOf(ClassElement element) => {
  for (final field in element.fields)
    if (!field.isStatic && _ruleOf(field) != null) field.name!: _ruleOf(field)!,
};

String? _ruleOf(FieldElement field) {
  if (_lww.hasAnnotationOf(field)) return 'lww';
  if (_serverWins.hasAnnotationOf(field)) return 'serverWins';
  if (_clientWins.hasAnnotationOf(field)) return 'clientWins';
  return null;
}

String _lowerFirst(String s) => s[0].toLowerCase() + s.substring(1);

/// `serverWins` -> `SERVER_WINS` (o enum do lado Java).
String _snakeUpper(String camel) =>
    camel.replaceAllMapped(RegExp('[A-Z]'), (m) => '_${m[0]}').toUpperCase();
