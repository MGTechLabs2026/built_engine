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

  test('the six non-combinable starting-kit items load, are immediately '
      'usable, and stay non-combinable', () {
    final registry = ContentRegistry();
    registry.loadAll(itemContentDefinitions);

    for (final id in [
      ItemIds.chair,
      ItemIds.mask,
      ItemIds.staff,
      ItemIds.fan,
      ItemIds.towel,
      ItemIds.cloth,
    ]) {
      final item = itemDefinitionFromContent(registry.get(id));
      expect(item.requirement!.minimumLevel, equals(0),
          reason: '$id must be usable with no training');
      expect(item.maxClass, isNull, reason: '$id must not be combinable');
      expect(item.gradeEvolutionCandidates, isEmpty);
    }
  });

  test('V1: polearm and rapier are immediately usable AND now carry a '
      'combine chain', () {
    final registry = ContentRegistry();
    registry.loadAll(itemContentDefinitions);

    for (final id in [ItemIds.polearm, ItemIds.rapier]) {
      final item = itemDefinitionFromContent(registry.get(id));
      expect(item.requirement!.minimumLevel, equals(0),
          reason: '$id stays gate-free');
      expect(item.maxClass, equals(3), reason: '$id now opens a combine chain');
      expect(item.gradeEvolutionCandidates, hasLength(2));
      for (final c in item.gradeEvolutionCandidates) {
        expect(registry.find(c.targetId), isNotNull,
            reason: '$id grade target ${c.targetId} must exist');
      }
    }
  });

  test('V1: the hand_wraps family is a full base -> grade-2 -> grade-3 chain', () {
    final registry = ContentRegistry();
    registry.loadAll(itemContentDefinitions);

    final base = itemDefinitionFromContent(registry.get(ItemIds.handWraps));
    expect(base.requirement!.minimumLevel, equals(0));
    expect(base.maxClass, equals(3));
    expect(
      base.gradeEvolutionCandidates.map((c) => c.targetId),
      containsAll([ItemIds.focusWraps, ItemIds.weightedWraps]),
    );
    for (final g2 in [ItemIds.focusWraps, ItemIds.weightedWraps]) {
      final item = itemDefinitionFromContent(registry.get(g2));
      expect(item.maxClass, equals(6));
      expect(item.gradeEvolutionCandidates, hasLength(1));
      final g3 = itemDefinitionFromContent(
          registry.get(item.gradeEvolutionCandidates.single.targetId));
      expect(g3.maxClass, equals(9));
    }
  });

  test('every loot-rollable base item carries a rarity tag; every '
      'gradeEvolution targetId across the whole roster resolves', () {
    final registry = ContentRegistry();
    registry.loadAll(itemContentDefinitions);
    const rarities = {'rarity:common', 'rarity:uncommon', 'rarity:rare', 'rarity:master'};

    // The reward weighter only ever rolls base items; grade forms are
    // reached through Combine and derive rarity from their grade.
    for (final id in [
      ItemIds.knife, ItemIds.ironSword, ItemIds.gloves, ItemIds.trainingStaff,
      ItemIds.clothArmor, ItemIds.trainingShoes,
      ItemIds.handWraps, ItemIds.polearm, ItemIds.rapier,
    ]) {
      final raw = itemContentDefinitions.firstWhere((d) => d['id'] == id);
      expect((raw['tags'] as List).cast<String>().any(rarities.contains), isTrue,
          reason: '$id needs a rarity tag');
    }

    for (final raw in itemContentDefinitions) {
      for (final e in (raw['gradeEvolution'] as List? ?? const [])) {
        final target = (e as Map)['targetId'] as String;
        expect(registry.find(target), isNotNull,
            reason: '${raw['id']} grade-evolves to missing $target');
      }
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
