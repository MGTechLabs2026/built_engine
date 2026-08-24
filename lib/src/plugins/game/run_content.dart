import 'package:build_engine/build_engine.dart';
import 'package:build_engine/item_plugin.dart';
import 'package:build_engine/martial_arts_plugin.dart';
import 'package:build_engine/technique_plugin.dart';

import 'enemy.dart';

/// The 5 named enemies the run draws from, split into two difficulty
/// pools — [RunEnemies.weakPool] for the first two fights of a cycle,
/// [RunEnemies.eliteBossPool] for the third. [scaledEnemy] scales
/// whichever base is drawn to the current cycle number.
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

  /// Base enemies for a cycle's first two ("weak") fights.
  static const weakPool = [trainingDummy, bandit, martialAdept];

  /// Base enemies for a cycle's third ("elite/boss") fight.
  static const eliteBossPool = [eliteWarrior, boss];
}

/// Scales [base]'s health/damage to [cycleNumber] (1-indexed) — a flat
/// 12% growth per completed cycle, applied to both fights-1&2 and
/// fight-3 bases alike, so the run gets harder indefinitely rather than
/// plateauing at a fixed 5-enemy roster. Deliberately simple ("do not
/// tune the numbers yet, we are measuring") — [id]/[damageStat]/
/// [initiative] pass through unscaled.
Enemy scaledEnemy(Enemy base, int cycleNumber) {
  final factor = 1 + 0.12 * (cycleNumber - 1);
  return Enemy(
    id: base.id,
    health: (base.health * factor).round(),
    damage: (base.damage * factor).round(),
    damageStat: base.damageStat,
    initiative: base.initiative,
  );
}

/// Granted for free at run start (already discovered, straight into the
/// Tome) — every other item/technique is earned as a reward. No starting
/// technique this time; the first one is always earned.
abstract final class RunStartingKit {
  static const itemIds = [ItemIds.knife, ItemIds.clothArmor];
}

/// Every item/technique the run can reward, beyond the starting kit —
/// the real `ItemPlugin`/`TechniquePlugin` content ids, not a
/// game-invented roster. `knife`/`clothArmor` are excluded (starting
/// kit); `basicPunch` is included (no longer a free starting grant).
const rewardPoolItemIds = [
  ItemIds.ironSword,
  ItemIds.gloves,
  ItemIds.trainingStaff,
  ItemIds.trainingShoes,
];
const rewardPoolTechniqueIds = [TechniqueIds.basicPunch, TechniqueIds.basicSlash, TechniqueIds.basicGuard];

/// The Tome's generic slots — any item/technique category fits any slot
/// (Backpack-Hero-style free placement, not the old fixed weapon/armor/
/// technique typing). [maxSlots] is a high ceiling (not a game-design
/// number — an endless run can offer far more than 9 `unlockSlot`
/// rewards over 200 cycles, and the reward should stay meaningful for
/// most of that) rather than a tight, quickly-exhausted cap. The first
/// [startingUnlockedCount] are unlocked at run start (the starting kit);
/// the rest unlock one at a time, in this fixed order, via the
/// `RewardKind.unlockSlot` reward.
abstract final class RunTomeSlots {
  static const maxSlots = 999;
  static const startingUnlockedCount = 9;

  static final List<SlotId> all = List.unmodifiable([
    for (var i = 1; i <= maxSlots; i++) SlotId('slot_$i'),
  ]);
}

/// The 3 style ids belonging to [tradition] (`MartialTraditions.western`/
/// `.eastern`) — the second step of the run's two-step style choice.
List<String> stylesFor(String tradition) => switch (tradition) {
      MartialTraditions.western => const [MartialStyles.boxing, MartialStyles.wrestling, MartialStyles.fencing],
      MartialTraditions.eastern => const [MartialStyles.shaolin, MartialStyles.taiChi, MartialStyles.wingChun],
      _ => const [MartialStyles.boxing, MartialStyles.wrestling, MartialStyles.fencing],
    };
