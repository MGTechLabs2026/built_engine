import 'package:build_engine/build_engine.dart';

/// Picks which of [candidates] (every other currently-alive participant in
/// the battle) to prioritize this turn — deliberately not "enemy"/"ally":
/// only content knows which actions attack versus assist, so this stays
/// neutral over all other living participants. Plugins implement this
/// directly, the same "no registry required" pattern `Condition`/`Effect`/
/// `CombatAction` already use.
abstract class TargetSelector {
  EntityId? selectTarget(EntityId actor, List<EntityId> candidates);
}

/// The initial, deliberately simple policy: always prioritize the first
/// candidate in whatever order it's given (participant order) —
/// deterministic, no ranking logic.
class FirstLivingParticipantTargetSelector implements TargetSelector {
  const FirstLivingParticipantTargetSelector();

  @override
  EntityId? selectTarget(EntityId actor, List<EntityId> candidates) =>
      candidates.isEmpty ? null : candidates.first;
}
