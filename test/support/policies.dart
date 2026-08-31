/// Shared `RunDecisionPolicy` implementations for game-run tests, so the
/// same helper isn't re-declared in every file that drives `runGame`.
library;

import 'package:build_engine/build_engine.dart';
import 'package:build_engine/game.dart';

/// Never replaces an occupied Tome slot — proves player decisions (not
/// just the seed) shape the final build.
class NeverReplacePolicy extends DefaultRunDecisionPolicy {
  const NeverReplacePolicy();

  @override
  bool chooseReplace(
    SlotId slot,
    BuildComponentRef current,
    BuildComponentRef incoming,
  ) =>
      false;
}

/// Fights cycle 1 (a training cycle before any reward has been granted
/// has nothing to train on), then trains every cycle after — exercises
/// learning / mastery / evolution across many sessions without fighting
/// the run's own combat difficulty. `DefaultRunDecisionPolicy` always
/// picks `'combat'` and so never trains on its own.
class TrainAfterFirstCombatPolicy extends DefaultRunDecisionPolicy {
  var _cycle = 0;

  @override
  String chooseCombatOrTraining(List<String> candidates) {
    _cycle++;
    return _cycle == 1 ? 'combat' : 'training';
  }

  @override
  int chooseReward(List<RewardKind> candidates) {
    final index = candidates.indexOf(RewardKind.itemOrTechnique);
    return index == -1 ? 0 : index;
  }
}
