import 'package:build_engine/auto_combat_plugin.dart';
import 'package:build_engine/build_engine.dart';
import 'package:build_engine/build_interpretation.dart';
import 'package:build_engine/combat_plugin.dart';
import 'package:build_engine/item_plugin.dart';
import 'package:build_engine/martial_arts_plugin.dart';
import 'package:build_engine/physique_plugin.dart';
import 'package:build_engine/technique_plugin.dart';

import 'decision_log.dart';
import 'enemy.dart';
import 'run_content.dart';
import 'run_decision_policy.dart';
import 'run_events.dart';
import 'run_result.dart';
import 'training_simulation.dart';

/// The player loop the milestone asks for, executed headlessly and
/// deterministically from (seed, policy):
///
///   New Run -> Random Physique -> Starting martial style -> Starting
///   Tome -> Combat -> Reward -> Discovery -> Training -> Mastery/
///   Learning -> Evolution -> Tome rebuild -> Combat -> ... -> Elite ->
///   Boss -> Run result
///
/// Built entirely by composing the plugins that already implement every
/// stage — nothing here is new engine machinery:
///
///   - `PhysiquePlugin.initializePhysique`, `MartialArtsPlugin.learnStyle`
///   - `ItemPlugin`/`TechniquePlugin` (discovery/learning/mastery/Tome
///     gating)
///   - `TomeService` (`context.tome`) for the Tome itself
///   - `CompositeBuildActionInterpreter` (Build Interpretation) to turn
///     `ActiveBuild` into `CombatAction`s — the real replacement for the
///     old vertical-slice `_actionFor`/`_damageTable` bridge
///   - `AutoCombatController` + `CombatPolicy.scored()` for automatic
///     combat — the player never picks an attack directly
///   - `TrainingSession` + `TimingExercise` +
///     `techniqueTrainingExerciseFor`/`itemTrainingExerciseFor` for
///     training
///   - `EvolutionResolver` (via `evolveTechnique`) for evolution
///
/// [seed] is the sole source of randomness (enemy AI has none; training
/// attempt quality and the reward pool's order are the two places `rng`
/// is actually drawn from). [policy] is the sole source of player
/// agency — reward choice, training target, Tome slot, and replace-or-not
/// all flow through it, so two calls with the same seed but different
/// policies produce different builds, per the milestone's "player
/// decisions determine build evolution." Every decision [policy] actually
/// makes is recorded into `RunResult.decisionLog` — replay it via
/// `runGame(seed, policy: ReplayDecisionPolicy(previousResult.decisionLog))`
/// to reproduce the exact same run.
///
/// Pass [eventBus] to observe the run live: construct an `EventBus`,
/// subscribe to whichever event types you care about *before* calling
/// `runGame`, and pass it in — every telemetry event publishes to that
/// same bus as the run executes, not only after it returns. Omitted, a
/// private `EventBus` is used internally (nothing to subscribe to from
/// outside, but no behavior changes).
///
/// Publishes the telemetry events documented in `run_events.dart` through
/// `context.events` — the same `EventBus` every other system already
/// uses — throughout the run, for a developer to subscribe to and watch
/// live, in addition to the full `RunResult` returned at the end.
RunResult runGame(
  int seed, {
  RunDecisionPolicy policy = const DefaultRunDecisionPolicy(),
  EventBus? eventBus,
}) {
  final stopwatch = Stopwatch()..start();
  final recordingPolicy = RecordingDecisionPolicy(policy);

  final events = eventBus ?? EventBus();
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

  events.publish(RunStarted(seed));

  final combatPlugin = CombatPlugin()..initialize(context);
  // MartialArtsPlugin.dependencies => ['combat'] must already be initialized.
  MartialArtsPlugin().initialize(context);
  PhysiquePlugin().initialize(context);
  ItemPlugin().initialize(context);
  TechniquePlugin().initialize(context);
  const interpreter =
      CompositeBuildActionInterpreter([TechniqueActionInterpreter(), ItemActionInterpreter()]);

  // ---- New Run / character ------------------------------------------
  final character = context.characters.create();
  context.components.add(character, const CombatantComponent(team: 'player', initiative: 10));
  context.components.add(character, const HealthComponent(current: 100, max: 100));

  // ---- Random Physique -------------------------------------------------
  // Publishes the existing PhysiqueAssigned event — no duplicate needed.
  final physiqueId = initializePhysique(character, context);

  // ---- Starting martial style (player decision) -------------------------
  final styleId = recordingPolicy
      .chooseStartingStyle(const [MartialStyles.boxing, MartialStyles.shaolin, MartialStyles.taiChi]);
  learnStyle(character, styleId, context);

  // ---- Starting Tome -----------------------------------------------------
  context.tome.defineTome(
    TomeDefinition.namedSlots(id: 'run_tome', slotIds: [for (final s in RunTomeSlots.all) s.id]),
  );
  context.tome.createTome(character, 'run_tome');

  final tomeHistory = <TomeSnapshot>[];
  final itemsDiscovered = <String>[];
  final itemsMastered = <String>[];
  final itemsUnlocked = <String>[];
  final techniquesLearned = <String>[];
  final techniquesEvolved = <String>[];
  final rewardsGranted = <String>[];
  final trainingRecords = <TrainingRecord>[];
  final encounters = <EncounterOutcome>[];
  var stepIndex = 0;
  int? firstRewardStep;
  int? firstItemMasteryStep;
  int? firstTechniqueEvolutionStep;

  void snapshot(String stepName) {
    final snapshotComponents = context.tome.resolve(character).components;
    tomeHistory.add(TomeSnapshot(afterStep: stepName, components: snapshotComponents));
    events.publish(TomeChanged(stepName: stepName, components: snapshotComponents));
  }

  List<SlotId> orderedSlots(List<SlotId> slots) {
    final occupied = context.tome.inspect(character).map((p) => p.slot).toSet();
    return [
      for (final s in slots)
        if (!occupied.contains(s)) s,
      for (final s in slots)
        if (occupied.contains(s)) s,
    ];
  }

  void placeItem(ItemDefinition item, String stepName) {
    final ref = BuildComponentRef(referenceType: itemReferenceType, contentId: item.id);
    final slot = recordingPolicy.chooseSlot(ref, orderedSlots(itemSlotsFor(item.category)));
    final existing = context.tome.inspect(character).where((p) => p.slot == slot);
    if (existing.isNotEmpty) {
      if (!recordingPolicy.chooseReplace(slot, existing.single.buildComponentRef, ref)) return;
      context.tome.remove(character, slot);
    }
    addItemToTome(character, slot, item, context);
    if (!itemsUnlocked.contains(item.id)) itemsUnlocked.add(item.id);
    snapshot(stepName);
  }

  void placeTechnique(TechniqueDefinition technique, String stepName) {
    final ref = BuildComponentRef(referenceType: techniqueReferenceType, contentId: technique.id);
    final slot = recordingPolicy
        .chooseSlot(ref, orderedSlots(const [RunTomeSlots.technique1, RunTomeSlots.technique2]));
    final existing = context.tome.inspect(character).where((p) => p.slot == slot);
    if (existing.isNotEmpty) {
      if (!recordingPolicy.chooseReplace(slot, existing.single.buildComponentRef, ref)) return;
      context.tome.remove(character, slot);
    }
    addTechniqueToTome(character, slot, technique, context);
    snapshot(stepName);
  }

  /// Evolution is the unlock mechanism for an evolved branch — it has no
  /// registered learning threshold of its own (only the 3 base techniques
  /// do), so it enters the Tome directly at whichever slot its base
  /// technique already occupied, exactly the pattern the original
  /// vertical slice already established for evolved content.
  void replaceWithEvolved(String baseId, String evolvedId, String stepName) {
    // BuildComponentRef has no custom == (see ARCHITECTURE.md — Tome
    // placements are plain value data, not identity-compared), so the
    // match must compare fields directly rather than `==`.
    final placement = context.tome.inspect(character).where((p) =>
        p.buildComponentRef.referenceType == techniqueReferenceType &&
        p.buildComponentRef.contentId == baseId).toList();
    if (placement.isEmpty) return;
    context.tome.replace(
      character,
      placement.single.slot,
      BuildComponentRef(referenceType: techniqueReferenceType, contentId: evolvedId),
    );
    snapshot(stepName);
  }

  // ---- Starting kit: granted free, already discovered/learned -----------
  final startingItem = itemDefinition(RunStartingKit.itemId, context);
  ownItem(character, startingItem.id, context);
  discoverItem(character, startingItem, context);
  itemsDiscovered.add(startingItem.id);
  placeItem(startingItem, 'Starting Tome (item)');

  final startingTechnique = techniqueDefinition(RunStartingKit.techniqueId, context);
  discoverTechnique(character, startingTechnique, context);
  attemptToLearnTechnique(character, startingTechnique, 10, context);
  techniquesLearned.add(startingTechnique.id);
  placeTechnique(startingTechnique, 'Starting Tome (technique)');

  // ---- Reward pool: every id beyond the starting kit, seed-shuffled -----
  final rewardPool = seededShuffle(
    [
      for (final id in rewardPoolItemIds) (referenceType: itemReferenceType, contentId: id),
      for (final id in rewardPoolTechniqueIds) (referenceType: techniqueReferenceType, contentId: id),
    ],
    rng,
  );
  var rewardIndex = 0;

  RunResult buildResult({required bool won}) {
    stopwatch.stop();
    events.publish(RunEnded(won: won, encounterCount: encounters.length));
    return RunResult(
      seed: seed,
      runDuration: stopwatch.elapsed,
      decisionLog: recordingPolicy.toLog(),
      physiqueId: physiqueId,
      styleId: styleId,
      tomeHistory: tomeHistory,
      itemsDiscovered: itemsDiscovered,
      itemsMastered: itemsMastered,
      itemsUnlocked: itemsUnlocked,
      techniquesLearned: techniquesLearned,
      techniquesEvolved: techniquesEvolved,
      encounters: encounters,
      rewardsGranted: rewardsGranted,
      trainingRecords: trainingRecords,
      finalBuild: context.tome.resolve(character).components,
      won: won,
      firstRewardStep: firstRewardStep,
      firstItemMasteryStep: firstItemMasteryStep,
      firstTechniqueEvolutionStep: firstTechniqueEvolutionStep,
    );
  }

  void grantReward(String stepName) {
    if (rewardIndex >= rewardPool.length) return;
    final offerCount = (rewardPool.length - rewardIndex).clamp(0, 2);
    final offered = rewardPool.sublist(rewardIndex, rewardIndex + offerCount);
    rewardIndex += offerCount;
    final refs = [for (final o in offered) BuildComponentRef(referenceType: o.referenceType, contentId: o.contentId)];
    events.publish(RewardOffered(refs));
    final chosen = offered[recordingPolicy.chooseReward(refs)];
    events.publish(RewardSelected(
      BuildComponentRef(referenceType: chosen.referenceType, contentId: chosen.contentId),
    ));
    firstRewardStep ??= stepIndex;

    if (chosen.referenceType == itemReferenceType) {
      final item = itemDefinition(chosen.contentId, context);
      ownItem(character, item.id, context);
      discoverItem(character, item, context);
      itemsDiscovered.add(item.id);
      rewardsGranted.add('item:${item.id}');
      if (isItemUsable(character, item, context)) placeItem(item, '$stepName reward');
    } else {
      final technique = techniqueDefinition(chosen.contentId, context);
      discoverTechnique(character, technique, context);
      rewardsGranted.add('technique:${technique.id}');
    }
  }

  List<String> trainingCandidates() {
    final ownedItemIds = <String>{};
    for (final entity in context.components.entitiesWith<ItemInstance>()) {
      final instance = context.components.get<ItemInstance>(entity)!;
      if (instance.owner == character) ownedItemIds.add(instance.definitionId);
    }
    final candidates = <String>[
      for (final id in ownedItemIds)
        if (!isItemUsable(character, itemDefinition(id, context), context)) itemSubject(id),
    ];
    for (final id in [RunStartingKit.techniqueId, ...rewardPoolTechniqueIds]) {
      final technique = techniqueDefinition(id, context);
      if (isTechniqueDiscovered(character, technique, context) &&
          !isTechniqueLearned(character, technique, context)) {
        candidates.add(techniqueSubject(id));
      }
    }
    return candidates;
  }

  void runTraining(String stepName) {
    // A Training Opportunity doubles as a rest point — reuses the
    // existing generic `Heal` effect, nothing new. Capped at max by
    // `Heal`'s own clamp, so this never overheals.
    const Heal(35).apply(context.ruleContextFor(character));

    final candidates = trainingCandidates();
    if (candidates.isEmpty) return;
    final target = recordingPolicy.chooseTrainingTarget(candidates);
    events.publish(TrainingStarted(target));
    final attempts = generateTrainingAttempts(rng);

    if (target.startsWith('item:')) {
      final itemId = target.substring('item:'.length);
      final item = itemDefinition(itemId, context);
      final wasUsable = isItemUsable(character, item, context);
      final exercise = itemTrainingExerciseFor(item, const TimingExercise());
      final session = TrainingSession(trainee: character, subject: itemSubject(itemId), exercise: exercise);
      for (final attempt in attempts) {
        session.submitAttempt(attempt);
      }
      final result = session.complete();
      final gain = trainingGain(result.profile);
      events.publish(TrainingResultRecorded(subject: target, profile: result.profile, gain: gain));
      trainingRecords.add(TrainingRecord(
        subject: target,
        attemptCount: attempts.length,
        averageQuality: result.profile.dimensions.isEmpty
            ? 0
            : TrainingStatistics.average(result.profile.dimensions.values.toList()),
        gain: gain,
      ));
      context.mastery.increase(character, itemSubject(itemId), gain);
      final nowUsable = isItemUsable(character, item, context);
      if (!wasUsable && nowUsable) {
        itemsMastered.add(itemId);
        firstItemMasteryStep ??= stepIndex;
        placeItem(item, '$stepName (item mastered)');
      }
    } else {
      final techniqueId = target.substring('technique:'.length);
      final technique = techniqueDefinition(techniqueId, context);
      final exercise = techniqueTrainingExerciseFor(technique, const TimingExercise());
      final session =
          TrainingSession(trainee: character, subject: techniqueSubject(techniqueId), exercise: exercise);
      for (final attempt in attempts) {
        session.submitAttempt(attempt);
      }
      final result = session.complete();
      final gain = trainingGain(result.profile);
      events.publish(TrainingResultRecorded(subject: target, profile: result.profile, gain: gain));
      trainingRecords.add(TrainingRecord(
        subject: target,
        attemptCount: attempts.length,
        averageQuality: result.profile.dimensions.isEmpty
            ? 0
            : TrainingStatistics.average(result.profile.dimensions.values.toList()),
        gain: gain,
      ));
      final learning = attemptToLearnTechnique(character, technique, gain, context);
      if (learning.learned) {
        techniquesLearned.add(techniqueId);
        placeTechnique(technique, '$stepName (technique learned)');

        if (technique.evolutionCandidates.isNotEmpty) {
          final evolution = evolveTechnique(character, technique, result.profile, context);
          if (evolution.evolved) {
            final evolvedId = evolution.chosenCandidate!.targetId;
            techniquesEvolved.add(evolvedId);
            firstTechniqueEvolutionStep ??= stepIndex;
            events.publish(TechniqueEvolved(fromId: techniqueId, toId: evolvedId));
            replaceWithEvolved(techniqueId, evolvedId, '$stepName (evolved)');
          }
        }
      }
    }
  }

  EntityId spawnEnemy(Enemy enemy) {
    final entity = context.entities.create();
    context.components
        .add(entity, CombatantComponent(team: 'enemy', initiative: enemy.initiative));
    context.components.add(entity, HealthComponent(current: enemy.health, max: enemy.health));
    return entity;
  }

  bool runCombat(RunStep step) {
    final enemy = step.enemy!;
    events.publish(EncounterStarted(name: step.name, enemyId: enemy.id));
    final enemyEntity = spawnEnemy(enemy);
    final build = context.tome.resolve(character);
    events.publish(ActiveBuildResolved(build.components));
    final playerActions =
        interpreter.interpret(build: build, actor: character, targets: [enemyEntity], context: context);
    final battle = combatPlugin.system.startBattle([character, enemyEntity]);
    final controller = AutoCombatController(
      context: context,
      combatSystem: combatPlugin.system,
      battle: battle,
      availableActions: [
        ...playerActions,
        AttackAction(actor: enemyEntity, targets: [character], baseDamage: enemy.damage, damageStat: enemy.damageStat),
      ],
      policy: CombatPolicy.scored(),
    );

    // ActionStarted already fires per action (Combat's own event) — this
    // only counts them for the "combat duration" balance signal, scoped
    // to this one battle.
    var turnsUsed = 0;
    final subscription = events.subscribe<ActionCompleted>((e) {
      if (e.battle == battle) turnsUsed++;
    });
    controller.runUntilBattleEnds();
    subscription.cancel();

    final playerHealth = context.components.get<HealthComponent>(character)!.current;
    final won = playerHealth > 0 && !controller.isActive;
    encounters.add(EncounterOutcome(
      name: step.name,
      enemyId: enemy.id,
      won: won,
      playerHealthAfter: playerHealth,
      turnsUsed: turnsUsed,
    ));
    events.publish(EncounterResolved(
      name: step.name,
      enemyId: enemy.id,
      won: won,
      playerHealthAfter: playerHealth,
    ));
    if (won) grantReward(step.name);
    return won;
  }

  // ---- Run the linear graph ----------------------------------------------
  for (; stepIndex < runSequence.length; stepIndex++) {
    final step = runSequence[stepIndex];
    if (step.type == RunStepType.combat) {
      if (!runCombat(step)) return buildResult(won: false);
    } else {
      runTraining(step.name);
    }
  }

  return buildResult(won: true);
}
