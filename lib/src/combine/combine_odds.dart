/// The pure fail/normal/rare odds for one Combine attempt, given the
/// shared `class` (tier) of the items being combined and how many items
/// are in the attempt. No randomness here — [CombineResolver] is what
/// actually rolls against these percentages.
///
/// Baseline (2 inputs) at tier `t`: `fail = min(10+(t-1)*10, 60)`,
/// `rare = max(15-(t-1)*2, 5)`, `normal` absorbs the remainder. Each
/// input beyond 2 nominally shifts 6 points off `fail` (4 to `normal`, 2
/// to `rare`); once `fail` would drop below its floor (5), the shortfall
/// is pulled back out of the `normal`/`rare` gains proportionally (2:1,
/// the same ratio as the per-item split) instead of just clamping `fail`
/// alone — this is what keeps the three summing to exactly 100 at every
/// input count, instead of overshooting past 100 once `fail` bottoms out.
/// See `docs/superpowers/specs/2026-08-24-item-combine-design.md`.
class CombineOdds {
  const CombineOdds({
    required this.failPercent,
    required this.normalPercent,
    required this.rarePercent,
  });

  final num failPercent;
  final num normalPercent;
  final num rarePercent;

  static CombineOdds forAttempt({required int tier, required int inputCount}) {
    final baseFail = (10 + (tier - 1) * 10).clamp(0, 60);
    final baseRare = (15 - (tier - 1) * 2).clamp(5, 100);
    final baseNormal = 100 - baseFail - baseRare;

    final extra = inputCount > 2 ? inputCount - 2 : 0;
    final nominalFail = baseFail - extra * 6;
    final fail = nominalFail < 5 ? 5 : nominalFail;
    final deficit = fail - nominalFail; // 0 until the floor is hit
    final nominalRare = baseRare + extra * 2;
    final rare = nominalRare - (deficit / 3).round();
    final normal = 100 - fail - rare; // absorbs any rounding remainder
    // silence "unused" for baseNormal, kept for readability of the derivation
    assert(baseNormal >= 0);

    return CombineOdds(failPercent: fail, normalPercent: normal, rarePercent: rare);
  }
}
