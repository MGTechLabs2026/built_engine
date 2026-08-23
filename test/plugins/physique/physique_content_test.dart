import 'package:build_engine/build_engine.dart';
import 'package:build_engine/physique_plugin.dart';
import 'package:test/test.dart';

void main() {
  test('all 4 physique definitions load atomically as a batch', () {
    final registry = ContentRegistry();
    final definitions = registry.loadAll(physiqueContentDefinitions);
    expect(definitions, hasLength(4));
    expect(registry.allOfType('physique'), hasLength(4));
  });

  group('physiqueDefinitionFromContent', () {
    test('parses sturdy: id, tags, and primary affinity', () {
      final registry = ContentRegistry();
      registry.loadAll(physiqueContentDefinitions);
      final definition = physiqueDefinitionFromContent(registry.get('sturdy'));
      expect(definition.id, equals('sturdy'));
      expect(definition.tags,
          equals({'physique', 'defense', 'western_affinity'}));
      expect(definition.primaryAffinity, equals('defense'));
    });

    test('parses power/burst/endurance primary affinities', () {
      final registry = ContentRegistry();
      registry.loadAll(physiqueContentDefinitions);
      expect(physiqueDefinitionFromContent(registry.get('power')).primaryAffinity,
          equals('strength'));
      expect(physiqueDefinitionFromContent(registry.get('burst')).primaryAffinity,
          equals('speed'));
      expect(
          physiqueDefinitionFromContent(registry.get('endurance'))
              .primaryAffinity,
          equals('stamina'));
    });

    test(
        'modifiersFor builds exactly 2 conditional multiply modifiers on '
        'the primary affinity stat, targeting the given character', () {
      final registry = ContentRegistry();
      registry.loadAll(physiqueContentDefinitions);
      final definition = physiqueDefinitionFromContent(registry.get('sturdy'));
      final character = const EntityId(1);

      final modifiers = definition.modifiersFor(character);

      expect(modifiers, hasLength(2));
      for (final modifier in modifiers) {
        expect(modifier.target, equals(character));
        expect(modifier.stat, equals('defense'));
        expect(modifier.operation, equals(ModifierOperation.multiply));
        expect(modifier.condition, isNotNull);
      }
      expect(modifiers.map((m) => m.value).toSet(), equals({1.25, 0.85}));
    });

    test('modifiersFor builds a fresh set per call, targeting whichever '
        'character is given', () {
      final registry = ContentRegistry();
      registry.loadAll(physiqueContentDefinitions);
      final definition = physiqueDefinitionFromContent(registry.get('sturdy'));

      final a = const EntityId(1);
      final b = const EntityId(2);

      expect(definition.modifiersFor(a).every((m) => m.target == a), isTrue);
      expect(definition.modifiersFor(b).every((m) => m.target == b), isTrue);
    });
  });
}
