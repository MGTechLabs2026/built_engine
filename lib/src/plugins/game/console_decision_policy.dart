import 'dart:io';

import 'package:build_engine/build_engine.dart';

import 'run_decision_policy.dart';

/// A [RunDecisionPolicy] that asks for each decision over a line-based
/// text protocol — print a prompt, read a line back. Anything that can
/// write lines to this process's stdin and read its stdout can drive a
/// run this way: a person typing at a real terminal, or an LLM/script
/// piping answers into the process. Not a UI — no rendering, no state
/// beyond the prompt/answer exchange itself.
///
/// [print]/[readLine] are injectable (default to real stdout/stdin) so
/// this stays testable without a real terminal, and so a non-stdio
/// driver (e.g. answers queued up ahead of time) can reuse the same
/// prompt/parsing logic.
///
/// If [readLine] ever returns `null` (stdin closed, or a scripted answer
/// source has run out), every remaining decision falls back to the same
/// default `DefaultRunDecisionPolicy` uses — first candidate, always
/// replace — so a run started interactively still always completes.
class ConsoleDecisionPolicy implements RunDecisionPolicy {
  ConsoleDecisionPolicy({
    void Function(String line)? print,
    String? Function()? readLine,
  })  : _print = print ?? _defaultPrint,
        _readLine = readLine ?? _defaultReadLine;

  final void Function(String line) _print;
  final String? Function() _readLine;

  static void _defaultPrint(String line) => stdout.writeln(line);
  static String? _defaultReadLine() => stdin.readLineSync();

  @override
  String chooseMartialTradition(List<String> candidates) {
    _print('\n=== Choose your martial tradition ===');
    return candidates[_promptIndex(candidates)];
  }

  @override
  String chooseStartingStyle(List<String> candidates) {
    _print('\n=== Choose your starting martial style ===');
    return candidates[_promptIndex(candidates)];
  }

  @override
  String chooseCombatOrTraining(List<String> candidates) {
    _print('\n=== Combat or training this cycle? ===');
    return candidates[_promptIndex(candidates)];
  }

  @override
  int chooseReward(List<RewardKind> candidates) {
    _print('\n=== Choose a reward ===');
    return _promptIndex([for (final c in candidates) _rewardLabel(c)]);
  }

  String _rewardLabel(RewardKind kind) => switch (kind) {
        RewardKind.unlockSlot => 'Unlock a new Tome slot',
        RewardKind.itemOrTechnique => 'Random item or technique',
        RewardKind.upgradePoint => '+1 upgrade point',
      };

  @override
  String chooseTrainingTarget(List<String> candidates) {
    _print('\n=== Choose what to train ===');
    return candidates[_promptIndex(candidates)];
  }

  @override
  SlotId chooseSlot(BuildComponentRef component, List<SlotId> candidateSlots) {
    _print('\n=== Choose a Tome slot for ${component.referenceType}:${component.contentId} ===');
    final chosen = _promptIndex([for (final s in candidateSlots) s.id]);
    return candidateSlots[chosen];
  }

  @override
  bool chooseReplace(SlotId slot, BuildComponentRef current, BuildComponentRef incoming) {
    _print(
      '\n=== Slot ${slot.id} is occupied by ${current.referenceType}:${current.contentId}. '
      'Replace with ${incoming.referenceType}:${incoming.contentId}? ===',
    );
    return _promptYesNo();
  }

  @override
  String chooseUpgradeSpend(List<String> candidates) {
    _print('\n=== Spend an upgrade point? ===');
    return candidates[_promptIndex(candidates)];
  }

  int _promptIndex(List<String> labels) {
    for (var i = 0; i < labels.length; i++) {
      _print('  [$i] ${labels[i]}');
    }
    while (true) {
      _print('> ');
      final line = _readLine()?.trim();
      if (line == null) return 0;
      final asIndex = int.tryParse(line);
      if (asIndex != null && asIndex >= 0 && asIndex < labels.length) return asIndex;
      final byLabel = labels.indexWhere((l) => l.toLowerCase() == line.toLowerCase());
      if (byLabel != -1) return byLabel;
      _print('Not a valid choice: "$line". Enter a number 0-${labels.length - 1}, or the exact label.');
    }
  }

  bool _promptYesNo() {
    while (true) {
      _print('  [y] yes   [n] no');
      _print('> ');
      final line = _readLine()?.trim().toLowerCase();
      if (line == null) return true;
      if (line == 'y' || line == 'yes') return true;
      if (line == 'n' || line == 'no') return false;
      _print('Not a valid choice: "$line". Enter y or n.');
    }
  }
}
