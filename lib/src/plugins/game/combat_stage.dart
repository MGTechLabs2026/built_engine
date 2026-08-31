import 'package:build_engine/auto_combat_plugin.dart';
import 'package:build_engine/build_engine.dart';
import 'package:build_engine/build_interpretation.dart';
import 'package:build_engine/combat_plugin.dart';
import 'package:build_engine/item_plugin.dart';

import 'enemy.dart';
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
    final build = context.tome.resolve(character);
    events.publish(ActiveBuildResolved(build.components));
    final playerActions =
        interpreter.interpret(build: build, actor: character, targets: [enemyEntity], context: context);
    // With no technique active in the Tome (the run's own starting state,
    // and any cycle where training hasn't produced one yet), `interpreter`
    // returns no player action at all — `AutoCombatController.step`
    // treats "no legal action for the current actor" as a hard stop, so
    // the battle would stall at full health rather than resolve. A
    // minimal always-available strike keeps the player able to act.
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
}
