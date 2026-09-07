import 'package:build_engine/auto_combat_plugin.dart';
import 'package:build_engine/build_engine.dart';
import 'package:build_engine/build_interpretation.dart';
import 'package:build_engine/combat_plugin.dart';
import 'package:build_engine/consumable_plugin.dart';
import 'package:build_engine/item_plugin.dart';
import 'package:build_engine/technique_plugin.dart';

import 'enemy.dart';
import 'game_run.dart' show ownedComponentRefs;
import 'run_events.dart';
import 'run_result.dart';

/// Owns the **harness's** combat resolution: turning the active Tome
/// build into a player action, spawning an enemy, and running one fight
/// to completion via `AutoCombatController`. Extracted from `runGame`
/// (previously 3 nested closures — see `ARCHITECTURE_AUDIT.md`'s
/// god-function finding). Owns [encounters], the fight-by-fight trail.
///
/// This deliberately runs a *simpler* combat model than the shipped
/// client's: `AutoCombatController` picks actions and applies damage with
/// no per-turn mastery success roll and no mid-fight stance entry. The
/// authoritative style-scoped combat rules live in `MartialArtsPlugin`'s
/// `StyleCombatRules` (audit A2); this harness does not apply Shaolin
/// Conditioning or Kunlun Burst Chain (they need per-turn resolution) —
/// but it must never implement a *conflicting* style rule of its own.
///
/// Per-active auras (SP2) are bound here via `AuraBinder` right after
/// `tome.resolve` and disposed in the fight's `finally`, so they are live
/// only for the duration of one fight. Per-fight consumable charges (SP3)
/// are granted here alongside the aura binding, inside the same `try`, and
/// disposed (reverse order) in the `finally` — so a throw between the two
/// binder calls leaves neither live.
///
/// The always-available fallback strike is injected whenever the resolved
/// build produces no *non-consumable* action — not merely when it produces
/// no action at all — because a consumable action can be self-only and is
/// filtered out once its charge pool empties, which would otherwise leave a
/// consumable-only Tome unable to damage the enemy (SP3 C1).
class CombatStage {
  CombatStage({
    required this.character,
    required this.context,
    required this.combatPlugin,
    required this.interpreter,
    required this.events,
  });

  final EntityId character;
  final PluginContext context;
  final CombatPlugin combatPlugin;
  final CompositeBuildActionInterpreter interpreter;
  final EventBus events;

  final encounters = <EncounterOutcome>[];

  /// The minimal always-available strike's damage stat, reading whichever
  /// weapon-stat tag the active weapon item (if any) already contributes
  /// a Modifier to — the same `_statFor` computation `ItemActionInterpreter`
  /// itself uses — so an equipped knife still helps even with no
  /// technique to swing it; falls back to bare-handed `'fist'` only if no
  /// weapon is active either.
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
    final build = context.tome
        .resolve(character, ownedRefs: ownedComponentRefs(character, context));
    events.publish(ActiveBuildResolved(build.asActiveBuild.components));
    final playerActions = interpreter.interpret(
        build: build, actor: character, targets: [enemyEntity], context: context);
    AuraBinding? auraBinding;
    ConsumableCharges? consumableCharges;
    EventSubscription? subscription;
    AutoCombatController? controller;
    var turnsUsed = 0;
    try {
      auraBinding = const AuraBinder().bind(
        build: build,
        interpreter: interpreter,
        context: context,
        opponents: [enemyEntity],
      );
      consumableCharges = const ConsumableBinder().grant(build: build, context: context);

      // The player needs at least one *damaging* action every fight. A
      // technique action always deals damage; an item contributes
      // modifiers, not actions. A consumable action (SP3) can be
      // self-only (heal / buff / cleanse) and, once its per-fight charge
      // pool empties, is filtered out entirely — so a Tome holding only
      // consumables and no technique would leave the player unable to
      // ever hurt the enemy, and the fight would run to the step cap
      // (SP3 C1 regression). Add the minimal always-available strike
      // whenever no non-consumable action is present; when a consumable
      // *is* the only build action, the strike sits alongside it and
      // takes over the moment the charge pool runs dry.
      final hasNonConsumableAction = playerActions.any(
          (a) => a.sourceRef?.referenceType != consumableReferenceType);
      final effectivePlayerActions = hasNonConsumableAction
          ? playerActions
          : [
              ...playerActions,
              AttackAction(
                actor: character,
                targets: [enemyEntity],
                baseDamage: 4,
                damageStat: fallbackStrikeStat(build.asActiveBuild),
              ),
            ];
      final battle = combatPlugin.system.startBattle([character, enemyEntity]);
      controller = AutoCombatController(
        context: context,
        combatSystem: combatPlugin.system,
        battle: battle,
        availableActions: [
          ...effectivePlayerActions,
          AttackAction(actor: enemyEntity, targets: [character], baseDamage: enemy.damage, damageStat: enemy.damageStat),
        ],
        policy: CombatPolicy.scored(scorer: const ConsumableAwareActionScorer()),
      );

      subscription = events.subscribe<ActionCompleted>((e) {
        if (e.battle != battle) return;
        turnsUsed++;
        // SP0b: attribute a performed technique action to its variant
        // instance so training-time inspiration can weigh it. The Technique
        // plugin stays Combat-free — this bridge lives in the harness, the
        // same split `TechniqueActionInterpreter` uses.
        final ref = e.action.sourceRef;
        if (ref != null &&
            ref.referenceType == techniqueReferenceType &&
            ref.instanceEntityId != null) {
          recordTechniqueVariantUsage(ref.instanceEntityId!, context);
        }
      });
      controller.runUntilBattleEnds();
    } finally {
      subscription?.cancel();
      consumableCharges?.dispose();
      auraBinding?.dispose();
    }

    final playerHealth = context.components.get<HealthComponent>(character)!.current;
    // `controller` is provably non-null here: reaching past the `finally`
    // means the `try` completed normally (no `catch`, so any throw before
    // the assignment has already propagated out of `runFight`), so Dart's
    // flow analysis promotes it — no `!` needed.
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
}
