import 'package:build_engine/build_engine.dart';
import 'package:build_engine/src/plugins/item/item_definition.dart';
import 'package:build_engine/src/plugins/item/item_requirement.dart';
import 'package:test/test.dart';

void main() {
  test('ItemDefinition carries id/category/tags/properties/requirement', () {
    const definition = ItemDefinition(
      id: 'iron_sword',
      category: 'weapon',
      tags: {'item', 'weapon', 'blade'},
      properties: {'attack': 3},
      requirement: ItemRequirement(masterySubject: 'item:iron_sword', minimumLevel: 2),
    );

    expect(definition.id, equals('iron_sword'));
    expect(definition.category, equals('weapon'));
    expect(definition.properties['attack'], equals(3));
    expect(definition.requirement!.minimumLevel, equals(2));
  });

  test('modifiersFor defaults to no modifiers when unset', () {
    const definition = ItemDefinition(
      id: 'knife',
      category: 'weapon',
      tags: {'item'},
      properties: {'attack': 2},
    );

    expect(definition.modifiersFor(const EntityId(1)), isEmpty);
  });

  test('maxClass/gradeEvolutionCandidates/classScalingPercent default to '
      'not-combinable/empty/15', () {
    const definition = ItemDefinition(
      id: 'knife', category: 'weapon', tags: {'item'}, properties: {'attack': 2},
    );

    expect(definition.maxClass, isNull);
    expect(definition.gradeEvolutionCandidates, isEmpty);
    expect(definition.classScalingPercent, equals(15));
  });

  test('scaledProperties applies +classScalingPercent% per class above 1', () {
    const definition = ItemDefinition(
      id: 'knife', category: 'weapon', tags: {'item'}, properties: {'attack': 10},
    );

    expect(definition.scaledProperties(1)['attack'], equals(10));
    expect(definition.scaledProperties(3)['attack'], closeTo(13.0, 0.001)); // 10 * 1.30
  });

  test('scaledProperties respects a custom classScalingPercent', () {
    const definition = ItemDefinition(
      id: 'knife', category: 'weapon', tags: {'item'}, properties: {'attack': 10},
      classScalingPercent: 25,
    );

    expect(definition.scaledProperties(3)['attack'], closeTo(15.0, 0.001)); // 10 * 1.50
  });

  test('toGradeEvolutionDefinition carries id/category/candidates through', () {
    const definition = ItemDefinition(
      id: 'simple_knife', category: 'weapon', tags: {'item'}, properties: {},
      gradeEvolutionCandidates: [EvolutionCandidate(targetId: 'sharp_knife')],
    );

    final evolution = definition.toGradeEvolutionDefinition();

    expect(evolution.id, equals('simple_knife'));
    expect(evolution.tier, equals('weapon'));
    expect(evolution.candidates.single.targetId, equals('sharp_knife'));
  });
}
