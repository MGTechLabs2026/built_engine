import 'package:build_engine/build_engine.dart';

/// Published by `addTechniqueToTome` once a technique has actually been
/// inserted into [owner]'s Tome — the one new event this plugin adds, for
/// the same reason `ItemAddedToTome` was: `TomeService` has no `EventBus`
/// of its own to hook a "was inserted" event onto otherwise.
class TechniqueAddedToTome {
  const TechniqueAddedToTome(this.owner, this.definitionId, this.slot);

  final EntityId owner;
  final String definitionId;
  final SlotId slot;
}

/// One technique successfully evolved into another — the terminal step of
/// the discover → learn → (mastery) → evolve lifecycle. Published on
/// `context.events` **exactly once per successful evolution, from exactly
/// one place**: [resolveTechniqueEvolutionAfterTraining]. No composition
/// layer (neither `TrainingStage` in the headless harness nor the client's
/// `TrainingAdapter`) publishes it independently any more — they call that
/// one function and react to the event like any other subscriber.
/// `evolveTechnique` itself is a pure resolver and never publishes.
///
/// A Technique-domain event: it names two technique definition ids and
/// nothing about any particular run, so it lives with the Technique
/// plugin. Lineage / telemetry consumers subscribe to it from
/// `package:build_engine/technique_plugin.dart`.
class TechniqueEvolved {
  const TechniqueEvolved({required this.fromId, required this.toId});

  /// The definition id of the technique that was trained.
  final String fromId;

  /// The definition id of the evolved technique it became.
  final String toId;
}
