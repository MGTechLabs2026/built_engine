import 'package:build_engine/affix_plugin.dart';
import 'package:build_engine/build_engine.dart';
import 'package:build_engine/game.dart';
import 'package:test/test.dart';

/// Deterministic policy that always takes the item/technique reward when
/// one is offered (`NeverReplacePolicy` / `DefaultRunDecisionPolicy`
/// always pick candidate 0, which is `unlockSlot` for the whole run — a
/// 999-slot Tome is never fully unlocked — so they never exercise the
/// item/technique reward arm this test needs). Same shape as
/// `_FightAndTakeItems` in `test/integration/consumable_combat_stage_test.dart`.
class _TakeItemRewards extends DefaultRunDecisionPolicy {
  const _TakeItemRewards();

  @override
  int chooseReward(List<RewardKind> candidates) {
    final index = candidates.indexOf(RewardKind.itemOrTechnique);
    return index == -1 ? 0 : index;
  }
}

void main() {
  test('a seed grants at least one affixed component; the reward string carries affix ids', () {
    // Several seeds guarantee at least one item/technique reward with an affix.
    final withAffix = <String>[];
    for (var seed = 0; seed < 25; seed++) {
      final result = runGame(seed, policy: const _TakeItemRewards());
      withAffix.addAll(result.rewardsGranted.where((r) => r.contains('+af_')));
    }
    expect(withAffix, isNotEmpty,
        reason: 'across 25 seeds some item/technique reward must roll an affix');
    // shape: "<base>+af_x" or "<base>+af_x+af_y"
    for (final r in withAffix) {
      final parts = r.split('+');
      expect(parts.first, anyOf(startsWith('item:'), startsWith('technique:')));
      expect(parts.skip(1), everyElement(startsWith('af_')));
      expect(parts.skip(1).length, lessThanOrEqualTo(2));
    }
  });

  test('AffixAcquired fires with a canonical acquisition; determinism holds', () {
    final bus = EventBus();
    final acquired = <AffixAcquired>[];
    bus.subscribe<AffixAcquired>(acquired.add);

    final a = runGame(3, policy: const _TakeItemRewards(), eventBus: bus);
    final b = runGame(3, policy: const _TakeItemRewards());
    expect(a.rewardsGranted, b.rewardsGranted,
        reason: 'affix resolution must not perturb the run RNG sequence');

    // One AffixAcquired per `+af_` segment across every reward string.
    final affixSegments = a.rewardsGranted
        .expand((r) => r.split('+').skip(1))
        .where((s) => s.startsWith('af_'))
        .length;
    expect(acquired, hasLength(affixSegments));
    expect(affixSegments, greaterThan(0));

    for (final ev in acquired) {
      final AffixAcquisition acq = ev.acquisition;
      expect(ev.rewardBaseId, anyOf(startsWith('item:'), startsWith('technique:')));
      expect(acq.affixId, startsWith('af_'));
      expect(acq.affixEventId, isNotEmpty);
      expect(acq.runId, 'seed:3');
      expect(acq.runNumber, 0);
      expect(acq.stat, isNotEmpty);
    }
  });
}
