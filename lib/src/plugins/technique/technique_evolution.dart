import 'package:build_engine/build_engine.dart';

import 'technique_definition.dart';
import 'technique_events.dart';
import 'technique_lifecycle.dart';

/// Resolves [technique]'s evolution candidates for [owner], weighted by
/// [profile] — a thin, discoverable wrapper over the existing
/// `EvolutionResolver`, which already does everything this milestone asks
/// for (candidate eligibility via `Condition`, weighting via
/// `TrainingProfile`-tag-matched `Modifier`s, the final draw via
/// `context.rng`). No new resolution logic lives here — see
/// `EvolutionResolver` itself for the mechanism. Pure: never publishes an
/// event, never mutates state. Prefer [resolveTechniqueEvolutionAfterTraining]
/// for the normal post-training flow — call this directly only when you
/// need the raw resolver draw without the eligibility gate or the event.
EvolutionResult evolveTechnique(
  EntityId owner,
  TechniqueDefinition technique,
  TrainingProfile profile,
  PluginContext context,
) =>
    const EvolutionResolver().resolve(
      context: context.ruleContextFor(owner),
      current: technique.toEvolutionDefinition(),
      profile: profile,
    );

/// **The one authoritative "did training just evolve this technique?"
/// step.** Call this once after a training session whose gain was applied
/// via [attemptToLearnTechnique], passing that session's [profile].
///
/// It owns the whole evolution *policy* so no composition layer restates
/// it:
///
///   1. No-ops (returns an [EvolutionResult] with `evolved == false`)
///      unless [technique] is now [isTechniqueLearned] **and** has at
///      least one [TechniqueDefinition.evolutionCandidates] entry.
///   2. Otherwise runs the pure [evolveTechnique] resolver against
///      [profile] — one `context.rng` draw when candidates are eligible,
///      so a given seed still reproduces the same outcome.
///   3. On a successful evolution, publishes [TechniqueEvolved] on
///      `context.events` **exactly once** — the sole publisher of that
///      domain event.
///
/// The caller keeps its own caller-specific follow-up (moving the evolved
/// form into the Tome slot, recording discovery / telemetry) — but the
/// decision and the event are decided here, in the Technique domain, not
/// in `TrainingStage` and the client's `TrainingAdapter` independently.
EvolutionResult resolveTechniqueEvolutionAfterTraining(
  EntityId owner,
  TechniqueDefinition technique,
  TrainingProfile profile,
  PluginContext context,
) {
  if (!isTechniqueLearned(owner, technique, context) ||
      technique.evolutionCandidates.isEmpty) {
    return EvolutionResult(
      fromId: technique.id,
      chosenCandidate: null,
      eligibleCandidates: const [],
    );
  }
  final result = evolveTechnique(owner, technique, profile, context);
  if (result.evolved) {
    context.events.publish(
      TechniqueEvolved(
        fromId: technique.id,
        toId: result.chosenCandidate!.targetId,
      ),
    );
  }
  return result;
}
