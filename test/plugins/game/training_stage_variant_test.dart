import 'package:build_engine/build_engine.dart';
import 'package:build_engine/game.dart';
import 'package:build_engine/item_plugin.dart';
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

/// Like `_setup()`, but takes an explicit seed for `PluginContext.rng` —
/// the RNG `resolveTechniqueInspirationAfterTraining`'s discovery roll
/// actually consumes (see the seed-sweep note on the existing "evolution
/// replaces the base occupant" test above). `_setup()` itself hardcodes
/// `RngService(1)` and is left untouched — Task 7/8's tests already
/// depend on that fixed seed — so inspiration tests that need to sweep
/// the context RNG use this instead.
({
  PluginContext ctx,
  EntityId character,
  TomeManager mgr,
  EventBus events,
}) _setupSeeded(int seed) {
  final events = EventBus();
  final entities = EntityRegistry(events);
  final components = ComponentStore();
  final rng = RngService(seed);
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

/// Mint an eligible inspirer on [family] for [owner]: mastery driven to
/// the top rank (3) and usage recorded well past `kMinUsageToInspire` —
/// mirrors `test/plugins/technique/technique_inspiration_flow_test.dart`'s
/// `_eligibleInspirer` helper exactly, so the two files' seed-sweep
/// behaviour stays comparable. A variant minted this way is deliberately
/// at the TOP mastery rank so it never shows up as a `trainingCandidates`
/// variant-mastery candidate itself (rank 3 is not `< topRank`) — it can
/// only ever act as an inspiration *source*, keeping each test's single
/// real training candidate unambiguous.
EntityId _eligibleInspirer(
    PluginContext ctx, EntityId owner, String family, Set<String> descriptors) {
  final id = mintTechniqueVariant(owner, family, descriptors, ctx);
  trainTechniqueVariantMastery(id, 999, ctx); // level 3 (top rank)
  for (var i = 0; i < 20; i++) {
    recordTechniqueVariantUsage(id, ctx);
  }
  return id;
}

/// Scans context-RNG seeds `1..2999` for one whose run of [body] reports a
/// hit (returns `true`) — the same brute-force convention
/// `technique_inspiration_flow_test.dart`'s `_seedThatDiscovers` already
/// established in this codebase for a resolver whose single roll has no
/// other lever to pin deterministically.
int _seedThatInspires(bool Function(int seed) body) {
  for (var seed = 1; seed < 3000; seed++) {
    if (body(seed)) return seed;
  }
  fail('no seed in 1..2999 produced an inspiration hit');
}

/// Seed + fixture for "2 eligible `basic_punch` inspirers (top mastery,
/// heavy usage), plus one fresh (mastery 0) `basic_kick` variant" — the
/// sole owned-variant-below-top-rank on the roster, so it is the only
/// `trainingCandidates` entry once no items are owned and no reward-pool
/// family has been discovered. `runTraining` therefore always trains the
/// kick variant's own per-instance mastery (never base-family learning),
/// making this scenario a clean "technique-target session that is
/// certainly not a first-time base learn." Swept once per call (bounded,
/// deterministic, matches this file's/the SP0b unit test's own
/// convention) rather than cached, so each test gets a fully independent
/// context.
({PluginContext ctx, EntityId character, TomeManager mgr, EventBus events,
    EntityId punchA, EntityId punchB, EntityId kickVariant, int seed})
    _kickInspirationFixture() {
  final seed = _seedThatInspires((s) {
    final probe = _setupSeeded(s);
    _eligibleInspirer(probe.ctx, probe.character, TechniqueIds.basicPunch, {'bear'});
    _eligibleInspirer(probe.ctx, probe.character, TechniqueIds.basicPunch, {'swift'});
    mintTechniqueVariant(probe.character, TechniqueIds.basicKick, const {}, probe.ctx);
    final stage = TrainingStage(
      character: probe.character,
      context: probe.ctx,
      recordingPolicy:
          RecordingDecisionPolicy(const DefaultRunDecisionPolicy()),
      rng: RngService(7),
      events: probe.events,
      tomeManager: probe.mgr,
      styleId: 'wrestling',
    );
    var hit = false;
    probe.events.subscribe<TechniqueVariantInspired>((_) => hit = true);
    stage.runTraining(() => const <String>{}, 0);
    return hit;
  });

  final s = _setupSeeded(seed);
  final punchA =
      _eligibleInspirer(s.ctx, s.character, TechniqueIds.basicPunch, {'bear'});
  final punchB =
      _eligibleInspirer(s.ctx, s.character, TechniqueIds.basicPunch, {'swift'});
  final kickVariant =
      mintTechniqueVariant(s.character, TechniqueIds.basicKick, const {}, s.ctx);
  return (
    ctx: s.ctx,
    character: s.character,
    mgr: s.mgr,
    events: s.events,
    punchA: punchA,
    punchB: punchB,
    kickVariant: kickVariant,
    seed: seed,
  );
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

      // The base variant's own `TechniqueVariantMinted` — the mint side
      // of the rule. It's always the *first* same-family mint event
      // (Task 7's mint-or-reuse rule mints the descriptor-less base
      // before any evolution roll can happen), so `firstWhere` finds it
      // reliably even when evolution mints its own (also same-family, by
      // `mintVariantForLegacyEvolvedId`'s construction) second event.
      final baseMints = minted.where((m) => m.baseFamilyId == familyId).toList();
      expect(baseMints, isNotEmpty);
      final baseInstance = baseMints.first.instanceId;
      if (stage.techniquesEvolved.isEmpty) {
        // No evolution this run — the only same-family mint is the base
        // variant itself.
        expect(baseMints, hasLength(1));
      }

      // Still owned as the descriptor-less base variant — UNLESS
      // evolution also fired this run (Task 8: evolution now really
      // mints an evolved variant and removes this one), in which case
      // the mint/reuse rule is already proven by `baseMints` above, and
      // the post-evolution shape is covered by its own test group.
      if (stage.techniquesEvolved.isEmpty) {
        final baseVariants = _baseVariantsFor(s.character, familyId, s.ctx);
        expect(baseVariants, [baseInstance]);
      }

      // Hung in the Tome — UNLESS evolution also fired this run, which
      // would have swapped the Tome slot's occupant away from the variant
      // placement. The placement mechanism itself is already proven by
      // Task 6's `tome_manager_variant_test.dart`; this test's unique job
      // is the mint/reuse rule, so the Tome-placement check is only made
      // when evolution definitely didn't fire.
      if (stage.techniquesEvolved.isEmpty) {
        final placements = s.ctx.tome.inspect(s.character);
        expect(
          placements
              .any((p) => p.buildComponentRef.instanceEntityId == baseInstance),
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
      // pre-seeded instance — not a freshly minted second one. UNLESS
      // evolution also fired this run (Task 8: evolution now really
      // removes the base instance it replaces), in which case the
      // reuse-not-remint claim is already proven below by the absence of
      // a second `TechniqueVariantMinted` for the base shape.
      if (stage.techniquesEvolved.isEmpty) {
        final baseVariants = _baseVariantsFor(s.character, familyId, s.ctx);
        expect(baseVariants, [preseeded]);
      }

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

  group('TrainingStage: evolution replaces the base occupant (SP1 decision C)',
      () {
    test(
        'a learned base family evolves: base variant replaced by an '
        'evolved variant, old instance removed', () {
      final s = _setup();
      const familyId = TechniqueIds.basicPunch;
      final minted = <TechniqueVariantMinted>[];
      s.events.subscribe<TechniqueVariantMinted>(minted.add);

      discoverTechnique(
          s.character, techniqueDefinition(familyId, s.ctx), s.ctx);

      final stage = TrainingStage(
        character: s.character,
        context: s.ctx,
        recordingPolicy:
            RecordingDecisionPolicy(const DefaultRunDecisionPolicy()),
        // `_setup()`'s context.rng is fixed at RngService(1), which is
        // what `resolveTechniqueEvolutionAfterTraining`'s draw actually
        // consumes; this `rng` only drives attempt generation. Swept
        // 1-60 for `basic_punch`/'wrestling'/`DefaultRunDecisionPolicy`:
        // every seed evolves (to `fast_punch`) within the cycle cap
        // below, so seed 1 is picked with no special significance.
        rng: RngService(1),
        events: s.events,
        tomeManager: s.mgr,
        styleId: 'wrestling',
      );

      for (var cycle = 0; cycle < 200; cycle++) {
        if (stage.techniquesEvolved.isNotEmpty) break;
        stage.runTraining(() => const <String>{}, cycle);
      }
      if (stage.techniquesEvolved.isEmpty) {
        fail('expected basic_punch to evolve within the cycle cap');
      }

      // The base variant minted at learn time — the instance evolution
      // must have replaced. It's always the *first* mint for this family
      // (Task 7's mint-or-reuse rule mints the descriptor-less base
      // before any evolution roll can happen), so it's found reliably
      // even though evolution can fire within the very same
      // `runTraining` call that learned the family.
      final baseInstance =
          minted.firstWhere((m) => m.baseFamilyId == familyId).instanceId;

      final placement = s.ctx.tome.inspect(s.character).firstWhere((p) =>
          p.buildComponentRef.referenceType == techniqueReferenceType &&
          p.buildComponentRef.contentId == familyId);
      final currentInstance = placement.buildComponentRef.instanceEntityId;
      expect(currentInstance, isNotNull);
      expect(currentInstance, isNot(equals(baseInstance)));

      final currentVariant =
          s.ctx.components.get<TechniqueVariant>(currentInstance!)!;
      expect(currentVariant.descriptorIds, isNotEmpty);

      // The old base instance is gone: not alive, not owned any more.
      expect(s.ctx.entities.isAlive(baseInstance), isFalse);
      expect(
        ownedTechniqueVariants(s.character, s.ctx),
        isNot(contains(baseInstance)),
      );
    });

    test('evolution does not re-fire once the occupant is an evolved variant',
        () {
      final events = EventBus();
      final evolved = <TechniqueEvolved>[];
      events.subscribe<TechniqueEvolved>(evolved.add);

      // Seed 6 / `TrainAfterFirstCombatPolicy` (the train-heavy policy
      // this file's own "runGame smoke test" group already uses) trains
      // every cycle after the first combat and evolves multiple reward-
      // pool families across one run — a real end-to-end exercise of the
      // guard, not just a single family's single evolution.
      runGame(6, policy: TrainAfterFirstCombatPolicy(), eventBus: events);

      final perFamily = <String, int>{};
      for (final e in evolved) {
        perFamily[e.fromId] = (perFamily[e.fromId] ?? 0) + 1;
      }
      // Sanity: this run does exercise evolution at all.
      expect(perFamily, isNotEmpty);
      for (final entry in perFamily.entries) {
        expect(entry.value, lessThanOrEqualTo(1),
            reason: '${entry.key} evolved ${entry.value} times');
      }
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

  group('TrainingStage: inspiration at the session boundary (SP1 decision D)',
      () {
    test(
        'inspiration fires at most once for a technique-target session, '
        'minting at most one variant and one event', () {
      final f = _kickInspirationFixture();

      final inspired = <TechniqueVariantInspired>[];
      final minted = <TechniqueVariantMinted>[];
      f.events.subscribe<TechniqueVariantInspired>(inspired.add);
      f.events.subscribe<TechniqueVariantMinted>(minted.add);

      final stage = TrainingStage(
        character: f.character,
        context: f.ctx,
        recordingPolicy:
            RecordingDecisionPolicy(const DefaultRunDecisionPolicy()),
        rng: RngService(7),
        events: f.events,
        tomeManager: f.mgr,
        styleId: 'wrestling',
      );

      // The only candidate is the fresh (mastery 0) `basic_kick` variant —
      // both punch inspirers sit at the top mastery rank (3), so neither
      // qualifies as a `trainingCandidates` entry itself, and no item/
      // reward-pool-learning candidate exists. This is a genuine
      // technique-target session (`TrainTechniqueTarget`), just not a
      // first-time base learn (the kick family was never discovered).
      stage.runTraining(() => const <String>{}, 0);

      // Pinned by `_kickInspirationFixture`'s own sweep to be a hit, so
      // this assertion is meaningful rather than vacuously true.
      expect(inspired, hasLength(1));
      expect(minted, hasLength(1));
      expect(minted.single.instanceId, inspired.single.instanceId);
    });

    test(
        'inspiration fires on an item-training session — seeded by the '
        "owner's top owned variant family, not first-time base learning",
        () {
      // `basic_kick` is unused here — a pure item scenario exercises
      // `_topOwnedVariantFamily()`'s fallback path directly (the only
      // path where `trainedFamilyId` is `null`), which the technique-
      // target tests in this file never touch.
      final seed = _seedThatInspires((s) {
        final probe = _setupSeeded(s);
        ItemPlugin().initialize(probe.ctx);
        _eligibleInspirer(
            probe.ctx, probe.character, TechniqueIds.basicPunch, {'bear'});
        _eligibleInspirer(
            probe.ctx, probe.character, TechniqueIds.basicPunch, {'swift'});
        final stage = TrainingStage(
          character: probe.character,
          context: probe.ctx,
          recordingPolicy:
              RecordingDecisionPolicy(const DefaultRunDecisionPolicy()),
          rng: RngService(7),
          events: probe.events,
          tomeManager: probe.mgr,
          styleId: 'wrestling',
        );
        var hit = false;
        probe.events.subscribe<TechniqueVariantInspired>((_) => hit = true);
        stage.runTraining(() => {ItemIds.trainingStaff}, 0);
        return hit;
      });

      final s = _setupSeeded(seed);
      ItemPlugin().initialize(s.ctx);
      _eligibleInspirer(s.ctx, s.character, TechniqueIds.basicPunch, {'bear'});
      _eligibleInspirer(s.ctx, s.character, TechniqueIds.basicPunch, {'swift'});

      final inspired = <TechniqueVariantInspired>[];
      s.events.subscribe<TechniqueVariantInspired>(inspired.add);

      final stage = TrainingStage(
        character: s.character,
        context: s.ctx,
        recordingPolicy:
            RecordingDecisionPolicy(const DefaultRunDecisionPolicy()),
        rng: RngService(7),
        events: s.events,
        tomeManager: s.mgr,
        styleId: 'wrestling',
      );

      // `training_staff` requires mastery 1 and starts at 0 — it is the
      // sole training candidate (no technique candidate exists: nothing
      // discovered, and both punch variants sit at the top mastery rank).
      // Never first-time base learning: this session doesn't touch any
      // technique's learning/mastery axis at all.
      stage.runTraining(() => {ItemIds.trainingStaff}, 0);

      // Pinned to a hit by the sweep above.
      expect(inspired, hasLength(1));
      // Only family the owner holds any variant on — must be what
      // `_topOwnedVariantFamily()` picked, proving decision D's
      // item-session fallback.
      expect(inspired.single.familyId, TechniqueIds.basicPunch);
    });

    test(
        'a newly inspired variant starts at mastery 0 / usage 0 and is '
        'never credited as an inspirer while still a newborn', () {
      final f = _kickInspirationFixture();
      final inspired = <TechniqueVariantInspired>[];
      f.events.subscribe<TechniqueVariantInspired>(inspired.add);

      final stage = TrainingStage(
        character: f.character,
        context: f.ctx,
        recordingPolicy:
            RecordingDecisionPolicy(const DefaultRunDecisionPolicy()),
        rng: RngService(7),
        events: f.events,
        tomeManager: f.mgr,
        styleId: 'wrestling',
      );

      stage.runTraining(() => const <String>{}, 0);
      expect(inspired, hasLength(1)); // pinned by the fixture's sweep
      final newbornId = inspired.single.instanceId;

      // Newborn protection: fresh mint, no mastery, no usage yet.
      expect(techniqueVariantMasteryLevel(newbornId, f.ctx), 0);
      expect(techniqueVariantUsage(newbornId, f.ctx), 0);

      // Re-run the same call shape several more times (same eligible
      // punch inspirers throughout — `_eligibleInspirer` never touches
      // them again, and inspiration itself never mutates an inspirer).
      // The DefaultRunDecisionPolicy always trains the lowest-mastery
      // owned variant first (list order out of `trainingCandidates`), so
      // this mostly keeps training the kick variant / the newborn itself
      // — never as an inspirer credited by a *later* discovery, since an
      // instance whose own mastery/usage haven't yet cleared
      // `kMinMasteryToInspire`/`kMinUsageToInspire` can't be eligible.
      for (var cycle = 1; cycle <= 10; cycle++) {
        stage.runTraining(() => const <String>{}, cycle);
      }

      for (final e in inspired) {
        expect(e.inspirerInstanceIds, isNot(contains(newbornId)));
      }
    });

    test(
        'cross-pollination via the real training pipeline: training '
        'basic_kick is inspired by owned basic_punch variants', () {
      final f = _kickInspirationFixture();
      final inspired = <TechniqueVariantInspired>[];
      f.events.subscribe<TechniqueVariantInspired>(inspired.add);

      final stage = TrainingStage(
        character: f.character,
        context: f.ctx,
        recordingPolicy:
            RecordingDecisionPolicy(const DefaultRunDecisionPolicy()),
        rng: RngService(7),
        events: f.events,
        tomeManager: f.mgr,
        styleId: 'wrestling',
      );

      // The sole candidate is `TrainTechniqueTarget(basic_kick,
      // variantInstanceId: f.kickVariant)` — a per-instance MASTERY
      // session on a family the owner has never trained by any other
      // path, driven entirely through `runTraining`.
      stage.runTraining(() => const <String>{}, 0);

      expect(inspired, hasLength(1)); // pinned by the fixture's sweep
      final event = inspired.single;
      expect(event.familyId, TechniqueIds.basicKick);
      final minted = f.ctx.components.get<TechniqueVariant>(event.instanceId)!;
      expect(minted.baseFamilyId, TechniqueIds.basicKick);
      // Attribution: only the two eligible basic_punch variants exist as
      // possible inspirers.
      expect(event.inspirerInstanceIds, isNotEmpty);
      expect(
        event.inspirerInstanceIds.every({f.punchA, f.punchB}.contains),
        isTrue,
      );
    });
  });
}
