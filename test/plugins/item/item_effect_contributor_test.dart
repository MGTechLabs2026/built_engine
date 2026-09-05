import 'package:build_engine/build_engine.dart';
import 'package:build_engine/item_plugin.dart';
import 'package:test/test.dart';

void main() {
  test('scaled attack + statBonuses fold into the supporting tier, keyed '
      "by the item's combat stat / raw bonus keys", () {
    final def = ItemDefinition(
      id: 'knife', category: 'weapon', tags: {'blade'},
      properties: {'attack': 4},
    );
    final instance = const ItemInstance(
      definitionId: 'knife', owner: EntityId(1), itemClass: 1,
      statBonuses: {'blade': 2, 'initiative': 1},
    );
    final profile = ItemEffectContributor(def, instance).effectProfile();
    expect(profile.tier(EffectTier.supporting), {
      'blade': 6, // 4 (scaled attack, class 1 -> no scaling) + 2 (statBonuses)
      'initiative': 1,
    });
    expect(profile.tier(EffectTier.permanent), isEmpty);
    expect(profile.tier(EffectTier.active), isEmpty);
  });

  test('an item with no attack property and no statBonuses yields an '
      'empty profile', () {
    final def = ItemDefinition(
      id: 'cloth_armor', category: 'armor', tags: const {}, properties: const {},
    );
    final profile = ItemEffectContributor(def, null).effectProfile();
    expect(profile.tier(EffectTier.supporting), isEmpty);
  });

  test('itemClass scaling is reflected in the profile, matching '
      'scaledProperties', () {
    final def = ItemDefinition(
      id: 'sword', category: 'weapon', tags: {'blade'},
      properties: {'attack': 10}, classScalingPercent: 20,
    );
    final instance = const ItemInstance(
        definitionId: 'sword', owner: EntityId(1), itemClass: 3);
    final profile = ItemEffectContributor(def, instance).effectProfile();
    // 10 * (1 + 0.20 * (3-1)) = 14
    expect(profile.amount(EffectTier.supporting, 'blade'), 14);
  });

  test('a null instance (legacy placement) still yields the definition-only '
      'part of the profile — attack scales at class 1', () {
    final def = ItemDefinition(
      id: 'knife', category: 'weapon', tags: {'blade'}, properties: {'attack': 4},
    );
    final profile = ItemEffectContributor(def, null).effectProfile();
    expect(profile.amount(EffectTier.supporting, 'blade'), 4);
  });
}
