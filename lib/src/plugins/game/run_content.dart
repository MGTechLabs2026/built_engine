import 'package:build_engine/build_engine.dart';
import 'package:build_engine/item_plugin.dart';
import 'package:build_engine/technique_plugin.dart';

import 'enemy.dart';

/// The 5 named enemies the milestone asks for — kept intentionally this
/// small ("keep content small"); the same 5 stat blocks are reused across
/// the run's 8 combats rather than inventing per-encounter variants.
abstract final class RunEnemies {
  static const trainingDummy =
      Enemy(id: 'training_dummy', health: 20, damage: 2, damageStat: 'dummy_attack', initiative: 1);
  static const bandit =
      Enemy(id: 'bandit', health: 27, damage: 4, damageStat: 'bandit_attack', initiative: 6);
  static const martialAdept =
      Enemy(id: 'martial_adept', health: 36, damage: 5, damageStat: 'adept_attack', initiative: 8);
  static const eliteWarrior =
      Enemy(id: 'elite_warrior', health: 44, damage: 6, damageStat: 'elite_attack', initiative: 9);
  static const boss = Enemy(id: 'boss', health: 55, damage: 7, damageStat: 'boss_attack', initiative: 9);
}

enum RunStepType { combat, training }

/// One node of the linear run graph — a plain game-layer concept, not a
/// map (per the milestone's own "do not implement maps yet").
class RunStep {
  const RunStep({
    required this.name,
    required this.type,
    this.enemy,
    this.isElite = false,
    this.isBoss = false,
  });

  final String name;
  final RunStepType type;
  final Enemy? enemy;
  final bool isElite;
  final bool isBoss;
}

/// The exact 11-step sequence the milestone suggests: 8 combats (5
/// regular + 2 Elite + 1 Boss) and 3 Training opportunities interspersed.
const runSequence = <RunStep>[
  RunStep(name: 'Encounter 1', type: RunStepType.combat, enemy: RunEnemies.trainingDummy),
  RunStep(name: 'Encounter 2', type: RunStepType.combat, enemy: RunEnemies.bandit),
  RunStep(name: 'Training Opportunity 1', type: RunStepType.training),
  RunStep(name: 'Encounter 3', type: RunStepType.combat, enemy: RunEnemies.martialAdept),
  RunStep(name: 'Elite 1', type: RunStepType.combat, enemy: RunEnemies.eliteWarrior, isElite: true),
  RunStep(name: 'Training Opportunity 2', type: RunStepType.training),
  RunStep(name: 'Encounter 4', type: RunStepType.combat, enemy: RunEnemies.bandit),
  RunStep(name: 'Encounter 5', type: RunStepType.combat, enemy: RunEnemies.martialAdept),
  RunStep(name: 'Training Opportunity 3', type: RunStepType.training),
  RunStep(name: 'Elite 2', type: RunStepType.combat, enemy: RunEnemies.eliteWarrior, isElite: true),
  RunStep(name: 'Boss', type: RunStepType.combat, enemy: RunEnemies.boss, isBoss: true),
];

/// Granted for free at run start (already discovered/learned, straight
/// into the Tome) — every other item/technique is earned as a reward.
abstract final class RunStartingKit {
  static const itemId = ItemIds.gloves;
  static const techniqueId = TechniqueIds.basicPunch;
}

/// Every item/technique the run can reward, beyond the starting kit —
/// the real `ItemPlugin`/`TechniquePlugin` content ids, not a
/// game-invented roster.
const rewardPoolItemIds = [
  ItemIds.knife,
  ItemIds.ironSword,
  ItemIds.trainingStaff,
  ItemIds.clothArmor,
  ItemIds.trainingShoes,
];
const rewardPoolTechniqueIds = [TechniqueIds.basicSlash, TechniqueIds.basicGuard];

/// The Tome's fixed slot layout for this run — 3 item slots (one per
/// `ItemCategories`) + 2 technique slots (room for the starting technique
/// plus one earned/evolved one). A simple, fixed layout; "do not
/// implement maps yet" applies to the run graph, not the Tome shape.
abstract final class RunTomeSlots {
  static const weapon = SlotId('weapon');
  static const armor = SlotId('armor');
  static const footwear = SlotId('footwear');
  static const technique1 = SlotId('technique_1');
  static const technique2 = SlotId('technique_2');
  static const all = [weapon, armor, footwear, technique1, technique2];
}

/// The Tome slot(s) valid for [category] (an `ItemDefinition.category`
/// value) — a pure game-layer mapping, not engine logic.
List<SlotId> itemSlotsFor(String category) => switch (category) {
      ItemCategories.weapon => const [RunTomeSlots.weapon],
      ItemCategories.armor => const [RunTomeSlots.armor],
      ItemCategories.footwear => const [RunTomeSlots.footwear],
      _ => const [RunTomeSlots.weapon],
    };
