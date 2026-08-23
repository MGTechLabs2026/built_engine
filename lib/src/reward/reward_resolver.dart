import '../rng/rng_service.dart';
import 'reward_candidate.dart';
import 'reward_definition.dart';
import 'reward_result.dart';

/// Resolves a [RewardDefinition]'s weighted candidates into a
/// [RewardResult] — a pure function of its inputs (no stored state of its
/// own), mirroring `BuildResolver`/`EvolutionResolver`'s own "pure
/// resolver" shape.
///
/// Draws only from the injected [RngService] — the sole source of
/// randomness, never a second random system — via the same weighted
/// cumulative-sum pick `EvolutionResolver` already uses.
class RewardResolver {
  const RewardResolver();

  /// Draws [rollCount] independent rewards (with replacement — the same
  /// candidate can be drawn more than once) from [definition]. Each draw
  /// is empty-safe: an empty candidate list, or candidates whose weights
  /// sum to zero or less, contribute no rewards rather than throwing.
  RewardResult resolve({
    required RngService rng,
    required RewardDefinition definition,
    int rollCount = 1,
  }) {
    final totalWeight =
        definition.candidates.fold<num>(0, (sum, candidate) => sum + candidate.weight);
    if (totalWeight <= 0) {
      return RewardResult(definitionId: definition.id, rewards: const []);
    }
    return RewardResult(
      definitionId: definition.id,
      rewards: [
        for (var i = 0; i < rollCount; i++) _weightedPick(definition.candidates, totalWeight, rng),
      ],
    );
  }

  RewardCandidate _weightedPick(
    List<RewardCandidate> candidates,
    num totalWeight,
    RngService rng,
  ) {
    final roll = rng.nextDouble() * totalWeight;
    var cumulative = 0.0;
    for (final candidate in candidates) {
      cumulative += candidate.weight;
      if (roll < cumulative) return candidate;
    }
    // Floating-point edge case (roll landed exactly on the total): the
    // last candidate is the correct pick either way.
    return candidates.last;
  }
}
