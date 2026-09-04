/// When a component's numeric effects are counted into a calculation.
/// Core-owned and fixed at three — each tier's inclusion rule is
/// calculation logic, not content, so a plugin cannot add tiers.
enum EffectTier {
  /// Counted while the owner *has* the component, hung or not.
  permanent,

  /// Counted only on a calculation that *uses* this component (e.g. the
  /// combat action performed with it).
  active,

  /// Counted while the component is *hung* (in the active build), on
  /// every calculation, whether or not the component itself is used.
  supporting,
}
