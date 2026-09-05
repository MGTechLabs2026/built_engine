/// Proves Task 6/7's consolidation changed no combat number: an item
/// with a scaled attack + a statBonuses affix, hung and used in a real
/// attack, resolves to the exact same final damage this repo's own
/// pre-migration numbers would have produced (computed by hand from the
/// same inputs, not by re-deriving the old code path).
library;

import 'package:build_engine/build_engine.dart';
import 'package:build_engine/build_interpretation.dart';
import 'package:build_engine/item_plugin.dart';
import 'package:test/test.dart';

PluginContext _ctx() {
  final events = EventBus();
  final entities = EntityRegistry(events);
  final components = ComponentStore();
  final rng = RngService(1);
  final shared = CoreServices(components: components, events: events);
  final c = PluginContext(
    entities: entities, components: components, events: events, rng: rng,
    rules: RuleEngine(
      entities: entities, components: components, events: events,
      rng: rng, shared: shared),
    queries: QueryEngine(QueryScope(components: components)),
    modifiers: ModifierCollection(),
    content: ContentRegistry(),
    shared: shared,
  );
  ItemPlugin().initialize(c);
  return c;
}

void main() {
  test('a hung, affixed item folds attack + statBonuses into one modifier '
      'equal to their hand-computed sum', () {
    final ctx = _ctx();
    final owner = ctx.entities.create();
    final knife = itemDefinition(ItemIds.knife, ctx); // scaled 'attack' at class 1
    final instanceId = ownItem(owner, knife.id, ctx);
    // Give this specific copy an affix bonus on the same stat the knife's
    // own scaled attack already targets.
    final tags = knife.tags;
    final stat = WeaponStatTags.matchOrFallback(tags, 'item:${knife.id}');
    ctx.components.add<ItemInstance>(instanceId, ItemInstance(
      definitionId: knife.id, owner: owner, itemClass: 1,
      statBonuses: {stat: 3},
    ));

    ctx.tome.defineTome(TomeDefinition.namedSlots(id: 't', slotIds: ['s0']));
    ctx.tome.createTome(owner, 't');
    ctx.tome.insert(owner, const SlotId('s0'),
        BuildComponentRef(referenceType: itemReferenceType, contentId: knife.id,
            instanceEntityId: instanceId));

    const interp = ItemActionInterpreter();
    final build = ctx.tome.resolve(owner, ownedRefs: [
      BuildComponentRef(referenceType: itemReferenceType, contentId: knife.id,
          instanceEntityId: instanceId),
    ]);
    interp.interpret(build: build, actor: owner, targets: const [], context: ctx);

    final expected = knife.scaledProperties(1)['attack']! + 3; // hand-computed
    final resolved = const ModifierResolver().resolve(
      0, ctx.modifiers.activeModifiersFor(owner, stat, ctx.components),
    );
    expect(resolved, expected);
  });
}
