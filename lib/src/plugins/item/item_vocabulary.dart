/// Stable content ids for the Item plugin's starter set
/// (`item_content.dart`) — same rationale as `MartialItemIds`/
/// `ElementalItemIds`: a typo here is a compile error, not a silent
/// runtime string mismatch.
abstract final class ItemIds {
  static const knife = 'knife';
  static const ironSword = 'iron_sword';
  static const gloves = 'gloves';
  static const trainingStaff = 'training_staff';
  static const clothArmor = 'cloth_armor';
  static const trainingShoes = 'training_shoes';

  // Content Expansion V1 — new combinable base: hand wraps (a fist
  // weapon for palm/finger builds; eastern-leaning). Same 5-form template
  // as the six originals: base -> 2 grade-2 branches -> 1 grade-3 each.
  static const handWraps = 'hand_wraps';
  static const focusWraps = 'focus_wraps';
  static const mastersWraps = 'masters_wraps';
  static const weightedWraps = 'weighted_wraps';
  static const diamondWraps = 'diamond_wraps';

  // Martial-style starting-kit items — each style grants a two-item kit
  // (a game-composition-layer concern; the pairing lives in the client).
  // All are immediately usable (`minimum: 0`, like `knife`) so they hang
  // on the Tome with no training gate.
  //
  // Content Expansion V1 gave `polearm` and `rapier` their own combine
  // chains (additive `maxClass`/`gradeEvolution` on their existing defs —
  // ids unchanged, still `minimum: 0`), so a style's starter weapon now
  // has somewhere to grow. The other six stay non-combinable — a starter
  // kit never holds two of the same piece to combine.
  static const polearm = 'polearm';
  static const chair = 'chair';
  static const mask = 'mask';
  static const rapier = 'rapier';
  static const staff = 'staff';
  static const fan = 'fan';
  static const towel = 'towel';
  static const cloth = 'cloth';

  // Combine chains for the two starter weapons that gained one in V1.
  static const reachSpear = 'reach_spear';
  static const sentinelSpear = 'sentinel_spear';
  static const warGlaive = 'war_glaive';
  static const vanguardGlaive = 'vanguard_glaive';

  static const duelistsRapier = 'duelists_rapier';
  static const mastersRapier = 'masters_rapier';
  static const swiftRapier = 'swift_rapier';
  static const windRapier = 'wind_rapier';

  // Combine grade chains — each of the 6 items above branches into 2
  // named grade-2 items (weighted by the base item's own trainingWeights
  // tags), each continuing linearly to one grade-3 "masterwork" tier.
  // Reachable only via `combineItems`, never placed directly as starter
  // content. See `docs/superpowers/specs/2026-08-24-item-combine-design.md`.

  static const sharpKnife = 'sharp_knife';
  static const masterworkSharpKnife = 'masterwork_sharp_knife';
  static const fastKnife = 'fast_knife';
  static const windcutterKnife = 'windcutter_knife';

  static const temperedIronSword = 'tempered_iron_sword';
  static const runicIronSword = 'runic_iron_sword';
  static const reinforcedIronSword = 'reinforced_iron_sword';
  static const warlordsIronSword = 'warlords_iron_sword';

  static const swiftGloves = 'swift_gloves';
  static const lightningGloves = 'lightning_gloves';
  static const ironKnuckleGloves = 'iron_knuckle_gloves';
  static const crushingGauntlets = 'crushing_gauntlets';

  static const balancedStaff = 'balanced_staff';
  static const sagesStaff = 'sages_staff';
  static const battleStaff = 'battle_staff';
  static const warstaffOfTheVanguard = 'warstaff_of_the_vanguard';

  static const paddedClothArmor = 'padded_cloth_armor';
  static const fortifiedClothArmor = 'fortified_cloth_armor';
  static const reinforcedClothArmor = 'reinforced_cloth_armor';
  static const bastionClothArmor = 'bastion_cloth_armor';

  static const swiftShoes = 'swift_shoes';
  static const windwalkerBoots = 'windwalker_boots';
  static const surefootedShoes = 'surefooted_shoes';
  static const steadfastBoots = 'steadfast_boots';
}

/// `ContentDefinition.type` values this plugin's content uses — plain
/// category labels Core never interprets.
abstract final class ItemCategories {
  static const weapon = 'weapon';
  static const armor = 'armor';
  static const footwear = 'footwear';
}

/// The canonical `Discovery`/`Mastery` subject for item [definitionId] —
/// `'item:<id>'`, matching the exact naming convention `MasteryComponent`/
/// `DiscoveryComponent`'s own doc comments already use as their worked
/// example. Centralized here so every call site (discovery, mastery
/// gating, the usability rule) agrees on the same string by construction
/// instead of by convention.
String itemSubject(String definitionId) => 'item:$definitionId';

/// The `BuildComponentRef.referenceType` every item occupies a Tome slot
/// under — the canonical replacement for the bare `'item'` string
/// literal previously scattered ad hoc across test fixtures
/// (`test/tome/tome_service_test.dart`, `test/reward/reward_resolver_test.dart`,
/// `test/integration/support/vertical_slice_runner.dart`) with no shared
/// source of truth.
const itemReferenceType = 'item';

/// Resource ids the Item plugin registers via `ResourcePool` — currently
/// just the Combine feature's cost
/// (`docs/superpowers/specs/2026-08-24-item-combine-design.md`).
abstract final class ItemResources {
  static const upgradePoints = 'upgrade_points';
}
