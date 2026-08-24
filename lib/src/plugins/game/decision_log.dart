import 'package:build_engine/build_engine.dart';
import 'package:build_engine/martial_arts_plugin.dart';

import 'run_decision_policy.dart';

/// A deterministic record of every decision an actual `runGame` call
/// made — the milestone's own "seed + player decisions... must reproduce
/// the run." Plain data, in the exact order [RunDecisionPolicy]'s methods
/// were called, so [ReplayDecisionPolicy] can feed the same answers back
/// in the same order.
class DecisionLog {
  const DecisionLog({
    required this.startingStyle,
    required this.rewardChoices,
    required this.trainingChoices,
    required this.slotChoices,
    required this.replaceChoices,
  });

  final String startingStyle;
  final List<int> rewardChoices;
  final List<String> trainingChoices;
  final List<SlotId> slotChoices;
  final List<bool> replaceChoices;
}

/// Wraps [inner], recording every decision it makes — `game_run.dart`
/// wraps whatever policy a caller supplies in one of these so every
/// `RunResult.decisionLog` reflects the decisions actually taken,
/// regardless of which concrete [RunDecisionPolicy] produced them.
class RecordingDecisionPolicy implements RunDecisionPolicy {
  RecordingDecisionPolicy(this.inner);

  final RunDecisionPolicy inner;

  String _startingStyle = MartialStyles.boxing;
  final List<int> _rewardChoices = [];
  final List<String> _trainingChoices = [];
  final List<SlotId> _slotChoices = [];
  final List<bool> _replaceChoices = [];

  @override
  String chooseStartingStyle(List<String> candidates) {
    final choice = inner.chooseStartingStyle(candidates);
    _startingStyle = choice;
    return choice;
  }

  @override
  int chooseReward(List<BuildComponentRef> candidates) {
    final choice = inner.chooseReward(candidates);
    _rewardChoices.add(choice);
    return choice;
  }

  @override
  String chooseTrainingTarget(List<String> candidates) {
    final choice = inner.chooseTrainingTarget(candidates);
    _trainingChoices.add(choice);
    return choice;
  }

  @override
  SlotId chooseSlot(BuildComponentRef component, List<SlotId> candidateSlots) {
    final choice = inner.chooseSlot(component, candidateSlots);
    _slotChoices.add(choice);
    return choice;
  }

  @override
  bool chooseReplace(SlotId slot, BuildComponentRef current, BuildComponentRef incoming) {
    final choice = inner.chooseReplace(slot, current, incoming);
    _replaceChoices.add(choice);
    return choice;
  }

  /// Snapshots every decision recorded so far into an immutable
  /// [DecisionLog].
  DecisionLog toLog() => DecisionLog(
        startingStyle: _startingStyle,
        rewardChoices: List.unmodifiable(_rewardChoices),
        trainingChoices: List.unmodifiable(_trainingChoices),
        slotChoices: List.unmodifiable(_slotChoices),
        replaceChoices: List.unmodifiable(_replaceChoices),
      );
}

/// Replays a previously-recorded [DecisionLog] instead of deciding
/// anything itself — feeding `runGame(sameSeed, policy:
/// ReplayDecisionPolicy(previousResult.decisionLog))` reproduces the
/// exact same run `previousResult` came from, proving "seed + decisions"
/// (not "seed" alone) determines the outcome.
class ReplayDecisionPolicy implements RunDecisionPolicy {
  ReplayDecisionPolicy(this.log);

  final DecisionLog log;

  var _rewardIndex = 0;
  var _trainingIndex = 0;
  var _slotIndex = 0;
  var _replaceIndex = 0;

  @override
  String chooseStartingStyle(List<String> candidates) => log.startingStyle;

  @override
  int chooseReward(List<BuildComponentRef> candidates) => log.rewardChoices[_rewardIndex++];

  @override
  String chooseTrainingTarget(List<String> candidates) => log.trainingChoices[_trainingIndex++];

  @override
  SlotId chooseSlot(BuildComponentRef component, List<SlotId> candidateSlots) =>
      log.slotChoices[_slotIndex++];

  @override
  bool chooseReplace(SlotId slot, BuildComponentRef current, BuildComponentRef incoming) =>
      log.replaceChoices[_replaceIndex++];
}
