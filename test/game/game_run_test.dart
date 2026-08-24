import 'package:build_engine/build_engine.dart';
import 'package:build_engine/game.dart';
import 'package:test/test.dart';

/// A policy that never replaces an occupied Tome slot — used to prove
/// player decisions (not just the seed) shape the final build.
class NeverReplacePolicy extends DefaultRunDecisionPolicy {
  const NeverReplacePolicy();

  @override
  bool chooseReplace(SlotId slot, BuildComponentRef current, BuildComponentRef incoming) => false;
}

void main() {
  group('complete run', () {
    test('a full run executes headlessly from a single runGame(seed) call, '
        'producing a fully-populated RunResult', () {
      final result = runGame(6);

      expect(result.seed, equals(6));
      expect(result.physiqueId, isNotEmpty);
      expect(result.styleId, isNotEmpty);
      expect(result.encounters, isNotEmpty);
      expect(result.tomeHistory, isNotEmpty);
      expect(result.finalBuild, isNotEmpty);
    });
  });

  group('early combat', () {
    test('the first encounter is fought and resolved automatically (no manual attack control)', () {
      final result = runGame(6);

      final first = result.encounters.first;
      expect(first.name, equals('Encounter 1'));
      expect(first.enemyId, equals('training_dummy'));
      expect(first.won, isTrue);
      expect(first.playerHealthAfter, lessThan(100)); // took damage, but survived
      expect(first.playerHealthAfter, greaterThan(0));
    });
  });

  group('reward', () {
    test('winning combats grant rewards drawn from the real Item/Technique content', () {
      final result = runGame(6);

      expect(result.rewardsGranted, isNotEmpty);
      for (final reward in result.rewardsGranted) {
        expect(reward, anyOf(startsWith('item:'), startsWith('technique:')));
      }
    });
  });

  group('discovery', () {
    test('rewarded items are discovered through the real generic Discovery system', () {
      final result = runGame(6);

      expect(result.itemsDiscovered, contains('gloves')); // starting kit
      expect(result.itemsDiscovered.length, greaterThan(1)); // plus at least one reward
    });
  });

  group('training', () {
    test('a Training Opportunity step runs a real TrainingSession and changes progress '
        '(mastery increases or a technique is learned)', () {
      final result = runGame(6);

      // At least one training-driven Tome rebuild happened.
      expect(
        result.tomeHistory.any((s) => s.afterStep.contains('mastered') || s.afterStep.contains('learned')),
        isTrue,
      );
    });
  });

  group('mastery', () {
    test('an item that required training becomes usable (mastered) via the real Mastery system', () {
      final result = runGame(6);

      expect(result.itemsMastered, contains('cloth_armor'));
    });
  });

  group('learning and evolution', () {
    test('a technique is learned and then evolves into a real branch via the real Evolution system', () {
      final result = runGame(6);

      expect(result.techniquesLearned, containsAll(['basic_punch', 'basic_slash']));
      expect(result.techniquesEvolved, isNotEmpty);
      // The evolved id replaced the base technique in the final build.
      expect(result.finalBuild.map((c) => c.contentId), contains(result.techniquesEvolved.single));
      expect(result.finalBuild.map((c) => c.contentId), isNot(contains('basic_slash')));
    });
  });

  group('Tome rebuild', () {
    test('the Tome is rebuilt multiple times across the run, each producing a distinct ActiveBuild', () {
      final result = runGame(6);

      expect(result.tomeHistory.length, greaterThan(2));
      // Every rebuild step actually changed the build compared to the previous one.
      for (var i = 1; i < result.tomeHistory.length; i++) {
        final before = result.tomeHistory[i - 1].components.map((c) => c.contentId).toSet();
        final after = result.tomeHistory[i].components.map((c) => c.contentId).toSet();
        expect(before, isNot(equals(after)), reason: 'step ${result.tomeHistory[i].afterStep}');
      }
    });
  });

  group('elite', () {
    test('both Elite encounters are fought and won on the way to the Boss', () {
      final result = runGame(6);

      final elites = result.encounters.where((e) => e.name.startsWith('Elite')).toList();
      expect(elites, hasLength(2));
      expect(elites.every((e) => e.enemyId == 'elite_warrior'), isTrue);
      expect(elites.every((e) => e.won), isTrue);
    });
  });

  group('boss', () {
    test('the final encounter is the Boss', () {
      final result = runGame(6);

      expect(result.encounters.last.name, equals('Boss'));
      expect(result.encounters.last.enemyId, equals('boss'));
    });
  });

  group('victory', () {
    test('seed 6 with the default policy wins the complete run (all 8 combats)', () {
      final result = runGame(6);

      expect(result.won, isTrue);
      expect(result.encounters, hasLength(8));
      expect(result.encounters.every((e) => e.won), isTrue);
    });
  });

  group('loss', () {
    test('seed 1 with the default policy loses — the run stops at the encounter that killed '
        'the player and does not proceed further', () {
      final result = runGame(1);

      expect(result.won, isFalse);
      expect(result.encounters.last.won, isFalse);
      expect(result.encounters.last.playerHealthAfter, equals(0));
    });
  });

  group('player agency: decisions determine build evolution', () {
    test('the same seed with a different decision policy produces a different final build', () {
      final withDefault = runGame(6);
      final withNeverReplace = runGame(6, policy: const NeverReplacePolicy());

      // Both still win (illustrating this isn't just "a worse run") but
      // the weapon slot diverges: the default policy replaces the
      // starting Gloves with a later reward; NeverReplacePolicy keeps
      // Gloves for the whole run.
      expect(withDefault.won, isTrue);
      expect(withNeverReplace.won, isTrue);
      expect(
        withDefault.finalBuild.map((c) => c.contentId).toSet(),
        isNot(equals(withNeverReplace.finalBuild.map((c) => c.contentId).toSet())),
      );
      expect(withNeverReplace.finalBuild.map((c) => c.contentId), contains('gloves'));
      expect(withDefault.finalBuild.map((c) => c.contentId), isNot(contains('gloves')));
    });

    test('run is not deterministic from seed alone: a policy change alone changes the outcome history',
        () {
      final withDefault = runGame(6);
      final withNeverReplace = runGame(6, policy: const NeverReplacePolicy());

      expect(withDefault.tomeHistory.length, isNot(equals(0)));
      // Different weapon-slot decisions produce a different Tome history
      // shape even though both runs share the same seed (and therefore
      // the same enemy sequence, the same reward pool order, and the
      // same training RNG draws).
      final defaultWeaponChoices =
          withDefault.tomeHistory.map((s) => s.components.map((c) => c.contentId).contains('knife'));
      final neverReplaceWeaponChoices = withNeverReplace.tomeHistory
          .map((s) => s.components.map((c) => c.contentId).contains('knife'));
      expect(defaultWeaponChoices.any((v) => v), isTrue);
      expect(neverReplaceWeaponChoices.any((v) => v), isFalse);
    });
  });

  group('deterministic given seed + decisions', () {
    test('the exact same seed and policy always produce an identical RunResult', () {
      RunResult run() => runGame(6, policy: const NeverReplacePolicy());
      final a = run();
      final b = run();

      expect(a.won, equals(b.won));
      expect(a.physiqueId, equals(b.physiqueId));
      expect(a.styleId, equals(b.styleId));
      expect(a.itemsDiscovered, equals(b.itemsDiscovered));
      expect(a.itemsMastered, equals(b.itemsMastered));
      expect(a.techniquesLearned, equals(b.techniquesLearned));
      expect(a.techniquesEvolved, equals(b.techniquesEvolved));
      expect(a.rewardsGranted, equals(b.rewardsGranted));
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
      final resultB = runGame(1);

      expect(resultA.won, isNot(equals(resultB.won)));
    });
  });
}
