import 'effect_profile.dart';
import 'effect_tier.dart';

/// Pure. Mirrors `ModifierResolver`/`BuildResolver`'s "function, no
/// storage" shape.
///
/// This function has no way to see component *identity* (it only
/// receives already-extracted [EffectProfile] values), so it cannot
/// itself assert "every hung profile's owner also appears in owned" —
/// that invariant is established one layer up, at [ResolvedBuild]
/// construction (`lib/src/tome/build_resolver.dart`), where `hung` is
/// derived as a subset of `owned` by construction rather than checked
/// after the fact. This resolver trusts its caller.
class EffectProfileResolver {
  const EffectProfileResolver();

  /// The total contribution to [stat] from a set of components:
  ///
  ///   Σ permanent[stat]  over `owned`
  /// + Σ supporting[stat] over `hung`
  /// + active[stat]       of `usedThisCalculation` (if any)
  num resolve({
    required Iterable<EffectProfile> owned,
    required Iterable<EffectProfile> hung,
    EffectProfile? usedThisCalculation,
    required String stat,
  }) {
    num total = 0;
    for (final profile in owned) {
      total += profile.amount(EffectTier.permanent, stat);
    }
    for (final profile in hung) {
      total += profile.amount(EffectTier.supporting, stat);
    }
    if (usedThisCalculation != null) {
      total += usedThisCalculation.amount(EffectTier.active, stat);
    }
    return total;
  }
}
