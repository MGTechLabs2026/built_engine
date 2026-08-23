import '../entity/entity_id.dart';
import '../modifier/modifier.dart';
import '../modifier/modifier_resolver.dart';
import '../modifier/modifier_source.dart';
import '../rng/weighted_pick.dart';
import '../rule/rule_context.dart';
import '../training/training_profile.dart';
import 'evolution_candidate.dart';
import 'evolution_definition.dart';
import 'evolution_result.dart';

/// Placeholder `Modifier.target`/`.source`/`.stat` for the ad-hoc weight
/// modifiers `EvolutionResolver` builds — `ModifierResolver.resolve` never
/// reads any of these three fields (only `operation`/`value`/`priority`
/// matter to it), so these values exist purely for readability, not
/// because anything consumes them.
const _weightModifierSource = ModifierSource('evolution_weight');
const _weightModifierTarget = EntityId(0);
const _weightStat = 'evolution_weight';

/// Resolves an [EvolutionDefinition]'s candidates into an [EvolutionResult]
/// — a pure function of its inputs (no stored state of its own), mirroring
/// `BuildResolver`/`ModifierResolver`'s own "pure resolver" shape.
///
/// Reuses existing infrastructure throughout rather than inventing new
/// machinery: candidate eligibility is the real `Condition` interface
/// (evaluated against the [RuleContext] the caller already has, e.g. via
/// `PluginContext.ruleContextFor(trainee)` — [RuleContext.subject] must be
/// the trainee for those conditions to gate correctly); candidate weight
/// is computed by feeding ad-hoc `Modifier`s through the real
/// `ModifierResolver`, one multiply modifier per tag a candidate shares
/// with the `TrainingProfile`'s dimensions; the final weighted pick draws
/// from `context.rng` — the sole source of randomness, never a second
/// random system.
class EvolutionResolver {
  const EvolutionResolver();

  EvolutionResult resolve({
    required RuleContext context,
    required EvolutionDefinition current,
    required TrainingProfile profile,
  }) {
    final eligible = [
      for (final candidate in current.candidates)
        if (candidate.conditions.every((condition) => condition.evaluate(context)))
          candidate,
    ];
    if (eligible.isEmpty) {
      return EvolutionResult(
        fromId: current.id,
        chosenCandidate: null,
        eligibleCandidates: const [],
      );
    }

    final chosen = weightedPick(
      eligible,
      (candidate) => _weightOf(candidate, profile),
      context.rng,
    );
    return EvolutionResult(
      fromId: current.id,
      chosenCandidate: chosen,
      eligibleCandidates: eligible,
    );
  }

  num _weightOf(EvolutionCandidate candidate, TrainingProfile profile) {
    final modifiers = [
      for (final tag in candidate.tags)
        if (profile.dimensions.containsKey(tag))
          Modifier(
            source: _weightModifierSource,
            target: _weightModifierTarget,
            stat: _weightStat,
            operation: ModifierOperation.multiply,
            value: 1 + profile.dimensions[tag]!,
          ),
    ];
    return const ModifierResolver().resolve(1.0, modifiers);
  }
}
