/// Phase 7 §11.5 / §13.1 — `runGame`'s opt-in Almanac parameters.
///
/// When `almanac != null`, `runId` and `runNumber` are required and their
/// absence throws `ArgumentError` at the boundary (a runtime `throw`, not
/// an `assert` — assertions are stripped in release/AOT). When
/// `almanac == null`, the guard short-circuits, no bridge is constructed,
/// and the run is byte-identical to `runGame(seed)` — determinism and
/// `DecisionLog` replay are unaffected.
library;

import 'package:build_engine/almanac.dart';
import 'package:build_engine/game.dart';
import 'package:test/test.dart';

import '../../support/policies.dart';

void main() {
  group('runtime validation (throw, not assert)', () {
    test('almanac != null with runId: null throws ArgumentError', () {
      final recorder = AlmanacRecorder();
      expect(
        () => runGame(6, almanac: recorder, runId: null, runNumber: 1),
        throwsArgumentError,
      );
    });

    test('almanac != null with runNumber: null throws ArgumentError', () {
      final recorder = AlmanacRecorder();
      expect(
        () =>
            runGame(6, almanac: recorder, runId: 'opaque-run', runNumber: null),
        throwsArgumentError,
      );
    });

    test('the guard fires even with assertions disabled — it is a real '
        'throw, reached before any run work', () {
      final recorder = AlmanacRecorder();
      Object? caught;
      try {
        runGame(6, almanac: recorder);
      } catch (e) {
        caught = e;
      }
      expect(caught, isA<ArgumentError>());
      expect(recorder.state.runs, isEmpty);
    });
  });

  group('almanac == null: behaviour unchanged', () {
    test('runGame(seed, almanac: null, runId: null, runNumber: null) does '
        'not throw and equals runGame(seed)', () {
      final baseline = runGame(6, policy: const NeverReplacePolicy());
      final withNulls = runGame(
        6,
        policy: const NeverReplacePolicy(),
        almanac: null,
        runId: null,
        runNumber: null,
      );

      expect(withNulls.won, equals(baseline.won));
      expect(withNulls.physiqueId, equals(baseline.physiqueId));
      expect(withNulls.martialTradition, equals(baseline.martialTradition));
      expect(withNulls.styleId, equals(baseline.styleId));
      expect(withNulls.itemsDiscovered, equals(baseline.itemsDiscovered));
      expect(withNulls.itemsMastered, equals(baseline.itemsMastered));
      expect(withNulls.techniquesLearned, equals(baseline.techniquesLearned));
      expect(withNulls.techniquesEvolved, equals(baseline.techniquesEvolved));
      expect(withNulls.rewardsGranted, equals(baseline.rewardsGranted));
      expect(withNulls.cyclesCompleted, equals(baseline.cyclesCompleted));
      expect(
        withNulls.encounters.map(
          (e) => (e.name, e.enemyId, e.won, e.playerHealthAfter),
        ),
        equals(
          baseline.encounters.map(
            (e) => (e.name, e.enemyId, e.won, e.playerHealthAfter),
          ),
        ),
      );
      expect(
        withNulls.finalBuild.map((c) => (c.referenceType, c.contentId)),
        equals(baseline.finalBuild.map((c) => (c.referenceType, c.contentId))),
      );
    });

    test('determinism: same seed + policy, almanac == null, twice => equal '
        'RunResult projection', () {
      RunResult run() => runGame(6, policy: const NeverReplacePolicy());
      final a = run();
      final b = run();

      expect(a.won, equals(b.won));
      expect(a.cyclesCompleted, equals(b.cyclesCompleted));
      expect(a.rewardsGranted, equals(b.rewardsGranted));
      expect(a.techniquesLearned, equals(b.techniquesLearned));
      expect(a.techniquesEvolved, equals(b.techniquesEvolved));
      expect(
        a.encounters.map(
          (e) => (e.name, e.enemyId, e.won, e.playerHealthAfter),
        ),
        equals(
          b.encounters.map(
            (e) => (e.name, e.enemyId, e.won, e.playerHealthAfter),
          ),
        ),
      );
      expect(
        a.finalBuild.map((c) => (c.referenceType, c.contentId)),
        equals(b.finalBuild.map((c) => (c.referenceType, c.contentId))),
      );
    });

    test('DecisionLog replay still reproduces the run with the parameters '
        'present but null', () {
      final original = runGame(6, policy: const NeverReplacePolicy());
      final replay = runGame(
        6,
        policy: ReplayDecisionPolicy(original.decisionLog),
        almanac: null,
      );

      expect(replay.won, equals(original.won));
      expect(
        replay.finalBuild.map((c) => (c.referenceType, c.contentId)),
        equals(original.finalBuild.map((c) => (c.referenceType, c.contentId))),
      );
    });
  });
}
