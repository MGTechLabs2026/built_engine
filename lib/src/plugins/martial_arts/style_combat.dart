import 'martial_vocabulary.dart';

/// **A2 — the authoritative style-scoped combat rules.**
///
/// The off-specialty damage penalty, Shaolin Conditioning and Kunlun
/// Burst Chain, extracted from the client's `CombatAdapter` so there is
/// exactly one implementation that an engine consumer, the headless
/// balance harness, or any future client all share. Pure and
/// deterministic: no RNG, no engine mutation, no Flutter — a consumer
/// builds one from a fighter's tag set and asks it how each action
/// resolves; the consumer applies the returned numbers.
///
/// Generic by construction: every rule keys off `spec:*` marker tags
/// ([MartialSpecs]) and the content-data [styleAlignedFamilies] map,
/// never `if (styleId == …)`, so a future style that grants the same
/// tags inherits the behaviour here with no change (audit A2
/// future-extensibility clause). The static per-style *affinity*
/// modifiers registered by `learnStyle` are unaffected — this type only
/// owns the parts that were previously reimplemented client-side.
class StyleCombatRules {
  StyleCombatRules(Set<String> fighterTags)
      : _aligned =
            styleAlignedFamilies[_styleIdOf(fighterTags)] ?? const <String>{},
        conditioning = fighterTags.contains(MartialSpecs.conditioning),
        burstChain = fighterTags.contains(MartialSpecs.burstChain);

  final Set<String> _aligned;

  /// Shaolin Conditioning is active for this fighter (`spec:conditioning`).
  final bool conditioning;

  /// Kunlun Burst Chain is active for this fighter (`spec:burst_chain`).
  final bool burstChain;

  static String _styleIdOf(Set<String> tags) => tags
      .firstWhere((t) => t.startsWith('style:'), orElse: () => 'style:')
      .substring('style:'.length);

  /// Outgoing-damage multiplier for an action carrying [actionTags]:
  /// `1.0` unless the action has a recognised weapon/technique family tag
  /// ([recognisedFamilyTags]) that is **not** in the fighter's aligned
  /// set — then [offSpecialtyDamageFactor]. Neutral content (no
  /// recognised family tag) and a fighter with no known style are never
  /// penalised. Matches the client's prior `offSpec` exactly.
  double outgoingDamageFactor(Iterable<String> actionTags) {
    if (_aligned.isEmpty) return 1.0;
    final fam = actionTags.where(recognisedFamilyTags.contains);
    if (fam.isEmpty) return 1.0;
    return fam.any(_aligned.contains) ? 1.0 : offSpecialtyDamageFactor;
  }

  /// Shaolin Conditioning: shave 1 off an incoming hit, floor 1 — a hit
  /// of 1 or less is unchanged. Returns [rawIncoming] untouched when
  /// Conditioning is inactive. The consumer is responsible for restoring
  /// the difference if the raw damage was already applied.
  num mitigateIncoming(num rawIncoming) =>
      (conditioning && rawIncoming > 1) ? rawIncoming - 1 : rawIncoming;

  /// Kunlun Burst Chain: the flat bonus damage one landed hit adds, plus
  /// the streak state to carry forward. [isBladeHit] is whether the
  /// landed action carried the `blade` family tag; [state] is the streak
  /// so far. The first blade hit in a chain adds `0` and starts the
  /// streak; each subsequent consecutive blade hit adds `+2 × (prior
  /// consecutive blade hits)`. The consumer resets to
  /// [BurstChainState.broken] on a miss or when the enemy acts.
  ({num bonus, BurstChainState state}) burstChainOnHit(
    BurstChainState state,
    bool isBladeHit,
  ) {
    if (!burstChain || !isBladeHit) return (bonus: 0, state: state);
    final bonus = state.streak > 0 ? state.streak * 2 : 0;
    return (bonus: bonus, state: BurstChainState(state.streak + 1));
  }
}

/// The per-fight state Kunlun Burst Chain needs — a count of consecutive
/// landed `blade` hits. Immutable; the consumer threads the returned
/// value forward and resets to [broken] on a miss or the enemy's turn.
class BurstChainState {
  const BurstChainState(this.streak);
  final int streak;

  /// The starting / reset state — no streak.
  static const broken = BurstChainState(0);
}
