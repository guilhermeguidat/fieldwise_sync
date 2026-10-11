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
// Arquivo de build-time: importa analyzer/build/source_gen, que ficam em
// dependencies porque o gerador roda no build_runner de quem usa o pacote.
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

    final cls = element.name!;
    final rules = _lowerFirst(cls);
    final entries = [
      for (final e in _rulesOf(element, annotation).entries)
        "  '${e.key}': FieldRule.${e.value},\n",
    ];
    return '''
const ${rules}FieldRules = <String, FieldRule>{
${entries.join()}};

const ${rules}Entity = EntityType<$cls>('$cls', $cls.fromJson, ${rules}FieldRules);''';
  }
}

/// Agrega todas as classes `@SyncEntity` do pacote num único
/// `lib/sync_config.json`:
/// `{ "default": "LWW", "entities": { "Classe": { "campo": "REGRA" } } }`.
/// A política sai **resolvida**: todo campo de negócio aparece com a sua regra
/// (a da anotação ou a `defaultRule` da entidade). `default` só cobre os
/// campos de protocolo, como `updatedAt` (o mesmo fallback do `fieldMerge`).
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
          a.annotation,
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

/// `campo -> regra` para cada campo de negócio de uma classe: a anotação do
/// campo ou, na falta dela, a `defaultRule` da `@SyncEntity`. Compartilhado
/// pelos dois geradores: é a única leitura das anotações.
Map<String, String> _rulesOf(ClassElement element, ConstantReader entity) {
  final entityDefault = entity
      .read('defaultRule')
      .revive()
      .accessor
      .split('.')
      .last;
  return {
    for (final field in element.fields)
      if (!field.isStatic &&
          !field.isSynthetic && // getters como `total` não são dado
          !_protocol.contains(field.name))
        field.name!: _ruleOf(field) ?? entityDefault,
  };
}

/// Campos de controle do protocolo (ADR 0001): não têm política.
const _protocol = {'id', 'version', 'updatedAt'};

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
