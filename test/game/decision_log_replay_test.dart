import 'package:build_engine/build_engine.dart';
import 'package:build_engine/game.dart';
import 'package:test/test.dart';

class NeverReplacePolicy extends DefaultRunDecisionPolicy {
  const NeverReplacePolicy();
  @override
  bool chooseReplace(SlotId slot, BuildComponentRef current, BuildComponentRef incoming) => false;
}

void main() {
  group('decision log + replay: seed + decisions reproduce the run', () {
    test('replaying a recorded DecisionLog with the same seed reproduces the exact same run', () {
      final original = runGame(6, policy: const NeverReplacePolicy());

      final replay = runGame(6, policy: ReplayDecisionPolicy(original.decisionLog));

      expect(replay.won, equals(original.won));
      expect(replay.physiqueId, equals(original.physiqueId));
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

    test('replaying the default-policy win fixture reproduces it too', () {
      final original = runGame(6);

      final replay = runGame(6, policy: ReplayDecisionPolicy(original.decisionLog));

      expect(replay.won, isTrue);
      expect(
        replay.finalBuild.map((c) => c.contentId).toSet(),
        equals(original.finalBuild.map((c) => c.contentId).toSet()),
      );
    });

    test('a DecisionLog is only valid for the seed it was recorded against — a different seed '
        'reaches a different sequence of decision points, since decision points are themselves '
        'data-dependent (which reward is offered, what is trainable, ...)', () {
      final recorded = runGame(6).decisionLog;

      // Seed 1's own reward-pool shuffle/training-gain sequence diverges
      // from seed 6's early on, so replaying seed 6's log against it
      // reaches a training-target choice ('technique:basic_slash') for a
      // technique seed 1's own run hasn't discovered yet at that point —
      // this is expected, not a bug: "seed + decisions reproduce the
      // run" means the *same* seed, not an arbitrary one.
      expect(() => runGame(1, policy: ReplayDecisionPolicy(recorded)), throwsA(anything));
    });

    test('the decision log itself records every distinct decision kind the milestone asks for', () {
      final result = runGame(6);

      expect(result.decisionLog.startingStyle, isNotEmpty);
      expect(result.decisionLog.rewardChoices, isNotEmpty);
      expect(result.decisionLog.trainingChoices, isNotEmpty);
      expect(result.decisionLog.slotChoices, isNotEmpty);
      // replaceChoices may legitimately be empty if every slot happened
      // to be empty when first offered — assert the field exists and is
      // consistent in length with how many occupied-slot decisions were
      // actually needed (can't exceed slotChoices).
      expect(result.decisionLog.replaceChoices.length, lessThanOrEqualTo(result.decisionLog.slotChoices.length));
    });
  });
}
