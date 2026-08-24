import 'package:build_engine/physique_plugin.dart';
import 'package:test/test.dart';

import 'support/vertical_slice_runner.dart';

/// The complete gameplay loop — see `support/vertical_slice_runner.dart`
/// for the full 14-step RUN this exercises headlessly (Character,
/// Physique, Discovery, Mastery, Tome, Training, Evolution, Reward,
/// Combat, AutoCombat, RngService, Modifiers, plus the real
/// `MartialArtsPlugin`/`learnStyle` for styles).
void main() {
  group('vertical slice: the complete gameplay loop', () {
    test('newRun -> characterCreated -> physiqueAssigned -> '
        'startingContentGiven -> tomeBuilt -> activeBuildResolved -> '
        'combatStarted -> combatResolved -> rewardGranted -> '
        'itemDiscovered -> itemTrained -> masteryIncreased -> '
        'evolutionResolved -> tomeRebuilt -> secondCombatStarted -> '
        'secondCombatResolved', () {
      final outcome = runVerticalSlice(1);

      expect(
        outcome.log,
        equals(const [
          'newRun',
          'characterCreated',
          'physiqueAssigned',
          'startingContentGiven',
          'tomeBuilt',
          'activeBuildResolved',
          'combatStarted',
          'combatResolved',
          'rewardGranted',
          'itemDiscovered',
          'itemTrained',
          'masteryIncreased',
          'evolutionResolved',
          'tomeRebuilt',
          'secondCombatStarted',
          'secondCombatResolved',
        ]),
      );
      expect(outcome.firstBattleWon, isTrue);
      expect(outcome.secondBattleWon, isTrue);
      expect(PhysiqueTypes.all, contains(outcome.physiqueId));
      expect(
        outcome.rewardedContentId,
        anyOf('basic_slash', 'basic_guard'),
      );
      expect(
        outcome.evolvedContentId,
        anyOf('${outcome.rewardedContentId}:refined', '${outcome.rewardedContentId}:forceful'),
      );
    });
  });

  group('reproducibility', () {
    test('the same seed reproduces an identical run — same log, same '
        'physique, same reward, same evolution, same battle outcomes', () {
      final runA = runVerticalSlice(7);
      final runB = runVerticalSlice(7);

      expect(runA.log, equals(runB.log));
      expect(runA.physiqueId, equals(runB.physiqueId));
      expect(runA.rewardedContentId, equals(runB.rewardedContentId));
      expect(runA.evolvedContentId, equals(runB.evolvedContentId));
      expect(runA.firstBattleWon, equals(runB.firstBattleWon));
      expect(runA.secondBattleWon, equals(runB.secondBattleWon));
    });

    test('different seeds can diverge (sanity: the run is not accidentally '
        'seed-independent)', () {
      final seeds = List.generate(10, (i) => i);
      final physiqueIds = seeds.map((s) => runVerticalSlice(s).physiqueId).toSet();

      expect(
        physiqueIds.length,
        greaterThan(1),
        reason: 'ten different seeds should not all assign the same physique',
      );
    });
  });
}
