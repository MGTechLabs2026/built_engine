import 'package:build_engine/auto_combat_plugin.dart';
import 'package:build_engine/build_engine.dart';
import 'package:build_engine/combat_plugin.dart';
import 'package:build_engine/martial_arts_plugin.dart';
import 'package:build_engine/physique_plugin.dart';
import 'package:test/test.dart';

// ============================================================================
// CONTENT — the smallest possible set for this vertical slice. Every
// reference below is an opaque `BuildComponentRef {referenceType, contentId}`
// — Core/Combat/Tome never interpret any of these strings. The one thing
// genuinely new here is this file's own "damage table": the game-layer
// bridge from a content id to a concrete `AttackAction`, which is exactly
// the translation AutoCombat's design deliberately leaves to content.
//
// No new engine abstraction was needed anywhere in this file — every step
// of the RUN maps onto an existing public method on an existing system.
// ============================================================================

/// Physiques: Sturdy/Power/Burst/Endurance — the real `PhysiquePlugin`/
/// `PhysiqueTypes` already implements exactly this set.
///
/// Martial styles: Boxing/Shaolin/Tai Chi — the real `MartialArtsPlugin`/
/// `MartialStyles`/`learnStyle` (this character learns Boxing, granting
/// the real `'western'` tradition tag `MartialTraditions.western` used
/// below to gate an Evolution candidate).
///
/// Items (Gloves/Knife/Sword) and techniques (Basic Punch/Slash/Guard) are
/// this slice's own tiny content set — not MartialArts' own (different)
/// item/technique roster, since this proof needs its own minimal names.
const _damageTable = <String, ({num damage, String stat})>{
  'basic_punch': (damage: 15, stat: 'punch'),
  'basic_slash': (damage: 20, stat: 'slash'),
  'basic_guard': (damage: 8, stat: 'guard'),
  // Evolution candidates for whichever technique the reward roll grants —
  // covering both branches of both possible rewarded techniques, so no
  // runtime branching is needed to look up a damage value.
  'basic_slash:refined': (damage: 26, stat: 'slash'),
  'basic_slash:forceful': (damage: 32, stat: 'slash'),
  'basic_guard:refined': (damage: 14, stat: 'guard'),
  'basic_guard:forceful': (damage: 18, stat: 'guard'),
};

/// Enemies: Training Dummy (fought first) and Bandit (fought second) are
/// both actually spawned this run; Martial Adept is content-complete data
/// only — not spawned, since the 14-step RUN calls for exactly one second
/// battle, not a third.
const _trainingDummy = (health: 30, damage: 2, stat: 'dummy_attack', initiative: 1);
const _bandit = (health: 70, damage: 14, stat: 'bandit_attack', initiative: 8);
// ignore: unused_element
const _martialAdept = (health: 100, damage: 20, stat: 'adept_attack', initiative: 12);

/// This run's own tiny "performance exercise": averages every measurement
/// key across every submitted attempt — a throwaway `TrainingExercise`
/// implementation, exactly the shape the Training Framework's own tests
/// use, standing in for a real game's actual input-timing/precision
/// exercise (not built here — out of scope, per the Training Framework's
/// own design).
class _PerformanceExercise implements TrainingExercise {
  const _PerformanceExercise();

  @override
  TrainingProfile evaluate(List<TrainingAttempt> attempts) {
    if (attempts.isEmpty) return const TrainingProfile({});
    final sums = <String, double>{};
    for (final attempt in attempts) {
      for (final entry in attempt.measurements.entries) {
        sums[entry.key] = (sums[entry.key] ?? 0) + entry.value;
      }
    }
    return TrainingProfile({
      for (final entry in sums.entries) entry.key: entry.value / attempts.length,
    });
  }
}

/// Bootstraps one fresh, fully-wired `PluginContext` from [seed] — the
/// same shared-instance pattern `ARCHITECTURE.md`'s bootstrap example
/// documents (one `RngService`, threaded through everything).
PluginContext _newRun(int seed) {
  final events = EventBus();
  final entities = EntityRegistry(events);
  final components = ComponentStore();
  final rng = RngService(seed);
  return PluginContext(
    entities: entities,
    components: components,
    events: events,
    rng: rng,
    rules: RuleEngine(entities: entities, components: components, events: events, rng: rng),
    queries: QueryEngine(QueryScope(components: components)),
    modifiers: ModifierCollection(),
    content: ContentRegistry(),
  );
}

EntityId _spawnEnemy(
  PluginContext context, {
  required num health,
  required num initiative,
}) {
  final enemy = context.entities.create();
  context.components.add(enemy, CombatantComponent(team: 'enemy', initiative: initiative));
  context.components.add(enemy, HealthComponent(current: health, max: health));
  return enemy;
}

/// The game-layer bridge from an opaque `BuildComponentRef` to a concrete
/// `CombatAction` — the translation `ActiveBuild` deliberately never does
/// itself (Combat must never inspect the Tome, and the Tome must never
/// contain combat logic). Only `'technique'`-typed refs become attacks in
/// this slice; `'item'`-typed refs (Gloves, this run) still occupy a Tome
/// slot and still appear in the resolved `ActiveBuild`, they just aren't
/// wielded as a separate attack of their own here.
CombatAction? _actionFor(BuildComponentRef ref, EntityId actor, List<EntityId> targets) {
  if (ref.referenceType != 'technique') return null;
  final stats = _damageTable[ref.contentId]!;
  return AttackAction(actor: actor, targets: targets, baseDamage: stats.damage, damageStat: stats.stat);
}

/// Key outcomes worth comparing across two identically-seeded runs, on
/// top of the milestone log itself — a run is only truly "reproducible"
/// if these values match too, not just the sequence of steps taken.
typedef _RunOutcome = ({
  List<String> log,
  String physiqueId,
  String rewardedContentId,
  String evolvedContentId,
  bool firstBattleWon,
  bool secondBattleWon,
});

/// Executes the entire 14-step RUN from the spec, headlessly, and returns
/// the milestone log plus the key outcomes a second identically-seeded run
/// must reproduce exactly.
_RunOutcome _runVerticalSlice(int seed) {
  final log = <String>[];
  void milestone(String name) => log.add(name);

  // ---- 1. Create new run --------------------------------------------
  final context = _newRun(seed);
  final combatPlugin = CombatPlugin()..initialize(context);
  // MartialArtsPlugin.dependencies => ['combat'] — Combat must already be
  // initialized first, the same dependency order `PluginManager` enforces.
  MartialArtsPlugin().initialize(context);
  PhysiquePlugin().initialize(context);
  milestone('newRun');

  // ---- 2. Create character -------------------------------------------
  final character = context.characters.create();
  context.components.add(character, const CombatantComponent(team: 'player', initiative: 10));
  context.components.add(character, const HealthComponent(current: 100, max: 100));
  milestone('characterCreated');

  // ---- 3. Randomly assign Physique ------------------------------------
  final physiqueId = initializePhysique(character, context);
  milestone('physiqueAssigned');

  // ---- 4. Give starting content ----------------------------------------
  // Real MartialArts style — grants `martial`/`style:boxing`/`western`.
  learnStyle(character, MartialStyles.boxing, context);
  // Starting kit must be at least discovered before it can occupy a Tome
  // slot — `unlock` auto-promotes through `discovered` in one call.
  context.discovery.unlock(character, 'item:gloves');
  context.discovery.unlock(character, 'technique:basic_punch');
  milestone('startingContentGiven');

  // ---- 5. Build initial Tome -------------------------------------------
  context.tome.defineTome(
    TomeDefinition.namedSlots(id: 'basic_tome', slotIds: ['weapon', 'technique']),
  );
  context.tome.createTome(character, 'basic_tome');
  context.tome.insert(
    character,
    const SlotId('weapon'),
    const BuildComponentRef(referenceType: 'item', contentId: 'gloves'),
  );
  context.tome.insert(
    character,
    const SlotId('technique'),
    const BuildComponentRef(referenceType: 'technique', contentId: 'basic_punch'),
  );
  milestone('tomeBuilt');

  // ---- 6. Resolve ActiveBuild -------------------------------------------
  var activeBuild = context.tome.resolve(character);
  milestone('activeBuildResolved');

  // ---- 7 & 8. Start auto combat, win/lose (vs Training Dummy) -----------
  final dummy = _spawnEnemy(
    context,
    health: _trainingDummy.health,
    initiative: _trainingDummy.initiative,
  );
  var battle = combatPlugin.system.startBattle([character, dummy]);
  var availableActions = [
    for (final ref in activeBuild.components)
      if (_actionFor(ref, character, [dummy]) case final action?) action,
    AttackAction(
      actor: dummy,
      targets: [character],
      baseDamage: _trainingDummy.damage,
      damageStat: _trainingDummy.stat,
    ),
  ];
  var controller = AutoCombatController(
    context: context,
    combatSystem: combatPlugin.system,
    battle: battle,
    availableActions: availableActions,
  );
  milestone('combatStarted');
  controller.runUntilBattleEnds();
  final firstBattleWon =
      context.components.get<CombatantComponent>(character) != null &&
          context.components.get<HealthComponent>(character)!.current > 0 &&
          !controller.isActive;
  milestone('combatResolved');

  // ---- 9. Generate reward -----------------------------------------------
  final rewardResult = const RewardResolver().resolve(
    rng: context.rng,
    definition: const RewardDefinition(
      id: 'training_dummy_loot',
      candidates: [
        RewardCandidate(
          ref: BuildComponentRef(referenceType: 'technique', contentId: 'basic_slash'),
          weight: 2,
        ),
        RewardCandidate(
          ref: BuildComponentRef(referenceType: 'technique', contentId: 'basic_guard'),
          weight: 1,
        ),
      ],
    ),
  );
  final rewardedRef = rewardResult.rewards.single.ref;
  milestone('rewardGranted');

  // ---- 10. Discover a new item or technique ------------------------------
  context.discovery.discover(character, rewardedRef.contentId);
  milestone('itemDiscovered');

  // ---- 11. Train it -------------------------------------------------------
  final session = TrainingSession(
    trainee: character,
    subject: rewardedRef.contentId,
    exercise: const _PerformanceExercise(),
  );
  session.submitAttempt(const TrainingAttempt({'precision': 0.9, 'power': 0.4}));
  session.submitAttempt(const TrainingAttempt({'precision': 0.8, 'power': 0.5}));
  final trainingResult = session.complete();
  milestone('itemTrained');

  // ---- 12. Apply mastery/learning result -----------------------------------
  context.mastery.define(
    MasteryDefinition(subject: rewardedRef.contentId, thresholds: const [10, 25]),
  );
  context.mastery.increase(character, rewardedRef.contentId, 15);
  milestone('masteryIncreased');

  final evolutionResult = const EvolutionResolver().resolve(
    context: context.ruleContextFor(character),
    current: EvolutionDefinition(
      id: rewardedRef.contentId,
      tier: EvolutionTiers.basic,
      candidates: [
        // Only eligible for a character trained in a western tradition —
        // proving a tag `learnStyle` (real MartialArts) granted gates a
        // real Evolution `Condition`.
        EvolutionCandidate(
          targetId: '${rewardedRef.contentId}:refined',
          tags: const {'precision'},
          conditions: const [HasTag(MartialTraditions.western)],
        ),
        EvolutionCandidate(
          targetId: '${rewardedRef.contentId}:forceful',
          tags: const {'power'},
        ),
      ],
    ),
    profile: trainingResult.profile,
  );
  final evolvedContentId = evolutionResult.chosenCandidate!.targetId;
  context.discovery.unlock(character, evolvedContentId);
  // A genuine, minimal use of the Modifier Engine beyond Evolution's own
  // internal use of it: mastery reaching level 1 grants a small permanent
  // damage bonus on whichever stat the evolved technique uses.
  context.modifiers.add(Modifier(
    source: ModifierSource('mastery:${rewardedRef.contentId}:${character.value}'),
    target: character,
    stat: _damageTable[evolvedContentId]!.stat,
    operation: ModifierOperation.add,
    value: 5,
  ));
  milestone('evolutionResolved');

  // ---- 13. Modify Tome -----------------------------------------------------
  context.tome.replace(
    character,
    const SlotId('technique'),
    BuildComponentRef(referenceType: 'technique', contentId: evolvedContentId),
  );
  milestone('tomeRebuilt');

  // ---- 14. Run combat again (vs Bandit) -------------------------------------
  activeBuild = context.tome.resolve(character);
  final bandit = _spawnEnemy(context, health: _bandit.health, initiative: _bandit.initiative);
  battle = combatPlugin.system.startBattle([character, bandit]);
  availableActions = [
    for (final ref in activeBuild.components)
      if (_actionFor(ref, character, [bandit]) case final action?) action,
    AttackAction(
      actor: bandit,
      targets: [character],
      baseDamage: _bandit.damage,
      damageStat: _bandit.stat,
    ),
  ];
  controller = AutoCombatController(
    context: context,
    combatSystem: combatPlugin.system,
    battle: battle,
    availableActions: availableActions,
  );
  milestone('secondCombatStarted');
  controller.runUntilBattleEnds();
  final secondBattleWon = !controller.isActive &&
      context.components.get<HealthComponent>(character)!.current > 0;
  milestone('secondCombatResolved');

  return (
    log: log,
    physiqueId: physiqueId,
    rewardedContentId: rewardedRef.contentId,
    evolvedContentId: evolvedContentId,
    firstBattleWon: firstBattleWon,
    secondBattleWon: secondBattleWon,
  );
}

void main() {
  group('vertical slice: the complete gameplay loop', () {
    test('newRun -> characterCreated -> physiqueAssigned -> '
        'startingContentGiven -> tomeBuilt -> activeBuildResolved -> '
        'combatStarted -> combatResolved -> rewardGranted -> '
        'itemDiscovered -> itemTrained -> masteryIncreased -> '
        'evolutionResolved -> tomeRebuilt -> secondCombatStarted -> '
        'secondCombatResolved', () {
      final outcome = _runVerticalSlice(1);

      expect(
        outcome.log,
        equals(const [
          'newRun',
          'characterCreated',
          'physiqueAssigned',
          'startingContentGiven',
          'tomeBuilt',
          'activeBuildResolved',
          'combatStarted',
          'combatResolved',
          'rewardGranted',
          'itemDiscovered',
          'itemTrained',
          'masteryIncreased',
          'evolutionResolved',
          'tomeRebuilt',
          'secondCombatStarted',
          'secondCombatResolved',
        ]),
      );
      expect(outcome.firstBattleWon, isTrue);
      expect(outcome.secondBattleWon, isTrue);
      expect(PhysiqueTypes.all, contains(outcome.physiqueId));
      expect(
        outcome.rewardedContentId,
        anyOf('basic_slash', 'basic_guard'),
      );
      expect(
        outcome.evolvedContentId,
        anyOf('${outcome.rewardedContentId}:refined', '${outcome.rewardedContentId}:forceful'),
      );
    });
  });

  group('reproducibility', () {
    test('the same seed reproduces an identical run — same log, same '
        'physique, same reward, same evolution, same battle outcomes', () {
      final runA = _runVerticalSlice(7);
      final runB = _runVerticalSlice(7);

      expect(runA.log, equals(runB.log));
      expect(runA.physiqueId, equals(runB.physiqueId));
      expect(runA.rewardedContentId, equals(runB.rewardedContentId));
      expect(runA.evolvedContentId, equals(runB.evolvedContentId));
      expect(runA.firstBattleWon, equals(runB.firstBattleWon));
      expect(runA.secondBattleWon, equals(runB.secondBattleWon));
    });

    test('different seeds can diverge (sanity: the run is not accidentally '
        'seed-independent)', () {
      final seeds = List.generate(10, (i) => i);
      final physiqueIds = seeds.map((s) => _runVerticalSlice(s).physiqueId).toSet();

      expect(
        physiqueIds.length,
        greaterThan(1),
        reason: 'ten different seeds should not all assign the same physique',
      );
    });
  });
}
