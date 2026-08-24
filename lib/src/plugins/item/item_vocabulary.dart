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
