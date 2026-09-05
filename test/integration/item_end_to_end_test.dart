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
  test(
      'full item lifecycle: discover -> locked -> mastery training -> '
      'usable -> Tome', () {
    final context = _newContext();
    ItemPlugin().initialize(context);
    context.tome.defineTome(
      TomeDefinition.namedSlots(id: 'basic_tome', slotIds: ['weapon']),
    );

    final character = context.characters.create();
    context.tome.createTome(character, 'basic_tome');
    final ironSword = itemDefinition(ItemIds.ironSword, context);

    // discover -> LOCKED
    discoverItem(character, ironSword, context);
    expect(context.discovery.stateOf(character, 'item:iron_sword'),
        equals(DiscoveryState.discovered));
    expect(isItemUsable(character, ironSword, context), isFalse);
    expect(
      () => addItemToTome(character, const SlotId('weapon'), ironSword, context),
      throwsA(isA<ItemNotUsableException>()),
    );

    // train mastery (below requirement) -> still LOCKED
    context.mastery.increase(character, 'item:iron_sword', 10);
    expect(context.mastery.levelOf(character, 'item:iron_sword'), equals(1));
    expect(isItemUsable(character, ironSword, context), isFalse);

    // train mastery to the requirement -> USABLE
    context.mastery.increase(character, 'item:iron_sword', 15);
    expect(context.mastery.levelOf(character, 'item:iron_sword'), equals(2));
    expect(isItemUsable(character, ironSword, context), isTrue);

    // -> Tome
    addItemToTome(character, const SlotId('weapon'), ironSword, context);
    final build = context.tome.resolve(character, ownedRefs: const []);
    expect(
      build.active.any((c) =>
          c.referenceType == itemReferenceType && c.contentId == ItemIds.ironSword),
      isTrue,
    );
    expect(isItemActive(character, ItemIds.ironSword, context), isTrue);
  });

  test('deterministic: two identically-seeded runs reach the same ResolvedBuild', () {
    List<(String, String)> runOnce() {
      final context = _newContext();
      ItemPlugin().initialize(context);
      context.tome.defineTome(
        TomeDefinition.namedSlots(id: 'basic_tome', slotIds: ['weapon']),
      );
      final character = context.characters.create();
      context.tome.createTome(character, 'basic_tome');
      final ironSword = itemDefinition(ItemIds.ironSword, context);

      discoverItem(character, ironSword, context);
      context.mastery.increase(character, 'item:iron_sword', 25);
      addItemToTome(character, const SlotId('weapon'), ironSword, context);

      return context.tome
          .resolve(character, ownedRefs: const [])
          .active
          .map((c) => (c.referenceType, c.contentId))
          .toList();
    }

    expect(runOnce(), equals(runOnce()));
  });
}
