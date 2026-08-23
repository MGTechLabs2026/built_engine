import '../rule/condition.dart';

/// One possible branch out of an [EvolutionDefinition] — e.g. one of
/// several forms a technique/item/style could evolve into. Deliberately
/// carries no name/flavor — [targetId] is an opaque reference to another
/// `EvolutionDefinition.id`, resolved by whatever content registry a
/// plugin keeps; `EvolutionResolver` never looks it up itself.
class EvolutionCandidate {
  const EvolutionCandidate({
    required this.targetId,
    this.tags = const {},
    this.conditions = const [],
  });

  final String targetId;

  /// Matched against `TrainingProfile.dimensions` keys to weight this
  /// candidate's selection likelihood — e.g. `{'speed'}` makes a
  /// high-speed trainee more likely to draw this candidate. Opaque to
  /// Core; a plugin picks whatever tag vocabulary it likes.
  final Set<String> tags;

  /// Eligibility gate — every condition must pass (the existing `Rule`
  /// AND-all-conditions convention) for this candidate to even be
  /// considered. An empty list is always eligible.
  final List<Condition> conditions;
}
