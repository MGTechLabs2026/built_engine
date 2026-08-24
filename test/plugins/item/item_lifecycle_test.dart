import 'package:build_engine/build_engine.dart';
import 'package:build_engine/src/plugins/item/item_content.dart';
import 'package:build_engine/src/plugins/item/item_events.dart';
import 'package:build_engine/src/plugins/item/item_instance.dart';
import 'package:build_engine/src/plugins/item/item_lifecycle.dart';
import 'package:build_engine/src/plugins/item/item_rules.dart';
import 'package:build_engine/src/plugins/item/item_vocabulary.dart';
import 'package:test/test.dart';

// Shares `mastery`/`discovery` between `RuleEngine` and `PluginContext` —
// required per ARCHITECTURE.md's bootstrap example whenever a Rule (fired
// through RuleEngine) needs to see mastery/discovery state written through
// `PluginContext.mastery`/`.discovery` directly, as this plugin's own
// usability rule does. Relying on each side's own default would silently
// give them two independent trackers (ARCHITECTURE_AUDIT.md's Observation B).
PluginContext _newContext() {
  final events = EventBus();
  final entities = EntityRegistry(events);
  final components = ComponentStore();
  final rng = RngService(1);
  final mastery = MasteryTracker(components: components, events: events);
  final discovery = DiscoveryTracker(components: components, events: events);
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
      mastery: mastery,
      discovery: discovery,
    ),
    queries: QueryEngine(QueryScope(components: components)),
    modifiers: ModifierCollection(),
    content: ContentRegistry(),
    mastery: mastery,
    discovery: discovery,
  );
}

void main() {
  late PluginContext context;

  setUp(() {
    context = _newContext();
    context.content.loadAll(itemContentDefinitions);
    for (final rule in buildItemUsabilityRules([
      itemDefinition(ItemIds.ironSword, context),
    ])) {
      context.rules.register(rule);
    }
    context.mastery.define(
      const MasteryDefinition(subject: 'item:iron_sword', thresholds: [10, 25]),
    );
  });

  test('ownItem creates an ItemInstance referencing the definition', () {
    final owner = context.entities.create();

    final itemEntity = ownItem(owner, ItemIds.ironSword, context);

    expect(context.components.get<ItemInstance>(itemEntity)!.definitionId,
        equals(ItemIds.ironSword));
    expect(isItemOwned(owner, ItemIds.ironSword, context), isTrue);
  });

  test('an item can be discovered', () {
    final owner = context.entities.create();
    final ironSword = itemDefinition(ItemIds.ironSword, context);

    discoverItem(owner, ironSword, context);

    expect(context.discovery.stateOf(owner, 'item:iron_sword'),
        equals(DiscoveryState.discovered));
  });

  test('a discovered item stays LOCKED (not usable) with insufficient mastery', () {
    final owner = context.entities.create();
    final ironSword = itemDefinition(ItemIds.ironSword, context);
    discoverItem(owner, ironSword, context);

    expect(isItemUsable(owner, ironSword, context), isFalse);
  });

  test('mastery increases through the generic Mastery system', () {
    final owner = context.entities.create();

    context.mastery.increase(owner, 'item:iron_sword', 10);

    expect(context.mastery.levelOf(owner, 'item:iron_sword'), equals(1));
  });

  test('item becomes USABLE once mastery reaches the required level', () {
    final owner = context.entities.create();
    final ironSword = itemDefinition(ItemIds.ironSword, context);
    discoverItem(owner, ironSword, context);

    context.mastery.increase(owner, 'item:iron_sword', 25);

    expect(isItemUsable(owner, ironSword, context), isTrue);
    // the usability rule also promoted Discovery to unlocked:
    expect(context.discovery.stateOf(owner, 'item:iron_sword'),
        equals(DiscoveryState.unlocked));
  });

  test('an unusable item cannot enter the Tome', () {
    final owner = context.entities.create();
    final ironSword = itemDefinition(ItemIds.ironSword, context);
    discoverItem(owner, ironSword, context);
    context.tome.defineTome(
      TomeDefinition.namedSlots(id: 'basic_tome', slotIds: ['weapon']),
    );
    context.tome.createTome(owner, 'basic_tome');

    expect(
      () => addItemToTome(owner, const SlotId('weapon'), ironSword, context),
      throwsA(isA<ItemNotUsableException>()),
    );
    expect(context.tome.inspect(owner), isEmpty);
  });

  test('a usable item can enter the Tome and becomes ACTIVE', () {
    final owner = context.entities.create();
    final ironSword = itemDefinition(ItemIds.ironSword, context);
    discoverItem(owner, ironSword, context);
    context.mastery.increase(owner, 'item:iron_sword', 25);
    context.tome.defineTome(
      TomeDefinition.namedSlots(id: 'basic_tome', slotIds: ['weapon']),
    );
    context.tome.createTome(owner, 'basic_tome');

    ItemAddedToTome? published;
    context.events.subscribe<ItemAddedToTome>((e) => published = e);

    addItemToTome(owner, const SlotId('weapon'), ironSword, context);

    expect(isItemActive(owner, ItemIds.ironSword, context), isTrue);
    expect(published, isNotNull);
    expect(published!.definitionId, equals(ItemIds.ironSword));
  });

  test('OWNED/DISCOVERED/USABLE/ACTIVE are independently queryable, not one boolean', () {
    final owner = context.entities.create();
    final ironSword = itemDefinition(ItemIds.ironSword, context);
    context.tome.defineTome(
      TomeDefinition.namedSlots(id: 'basic_tome', slotIds: ['weapon']),
    );
    context.tome.createTome(owner, 'basic_tome');
    ownItem(owner, ItemIds.ironSword, context);

    // Owned, but not discovered/usable/active yet.
    expect(isItemOwned(owner, ItemIds.ironSword, context), isTrue);
    expect(isItemUsable(owner, ironSword, context), isFalse);
    expect(isItemActive(owner, ItemIds.ironSword, context), isFalse);

    discoverItem(owner, ironSword, context);
    context.mastery.increase(owner, 'item:iron_sword', 25);
    addItemToTome(owner, const SlotId('weapon'), ironSword, context);

    expect(isItemOwned(owner, ItemIds.ironSword, context), isTrue);
    expect(isItemUsable(owner, ironSword, context), isTrue);
    expect(isItemActive(owner, ItemIds.ironSword, context), isTrue);
  });

  test('an item with no requirement is usable immediately once discovered', () {
    final owner = context.entities.create();
    final knife = itemDefinition(ItemIds.knife, context);

    discoverItem(owner, knife, context);

    expect(isItemUsable(owner, knife, context), isTrue);
  });
}
