import 'package:build_engine/build_engine.dart';

import 'technique_definition.dart';

/// Resolves [technique]'s evolution candidates for [owner], weighted by
/// [profile] — a thin, discoverable wrapper over the existing
/// `EvolutionResolver`, which already does everything this milestone asks
/// for (candidate eligibility via `Condition`, weighting via
/// `TrainingProfile`-tag-matched `Modifier`s, the final draw via
/// `context.rng`). No new resolution logic lives here — see
/// `EvolutionResolver` itself for the mechanism. Never called
/// automatically by `attemptToLearnTechnique`; evolution stays an
/// explicit, separate operation the caller invokes when ready.
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
