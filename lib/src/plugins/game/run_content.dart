import 'package:build_engine/build_engine.dart';
import 'package:build_engine/consumable_plugin.dart';
import 'package:build_engine/item_plugin.dart';
import 'package:build_engine/technique_plugin.dart';

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

// No affix roster constant lives here by design (spec §7): reward-affix
// pools are enumerated at resolve time from the AffixPlugin's own
// `type: 'affix'` content via `context.content.withTag('affix_pool:*')`.
// AffixPlugin is the single source of affix content; the harness keeps no
// duplicate list.

/// Every consumable the run can reward — reward-pool only, never in
/// [RunStartingKit]. The real `ConsumablePlugin` content ids.
const rewardPoolConsumableIds = [
  ConsumableIds.healPotion,
  ConsumableIds.firebomb,
  ConsumableIds.powerTonic,
  ConsumableIds.cleanseTonic,
];

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
