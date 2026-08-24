import 'package:build_engine/build_engine.dart';
import 'package:build_engine/src/plugins/item/item_content.dart';
import 'package:build_engine/src/plugins/item/item_vocabulary.dart';
import 'package:test/test.dart';

void main() {
  test('all 6 starter items load through ContentRegistry', () {
    final registry = ContentRegistry();
    registry.loadAll(itemContentDefinitions);

    for (final id in [
      ItemIds.knife,
      ItemIds.ironSword,
      ItemIds.gloves,
      ItemIds.trainingStaff,
      ItemIds.clothArmor,
      ItemIds.trainingShoes,
    ]) {
      expect(registry.find(id), isNotNull, reason: '$id should be loaded');
    }
  });

  test('itemDefinitionFromContent parses properties and requirement', () {
    final registry = ContentRegistry();
    registry.loadAll(itemContentDefinitions);

    final ironSword = itemDefinitionFromContent(registry.get(ItemIds.ironSword));

    expect(ironSword.category, equals('weapon'));
    expect(ironSword.properties['attack'], equals(3));
    expect(ironSword.requirement!.masterySubject, equals('item:iron_sword'));
    expect(ironSword.requirement!.minimumLevel, equals(2));
  });

  test('an item with minimum 0 has a requirement but no thresholds needed', () {
    final registry = ContentRegistry();
    registry.loadAll(itemContentDefinitions);

    final knife = itemDefinitionFromContent(registry.get(ItemIds.knife));

    expect(knife.requirement!.minimumLevel, equals(0));
  });

  test('modifiersFor turns properties into unconditional add Modifiers', () {
    final registry = ContentRegistry();
    registry.loadAll(itemContentDefinitions);
    final ironSword = itemDefinitionFromContent(registry.get(ItemIds.ironSword));

    final modifiers = ironSword.modifiersFor(const EntityId(1));

    expect(modifiers, hasLength(1));
    expect(modifiers.single.stat, equals('attack'));
    expect(modifiers.single.value, equals(3));
    expect(modifiers.single.operation, equals(ModifierOperation.add));
  });

  test('itemDefinitionFromContent parses maxClass/gradeEvolution/classScalingPercent', () {
    final registry = ContentRegistry();
    registry.load({
      'id': 'simple_knife',
      'type': 'weapon',
      'tags': ['item', 'weapon'],
      'properties': {'attack': 2},
      'maxClass': 3,
      'classScalingPercent': 20,
      'gradeEvolution': [
        {'targetId': 'sharp_knife', 'tags': ['precision']},
        {'targetId': 'heavy_knife', 'tags': ['power']},
      ],
    });

    final simpleKnife = itemDefinitionFromContent(registry.get('simple_knife'));

    expect(simpleKnife.maxClass, equals(3));
    expect(simpleKnife.classScalingPercent, equals(20));
    expect(
      simpleKnife.gradeEvolutionCandidates.map((c) => c.targetId),
      equals(['sharp_knife', 'heavy_knife']),
    );
    expect(simpleKnife.gradeEvolutionCandidates.first.tags, equals({'precision'}));
  });

  test('an item with no maxClass/gradeEvolution declared stays non-combinable', () {
    final registry = ContentRegistry();
    registry.load({
      'id': 'plain_item',
      'type': 'weapon',
      'tags': ['item', 'weapon'],
      'properties': {'attack': 1},
    });

    final plainItem = itemDefinitionFromContent(registry.get('plain_item'));

    expect(plainItem.maxClass, isNull);
    expect(plainItem.gradeEvolutionCandidates, isEmpty);
    expect(plainItem.classScalingPercent, equals(15)); // default
  });

  test('every shipped item now carries a real Combine grade chain', () {
    final registry = ContentRegistry();
    registry.loadAll(itemContentDefinitions);

    final knife = itemDefinitionFromContent(registry.get(ItemIds.knife));

    expect(knife.maxClass, equals(3));
    expect(
      knife.gradeEvolutionCandidates.map((c) => c.targetId),
      equals([ItemIds.sharpKnife, ItemIds.fastKnife]),
    );
    expect(knife.gradeEvolutionCandidates.first.tags, equals({TrainingDimensions.precision}));
  });
}
