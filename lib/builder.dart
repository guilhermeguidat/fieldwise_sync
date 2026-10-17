/// Geradores do `build_runner`. Das mesmas anotações saem
/// `<nome>FieldRules`/`<nome>Entity` em cada `*.g.dart` ([SyncConfigGenerator])
/// e `lib/sync_config.json` para o servidor ([SyncConfigJsonBuilder]).
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

/// Junta as classes `@SyncEntity` do pacote em `lib/sync_config.json`:
/// `{ "default": "LWW", "entities": { "Classe": { "campo": "REGRA" } } }`.
/// Todo campo de negócio sai com a regra resolvida; `default` só cobre os
/// campos de protocolo.
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

/// `campo -> regra` de cada campo de negócio: a anotação do campo ou a
/// `defaultRule` da entidade. Única leitura das anotações, usada pelos dois
/// geradores.
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

/// Campos de controle do protocolo, sem política.
const _protocol = {'id', 'version', 'updatedAt'};

String? _ruleOf(FieldElement field) {
  if (_lww.hasAnnotationOf(field)) return 'lww';
  if (_serverWins.hasAnnotationOf(field)) return 'serverWins';
  if (_clientWins.hasAnnotationOf(field)) return 'clientWins';
  return null;
}

String _lowerFirst(String s) => s[0].toLowerCase() + s.substring(1);

/// `serverWins` -> `SERVER_WINS`, o formato das regras no JSON.
String _snakeUpper(String camel) =>
    camel.replaceAllMapped(RegExp('[A-Z]'), (m) => '_${m[0]}').toUpperCase();
