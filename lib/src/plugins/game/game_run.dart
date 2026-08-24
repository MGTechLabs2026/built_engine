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

/// The endless roguelike loop:
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
/// safety net for the headless simulation, not a game-design "win."
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
RunResult runGame(
  int seed, {
  String characterName = 'Player',
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

  events.publish(RunStarted(seed: seed, characterName: characterName));

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
  final physiqueId = initializePhysique(character, context);

  // ---- Martial tradition + starting style (player decisions) -----------
  final traditionId = recordingPolicy
      .chooseMartialTradition(const [MartialTraditions.western, MartialTraditions.eastern]);
  final styleId = recordingPolicy.chooseStartingStyle(stylesFor(traditionId));
  learnStyle(character, styleId, context);

  // ---- Starting Tome: generic slots (a high ceiling, see RunTomeSlots),
  // `RunTomeSlots.startingUnlockedCount` unlocked at start -------------
  context.tome.defineTome(
    TomeDefinition.namedSlots(id: 'run_tome', slotIds: [for (final s in RunTomeSlots.all) s.id]),
  );
  context.tome.createTome(character, 'run_tome');

  final unlockedSlots = RunTomeSlots.all.sublist(0, RunTomeSlots.startingUnlockedCount).toList();
  var nextLockedSlotIndex = RunTomeSlots.startingUnlockedCount;

  final tomeHistory = <TomeSnapshot>[];
  final itemsDiscovered = <String>[];
  final itemsMastered = <String>[];
  final itemsUnlocked = <String>[];
  final techniquesLearned = <String>[];
  final techniquesEvolved = <String>[];
  final rewardsGranted = <String>[];
  final trainingRecords = <TrainingRecord>[];
  final encounters = <EncounterOutcome>[];
  var cycleIndex = 0;
  var upgradeSpendCounter = 0;
  int? firstRewardStep;
  int? firstItemMasteryStep;
  int? firstTechniqueEvolutionStep;

  void snapshot(String stepName) {
    final snapshotComponents = context.tome.resolve(character).components;
    tomeHistory.add(TomeSnapshot(afterStep: stepName, components: snapshotComponents));
    events.publish(TomeChanged(stepName: stepName, components: snapshotComponents));
  }

  List<SlotId> orderedUnlockedSlots() {
    final occupied = context.tome.inspect(character).map((p) => p.slot).toSet();
    return [
      for (final s in unlockedSlots)
        if (!occupied.contains(s)) s,
      for (final s in unlockedSlots)
        if (occupied.contains(s)) s,
    ];
  }

  void placeItem(ItemDefinition item, String stepName) {
    final ref = BuildComponentRef(referenceType: itemReferenceType, contentId: item.id);
    final slot = recordingPolicy.chooseSlot(ref, orderedUnlockedSlots());
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
    final slot = recordingPolicy.chooseSlot(ref, orderedUnlockedSlots());
    final existing = context.tome.inspect(character).where((p) => p.slot == slot);
    if (existing.isNotEmpty) {
      if (!recordingPolicy.chooseReplace(slot, existing.single.buildComponentRef, ref)) return;
      context.tome.remove(character, slot);
    }
    addTechniqueToTome(character, slot, technique, context);
    snapshot(stepName);
  }

  /// Evolution is the unlock mechanism for an evolved branch — it enters
  /// the Tome directly at whichever slot its base technique already
  /// occupied.
  void replaceWithEvolved(String baseId, String evolvedId, String stepName) {
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

  void restoreHealth() {
    const Heal(9999).apply(context.ruleContextFor(character));
  }

  void applyUpgrade(String choice) {
    if (choice == 'stat:health') {
      final health = context.components.get<HealthComponent>(character)!;
      context.components
          .add(character, HealthComponent(current: health.current + 15, max: health.max + 15));
      return;
    }
    if (choice == 'stat:speed') {
      final combatant = context.components.get<CombatantComponent>(character)!;
      context.components
          .add(character, CombatantComponent(team: combatant.team, initiative: combatant.initiative + 2));
      return;
    }
    if (choice == 'stat:attack') {
      for (final tag in WeaponStatTags.values) {
        context.modifiers.add(Modifier(
          source: ModifierSource('upgrade:stat:attack:${character.value}:$upgradeSpendCounter:$tag'),
          target: character,
          stat: tag,
          operation: ModifierOperation.add,
          value: 2,
        ));
      }
      return;
    }
    if (choice.startsWith('item:')) {
      final id = choice.substring('item:'.length);
      final item = itemDefinition(id, context);
      final stat = WeaponStatTags.matchOrFallback(item.tags, 'item:$id');
      context.modifiers.add(Modifier(
        source: ModifierSource('upgrade:item:$id:${character.value}:$upgradeSpendCounter'),
        target: character,
        stat: stat,
        operation: ModifierOperation.add,
        value: 2,
      ));
      return;
    }
    if (choice.startsWith('technique:')) {
      final id = choice.substring('technique:'.length);
      final technique = techniqueDefinition(id, context);
      final stat = WeaponStatTags.matchOrFallback(technique.tags, techniqueSubject(id));
      context.modifiers.add(Modifier(
        source: ModifierSource('upgrade:technique:$id:${character.value}:$upgradeSpendCounter'),
        target: character,
        stat: stat,
        operation: ModifierOperation.add,
        value: 2,
      ));
    }
  }

  Set<String> ownedItemIds() {
    final ids = <String>{};
    for (final entity in context.components.entitiesWith<ItemInstance>()) {
      final instance = context.components.get<ItemInstance>(entity)!;
      if (instance.owner == character) ids.add(instance.definitionId);
    }
    return ids;
  }

  Set<String> knownTechniqueIds() => {
        for (final id in rewardPoolTechniqueIds)
          if (isTechniqueLearned(character, techniqueDefinition(id, context), context)) id,
      };

  void manageTome() {
    while (context.resources.currentOf(character, 'upgrade_points') > 0) {
      final candidates = <String>[
        'stat:health',
        'stat:attack',
        'stat:speed',
        for (final id in ownedItemIds()) 'item:$id',
        for (final id in knownTechniqueIds()) 'technique:$id',
        'skip',
      ];
      final choice = recordingPolicy.chooseUpgradeSpend(candidates);
      if (choice == 'skip') break;
      context.resources.subtract(character, 'upgrade_points', 1);
      upgradeSpendCounter++;
      applyUpgrade(choice);
      events.publish(UpgradePointSpent(target: choice, amount: 1));
    }

    // A chosen `equip:` candidate can still end up doing nothing (the
    // target slot is occupied and `chooseReplace` declines it) — track
    // those so a declined attempt isn't offered again this visit. Without
    // this, a policy that deterministically re-picks the same candidate
    // every time (any `DefaultRunDecisionPolicy`-derived one, by
    // construction) would loop forever re-offering-and-declining the
    // exact same equip. A 500-iteration cap is a pure safety net on top
    // (mirrors the run's own 200-cycle cap), never meant to be hit.
    final rejectedThisVisit = <String>{};
    for (var i = 0; i < 500; i++) {
      final placements = context.tome.inspect(character);
      final placedRefs = {
        for (final p in placements) (p.buildComponentRef.referenceType, p.buildComponentRef.contentId),
      };
      // Auto-equip only ever fills an EMPTY unlocked slot on its own
      // initiative — it never forces an eviction. With no empty slot
      // left, no `equip:` candidate is offered at all (regardless of
      // what's benched); freeing a slot via `unequip:` first is the only
      // way to make room. Without this, a "replace: always true" policy
      // (like `DefaultRunDecisionPolicy`) would keep swapping benched
      // items into already-occupied slots, evicting whatever was there
      // (including a hard-won evolved technique) purely because it
      // happened to be the first candidate this iteration.
      final hasEmptySlot = unlockedSlots.length > placements.length;
      final benchedItemIds = [
        if (hasEmptySlot)
          for (final id in ownedItemIds())
            if (!placedRefs.contains((itemReferenceType, id)) &&
                isItemUsable(character, itemDefinition(id, context), context) &&
                !rejectedThisVisit.contains('equip:item:$id'))
              id,
      ];
      final benchedTechniqueIds = [
        if (hasEmptySlot)
          for (final id in knownTechniqueIds())
            if (!placedRefs.contains((techniqueReferenceType, id)) &&
                !rejectedThisVisit.contains('equip:technique:$id'))
              id,
      ];
      // `'done'` sits between the equip/unequip options — every equip:
      // option before it, every unequip: option after — so
      // `DefaultRunDecisionPolicy`'s "always take the first option"
      // always means "equip whatever's benched," never "unequip your
      // own gear for no reason."
      final candidates = <String>[
        for (final id in benchedItemIds) 'equip:item:$id',
        for (final id in benchedTechniqueIds) 'equip:technique:$id',
        'done',
        for (final p in placements)
          'unequip:${p.slot.id}:${p.buildComponentRef.referenceType}:${p.buildComponentRef.contentId}',
      ];
      if (candidates.length == 1) break; // nothing benched or placed to manage
      final choice = recordingPolicy.chooseTomeAction(candidates);
      if (choice == 'done') break;
      if (choice.startsWith('equip:item:')) {
        final id = choice.substring('equip:item:'.length);
        placeItem(itemDefinition(id, context), 'Manage Tome (equip)');
        if (!context.tome.inspect(character).any(
            (p) => p.buildComponentRef.referenceType == itemReferenceType && p.buildComponentRef.contentId == id)) {
          rejectedThisVisit.add(choice);
        }
      } else if (choice.startsWith('equip:technique:')) {
        final id = choice.substring('equip:technique:'.length);
        placeTechnique(techniqueDefinition(id, context), 'Manage Tome (equip)');
        if (!context.tome.inspect(character).any((p) =>
            p.buildComponentRef.referenceType == techniqueReferenceType && p.buildComponentRef.contentId == id)) {
          rejectedThisVisit.add(choice);
        }
      } else if (choice.startsWith('unequip:')) {
        final slotId = choice.substring('unequip:'.length).split(':').first;
        context.tome.remove(character, SlotId(slotId));
        snapshot('Manage Tome (unequip)');
      }
    }
  }

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
    placeItem(item, 'Starting Tome ($itemId)');
  }
  manageTome();

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
      characterName: characterName,
      runDuration: stopwatch.elapsed,
      decisionLog: recordingPolicy.toLog(),
      physiqueId: physiqueId,
      martialTradition: traditionId,
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
      cyclesCompleted: cycleIndex,
      firstRewardStep: firstRewardStep,
      firstItemMasteryStep: firstItemMasteryStep,
      firstTechniqueEvolutionStep: firstTechniqueEvolutionStep,
    );
  }

  List<RewardKind> rewardCandidates() => [
        if (nextLockedSlotIndex < RunTomeSlots.all.length) RewardKind.unlockSlot,
        if (rewardIndex < rewardPool.length) RewardKind.itemOrTechnique,
        RewardKind.upgradePoint,
      ];

  String resolveReward(RewardKind kind, String stepName) {
    switch (kind) {
      case RewardKind.unlockSlot:
        final slot = RunTomeSlots.all[nextLockedSlotIndex];
        unlockedSlots.add(slot);
        nextLockedSlotIndex++;
        events.publish(SlotUnlocked(slot));
        return 'slot:${slot.id}';
      case RewardKind.itemOrTechnique:
        final entry = rewardPool[rewardIndex];
        rewardIndex++;
        if (entry.referenceType == itemReferenceType) {
          final item = itemDefinition(entry.contentId, context);
          ownItem(character, item.id, context);
          discoverItem(character, item, context);
          itemsDiscovered.add(item.id);
          if (isItemUsable(character, item, context)) placeItem(item, '$stepName reward');
          return 'item:${item.id}';
        } else {
          final technique = techniqueDefinition(entry.contentId, context);
          discoverTechnique(character, technique, context);
          return 'technique:${technique.id}';
        }
      case RewardKind.upgradePoint:
        context.resources.add(character, 'upgrade_points', 1);
        return 'upgrade_point';
    }
  }

  void grantReward(String stepName) {
    final candidates = rewardCandidates();
    events.publish(RewardOffered(candidates));
    final chosenKind = candidates[recordingPolicy.chooseReward(candidates)];
    events.publish(RewardSelected(chosenKind));
    firstRewardStep ??= cycleIndex;
    rewardsGranted.add(resolveReward(chosenKind, stepName));
  }

  List<String> trainingCandidates() {
    final candidates = <String>[
      for (final id in ownedItemIds())
        if (!isItemUsable(character, itemDefinition(id, context), context)) itemSubject(id),
    ];
    for (final id in rewardPoolTechniqueIds) {
      final technique = techniqueDefinition(id, context);
      if (isTechniqueDiscovered(character, technique, context) &&
          !isTechniqueLearned(character, technique, context)) {
        candidates.add(techniqueSubject(id));
      }
    }
    return candidates;
  }

  void runTraining() {
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
        firstItemMasteryStep ??= cycleIndex;
        placeItem(item, 'Training (item mastered)');
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
        placeTechnique(technique, 'Training (technique learned)');

        if (technique.evolutionCandidates.isNotEmpty) {
          final evolution = evolveTechnique(character, technique, result.profile, context);
          if (evolution.evolved) {
            final evolvedId = evolution.chosenCandidate!.targetId;
            techniquesEvolved.add(evolvedId);
            firstTechniqueEvolutionStep ??= cycleIndex;
            events.publish(TechniqueEvolved(fromId: techniqueId, toId: evolvedId));
            replaceWithEvolved(techniqueId, evolvedId, 'Training (evolved)');
          }
        }
      }
    }
  }

  String fallbackStrikeStat(ActiveBuild build) {
    for (final ref in build.components) {
      if (ref.referenceType != itemReferenceType) continue;
      final definition = context.content.find(ref.contentId);
      if (definition == null) continue;
      final item = itemDefinitionFromContent(definition);
      if (!item.properties.containsKey('attack')) continue;
      return WeaponStatTags.matchOrFallback(item.tags, 'item:${item.id}');
    }
    return 'fist';
  }

  EntityId spawnEnemy(Enemy enemy) {
    final entity = context.entities.create();
    context.components
        .add(entity, CombatantComponent(team: 'enemy', initiative: enemy.initiative));
    context.components.add(entity, HealthComponent(current: enemy.health, max: enemy.health));
    return entity;
  }

  bool runFight(String name, Enemy enemy) {
    events.publish(EncounterStarted(name: name, enemyId: enemy.id));
    final enemyEntity = spawnEnemy(enemy);
    final build = context.tome.resolve(character);
    events.publish(ActiveBuildResolved(build.components));
    final playerActions =
        interpreter.interpret(build: build, actor: character, targets: [enemyEntity], context: context);
    // With no technique active in the Tome (the run's own starting state,
    // and any cycle where training hasn't produced one yet), `interpreter`
    // returns no player action at all — `AutoCombatController.step`
    // treats "no legal action for the current actor" as a hard stop, so
    // the battle would stall at full health rather than resolve. A
    // minimal always-available strike keeps the player able to act; it
    // reads whichever weapon-stat tag the active weapon item (if any)
    // already contributes a Modifier to — the same `_statFor` computation
    // `ItemActionInterpreter` itself uses — so an equipped knife still
    // helps even with no technique to swing it; falling back to bare-
    // handed `'fist'` only if no weapon is active either.
    final effectivePlayerActions = playerActions.isEmpty
        ? [AttackAction(actor: character, targets: [enemyEntity], baseDamage: 4, damageStat: fallbackStrikeStat(build))]
        : playerActions;
    final battle = combatPlugin.system.startBattle([character, enemyEntity]);
    final controller = AutoCombatController(
      context: context,
      combatSystem: combatPlugin.system,
      battle: battle,
      availableActions: [
        ...effectivePlayerActions,
        AttackAction(actor: enemyEntity, targets: [character], baseDamage: enemy.damage, damageStat: enemy.damageStat),
      ],
      policy: CombatPolicy.scored(),
    );

    var turnsUsed = 0;
    final subscription = events.subscribe<ActionCompleted>((e) {
      if (e.battle == battle) turnsUsed++;
    });
    controller.runUntilBattleEnds();
    subscription.cancel();

    final playerHealth = context.components.get<HealthComponent>(character)!.current;
    final won = playerHealth > 0 && !controller.isActive;
    encounters.add(EncounterOutcome(
      name: name,
      enemyId: enemy.id,
      won: won,
      playerHealthAfter: playerHealth,
      turnsUsed: turnsUsed,
    ));
    events.publish(EncounterResolved(name: name, enemyId: enemy.id, won: won, playerHealthAfter: playerHealth));
    return won;
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
      upgradePoints: context.resources.currentOf(character, 'upgrade_points'),
      // Only the currently-unlocked slots — RunTomeSlots.all is a large
      // fixed ceiling (see its own doc comment), not a small number worth
      // enumerating in full every cycle.
      slots: [for (final slot in unlockedSlots) (slot: slot, occupant: placements[slot])],
      totalSlotCapacity: RunTomeSlots.all.length,
      ownedItemIds: ownedItemIds().toList(),
      knownTechniqueIds: knownTechniqueIds().toList(),
    ));
  }

  for (cycleIndex = 0; cycleIndex < cycleCap; cycleIndex++) {
    final cycleNumber = cycleIndex + 1;
    events.publish(CycleStarted(cycleNumber));
    publishStatus();

    final combatOrTrainingCandidates = <String>[
      'combat',
      if (trainingCandidates().isNotEmpty) 'training',
    ];
    final choice = recordingPolicy.chooseCombatOrTraining(combatOrTrainingCandidates);
    if (choice == 'training') {
      runTraining();
      restoreHealth();
      manageTome();
      continue;
    }

    final weakBase1 = RunEnemies.weakPool[rng.nextInt(RunEnemies.weakPool.length)];
    if (!runFight('Cycle $cycleNumber Fight 1', scaledEnemy(weakBase1, cycleNumber))) {
      return buildResult(won: false);
    }
    grantReward('Cycle $cycleNumber Fight 1');

    final weakBase2 = RunEnemies.weakPool[rng.nextInt(RunEnemies.weakPool.length)];
    if (!runFight('Cycle $cycleNumber Fight 2', scaledEnemy(weakBase2, cycleNumber))) {
      return buildResult(won: false);
    }
    grantReward('Cycle $cycleNumber Fight 2');

    final eliteBase = RunEnemies.eliteBossPool[rng.nextInt(RunEnemies.eliteBossPool.length)];
    if (!runFight('Cycle $cycleNumber Fight 3', scaledEnemy(eliteBase, cycleNumber))) {
      return buildResult(won: false);
    }
    grantReward('Cycle $cycleNumber Fight 3');

    restoreHealth();
    manageTome();
  }

  return buildResult(won: true);
}
