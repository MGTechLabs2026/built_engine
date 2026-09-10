import 'package:build_engine/almanac.dart';
import 'package:build_engine/game.dart';
import 'package:test/test.dart';

/// Deterministic policy that always takes the item/technique reward when
/// one is offered. `NeverReplacePolicy` / `DefaultRunDecisionPolicy`
/// always pick candidate 0, which is `unlockSlot` for the whole run (a
/// 999-slot Tome is never fully unlocked), so they never exercise the
/// item/technique reward arm — and therefore never roll an affix. Same
/// shape as `_TakeItemRewards` in
/// `test/plugins/game/affix_reward_wiring_test.dart`.
class _TakeItemRewards extends DefaultRunDecisionPolicy {
  const _TakeItemRewards();

  @override
  int chooseReward(List<RewardKind> candidates) {
    final index = candidates.indexOf(RewardKind.itemOrTechnique);
    return index == -1 ? 0 : index;
  }
}

void main() {
  test('runGame records acquired affixes into the Almanac', () {
    for (var seed = 0; seed < 25; seed++) {
      final recorder = AlmanacRecorder();
      final result = runGame(
        seed,
        policy: const _TakeItemRewards(),
        almanac: recorder,
        runId: 'run-$seed',
        runNumber: 1,
      );
      final rolledAffix = result.rewardsGranted.any((r) => r.contains('+af_'));
      if (!rolledAffix) continue;

      expect(recorder.state.affixes, isNotEmpty);
      final rec = recorder.state.affixes.first;
      expect(rec.discoveryObservations, isNotEmpty);
      expect(rec.snapshot.value, greaterThan(0));

      // Build snapshots now carry affixes (no `const []` stub). The flat
      // accessor is `recorder.state.builds`.
      final anyBuildHasAffix = recorder.state.builds.any(
        (b) => b.affixes.isNotEmpty,
      );
      expect(anyBuildHasAffix, isTrue);
      return; // asserted on the first affix-bearing seed
    }
    fail('no seed in 0..24 rolled an affix — widen the range');
  });

  test('re-recording the same acquisition is idempotent', () {
    for (var seed = 0; seed < 25; seed++) {
      final recorder = AlmanacRecorder();
      final result = runGame(
        seed,
        policy: const _TakeItemRewards(),
        almanac: recorder,
        runId: 'run-$seed',
        runNumber: 1,
      );
      if (!result.rewardsGranted.any((r) => r.contains('+af_'))) continue;

      final rec = recorder.state.affixes.first;
      final obs = rec.discoveryObservations.first;
      final before = rec.discoveryObservations.length;
      recorder.recordAffixDiscovered(
        affixId: rec.affixId,
        observation: obs,
        snapshot: rec.snapshot,
        timestamp: DateTime.utc(2026),
      );
      final after = recorder.state.affixes
          .firstWhere((a) => a.affixId == rec.affixId)
          .discoveryObservations
          .length;
      expect(after, before, reason: '(affixId, affixEventId) de-dupe holds');
      return;
    }
    fail('no seed in 0..24 rolled an affix — widen the range');
  });
}
