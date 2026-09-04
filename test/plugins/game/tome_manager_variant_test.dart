import 'package:build_engine/build_engine.dart';
import 'package:build_engine/game.dart';
import 'package:build_engine/technique_plugin.dart';
import 'package:test/test.dart';

import '../../support/policies.dart';

// Minimal harness: a real PluginContext with Technique + a tome, and a
// RecordingDecisionPolicy wrapping DefaultRunDecisionPolicy.
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
  test('placeTechniqueVariant hangs the instance and stores its id', () {
    final s = _setup();
    // A derived variant hangs without a learning gate.
    final id = mintVariantForLegacyEvolvedId(s.character, 'heavy_punch', s.ctx);
    s.mgr.placeTechniqueVariant(id, 'test place');

    final placements = s.ctx.tome.inspect(s.character);
    expect(placements, hasLength(1));
    expect(placements.single.buildComponentRef.referenceType,
        techniqueReferenceType);
    expect(placements.single.buildComponentRef.contentId, 'basic_punch');
    expect(placements.single.buildComponentRef.instanceEntityId, id);
    expect(s.mgr.slotOfTechniqueVariant(id), placements.single.slot);
  });

  test('replaceWithTechniqueVariant swaps the occupant of a specific slot', () {
    final s = _setup();
    final base = mintVariantForLegacyEvolvedId(s.character, 'heavy_punch', s.ctx);
    s.mgr.placeTechniqueVariant(base, 'place base');
    final slot = s.mgr.slotOfTechniqueVariant(base)!;
    final evolved =
        mintVariantForLegacyEvolvedId(s.character, 'hammer_blow', s.ctx);

    s.mgr.replaceWithTechniqueVariant(slot, evolved, 'evolve');

    final placements = s.ctx.tome.inspect(s.character);
    expect(placements, hasLength(1));
    expect(placements.single.slot, slot);
    expect(placements.single.buildComponentRef.instanceEntityId, evolved);
  });
}
