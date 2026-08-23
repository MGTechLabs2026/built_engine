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
