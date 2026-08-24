import 'package:build_engine/build_engine.dart';
import 'package:build_engine/src/plugins/technique/technique_definition.dart';
import 'package:test/test.dart';

void main() {
  test('TechniqueDefinition carries id/name/tier/tags/properties', () {
    const definition = TechniqueDefinition(
      id: 'basic_punch',
      name: 'Basic Punch',
      tier: EvolutionTiers.basic,
      tags: {'technique', 'fist'},
      properties: {'damage': 6},
    );

    expect(definition.id, equals('basic_punch'));
    expect(definition.name, equals('Basic Punch'));
    expect(definition.tier, equals(EvolutionTiers.basic));
    expect(definition.properties['damage'], equals(6));
  });

  test('toEvolutionDefinition builds a matching EvolutionDefinition', () {
    const definition = TechniqueDefinition(
      id: 'basic_punch',
      name: 'Basic Punch',
      tier: EvolutionTiers.basic,
      tags: {'technique'},
      properties: {},
      evolutionCandidates: [
        EvolutionCandidate(targetId: 'light_punch', tags: {'precision'}),
      ],
    );

    final evolution = definition.toEvolutionDefinition();

    expect(evolution.id, equals('basic_punch'));
    expect(evolution.tier, equals(EvolutionTiers.basic));
    expect(evolution.candidates.single.targetId, equals('light_punch'));
  });

  test('modifiersFor defaults to no modifiers when unset', () {
    const definition = TechniqueDefinition(
      id: 'basic_punch',
      name: 'Basic Punch',
      tier: EvolutionTiers.basic,
      tags: {},
      properties: {},
    );

    expect(definition.modifiersFor(const EntityId(1)), isEmpty);
  });
}
