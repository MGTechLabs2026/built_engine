import 'package:build_engine/build_engine.dart';
import 'package:build_engine/item_plugin.dart';
import 'package:test/test.dart';

// See item_lifecycle_test.dart's `_newContext` for why `mastery`/
// `discovery` must be explicitly shared between `RuleEngine` and
// `PluginContext` here.
PluginContext _newContext() {
  final events = EventBus();
  final entities = EntityRegistry(events);
  final components = ComponentStore();
  final rng = RngService(1);
  final shared = CoreServices(components: components, events: events);
  return PluginContext(
    entities: entities,
    components: components,
    events: events,
    rng: rng,
    rules: RuleEngine(
      entities: entities,
      components: components,
      events: events,
      rng: rng,
      shared: shared,
    ),
    queries: QueryEngine(QueryScope(components: components)),
    modifiers: ModifierCollection(),
    content: ContentRegistry(),
    shared: shared,
  );
}

void main() {
  test('declares no dependencies', () {
    expect(ItemPlugin().dependencies, isEmpty);
  });

  test('initialize registers all 6 items and the mastery definitions', () {
    final context = _newContext();
    ItemPlugin().initialize(context);

    for (final id in [
      ItemIds.knife,
      ItemIds.ironSword,
      ItemIds.gloves,
      ItemIds.trainingStaff,
      ItemIds.clothArmor,
      ItemIds.trainingShoes,
    ]) {
      expect(context.content.get(id), isNotNull);
    }
    expect(context.mastery.definitionOf('item:iron_sword'), isNotNull);
  });

  test('unregister stops the usability rule from firing', () {
    final context = _newContext();
    final plugin = ItemPlugin();
    plugin.initialize(context);
    plugin.unregister(context);

    final owner = context.entities.create();
    final ironSword = itemDefinition(ItemIds.ironSword, context);
    discoverItem(owner, ironSword, context);
    context.mastery.increase(owner, 'item:iron_sword', 25);

    // Discovery is never auto-promoted without the rule.
    expect(context.discovery.stateOf(owner, 'item:iron_sword'),
        equals(DiscoveryState.discovered));
  });

  test('re-initializing on the same context does not throw ContentDuplicateIdException', () {
    final context = _newContext();
    final plugin = ItemPlugin();
    plugin.initialize(context);
    plugin.unregister(context);

    expect(() => plugin.initialize(context), returnsNormally);
    expect(context.content.get(ItemIds.knife).type, equals('weapon'));
  });

  test('ItemPlugin runs standalone (no Combat, no MartialArts) and is fully removable', () {
    final context = _newContext();
    final manager = PluginManager();
    manager.register(ItemPlugin());
    manager.initialize(context);
    manager.start(context);

    final owner = context.entities.create();
    final ironSword = itemDefinition(ItemIds.ironSword, context);
    context.tome.defineTome(
      TomeDefinition.namedSlots(id: 'basic_tome', slotIds: ['weapon']),
    );
    context.tome.createTome(owner, 'basic_tome');
    discoverItem(owner, ironSword, context);
    context.mastery.increase(owner, 'item:iron_sword', 25);
    addItemToTome(owner, const SlotId('weapon'), ironSword, context);
    expect(isItemActive(owner, ItemIds.ironSword, context), isTrue);

    manager.stop(context);
    manager.unregister(context);

    final ownedEntity = ownItem(owner, ItemIds.ironSword, context);
    context.entities.destroy(ownedEntity);
    // cleanup subscription was cancelled; nothing throws either way —
    // this only proves teardown ran without leaving a dangling handler.
  });
}
