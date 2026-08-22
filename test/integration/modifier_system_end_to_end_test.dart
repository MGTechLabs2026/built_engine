import 'package:build_engine/build_engine.dart';
import 'package:test/test.dart';

void main() {
  test(
      'ModifierCollection + ModifierResolver: stacking, conditional, and '
      'temporary modifiers resolve correctly end to end', () {
    final collection = ModifierCollection();
    const resolver = ModifierResolver();
    final components = ComponentStore();
    const target = EntityId(1);

    // Permanent flat bonus from equipment.
    collection.add(Modifier(
      source: const ModifierSource('item_sword'),
      target: target,
      stat: 'damage',
      operation: ModifierOperation.add,
      value: 5,
    ));

    // Conditional multiplier, only active while enraged.
    collection.add(Modifier(
      source: const ModifierSource('status_enraged'),
      target: target,
      stat: 'damage',
      operation: ModifierOperation.multiply,
      value: 2,
      condition: HasTagQuery('enraged'),
    ));

    // A temporary buff that expires after 1 tick.
    collection.add(Modifier(
      source: const ModifierSource('buff_adrenaline'),
      target: target,
      stat: 'damage',
      operation: ModifierOperation.add,
      value: 3,
      duration: 1,
    ));

    num currentDamage() => resolver.resolve(
          10,
          collection.activeModifiersFor(target, 'damage', components),
        );

    // Not enraged yet: base 10 + item 5 + buff 3 = 18 (multiplier inactive).
    expect(currentDamage(), equals(18));

    // Become enraged: (10 + 5 + 3) * 2 = 36.
    components.add(target, TagSet({'enraged'}));
    expect(currentDamage(), equals(36));

    // Tick past the buff's duration: (10 + 5) * 2 = 30.
    collection.tick();
    expect(currentDamage(), equals(30));

    // Remove the equipment bonus by source: 10 * 2 = 20.
    collection.removeBySource(const ModifierSource('item_sword'));
    expect(currentDamage(), equals(20));
  });
}
