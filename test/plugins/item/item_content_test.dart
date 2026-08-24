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
}
