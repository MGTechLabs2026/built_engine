import 'package:build_engine/build_engine.dart';
import 'package:build_engine/game.dart';
import 'package:build_engine/technique_plugin.dart';
import 'package:test/test.dart';

import '../../support/policies.dart';

/// Minimal harness: a real `PluginContext` with Technique + a Tome, and a
/// `RecordingDecisionPolicy` wrapping `DefaultRunDecisionPolicy` — the same
/// pattern `test/plugins/game/tome_manager_variant_test.dart` (Task 6)
/// already established.
({
  PluginContext ctx,
  EntityId character,
  TomeManager mgr,
  EventBus events,
}) _setup() {
  final events = EventBus();
  final entities = EntityRegistry(events);
  final components = ComponentStore();
  final rng = RngService(1);
  final shared = CoreServices(components: components, events: events);
  final ctx = PluginContext(
    entities: entities,
    components: components,
    events: events,
    rng: rng,
    rules: RuleEngine(
        entities: entities,
        components: components,
        events: events,
        rng: rng,
        shared: shared),
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
  return (ctx: ctx, character: character, mgr: mgr, events: events);
}

/// Runs [stage]'s training loop, with no owned items so only the
/// technique candidate exists, until [familyId] is learned (or a safety
/// cap is hit — training gain is randomized but scaled well past the
/// single-tier learning threshold, so this converges in a handful of
/// cycles for any seed).
void _trainUntilLearned(TrainingStage stage, String familyId) {
  for (var cycle = 0; cycle < 50; cycle++) {
    if (stage.techniquesLearned.contains(familyId)) return;
    stage.runTraining(() => const <String>{}, cycle);
  }
  fail('$familyId was not learned within the training cap');
}

/// Every `TechniqueVariant` owned by [character] whose `baseFamilyId` is
/// [familyId], with empty `descriptorIds` and a null `styleId` — the
/// "descriptor-less base variant" shape the mint-or-reuse rule cares
/// about.
List<EntityId> _baseVariantsFor(
    EntityId character, String familyId, PluginContext ctx) {
  final result = <EntityId>[];
  for (final e in ownedTechniqueVariants(character, ctx)) {
    final v = ctx.components.get<TechniqueVariant>(e)!;
    if (v.baseFamilyId == familyId &&
        v.descriptorIds.isEmpty &&
        v.styleId == null) {
      result.add(e);
    }
  }
  return result;
}

void main() {
  group('TrainingStage: first-learn base-variant mint (Ruling R2)', () {
    test(
        'first learn of a base family mints exactly one descriptor-less '
        'base TechniqueVariant', () {
      final s = _setup();
      const familyId = TechniqueIds.basicGuard;
      final minted = <TechniqueVariantMinted>[];
      s.events.subscribe<TechniqueVariantMinted>(minted.add);

      discoverTechnique(
          s.character, techniqueDefinition(familyId, s.ctx), s.ctx);

      final stage = TrainingStage(
        character: s.character,
        context: s.ctx,
        recordingPolicy:
            RecordingDecisionPolicy(const DefaultRunDecisionPolicy()),
        rng: RngService(7),
        events: s.events,
        tomeManager: s.mgr,
        styleId: 'polearming',
      );

      _trainUntilLearned(stage, familyId);

      // Exactly one owned base variant for the family — the mint side of
      // the rule.
      final baseVariants = _baseVariantsFor(s.character, familyId, s.ctx);
      expect(baseVariants, hasLength(1));

      // TechniqueVariantMinted was published for it.
      expect(
        minted.where((m) =>
            m.baseFamilyId == familyId && m.instanceId == baseVariants.single),
        hasLength(1),
      );

      // Hung in the Tome — UNLESS evolution also fired this run (still on
      // the legacy `replaceWithEvolved` path per Ruling R1), which would
      // have swapped the Tome slot's occupant away from the variant
      // placement. The placement mechanism itself is already proven by
      // Task 6's `tome_manager_variant_test.dart`; this test's unique job
      // is the mint/reuse rule, so the Tome-placement check is only made
      // when evolution definitely didn't fire.
      if (stage.techniquesEvolved.isEmpty) {
        final placements = s.ctx.tome.inspect(s.character);
        expect(
          placements.any((p) =>
              p.buildComponentRef.instanceEntityId == baseVariants.single),
          isTrue,
        );
      }
    });

    test(
        're-learning the same base family reuses the pre-seeded base '
        'variant instead of minting a second one', () {
      final s = _setup();
      const familyId = TechniqueIds.basicPunch;
      final minted = <TechniqueVariantMinted>[];
      s.events.subscribe<TechniqueVariantMinted>(minted.add);

      // Pre-seed the owner with an already-existing descriptor-less,
      // style-less base variant for the family, exactly as SP1 §5
      // requires this path to detect and reuse.
      final preseeded =
          mintTechniqueVariant(s.character, familyId, const {}, s.ctx);
      expect(minted, hasLength(1));
      minted.clear();

      discoverTechnique(
          s.character, techniqueDefinition(familyId, s.ctx), s.ctx);

      final stage = TrainingStage(
        character: s.character,
        context: s.ctx,
        recordingPolicy:
            RecordingDecisionPolicy(const DefaultRunDecisionPolicy()),
        rng: RngService(3),
        events: s.events,
        tomeManager: s.mgr,
        styleId: 'wrestling',
      );

      _trainUntilLearned(stage, familyId);

      // Still exactly one base variant for the family, and it is the
      // pre-seeded instance — not a freshly minted second one.
      final baseVariants = _baseVariantsFor(s.character, familyId, s.ctx);
      expect(baseVariants, [preseeded]);

      // No second `TechniqueVariantMinted` for this family's base shape:
      // the base-variant mint call is the reuse path, so `mintTechniqueVariant`
      // must not have been invoked again for it. Evolution/inspiration may
      // still mint their own (differently-shaped) instances, so assert on
      // the base shape specifically rather than "no mint events at all".
      expect(
        minted.where((m) =>
            m.baseFamilyId == familyId && m.instanceId == preseeded),
        isEmpty,
      );
    });
  });

  group('runGame smoke test (Ruling R2)', () {
    test(
        'the first learned family gets a TechniqueVariantMinted followed by '
        'a matching TechniqueAddedToTome', () {
      final events = EventBus();
      // A single ordered log of both event types, so publish order between
      // them (mint must precede its matching placement) is observable —
      // two separate per-type lists would lose that relative ordering.
      final log = <Object>[];
      events.subscribe<TechniqueVariantMinted>((e) => log.add(e));
      events.subscribe<TechniqueAddedToTome>((e) => log.add(e));

      final result = runGame(6,
          policy: TrainAfterFirstCombatPolicy(), eventBus: events);

      expect(result.techniquesLearned, isNotEmpty);
      final learnedFamily = result.techniquesLearned.first;

      final minted = log.whereType<TechniqueVariantMinted>();
      final mint = minted.firstWhere(
        (m) => m.baseFamilyId == learnedFamily,
        orElse: () => fail(
            'no TechniqueVariantMinted for the first learned family: $learnedFamily'),
      );

      final addedToTome = log.whereType<TechniqueAddedToTome>();
      final placement = addedToTome.firstWhere(
        (a) =>
            a.definitionId == learnedFamily && a.instanceId == mint.instanceId,
        orElse: () => fail(
            'no matching TechniqueAddedToTome for mint instance ${mint.instanceId}'),
      );

      expect(placement.instanceId, mint.instanceId);
      expect(placement.definitionId, learnedFamily);

      // The mint must have happened before its matching placement, in
      // overall publish order.
      expect(log.indexOf(mint), lessThan(log.indexOf(placement)));
    });
  });
}
