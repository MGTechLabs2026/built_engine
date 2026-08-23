import 'rng_service.dart';

/// Draws one item from [items] with probability proportional to
/// [weightOf] — the one weighted-random-pick algorithm shared by
/// `EvolutionResolver` and `RewardResolver` (previously two independent
/// copies of the identical cumulative-sum draw; see
/// `ARCHITECTURE_AUDIT.md`'s duplicate-engine-functionality finding).
///
/// Returns `null` if [items] is empty, or every weight sums to zero or
/// less — callers distinguish "nothing to choose from" from "nothing
/// chosen" however their own result type needs to. The sole source of
/// randomness is [rng.nextDouble()] — never `dart:math` directly, so a
/// draw stays reproducible from [rng]'s seed.
T? weightedPick<T>(List<T> items, num Function(T item) weightOf, RngService rng) {
  if (items.isEmpty) return null;
  final weights = [for (final item in items) weightOf(item)];
  final totalWeight = weights.fold<num>(0, (sum, weight) => sum + weight);
  if (totalWeight <= 0) return null;

  final roll = rng.nextDouble() * totalWeight;
  var cumulative = 0.0;
  for (var i = 0; i < items.length; i++) {
    cumulative += weights[i];
    if (roll < cumulative) return items[i];
  }
  // Floating-point edge case (roll landed exactly on the total): the
  // last item is the correct pick either way.
  return items.last;
}
