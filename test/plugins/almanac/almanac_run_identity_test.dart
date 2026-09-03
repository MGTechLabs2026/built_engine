/// Phase 4.9 — `runId` is the run's only identity. `runNumber` is an ordinal
/// and `seed` is replay metadata that keys nothing, so two runs from one seed
/// are two runs.
library;

import 'package:build_engine/src/plugins/almanac/almanac_models.dart';
import 'package:build_engine/src/plugins/almanac/almanac_recorder.dart';
import 'package:test/test.dart';

import 'support/almanac_fixtures.dart';

void main() {
  group('run identity', () {
    test('one seed, two runIds gives two run records', () {
      final recorder =
          AlmanacRecorder()
            ..beginRun(
              runId: 'run-a',
              runNumber: 1,
              seed: 12345,
              lineageId: 'western',
              physiqueId: 'phy-a',
              startedAt: at(1),
            )
            ..beginRun(
              runId: 'run-b',
              runNumber: 2,
              seed: 12345,
              lineageId: 'western',
              physiqueId: 'phy-a',
              startedAt: at(2),
            );

      final runs = recorder.state.runs;
      expect(runs, hasLength(2));
      expect(runs.map((r) => r.runId).toList(), ['run-a', 'run-b']);
      expect(runs.every((r) => r.seed == 12345), isTrue);
      expect(runs.map((r) => r.runNumber).toList(), [1, 2]);
    });

    test('the seed is stored but keys nothing', () {
      final recorder =
          AlmanacRecorder()
            ..beginRun(
              runId: 'run-a',
              runNumber: 1,
              seed: 7,
              lineageId: 'western',
              physiqueId: 'phy-a',
              startedAt: at(1),
            )
            // A different seed under the SAME runId is a contradiction, not a new
            // run: identity is the runId alone.
            ..beginRun(
              runId: 'run-a',
              runNumber: 1,
              lineageId: 'western',
              physiqueId: 'phy-a',
              startedAt: at(1),
            );

      expect(recorder.state.runs, hasLength(1));
      expect(recorder.state.runs.single.seed, 7);
      expect(
        () => recorder.beginRun(
          runId: 'run-a',
          runNumber: 1,
          seed: 8,
          lineageId: 'western',
          physiqueId: 'phy-a',
          startedAt: at(1),
        ),
        throwsA(
          isA<AlmanacIntegrityException>().having(
            (e) => e.field,
            'field',
            'seed',
          ),
        ),
      );
      expect(recorder.state.runs.single.seed, 7);
    });

    test('two runs reusing one opaque event id keep disjoint ledgers', () {
      final recorder =
          AlmanacRecorder()
            ..beginRun(
              runId: 'run-a',
              runNumber: 1,
              seed: 12345,
              lineageId: 'western',
              physiqueId: 'phy-a',
              startedAt: at(1),
            )
            ..beginRun(
              runId: 'run-b',
              runNumber: 2,
              seed: 12345,
              lineageId: 'western',
              physiqueId: 'phy-a',
              startedAt: at(2),
            );

      for (final runId in ['run-a', 'run-b']) {
        final runNumber = runId == 'run-a' ? 1 : 2;
        recorder
          ..recordFight(
            runId: runId,
            fightId: 'e0',
            sequence: 0,
            name: 'Bandit',
            enemyId: 'enemy-bandit',
            won: true,
            playerHealthAfter: 10,
            turnsUsed: 5,
          )
          ..recordTechniqueUsed(
            TechniqueUsageObservation(
              usageEventId: 'u0',
              runId: runId,
              runNumber: runNumber,
              instanceId: 'ti-1',
            ),
          )
          ..recordTrainingSession(
            TrainingObservation(
              trainingEventId: 't0',
              runId: runId,
              runNumber: runNumber,
            ),
          );
      }

      final runs = recorder.state.runs;
      expect(runs.map((r) => r.fights.length).toList(), [1, 1]);
      expect(runs.map((r) => r.trainingSessions).toList(), [1, 1]);
      expect(runs.map((r) => r.techniquesUsed).toList(), [1, 1]);
      expect(recorder.state.techniques.single.totalUsage, 2);
      expect(recorder.state.techniques.single.runsUsed, [1, 2]);
    });

    test('each run completes independently', () {
      final recorder =
          AlmanacRecorder()
            ..beginRun(
              runId: 'run-a',
              runNumber: 1,
              lineageId: 'western',
              physiqueId: 'phy-a',
              startedAt: at(1),
            )
            ..beginRun(
              runId: 'run-b',
              runNumber: 2,
              lineageId: 'eastern',
              physiqueId: 'phy-b',
              startedAt: at(2),
            )
            ..completeRun(
              runId: 'run-b',
              completedAt: at(3),
              outcome: RunOutcome.won,
              finalBuildId: 'b-b',
            );

      final runs = recorder.state.runs;
      expect(runs.first.outcome, RunOutcome.abandoned);
      expect(runs.first.finalBuildId, isNull);
      expect(runs.last.outcome, RunOutcome.won);
      expect(runs.last.finalBuildId, 'b-b');
    });
  });
}
