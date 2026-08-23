import '../tome/build_component_ref.dart';

/// One weighted possibility in a [RewardDefinition] — [ref] reuses the
/// same opaque content-reference shape the Tome/Build system already
/// established (item, technique, currency, consumable, trinket, or
/// anything else a plugin invents; Core never interprets it), rather than
/// a duplicate reward-specific reference type.
class RewardCandidate {
  const RewardCandidate({required this.ref, required this.weight});

  final BuildComponentRef ref;

  /// A plain, static weight — this candidate's share of the total when
  /// [RewardResolver] draws from a [RewardDefinition]. Not affected by any
  /// external profile/state; unlike `EvolutionCandidate`, no dynamic
  /// per-call weighting was requested for this system.
  final num weight;
}
