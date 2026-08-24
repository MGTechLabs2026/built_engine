/// Shared `'fist'`/`'blade'` stat-tag vocabulary and matching logic —
/// extracted once (`ARCHITECTURE_AUDIT.md`'s category-12 Low finding)
/// after `TechniqueActionInterpreter` and `ItemActionInterpreter`
/// independently duplicated the identical constant and matching loop.
/// Both files already live in this same module, so there's no
/// plugin-boundary reason to keep two copies.
abstract final class WeaponStatTags {
  static const values = ['fist', 'blade'];

  /// The first tag in [values] that [tags] contains, or [fallback] if
  /// none match.
  static String matchOrFallback(Set<String> tags, String fallback) {
    for (final tag in values) {
      if (tags.contains(tag)) return tag;
    }
    return fallback;
  }
}
