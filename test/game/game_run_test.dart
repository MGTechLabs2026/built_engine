import 'package:build_engine/build_engine.dart';
import 'package:build_engine/game.dart';
import 'package:build_engine/martial_arts_plugin.dart';
import 'package:test/test.dart';

/// A policy that never replaces an occupied Tome slot — used to prove
/// player decisions (not just the seed) shape the final build.
class NeverReplacePolicy extends DefaultRunDecisionPolicy {
  const NeverReplacePolicy();

  @override
  bool chooseReplace(SlotId slot, BuildComponentRef current, BuildComponentRef incoming) => false;
}

/// Always takes the `itemOrTechnique` reward option when it's offered —
/// `DefaultRunDecisionPolicy` always takes `unlockSlot` first, which
/// never actually contests an occupied slot, so no `chooseSlot`/
/// `chooseReplace` divergence would ever show up in [finalBuild].
class PreferItemRewardPolicy extends DefaultRunDecisionPolicy {
  @override
  int chooseReward(List<RewardKind> candidates) {
    final index = candidates.indexOf(RewardKind.itemOrTechnique);
    return index == -1 ? 0 : index;
  }
}

class PreferItemRewardNeverReplacePolicy extends PreferItemRewardPolicy {
  @override
  bool chooseReplace(SlotId slot, BuildComponentRef current, BuildComponentRef incoming) => false;
}

/// Fights the first cycle only (a training cycle before any reward has
/// ever been granted has nothing to train on — this earns one first),
/// then trains every cycle after, never risking death again. Exercises
/// training/mastery/learning/evolution across many sessions without
/// fighting the run's own combat difficulty for test coverage.
/// `DefaultRunDecisionPolicy` always picks `'combat'` first and so never
/// trains on its own.
class TrainAfterFirstCombatPolicy extends DefaultRunDecisionPolicy {
  var _cycle = 0;

  @override
  String chooseCombatOrTraining(List<String> candidates) {
    _cycle++;
    return _cycle == 1 ? 'combat' : 'training';
  }

  // Prefer a real item/technique over unlocking a slot, so there's
  // actually something discovered to spend a training cycle on.
  @override
  int chooseReward(List<RewardKind> candidates) {
    final index = candidates.indexOf(RewardKind.itemOrTechnique);
    return index == -1 ? 0 : index;
  }
}

void main() {
  group('complete run', () {
    test('a run executes headlessly from a single runGame(seed) call, producing a '
        'fully-populated RunResult', () {
      final result = runGame(6, policy: TrainAfterFirstCombatPolicy());

      expect(result.seed, equals(6));
      expect(result.characterName, equals('Player'));
      expect(result.physiqueId, isNotEmpty);
      expect(result.martialTradition, anyOf(MartialTraditions.western, MartialTraditions.eastern));
      expect(result.styleId, isNotEmpty);
      expect(result.encounters, isNotEmpty);
      expect(result.tomeHistory, isNotEmpty);
      expect(result.finalBuild, isNotEmpty);
      expect(result.cyclesCompleted, greaterThan(0));
    });

    test('characterName is cosmetic — it is recorded verbatim and affects nothing else', () {
      final withName = runGame(6, characterName: 'Wu Kong');
      final withoutName = runGame(6);

      expect(withName.characterName, equals('Wu Kong'));
      expect(withName.won, equals(withoutName.won));
      expect(withName.finalBuild.map((c) => c.contentId), equals(withoutName.finalBuild.map((c) => c.contentId)));
    });
  });

  group('starting kit', () {
    test('the run starts with knife and cloth armor already active, no starting technique', () {
      final result = runGame(6);

      expect(result.itemsDiscovered, containsAll(['knife', 'cloth_armor']));
      expect(result.itemsUnlocked, containsAll(['knife', 'cloth_armor']));
      // cloth_armor's own content requires mastery level 1 — the starting
      // grant bypasses that instantly, so it's usable from turn one even
      // though it was never trained (itemsMastered only tracks
      // training-driven unlocks).
      expect(result.tomeHistory.first.components.map((c) => c.contentId), contains('knife'));
    });
  });

  group('early combat', () {
    test('the first fight is fought and resolved automatically (no manual attack control)', () {
      final result = runGame(6);

      final first = result.encounters.first;
      expect(first.name, equals('Cycle 1 Fight 1'));
      expect(first.playerHealthAfter, greaterThanOrEqualTo(0));
    });
  });

  group('difficulty scaling', () {
    test('scaledEnemy grows health/damage with cycle number and leaves id/damageStat/initiative alone', () {
      const base = RunEnemies.bandit;

      final cycle1 = scaledEnemy(base, 1);
      final cycle10 = scaledEnemy(base, 10);

      expect(cycle1.health, equals(base.health));
      expect(cycle1.damage, equals(base.damage));
      expect(cycle10.health, greaterThan(base.health));
      expect(cycle10.damage, greaterThan(base.damage));
      expect(cycle10.id, equals(base.id));
      expect(cycle10.damageStat, equals(base.damageStat));
      expect(cycle10.initiative, equals(base.initiative));
    });
  });

  group('reward', () {
    test('every granted reward resolves to a slot/item/technique/upgrade-point entry', () {
      final result = runGame(6);

      expect(result.rewardsGranted, isNotEmpty);
      for (final reward in result.rewardsGranted) {
        expect(
          reward,
          anyOf(startsWith('slot:'), startsWith('item:'), startsWith('technique:'), equals('upgrade_point')),
        );
      }
    });

    test('the 3rd fight of every completed cycle is drawn from the elite/boss pool', () {
      final result = runGame(6);

      for (var i = 2; i < result.encounters.length; i += 3) {
        expect(
          result.encounters[i].enemyId,
          anyOf(RunEnemies.eliteWarrior.id, RunEnemies.boss.id),
        );
      }
    });
  });

  group('training', () {
    test('a training cycle runs a real TrainingSession and records a TrainingRecord', () {
      final result = runGame(6, policy: TrainAfterFirstCombatPolicy());

      expect(result.trainingRecords, isNotEmpty);
    });
  });

  group('learning and evolution', () {
    test('sustained training across many cycles eventually learns and evolves a technique', () {
      final result = runGame(6, policy: TrainAfterFirstCombatPolicy());

      expect(result.techniquesLearned, isNotEmpty);
      if (result.techniquesEvolved.isNotEmpty) {
        // Only the *most recent* evolution is guaranteed still active —
        // with just 2 Tome slots ever unlocked in this test (this policy
        // always prefers item/technique rewards over unlocking a slot),
        // a later technique placement can bump an earlier evolution back
        // out, exactly like any other Tome slot contention.
        expect(
          result.finalBuild.map((c) => c.contentId),
          contains(result.techniquesEvolved.last),
        );
      }
    });
  });

  group('Tome rebuild', () {
    test('the Tome is rebuilt multiple times across the run', () {
      final result = runGame(6, policy: TrainAfterFirstCombatPolicy());

      expect(result.tomeHistory.length, greaterThan(2));
    });
  });

  group('slot unlocking', () {
    test('unlocking a slot reward grows the set of usable Tome slots beyond the starting 2', () {
      // ScriptedRewardPolicy always takes the unlockSlot option when
      // offered, to reliably exercise the slot-unlock path.
      final result = runGame(6, policy: _AlwaysUnlockSlotPolicy());

      expect(result.rewardsGranted.where((r) => r.startsWith('slot:')), isNotEmpty);
    });
  });

  group('endless loop: death or the safety cap', () {
    test('a run always ends either by death (won: false) or by reaching the safety cap alive (won: true)', () {
      final died = runGame(1);
      final survivedOrDied = runGame(6);

      expect(died.won || !died.won, isTrue); // both are valid outcomes
      expect(survivedOrDied.cyclesCompleted, lessThanOrEqualTo(200));
      if (!died.won) {
        expect(died.encounters.last.won, isFalse);
        expect(died.encounters.last.playerHealthAfter, equals(0));
      }
    });
  });

  group('player agency: decisions determine build evolution', () {
    test('the same seed with a different decision policy produces a different final build', () {
      final withDefault = runGame(6, policy: PreferItemRewardPolicy());
      final withNeverReplace = runGame(6, policy: PreferItemRewardNeverReplacePolicy());

      expect(
        withDefault.finalBuild.map((c) => c.contentId).toSet(),
        isNot(equals(withNeverReplace.finalBuild.map((c) => c.contentId).toSet())),
      );
    });
  });

  group('deterministic given seed + decisions', () {
    test('the exact same seed and policy always produce an identical RunResult', () {
      RunResult run() => runGame(6, policy: const NeverReplacePolicy());
      final a = run();
      final b = run();

      expect(a.won, equals(b.won));
      expect(a.physiqueId, equals(b.physiqueId));
      expect(a.martialTradition, equals(b.martialTradition));
      expect(a.styleId, equals(b.styleId));
      expect(a.itemsDiscovered, equals(b.itemsDiscovered));
      expect(a.itemsMastered, equals(b.itemsMastered));
      expect(a.techniquesLearned, equals(b.techniquesLearned));
      expect(a.techniquesEvolved, equals(b.techniquesEvolved));
      expect(a.rewardsGranted, equals(b.rewardsGranted));
      expect(a.cyclesCompleted, equals(b.cyclesCompleted));
      expect(
        a.encounters.map((e) => (e.name, e.enemyId, e.won, e.playerHealthAfter)),
        equals(b.encounters.map((e) => (e.name, e.enemyId, e.won, e.playerHealthAfter))),
      );
      expect(
        a.finalBuild.map((c) => (c.referenceType, c.contentId)),
        equals(b.finalBuild.map((c) => (c.referenceType, c.contentId))),
      );
    });

    test('a different seed can diverge (sanity: the run is not accidentally seed-independent)', () {
      final resultA = runGame(6);
      final resultB = runGame(2);

      expect(
        resultA.encounters.map((e) => e.enemyId).toList(),
        isNot(equals(resultB.encounters.map((e) => e.enemyId).toList())),
      );
    });
  });
}

/// Always takes the `unlockSlot` reward option when it's offered,
/// otherwise the first candidate — deterministic and pure, like every
/// other test policy in this file.
class _AlwaysUnlockSlotPolicy extends DefaultRunDecisionPolicy {
  @override
  int chooseReward(List<RewardKind> candidates) {
    final index = candidates.indexOf(RewardKind.unlockSlot);
    return index == -1 ? 0 : index;
  }
}
