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
    required this.martialTradition,
    required this.startingStyle,
    required this.combatOrTrainingChoices,
    required this.rewardChoices,
    required this.trainingChoices,
    required this.slotChoices,
    required this.replaceChoices,
    required this.upgradeSpendChoices,
    required this.tomeActionChoices,
  });

  final String martialTradition;
  final String startingStyle;
  final List<String> combatOrTrainingChoices;
  final List<int> rewardChoices;
  final List<String> trainingChoices;
  final List<SlotId> slotChoices;
  final List<bool> replaceChoices;
  final List<String> upgradeSpendChoices;
  final List<String> tomeActionChoices;
}

/// Wraps [inner], recording every decision it makes — `game_run.dart`
/// wraps whatever policy a caller supplies in one of these so every
/// `RunResult.decisionLog` reflects the decisions actually taken,
/// regardless of which concrete [RunDecisionPolicy] produced them.
class RecordingDecisionPolicy implements RunDecisionPolicy {
  RecordingDecisionPolicy(this.inner);

  final RunDecisionPolicy inner;

  String _martialTradition = MartialTraditions.western;
  String _startingStyle = MartialStyles.polearming;
  final List<String> _combatOrTrainingChoices = [];
  final List<int> _rewardChoices = [];
  final List<String> _trainingChoices = [];
  final List<SlotId> _slotChoices = [];
  final List<bool> _replaceChoices = [];
  final List<String> _upgradeSpendChoices = [];
  final List<String> _tomeActionChoices = [];

  @override
  String chooseMartialTradition(List<String> candidates) {
    final choice = inner.chooseMartialTradition(candidates);
    _martialTradition = choice;
    return choice;
  }

  @override
  String chooseStartingStyle(List<String> candidates) {
    final choice = inner.chooseStartingStyle(candidates);
    _startingStyle = choice;
    return choice;
  }

  @override
  String chooseCombatOrTraining(List<String> candidates) {
    final choice = inner.chooseCombatOrTraining(candidates);
    _combatOrTrainingChoices.add(choice);
    return choice;
  }

  @override
  int chooseReward(List<RewardKind> candidates) {
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

  @override
  String chooseUpgradeSpend(List<String> candidates) {
    final choice = inner.chooseUpgradeSpend(candidates);
    _upgradeSpendChoices.add(choice);
    return choice;
  }

  @override
  String chooseTomeAction(List<String> candidates) {
    final choice = inner.chooseTomeAction(candidates);
    _tomeActionChoices.add(choice);
    return choice;
  }

  /// Snapshots every decision recorded so far into an immutable
  /// [DecisionLog].
  DecisionLog toLog() => DecisionLog(
        martialTradition: _martialTradition,
        startingStyle: _startingStyle,
        combatOrTrainingChoices: List.unmodifiable(_combatOrTrainingChoices),
        rewardChoices: List.unmodifiable(_rewardChoices),
        trainingChoices: List.unmodifiable(_trainingChoices),
        slotChoices: List.unmodifiable(_slotChoices),
        replaceChoices: List.unmodifiable(_replaceChoices),
        upgradeSpendChoices: List.unmodifiable(_upgradeSpendChoices),
        tomeActionChoices: List.unmodifiable(_tomeActionChoices),
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

  var _combatOrTrainingIndex = 0;
  var _rewardIndex = 0;
  var _trainingIndex = 0;
  var _slotIndex = 0;
  var _replaceIndex = 0;
  var _upgradeSpendIndex = 0;
  var _tomeActionIndex = 0;

  @override
  String chooseMartialTradition(List<String> candidates) => log.martialTradition;

  @override
  String chooseStartingStyle(List<String> candidates) => log.startingStyle;

  @override
  String chooseCombatOrTraining(List<String> candidates) =>
      log.combatOrTrainingChoices[_combatOrTrainingIndex++];

  @override
  int chooseReward(List<RewardKind> candidates) => log.rewardChoices[_rewardIndex++];

  @override
  String chooseTrainingTarget(List<String> candidates) => log.trainingChoices[_trainingIndex++];

  @override
  SlotId chooseSlot(BuildComponentRef component, List<SlotId> candidateSlots) =>
      log.slotChoices[_slotIndex++];

  @override
  bool chooseReplace(SlotId slot, BuildComponentRef current, BuildComponentRef incoming) =>
      log.replaceChoices[_replaceIndex++];

  @override
  String chooseUpgradeSpend(List<String> candidates) => log.upgradeSpendChoices[_upgradeSpendIndex++];

  @override
  String chooseTomeAction(List<String> candidates) => log.tomeActionChoices[_tomeActionIndex++];
}

/// A plain, human-inspectable text encoding of a [DecisionLog] — one
/// `key: comma,separated,values` line per field — for persisting an
/// interactive session's decisions to a file so a later process (a
/// different `dart run` invocation, not just a later call in the same
/// one) can replay it via [loadDecisionLog].
String saveDecisionLog(DecisionLog log) {
  final buffer = StringBuffer()
    ..writeln('martialTradition: ${log.martialTradition}')
    ..writeln('startingStyle: ${log.startingStyle}')
    ..writeln('combatOrTrainingChoices: ${log.combatOrTrainingChoices.join(',')}')
    ..writeln('rewardChoices: ${log.rewardChoices.join(',')}')
    ..writeln('trainingChoices: ${log.trainingChoices.join(',')}')
    ..writeln('slotChoices: ${log.slotChoices.map((s) => s.id).join(',')}')
    ..writeln('replaceChoices: ${log.replaceChoices.join(',')}')
    ..writeln('upgradeSpendChoices: ${log.upgradeSpendChoices.join(',')}')
    ..writeln('tomeActionChoices: ${log.tomeActionChoices.join(',')}');
  return buffer.toString();
}

/// The inverse of [saveDecisionLog].
DecisionLog loadDecisionLog(String text) {
  final fields = <String, String>{};
  for (final line in text.split('\n')) {
    final separator = line.indexOf(': ');
    if (separator == -1) continue;
    fields[line.substring(0, separator)] = line.substring(separator + 2);
  }
  List<String> values(String key) {
    final raw = fields[key] ?? '';
    return raw.isEmpty ? const [] : raw.split(',');
  }

  return DecisionLog(
    martialTradition: fields['martialTradition'] ?? '',
    startingStyle: fields['startingStyle'] ?? '',
    combatOrTrainingChoices: values('combatOrTrainingChoices'),
    rewardChoices: [for (final v in values('rewardChoices')) int.parse(v)],
    trainingChoices: values('trainingChoices'),
    slotChoices: [for (final v in values('slotChoices')) SlotId(v)],
    replaceChoices: [for (final v in values('replaceChoices')) v == 'true'],
    upgradeSpendChoices: values('upgradeSpendChoices'),
    tomeActionChoices: values('tomeActionChoices'),
  );
}
