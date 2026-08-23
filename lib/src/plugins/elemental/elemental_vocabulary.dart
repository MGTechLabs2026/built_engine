/// Centralized resource/status name constants for Elemental —
/// `ARCHITECTURE_AUDIT.md`'s observation B flagged these as raw string
/// literals repeated across several files, where a typo would be a
/// silent runtime mismatch (a rule/effect that quietly never matches)
/// rather than a compile error. Purely a plugin-local naming
/// convention — Core still never interprets resource/status values.
abstract final class ElementalResources {
  static const mana = 'mana';
}

/// Status tags applied by [ApplyElementalStatus] and read by
/// [buildElementalRules]'s "water conducts" rule.
abstract final class ElementalStatuses {
  static const burning = 'status:burning';
  static const soaked = 'status:soaked';
  static const shocked = 'status:shocked';
}
