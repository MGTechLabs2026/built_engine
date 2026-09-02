import 'package:build_engine/build_engine.dart';

/// Published by `addTechniqueToTome` once a technique has actually been
/// inserted into [owner]'s Tome — the one new event this plugin adds, for
/// the same reason `ItemAddedToTome` was: `TomeService` has no `EventBus`
/// of its own to hook a "was inserted" event onto otherwise.
class TechniqueAddedToTome {
  const TechniqueAddedToTome(this.owner, this.definitionId, this.slot,
      {this.instanceId});

  final EntityId owner;
  final String definitionId;
  final SlotId slot;

  /// The technique-variant instance that was hung, if this placement
  /// carries one (SP0a onwards). `null` for a pre-instancing placement.
  final EntityId? instanceId;
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

/// Published by `mintTechniqueVariant` once a new technique-variant
/// instance entity exists for [owner]. Mirrors `ItemAddedToTome`'s
/// "TomeService has no EventBus of its own" reasoning for living here.
class TechniqueVariantMinted {
  const TechniqueVariantMinted(this.owner, this.instanceId, this.baseFamilyId);
  final EntityId owner;
  final EntityId instanceId;
  final String baseFamilyId;
}

/// Published by `removeTechniqueVariant` once the instance entity and its
/// per-instance state are gone.
class TechniqueVariantRemoved {
  const TechniqueVariantRemoved(this.owner, this.instanceId);
  final EntityId owner;
  final EntityId instanceId;
}

/// One training session inspired a new derived variant. Published exactly
/// once per discovery, from exactly one place —
/// `resolveTechniqueInspirationAfterTraining` — mirroring
/// `TechniqueEvolved`'s single-publisher discipline. Lineage / telemetry
/// / UI consumers subscribe from
/// `package:build_engine/technique_plugin.dart`. RNG internals and
/// intermediate scores are deliberately not exposed.
class TechniqueVariantInspired {
  const TechniqueVariantInspired({
    required this.owner,
    required this.instanceId,
    required this.familyId,
    required this.descriptorIds,
    required this.inspirerInstanceIds,
  });

  /// Owner of the newly minted variant.
  final EntityId owner;

  /// The freshly minted variant entity.
  final EntityId instanceId;

  /// Its base family (`== the trained family`).
  final String familyId;

  /// The descriptors selected for the new variant — lets a client name it.
  final Set<String> descriptorIds;

  /// The variants whose attributes *actually* caused the generated
  /// descriptor selection (`InspirationResult.inspirerInstanceIds`
  /// verbatim — spec §6.2 step 9). A **subset** of the eligible inspirers,
  /// ascending eligible-index order: an eligible variant that shaped no
  /// drawn descriptor is absent, so a client's "X + Y inspired this" is
  /// always truthful. Never "every eligible variant".
  final List<EntityId> inspirerInstanceIds;
}
