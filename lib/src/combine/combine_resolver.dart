// lib/src/combine/combine_resolver.dart
import '../evolution/evolution_definition.dart';
import '../evolution/evolution_resolver.dart';
import '../evolution/evolution_result.dart';
import '../rng/rng_service.dart';
import '../rule/rule_context.dart';
import '../training/training_profile.dart';
import 'combine_exceptions.dart';
import 'combine_input.dart';
import 'combine_odds.dart';
import 'combine_outcome.dart';
import 'combine_result.dart';

/// The generic Combine resolver: N same-`matchKey`/same-`tier` [inputs]
/// roll once against [CombineOdds] into fail/tierUpgrade/branchUpgrade.
/// Branch selection is delegated entirely to the existing
/// [EvolutionResolver] — this class knows nothing about what a "branch"
/// is, only that a `branchUpgrade` roll may or may not have somewhere to
/// go (a [branchDefinition] with no eligible candidates means it never
/// does, and the roll falls back to `tierUpgrade`). Pure function of its
/// inputs plus [rng] — no stored state — mirroring [EvolutionResolver]'s
/// own shape exactly. Resource cost and the upfront "is this even
/// attemptable" terminal check are the caller's job (e.g. a content
/// plugin's combine entry point), not this class's.
class CombineResolver {
  const CombineResolver();

  CombineResult resolve({
    required List<CombineInput> inputs,
    required bool atMaxTierForBranch,
    required RuleContext branchContext,
    required EvolutionDefinition branchDefinition,
    required TrainingProfile branchProfile,
    required RngService rng,
  }) {
    if (inputs.length < 2) {
      throw ArgumentError.value(
        inputs.length, 'inputs', 'Combine requires at least 2 inputs');
    }
    final first = inputs.first;
    for (final input in inputs.skip(1)) {
      if (input.matchKey != first.matchKey || input.tier != first.tier) {
        throw CombineMismatchException(first, input);
      }
    }

    final odds = CombineOdds.forAttempt(tier: first.tier, inputCount: inputs.length);
    final roll = rng.nextDouble() * 100;
    var outcome = roll < odds.failPercent
        ? CombineOutcome.fail
        : roll < odds.failPercent + odds.normalPercent
            ? CombineOutcome.tierUpgrade
            : CombineOutcome.branchUpgrade;

    EvolutionResult? evolutionResult;
    if (outcome == CombineOutcome.branchUpgrade) {
      evolutionResult = const EvolutionResolver().resolve(
        context: branchContext,
        current: branchDefinition,
        profile: branchProfile,
      );
      if (!evolutionResult.evolved) {
        // No eligible branch right now -> falls back to a tier upgrade
        // instead of wasting the attempt.
        outcome = CombineOutcome.tierUpgrade;
      }
    }
    if (outcome == CombineOutcome.tierUpgrade && atMaxTierForBranch) {
      // Nothing left to gain within this branch -> escalate to a branch
      // attempt. The caller guarantees this branch is only reachable when a
      // branch path IS eligible right now, so this resolve call should evolve.
      // If it doesn't (defensive against protocol violation), fall back to
      // tierUpgrade to maintain invariant: branchUpgrade only if
      // chosenBranchTargetId is non-null.
      evolutionResult = const EvolutionResolver().resolve(
        context: branchContext,
        current: branchDefinition,
        profile: branchProfile,
      );
      if (evolutionResult.evolved) {
        outcome = CombineOutcome.branchUpgrade;
      }
    }

    return CombineResult(
      outcome: outcome,
      survivorIndex: rng.nextInt(inputs.length),
      chosenBranchTargetId: evolutionResult?.chosenCandidate?.targetId,
    );
  }
}
