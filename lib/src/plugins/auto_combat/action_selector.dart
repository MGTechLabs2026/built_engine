import 'package:build_engine/build_engine.dart';
import 'package:build_engine/combat_plugin.dart';

/// Picks one action from [legalActions] (non-empty, already filtered to
/// the current actor's turn and to actions whose targets are all alive)
/// — [preferredTarget] is a hint from `TargetSelector`, `null` if none was
/// available. Plugins implement this directly, no registry.
abstract class ActionSelector {
  CombatAction selectAction(
    EntityId actor,
    List<CombatAction> legalActions,
    EntityId? preferredTarget,
  );
}

/// The initial, deliberately simple policy: prefers the first legal
/// action whose targets include [preferredTarget]; falls back to the
/// first legal action overall if none match (or no target was
/// preferred) — deterministic, no ranking/scoring logic.
class FirstMatchingActionSelector implements ActionSelector {
  const FirstMatchingActionSelector();

  @override
  CombatAction selectAction(
    EntityId actor,
    List<CombatAction> legalActions,
    EntityId? preferredTarget,
  ) {
    if (preferredTarget != null) {
      for (final action in legalActions) {
        if (action.targets.contains(preferredTarget)) return action;
      }
    }
    return legalActions.first;
  }
}
