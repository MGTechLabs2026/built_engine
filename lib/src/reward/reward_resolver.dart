import '../rng/rng_service.dart';
import '../rng/weighted_pick.dart';
import 'reward_candidate.dart';
import 'reward_definition.dart';
import 'reward_result.dart';

/// Resolves a [RewardDefinition]'s weighted candidates into a
/// [RewardResult] — a pure function of its inputs (no stored state of its
/// own), mirroring `BuildResolver`/`EvolutionResolver`'s own "pure
/// resolver" shape.
///
/// Draws only from the injected [RngService] — the sole source of
/// randomness, never a second random system — via the shared
/// [weightedPick] helper `EvolutionResolver` also uses.
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
    final rewards = <RewardCandidate>[];
    for (var i = 0; i < rollCount; i++) {
      final chosen = weightedPick(definition.candidates, (c) => c.weight, rng);
      if (chosen != null) rewards.add(chosen);
    }
    return RewardResult(definitionId: definition.id, rewards: rewards);
  }
}
