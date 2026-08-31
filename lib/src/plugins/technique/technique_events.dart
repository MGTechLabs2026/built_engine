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
/// the discover → learn → (mastery) → evolve lifecycle. Published on the
/// caller-supplied `EventBus` exactly once per successful evolution, by
/// whoever drives training to that point (`TrainingStage` in `runGame`;
/// an equivalent caller in an embedding client). `evolveTechnique`
/// itself is a pure resolver and never publishes.
///
/// A Technique-domain event: it names two technique definition ids and
/// nothing about any particular run, so it lives with the Technique
/// plugin rather than the game-run composition layer even though
/// `runGame` is one of its publishers. Lineage / telemetry consumers
/// subscribe to it from `package:build_engine/technique_plugin.dart`.
class TechniqueEvolved {
  const TechniqueEvolved({required this.fromId, required this.toId});

  /// The definition id of the technique that was trained.
  final String fromId;

  /// The definition id of the evolved technique it became.
  final String toId;
}
