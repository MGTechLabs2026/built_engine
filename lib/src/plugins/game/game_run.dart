import 'package:build_engine/almanac.dart';
import 'package:build_engine/build_engine.dart';
import 'package:build_engine/build_interpretation.dart';
import 'package:build_engine/combat_plugin.dart';
import 'package:build_engine/item_plugin.dart';
import 'package:build_engine/martial_arts_plugin.dart';
import 'package:build_engine/physique_plugin.dart';
import 'package:build_engine/technique_plugin.dart';

import 'almanac_bridge.dart';
import 'combat_stage.dart';
import 'decision_log.dart';
import 'enemy_content.dart';
import 'reward_stage.dart';
import 'run_content.dart';
import 'run_decision_policy.dart';
import 'run_events.dart';
import 'run_result.dart';
import 'tome_manager.dart';
import 'training_simulation.dart';
import 'training_stage.dart';

/// [character]'s currently owned item ids — pure query, no stored state
/// of its own.
Set<String> ownedItemIds(EntityId character, PluginContext context) {
  final ids = <String>{};
  for (final entity in context.components.entitiesWith<ItemInstance>()) {
    final instance = context.components.get<ItemInstance>(entity)!;
    if (instance.owner == character) ids.add(instance.definitionId);
  }
  return ids;
}

/// Base families [character] owns at least one `TechniqueVariant` on —
/// pure query. Replaces the pre-SP1 "reward-roster family that is
/// isTechniqueLearned" set (SP1 Task 10).
Set<String> knownTechniqueIds(EntityId character, PluginContext context) => {
      for (final e in ownedTechniqueVariants(character, context))
        context.components.get<TechniqueVariant>(e)!.baseFamilyId,
    };

void restoreHealth(EntityId character, PluginContext context) {
  const Heal(9999).apply(context.ruleContextFor(character));
}

/// The **headless reference / balance-simulation** loop — see
/// `lib/game.dart` for the ownership split. This is a CI/balance probe,
/// not the shipped run: the client (`Tome_client`) owns the structured
/// run flow, sequencing and presentation; this harness composes the same
/// engine-owned domain rules into an endless survival loop so a seed is
/// reproducible and a `DecisionLog` can replay it.
///
///   New Run -> name -> Random Physique -> martial tradition -> starting
///   style -> Starting Tome (knife + cloth armor, 9 of RunTomeSlots.maxSlots
///   slots unlocked)
///   -> [combat or training] -> (combat: 3 fights, one reward choice
///   after each) or (training: one session) -> restore health -> Manage
///   Tome (spend banked upgrade points) -> loop
///
/// Repeats until the player dies (`won: false`) or a 200-cycle safety
/// cap is reached alive (`won: true`) — the cap is a pure engineering
/// safety net for the simulation, not a game-design "win," and the
/// endless loop here is the harness's own shape, not the client's
/// structured 2/4/6/8-normal + 1-hard progression.
///
/// Built entirely by composing the plugins that already implement every
/// stage — nothing here is new engine machinery:
///
///   - `PhysiquePlugin.initializePhysique`, `MartialArtsPlugin.learnStyle`
///   - `ItemPlugin`/`TechniquePlugin` (discovery/learning/mastery/Tome
///     gating)
///   - `TomeService` (`context.tome`) for the Tome itself
///   - `CompositeBuildActionInterpreter` (Build Interpretation) to turn
///     `ActiveBuild` into `CombatAction`s
///   - `AutoCombatController` + `CombatPolicy.scored()` for automatic
///     combat — the player never picks an attack directly
///   - `TrainingSession` + `TimingExercise` +
///     `techniqueTrainingExerciseFor`/`itemTrainingExerciseFor` for
///     training
///   - `EvolutionResolver` (via `evolveTechnique`) for evolution
///   - `context.resources` (the generic Resource Engine) for banked
///     upgrade points
///   - `context.modifiers` (the generic Modifier Engine) for permanent
///     upgrade-point stat bumps, stacking on top of whatever
///     `ItemActionInterpreter`/`TechniqueActionInterpreter` already add
///
/// [seed] is the sole source of randomness (enemy AI has none; training
/// attempt quality, the reward pool's shuffle order, and which pool
/// entry each fight draws are the places `rng` is actually drawn from).
/// [characterName] is cosmetic only — it has no effect on gameplay or
/// determinism, purely for identifying whose run this was in a report.
/// [policy] is the sole source of player agency; two calls with the same
/// seed but different policies produce different runs, per "player
/// decisions determine build evolution." Every decision [policy] makes
/// is recorded into `RunResult.decisionLog` — replay it via
/// `runGame(seed, policy: ReplayDecisionPolicy(previousResult.decisionLog))`
/// to reproduce the exact same run.
///
/// Pass [eventBus] to observe the run live: construct an `EventBus`,
/// subscribe to whichever event types you care about *before* calling
/// `runGame`, and pass it in — every telemetry event publishes to that
/// same bus as the run executes, not only after it returns. Omitted, a
/// private `EventBus` is used internally.
///
/// The run's own state is split across four small collaborators —
/// [TomeManager] (placement/upgrade-spend), [RewardStage] (the reward
/// pool), [TrainingStage] (training resolution), [CombatStage] (fights)
/// — each independently constructable and testable, rather than one
/// large function body closing over everything (`ARCHITECTURE_AUDIT.md`'s
/// god-function finding). `runGame` itself is the composition root: it
/// wires the four together and drives the cycle loop, exactly the same
/// order of `rng`/`policy` calls as before this split, so a given seed
/// still reproduces the exact same run.
RunResult runGame(
  int seed, {
  String characterName = 'Player',
  RunDecisionPolicy policy = const DefaultRunDecisionPolicy(),
  EventBus? eventBus,
  AlmanacRecorder? almanac,
  String? runId,
  int? runNumber,
}) {
  // Runtime validation (not `assert` — assertions are stripped in
  // release/AOT). Inert when `almanac == null`: both sub-conditions
  // short-circuit and nothing throws.
  if (almanac != null && (runId == null || runNumber == null)) {
    throw ArgumentError('runGame(almanac:) requires runId and runNumber');
  }
  HeadlessGameAlmanacBridge? bridge;
  final stopwatch = Stopwatch()..start();
  final recordingPolicy = RecordingDecisionPolicy(policy);

  final events = eventBus ?? EventBus();
  if (almanac != null) {
    bridge = HeadlessGameAlmanacBridge(almanac,
        runId: runId!, runNumber: runNumber!, seed: seed);
  }
  final entities = EntityRegistry(events);
  final components = ComponentStore();
  final rng = RngService(seed);
  final shared = CoreServices(components: components, events: events);
  final context = PluginContext(
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

  events.publish(RunStarted(seed: seed, characterName: characterName));

  final combatPlugin = CombatPlugin()..initialize(context);
  // MartialArtsPlugin.dependencies => ['combat'] must already be initialized.
  MartialArtsPlugin().initialize(context);
  PhysiquePlugin().initialize(context);
  ItemPlugin().initialize(context);
  TechniquePlugin().initialize(context);
  // No dedicated "Enemy plugin" — enemies exist only for this
  // run-composition layer, so their content is loaded directly here
  // rather than via a GamePlugin.initialize.
  context.content.loadAll(enemyContentDefinitions);
  const interpreter =
      CompositeBuildActionInterpreter([TechniqueActionInterpreter(), ItemActionInterpreter()]);

  // ---- New Run / character ------------------------------------------
  final character = context.characters.create();
  bridge?.attach(events, context, character);
  context.components.add(character, const CombatantComponent(team: 'player', initiative: 10));
  context.components.add(character, const HealthComponent(current: 100, max: 100));

  // ---- Random Physique -------------------------------------------------
  final physiqueId = initializePhysique(character, context);

  // ---- Martial tradition + starting style (player decisions) -----------
  final traditionId = recordingPolicy
      .chooseMartialTradition(const [MartialTraditions.western, MartialTraditions.eastern]);
  final styleId = recordingPolicy.chooseStartingStyle(stylesForTradition(traditionId));
  learnStyle(character, styleId, context);
  bridge?.setRunProfile(
      lineageId: martialTraditionOf(styleId) ?? styleId, physiqueId: physiqueId);

  // ---- Starting Tome: generic slots (a high ceiling, see RunTomeSlots),
  // `RunTomeSlots.startingUnlockedCount` unlocked at start -------------
  context.tome.defineTome(
    TomeDefinition.namedSlots(id: 'run_tome', slotIds: [for (final s in RunTomeSlots.all) s.id]),
  );
  context.tome.createTome(character, 'run_tome');

  final unlockedSlots = RunTomeSlots.all.sublist(0, RunTomeSlots.startingUnlockedCount).toList();
  final tomeManager = TomeManager(
    character: character,
    context: context,
    recordingPolicy: recordingPolicy,
    events: events,
    unlockedSlots: unlockedSlots,
  );

  final itemsDiscovered = <String>[];
  var cycleIndex = 0;

  void manageTome() => tomeManager.manageTome(
        ownedItemIds: () => ownedItemIds(character, context),
        knownTechniqueIds: () => knownTechniqueIds(character, context),
      );

  // ---- Starting kit: granted free, already discovered ---------------
  for (final itemId in RunStartingKit.itemIds) {
    final item = itemDefinition(itemId, context);
    ownItem(character, item.id, context);
    discoverItem(character, item, context);
    itemsDiscovered.add(item.id);
    if (item.requirement != null) {
      // Instantly satisfy whatever mastery threshold this item's own
      // content requires — a real reward-path grant of the same item
      // still requires real training; only the starting-kit grant is
      // treated as already-mastered gear.
      context.mastery.increase(character, itemSubject(item.id), 999);
    }
    tomeManager.placeItem(item, 'Starting Tome ($itemId)');
  }
  manageTome();
  bridge?.recordBuildPhase(BuildPhase.initial);

  // ---- Reward pool: every id beyond the starting kit, seed-shuffled -----
  final rewardPool = seededShuffle(
    [
      for (final id in rewardPoolItemIds) (referenceType: itemReferenceType, contentId: id),
      for (final id in rewardPoolTechniqueIds) (referenceType: techniqueReferenceType, contentId: id),
    ],
    rng,
  );
  final rewardStage = RewardStage(
    character: character,
    context: context,
    recordingPolicy: recordingPolicy,
    events: events,
    tomeManager: tomeManager,
    itemsDiscovered: itemsDiscovered,
    rewardPool: rewardPool,
  );
  final trainingStage = TrainingStage(
    character: character,
    context: context,
    recordingPolicy: recordingPolicy,
    rng: rng,
    events: events,
    tomeManager: tomeManager,
    styleId: styleId,
  );
  final combatStage = CombatStage(
    character: character,
    context: context,
    combatPlugin: combatPlugin,
    interpreter: interpreter,
    events: events,
  );

  RunResult buildResult({required bool won}) {
    stopwatch.stop();
    events.publish(RunEnded(won: won, encounterCount: combatStage.encounters.length));
    bridge?.detach();
    return RunResult(
      seed: seed,
      characterName: characterName,
      runDuration: stopwatch.elapsed,
      decisionLog: recordingPolicy.toLog(),
      physiqueId: physiqueId,
      martialTradition: traditionId,
      styleId: styleId,
      tomeHistory: tomeManager.tomeHistory,
      itemsDiscovered: itemsDiscovered,
      itemsMastered: trainingStage.itemsMastered,
      itemsUnlocked: tomeManager.itemsUnlocked,
      techniquesLearned: trainingStage.techniquesLearned,
      techniquesEvolved: trainingStage.techniquesEvolved,
      encounters: combatStage.encounters,
      rewardsGranted: rewardStage.rewardsGranted,
      trainingRecords: trainingStage.trainingRecords,
      finalBuild: context.tome.resolve(character).components,
      won: won,
      cyclesCompleted: cycleIndex,
      firstRewardStep: rewardStage.firstRewardStep,
      firstItemMasteryStep: trainingStage.firstItemMasteryStep,
      firstTechniqueEvolutionStep: trainingStage.firstTechniqueEvolutionStep,
    );
  }

  // ---- The endless loop --------------------------------------------------
  const cycleCap = 200;
  void publishStatus() {
    final placements = {
      for (final p in context.tome.inspect(character)) p.slot: p.buildComponentRef,
    };
    final health = context.components.get<HealthComponent>(character)!;
    final combatant = context.components.get<CombatantComponent>(character)!;
    events.publish(RunStatus(
      health: health.current,
      maxHealth: health.max,
      initiative: combatant.initiative,
      upgradePoints: context.resources.currentOf(character, ItemResources.upgradePoints),
      // Only the currently-unlocked slots — RunTomeSlots.all is a large
      // fixed ceiling (see its own doc comment), not a small number worth
      // enumerating in full every cycle.
      slots: [for (final slot in tomeManager.unlockedSlots) (slot: slot, occupant: placements[slot])],
      totalSlotCapacity: RunTomeSlots.all.length,
      ownedItemIds: ownedItemIds(character, context).toList(),
      knownTechniqueIds: knownTechniqueIds(character, context).toList(),
    ));
  }

  for (cycleIndex = 0; cycleIndex < cycleCap; cycleIndex++) {
    final cycleNumber = cycleIndex + 1;
    events.publish(CycleStarted(cycleNumber));
    publishStatus();

    final combatOrTrainingCandidates = <String>[
      'combat',
      if (trainingStage.trainingCandidates(() => ownedItemIds(character, context)).isNotEmpty) 'training',
    ];
    final choice = recordingPolicy.chooseCombatOrTraining(combatOrTrainingCandidates);
    if (choice == 'training') {
      trainingStage.runTraining(() => ownedItemIds(character, context), cycleIndex);
      restoreHealth(character, context);
      manageTome();
      bridge?.recordBuildPhase(BuildPhase.postTraining);
      continue;
    }

    final weakBase1 = enemyDefinition(
        RunEnemies.weakPool[rng.nextInt(RunEnemies.weakPool.length)], context);
    if (!combatStage.runFight('Cycle $cycleNumber Fight 1', scaledEnemy(weakBase1, cycleNumber))) {
      return buildResult(won: false);
    }
    rewardStage.grantReward('Cycle $cycleNumber Fight 1', cycleIndex);
    bridge?.recordBuildPhase(BuildPhase.postReward);

    final weakBase2 = enemyDefinition(
        RunEnemies.weakPool[rng.nextInt(RunEnemies.weakPool.length)], context);
    if (!combatStage.runFight('Cycle $cycleNumber Fight 2', scaledEnemy(weakBase2, cycleNumber))) {
      return buildResult(won: false);
    }
    rewardStage.grantReward('Cycle $cycleNumber Fight 2', cycleIndex);
    bridge?.recordBuildPhase(BuildPhase.postReward);

    final eliteBase = enemyDefinition(
        RunEnemies.eliteBossPool[rng.nextInt(RunEnemies.eliteBossPool.length)], context);
    if (!combatStage.runFight('Cycle $cycleNumber Fight 3', scaledEnemy(eliteBase, cycleNumber))) {
      return buildResult(won: false);
    }
    rewardStage.grantReward('Cycle $cycleNumber Fight 3', cycleIndex);
    bridge?.recordBuildPhase(BuildPhase.postReward);

    restoreHealth(character, context);
    manageTome();
  }

  return buildResult(won: true);
}
