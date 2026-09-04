import 'package:build_engine/build_engine.dart';
import 'package:build_engine/game.dart';
import 'package:build_engine/item_plugin.dart';
import 'package:test/test.dart';

({PluginContext ctx, EntityId character, TomeManager mgr}) _setup() {
  final events = EventBus();
  final entities = EntityRegistry(events);
  final components = ComponentStore();
  final rng = RngService(1);
  final shared = CoreServices(components: components, events: events);
  final ctx = PluginContext(
    entities: entities, components: components, events: events, rng: rng,
    rules: RuleEngine(
      entities: entities, components: components, events: events,
      rng: rng, shared: shared),
    queries: QueryEngine(QueryScope(components: components)),
    modifiers: ModifierCollection(),
    content: ContentRegistry(),
    shared: shared,
  );
  ItemPlugin().initialize(ctx);
  final character = ctx.characters.create();
  ctx.tome.defineTome(TomeDefinition.namedSlots(
      id: 't', slotIds: ['slot_1', 'slot_2']));
  ctx.tome.createTome(character, 't');
  final mgr = TomeManager(
    character: character,
    context: ctx,
    recordingPolicy: RecordingDecisionPolicy(const DefaultRunDecisionPolicy()),
    events: events,
    unlockedSlots: [SlotId('slot_1'), SlotId('slot_2')],
  );
  return (ctx: ctx, character: character, mgr: mgr);
}

void main() {
  test('placeItem hangs a specific owned ItemInstance, not a null-instance ref',
      () {
    final s = _setup();
    final item = itemDefinition(ItemIds.knife, s.ctx);
    ownItem(s.character, item.id, s.ctx);
    discoverItem(s.character, item, s.ctx);
    s.mgr.placeItem(item, 'test place');

    final placements = s.ctx.tome.inspect(s.character);
    expect(placements, hasLength(1));
    expect(placements.single.buildComponentRef.instanceEntityId, isNotNull);
  });

  test('two owned copies of one item place as two distinct instances', () {
    final s = _setup();
    final item = itemDefinition(ItemIds.knife, s.ctx);
    final first = ownItem(s.character, item.id, s.ctx);
    final second = ownItem(s.character, item.id, s.ctx);
    discoverItem(s.character, item, s.ctx);
    expect(first, isNot(second));

    s.mgr.placeItem(item, 'place first');
    final placedAfterFirst =
        s.ctx.tome.inspect(s.character).single.buildComponentRef.instanceEntityId;
    expect(placedAfterFirst, anyOf(first, second));

    // Placing again picks the OTHER still-unplaced copy, not the same one.
    s.mgr.placeItem(item, 'place second');
    final placedIds = s.ctx.tome
        .inspect(s.character)
        .map((p) => p.buildComponentRef.instanceEntityId)
        .toSet();
    expect(placedIds, {first, second});
  });
}
