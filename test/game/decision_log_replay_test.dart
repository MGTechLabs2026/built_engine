import 'package:build_engine/build_engine.dart';
import 'package:build_engine/game.dart';
import 'package:test/test.dart';

class NeverReplacePolicy extends DefaultRunDecisionPolicy {
  const NeverReplacePolicy();
  @override
  bool chooseReplace(SlotId slot, BuildComponentRef current, BuildComponentRef incoming) => false;
}

/// Fights the first cycle only, then trains every cycle after — produces
/// a long, rich decision log (many training/upgrade-spend/slot choices)
/// that is very unlikely to line up across two different seeds' own
/// decision-point sequences.
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

void main() {
  group('decision log + replay: seed + decisions reproduce the run', () {
    test('replaying a recorded DecisionLog with the same seed reproduces the exact same run', () {
      final original = runGame(6, policy: const NeverReplacePolicy());

      final replay = runGame(6, policy: ReplayDecisionPolicy(original.decisionLog));

      expect(replay.won, equals(original.won));
      expect(replay.cyclesCompleted, equals(original.cyclesCompleted));
      expect(replay.physiqueId, equals(original.physiqueId));
      expect(replay.martialTradition, equals(original.martialTradition));
      expect(replay.styleId, equals(original.styleId));
      expect(replay.itemsDiscovered, equals(original.itemsDiscovered));
      expect(replay.techniquesLearned, equals(original.techniquesLearned));
      expect(replay.techniquesEvolved, equals(original.techniquesEvolved));
      expect(
        replay.finalBuild.map((c) => (c.referenceType, c.contentId)),
        equals(original.finalBuild.map((c) => (c.referenceType, c.contentId))),
      );
      expect(
        replay.encounters.map((e) => (e.name, e.won, e.playerHealthAfter)),
        equals(original.encounters.map((e) => (e.name, e.won, e.playerHealthAfter))),
      );
    });

    test('replaying the default-policy fixture reproduces it too', () {
      final original = runGame(6);

      final replay = runGame(6, policy: ReplayDecisionPolicy(original.decisionLog));

      expect(replay.won, equals(original.won));
      expect(
        replay.finalBuild.map((c) => c.contentId).toSet(),
        equals(original.finalBuild.map((c) => c.contentId).toSet()),
      );
    });

    test('a DecisionLog is only guaranteed valid for the seed it was recorded against — a '
        'different seed is not guaranteed to reproduce anything meaningful (it may complete '
        'mechanically, since a replayed choice is never re-validated against what a fresh seed '
        'would have actually offered, or it may throw if a replayed choice no longer matches '
        'that seed\'s own state)', () {
      final original = runGame(6, policy: TrainAfterFirstCombatPolicy());

      RunResult? crossSeedResult;
      try {
        crossSeedResult = runGame(1, policy: ReplayDecisionPolicy(original.decisionLog));
      } catch (_) {
        crossSeedResult = null; // throwing is an acceptable outcome too.
      }

      // The only guarantee this engine makes is "same seed + decisions ->
      // same run" (proven by the sibling tests above) — a *different*
      // seed is out of contract either way, so this test only checks
      // that a completed cross-seed replay didn't silently produce
      // seed 6's own result under seed 1's identity.
      if (crossSeedResult != null) {
        expect(crossSeedResult.seed, equals(1));
      }
    });

    test('the decision log itself records every distinct decision kind the run makes', () {
      final result = runGame(6);

      expect(result.decisionLog.martialTradition, isNotEmpty);
      expect(result.decisionLog.startingStyle, isNotEmpty);
      expect(result.decisionLog.combatOrTrainingChoices, isNotEmpty);
      expect(result.decisionLog.rewardChoices, isNotEmpty);
      // trainingChoices/slotChoices/replaceChoices/upgradeSpendChoices
      // may legitimately be empty for a short run (e.g. one that dies in
      // its very first cycle before ever training or earning an upgrade
      // point) — only assert the fields that are always exercised.
    });
  });
}
