import 'package:build_engine/build_engine.dart';

/// A learnable movement/ability's immutable, content-derived shape —
/// the third occurrence of the `MartialItemDefinition`/`ItemDefinition`
/// pattern. [tier] is a plain string from the existing `EvolutionTiers`
/// vocabulary (`basic`/`intermediate`/`advanced`/`master`) — no new tier
/// enum. [requirements] reuses `ContentDefinition.conditions` verbatim
/// (gates the LEARNING operation, not Tome placement — that's gated by
/// `isTechniqueLearned` instead). [evolutionCandidates] plus [tier]/[id]
/// are exactly what `EvolutionDefinition` needs — [toEvolutionDefinition]
/// builds one on demand rather than storing a redundant nested object.
/// [properties]/[modifiersFor] mirror `ItemDefinition`'s exact shape:
/// descriptive only, never auto-applied this pass (no combat action
/// interpretation yet).
class TechniqueDefinition {
  const TechniqueDefinition({
    required this.id,
    required this.name,
    required this.tier,
    required this.tags,
    required this.properties,
    this.requirements = const [],
    this.evolutionCandidates = const [],
    this.modifiersFor = _noModifiers,
  });

  final String id;
  final String name;
  final String tier;
  final Set<String> tags;
  final Map<String, num> properties;
  final List<Condition> requirements;
  final List<EvolutionCandidate> evolutionCandidates;
  final List<Modifier> Function(EntityId owner) modifiersFor;

  static List<Modifier> _noModifiers(EntityId owner) => const [];

  /// Builds the `EvolutionDefinition` this technique represents, for
  /// `EvolutionResolver.resolve` to consume — see `technique_evolution.dart`.
  EvolutionDefinition toEvolutionDefinition() =>
      EvolutionDefinition(id: id, tier: tier, candidates: evolutionCandidates);
}
