import 'package:build_engine/build_engine.dart';
import 'package:build_engine/game.dart';
import 'package:build_engine/technique_plugin.dart';
import 'package:test/test.dart';

// Minimal harness: a real PluginContext with Technique + a tome, and a
// RecordingDecisionPolicy wrapping DefaultRunDecisionPolicy — the same
// hand-built-context pattern as tome_manager_variant_test.dart (Task 6) /
// training_stage_variant_test.dart (Tasks 7-9).
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
  TechniquePlugin().initialize(ctx);
  final character = ctx.characters.create();
  ctx.tome.defineTome(TomeDefinition.namedSlots(
      id: 't', slotIds: ['slot_1', 'slot_2', 'slot_3']));
  ctx.tome.createTome(character, 't');
  final mgr = TomeManager(
    character: character,
    context: ctx,
    recordingPolicy: RecordingDecisionPolicy(const DefaultRunDecisionPolicy()),
    events: events,
    unlockedSlots: [SlotId('slot_1'), SlotId('slot_2'), SlotId('slot_3')],
  );
  return (ctx: ctx, character: character, mgr: mgr);
}

void main() {
  test(
      'manageTome equips a loose owned TechniqueVariant by instance id and '
      'never conflates it with an already-placed variant of the same family',
      () {
    final s = _setup();

    // Two variants of the SAME base family (basic_punch, via the 'fist'
    // tag both heavy_punch and fast_punch carry), with different
    // descriptors. One is already hung; the other is loose/unplaced.
    final hungId =
        mintVariantForLegacyEvolvedId(s.character, TechniqueIds.heavyPunch, s.ctx);
    s.mgr.placeTechniqueVariant(hungId, 'setup: hang base variant');
    final hungSlot = s.mgr.slotOfTechniqueVariant(hungId)!;

    final looseId =
        mintVariantForLegacyEvolvedId(s.character, TechniqueIds.fastPunch, s.ctx);

    // Sanity: both variants share a contentId (their base family) but are
    // distinct instances.
    expect(
        s.ctx.components.get<TechniqueVariant>(hungId)!.baseFamilyId,
        s.ctx.components.get<TechniqueVariant>(looseId)!.baseFamilyId);
    expect(hungId, isNot(looseId));

    // hasEmptySlot: 3 unlocked slots, 1 placement so far.
    expect(s.ctx.tome.inspect(s.character), hasLength(1));

    // DefaultRunDecisionPolicy always takes the first candidate, and the
    // equip:techniqueVariant: option for the loose variant sorts before
    // 'done' in manageTome's candidate list, so this drives an auto-equip.
    s.mgr.manageTome(
      ownedItemIds: () => {},
      knownTechniqueIds: () => knownTechniqueIds(s.character, s.ctx),
    );

    final placements = s.ctx.tome.inspect(s.character);
    expect(placements, hasLength(2));

    final placedInstanceIds = [
      for (final p in placements) p.buildComponentRef.instanceEntityId,
    ];
    // Both instances are present, distinct, and in different slots — even
    // though both placements share the same contentId (the base family).
    expect(placedInstanceIds.toSet(), {hungId, looseId});
    expect(placedInstanceIds.toSet().length, placedInstanceIds.length);

    final loosePlacement =
        placements.singleWhere((p) => p.buildComponentRef.instanceEntityId == looseId);
    expect(loosePlacement.slot, isNot(hungSlot));

    final contentIds = {
      for (final p in placements) p.buildComponentRef.contentId,
    };
    expect(contentIds, {TechniqueIds.basicPunch});
  });
}
