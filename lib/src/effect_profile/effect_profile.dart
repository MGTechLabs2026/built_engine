import 'effect_tier.dart';

/// A component's numeric contributions, grouped by tier. The inner map
/// is open, string-keyed (`'initiative'`, `'damage'`, ...) — Core never
/// enumerates the keys, the same treatment `TrainingProfile.dimensions`
/// and `MasteryComponent.progress` already get. A consumer reads the
/// keys it cares about; an unknown key is simply never asked for.
///
/// Recursively immutable. The bare `const` constructor is for
/// compile-time-const literals only (e.g. [empty]) — general callers
/// building a profile from computed maps MUST use [EffectProfile.of],
/// which deep-copies into unmodifiable maps so external mutation of the
/// caller's own map can never desync a profile after construction.
class EffectProfile {
  const EffectProfile(this._byTier);

  /// Deep-copies [byTier] into unmodifiable maps at both levels. The
  /// safe general-purpose constructor.
  factory EffectProfile.of(Map<EffectTier, Map<String, num>> byTier) =>
      EffectProfile(Map.unmodifiable({
        for (final entry in byTier.entries)
          entry.key: Map<String, num>.unmodifiable(entry.value),
      }));

  final Map<EffectTier, Map<String, num>> _byTier;

  static const empty = EffectProfile({});

  /// Every stat contribution declared for [tier]. Empty map if none.
  Map<String, num> tier(EffectTier tier) => _byTier[tier] ?? const {};

  /// Convenience for one (tier, stat) lookup. 0 if absent.
  num amount(EffectTier tier, String stat) => _byTier[tier]?[stat] ?? 0;

  /// Merge two profiles tier-by-tier, stat-by-stat (additive union).
  /// Used when one component has more than one contributor feeding its
  /// profile (e.g. an item's base stat plus its rolled affix).
  EffectProfile merge(EffectProfile other) {
    final result = <EffectTier, Map<String, num>>{};
    for (final t in EffectTier.values) {
      final a = tier(t);
      final b = other.tier(t);
      if (a.isEmpty && b.isEmpty) continue;
      final combined = <String, num>{...a};
      b.forEach((stat, value) => combined[stat] = (combined[stat] ?? 0) + value);
      result[t] = combined;
    }
    return EffectProfile.of(result);
  }
}
