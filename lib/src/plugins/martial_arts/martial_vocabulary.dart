/// Centralized resource/stance name constants for MartialArts —
/// `ARCHITECTURE_AUDIT.md`'s observation B flagged these as raw string
/// literals repeated across several files, where a typo would be a
/// silent runtime mismatch (a rule that quietly never fires) rather
/// than a compile error. Purely a plugin-local naming convention — Core
/// still never interprets resource/tag values.
abstract final class MartialResources {
  static const qi = 'qi';
  static const momentum = 'momentum';
}

/// Stance tags granted by techniques (`martial_technique_action.dart`)
/// and read by conditions/rules/modifiers elsewhere in this plugin.
abstract final class MartialStances {
  static const guard = 'stance:guard';
  static const ironBody = 'stance:iron_body';
  static const taiChi = 'stance:tai_chi';
}

/// Stable content ids for MartialArts' items/trinkets
/// (`martial_item_content.dart`) — referenced by content definitions,
/// `martial_arts_rules.dart`'s passive-regen rules (`.momentumTrinket`/
/// `.qiPendant`), and by `martialItem(id, context)` call sites, so a
/// rename here propagates everywhere instead of silently breaking a
/// second, independently-typed string literal.
abstract final class MartialItemIds {
  static const brassKnuckles = 'brass_knuckles';
  static const ironPalmWraps = 'iron_palm_wraps';
  static const taiChiSilkSash = 'tai_chi_silk_sash';
  static const sparringGloves = 'sparring_gloves';
  static const weightedVest = 'weighted_vest';
  static const momentumTrinket = 'momentum_trinket';
  static const qiPendant = 'qi_pendant';
  static const counterstrikeRing = 'counterstrike_ring';
}
