import 'package:build_engine/build_engine.dart';
import 'package:build_engine/item_plugin.dart';
import 'package:test/test.dart';

void main() {
  test('itemDefinitionFromContent reads the auras id list', () {
    final registry = ContentRegistry();
    final def = registry.load({
      'id': 'test_boots',
      'type': 'footwear',
      'tags': <String>[],
      'properties': {'attack': 1},
      'auras': ['aura.one', 'aura.two'],
    });
    expect(itemDefinitionFromContent(def).auraRuleIds, ['aura.one', 'aura.two']);
  });

  test('an item with no auras key has an empty auraRuleIds', () {
    final registry = ContentRegistry();
    final def = registry.load({
      'id': 'plain',
      'type': 'weapon',
      'tags': <String>[],
      'properties': {'attack': 2},
    });
    expect(itemDefinitionFromContent(def).auraRuleIds, isEmpty);
  });

  test('ItemDefinition default auraRuleIds is const []', () {
    const def = ItemDefinition(
      id: 'x', category: 'weapon', tags: {}, properties: {},
    );
    expect(def.auraRuleIds, isEmpty);
  });
}
