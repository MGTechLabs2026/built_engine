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
/// roll once against [CombineOdds] into fail/classUpgrade/gradeUpgrade.
/// Grade branching is delegated entirely to the existing
/// [EvolutionResolver] — this class knows nothing about what a "grade"
/// is, only that a `gradeUpgrade` roll may or may not have somewhere to go
/// (an [gradeEvolution] with no eligible candidates means it never does, and
/// the roll falls back to `classUpgrade`). Pure function of its inputs plus
/// [rng] — no stored state — mirroring [EvolutionResolver]'s own shape
/// exactly. Resource cost and the upfront "is this even attemptable"
/// terminal check are the caller's job (e.g. a content plugin's combine
/// entry point), not this class's.
class CombineResolver {
  const CombineResolver();

  CombineResult resolve({
    required List<CombineInput> inputs,
    required bool atMaxTierForGrade,
    required RuleContext gradeContext,
    required EvolutionDefinition gradeEvolution,
    required TrainingProfile gradeProfile,
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
            ? CombineOutcome.classUpgrade
            : CombineOutcome.gradeUpgrade;

    EvolutionResult? evolutionResult;
    if (outcome == CombineOutcome.gradeUpgrade) {
      evolutionResult = const EvolutionResolver().resolve(
        context: gradeContext,
        current: gradeEvolution,
        profile: gradeProfile,
      );
      if (!evolutionResult.evolved) {
        // No eligible grade branch right now -> falls back to a class
        // upgrade instead of wasting the attempt.
        outcome = CombineOutcome.classUpgrade;
      }
    }
    if (outcome == CombineOutcome.classUpgrade && atMaxTierForGrade) {
      // Nothing left to gain within this grade -> escalate to a grade
      // attempt. The caller guarantees this branch is only reachable when a
      // grade path IS eligible right now, so this resolve call should evolve.
      // If it doesn't (defensive against protocol violation), fall back to
      // classUpgrade to maintain invariant: gradeUpgrade only if
      // chosenGradeTargetId is non-null.
      evolutionResult = const EvolutionResolver().resolve(
        context: gradeContext,
        current: gradeEvolution,
        profile: gradeProfile,
      );
      if (evolutionResult.evolved) {
        outcome = CombineOutcome.gradeUpgrade;
      }
    }

    return CombineResult(
      outcome: outcome,
      survivorIndex: rng.nextInt(inputs.length),
      chosenGradeTargetId: evolutionResult?.chosenCandidate?.targetId,
    );
  }
}
