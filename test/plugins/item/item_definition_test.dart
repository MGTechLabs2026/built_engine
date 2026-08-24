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
}
