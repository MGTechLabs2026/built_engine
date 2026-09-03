/// Phase 4.9 — every Almanac id is an opaque token.
///
/// The same event stream, once with structured adapter ids (`run-1:u0`) and
/// once with arbitrary ids (`action-8f3a91`), must produce structurally
/// identical history apart from the id strings themselves. And an id whose text
/// names a DIFFERENT run must still bind to the explicit `runId` field.
library;

import 'package:build_engine/src/plugins/almanac/almanac_models.dart';
import 'package:build_engine/src/plugins/almanac/almanac_queries.dart';
import 'package:build_engine/src/plugins/almanac/almanac_recorder.dart';
import 'package:test/test.dart';

import 'support/almanac_fixtures.dart';

/// Drives one identical run through the recorder using caller-chosen ids.
AlmanacRecorder _drive({
  required String fightId,
  required String usageEventId,
  required String trainingEventId,
  required String buildId,
}) {
  final recorder =
      AlmanacRecorder()
        ..beginRun(
          runId: 'run-1',
          runNumber: 1,
          lineageId: 'western',
          physiqueId: 'phy-a',
          startedAt: at(1),
        )
        ..recordFight(
          runId: 'run-1',
          fightId: fightId,
          sequence: 0,
          name: 'Bandit',
          enemyId: 'enemy-bandit',
          won: true,
          playerHealthAfter: 10,
          turnsUsed: 5,
        )
        ..recordTechniqueUsed(
          TechniqueUsageObservation(
            usageEventId: usageEventId,
            runId: 'run-1',
            runNumber: 1,
            instanceId: 'ti-1',
          ),
        )
        ..recordTrainingSession(
          TrainingObservation(
            trainingEventId: trainingEventId,
            runId: 'run-1',
            runNumber: 1,
          ),
        )
        ..recordBuildSnapshot(buildRecord(runId: 'run-1', buildId: buildId))
        ..completeRun(
          runId: 'run-1',
          completedAt: at(2),
          outcome: RunOutcome.won,
          finalBuildId: buildId,
        );
  return recorder;
}

void main() {
  group('id opacity', () {
    test('structured and arbitrary ids yield the same shape of history', () {
      final structured =
          _drive(
            fightId: 'run-1:e0',
            usageEventId: 'run-1:u0',
            trainingEventId: 'run-1:t0',
            buildId: 'run-1:finalBuild:0',
          ).state;
      final opaque =
          _drive(
            fightId: 'action-8f3a91',
            usageEventId: 'action-1c02de',
            trainingEventId: 'action-4b77aa',
            buildId: 'action-90ff31',
          ).state;

      expect(opaque.runs.single.fights, hasLength(1));
      expect(opaque.runs.single.enemiesDefeated, 1);
      expect(opaque.runs.single.techniquesUsed, 1);
      expect(opaque.runs.single.trainingSessions, 1);
      expect(opaque.builds, hasLength(1));
      expect(opaque.techniques.single.totalUsage, 1);

      expect(
        opaque.runs.single.enemiesDefeated,
        structured.runs.single.enemiesDefeated,
      );
      expect(
        opaque.runs.single.techniquesUsed,
        structured.runs.single.techniquesUsed,
      );
      expect(opaque.builds.length, structured.builds.length);
      expect(
        opaque.techniques.single.totalUsage,
        structured.techniques.single.totalUsage,
      );
    });

    test(
      'the query API reads the same history whichever id scheme was used',
      () {
        final structured = AlmanacQueries(
          _drive(
            fightId: 'run-1:e0',
            usageEventId: 'run-1:u0',
            trainingEventId: 'run-1:t0',
            buildId: 'run-1:finalBuild:0',
          ).state,
        );
        final opaque = AlmanacQueries(
          _drive(
            fightId: 'action-8f3a91',
            usageEventId: 'action-1c02de',
            trainingEventId: 'action-4b77aa',
            buildId: 'action-90ff31',
          ).state,
        );

        // runId ('run-1') and instanceId ('ti-1') are identical between the two
        // drives; only the opaque event/build ids differ.
        expect(
          opaque.getRunHistory().map((r) => r.runId),
          structured.getRunHistory().map((r) => r.runId),
        );
        expect(
          opaque.getRunsUsingTechnique('ti-1').map((r) => r.runId),
          structured.getRunsUsingTechnique('ti-1').map((r) => r.runId),
        );
        expect(
          opaque.getTechniqueHistory('ti-1')!.totalUsage,
          structured.getTechniqueHistory('ti-1')!.totalUsage,
        );
        expect(
          opaque.getBuildHistory().length,
          structured.getBuildHistory().length,
        );
        expect(
          opaque.getBuildsForRun('run-1').map((b) => b.phase),
          structured.getBuildsForRun('run-1').map((b) => b.phase),
        );
      },
    );

    test('a usageEventId naming another run binds to its explicit runId', () {
      final recorder =
          AlmanacRecorder()
            ..recordTechniqueUsed(
              // The text says `run-9`; the field says `run-1`. The field wins.
              const TechniqueUsageObservation(
                usageEventId: 'run-9:u0',
                runId: 'run-1',
                runNumber: 1,
                instanceId: 'ti-1',
              ),
            )
            ..recordTechniqueUsed(
              const TechniqueUsageObservation(
                usageEventId: 'run-9:u0',
                runId: 'run-2',
                runNumber: 2,
                instanceId: 'ti-1',
              ),
            );

      final technique = recorder.state.techniques.single;
      expect(technique.totalUsage, 2);
      expect(technique.usageObservations.map((o) => o.runId).toList(), [
        'run-1',
        'run-2',
      ]);
      expect(recorder.state.runs.map((r) => r.runId).toList(), isEmpty);
    });

    test('a fightId naming another run binds to its explicit runId', () {
      final recorder =
          AlmanacRecorder()..recordFight(
            runId: 'run-2',
            fightId: 'run-1:e0',
            sequence: 0,
            name: 'Bandit',
            enemyId: 'enemy-bandit',
            won: true,
            playerHealthAfter: 10,
            turnsUsed: 5,
          );

      final run = recorder.state.runs.single;
      expect(run.runId, 'run-2');
      expect(run.fights.single.runId, 'run-2');
      expect(run.fights.single.fightId, 'run-1:e0');
    });

    test('ids containing separators are stored whole, never split', () {
      const gnarly = 'a:b:c::d:';
      final recorder =
          AlmanacRecorder()..recordMilestone(
            type: MilestoneType.firstWinWithLineage,
            runId: 'run-1',
            runNumber: 1,
            timestamp: at(1),
            contextId: gnarly,
          );

      final milestone = recorder.state.milestones.single;
      expect(milestone.contextId, gnarly);
      expect(milestone.type, MilestoneType.firstWinWithLineage);
      // A second one with the same context is the same milestone; a different
      // one is not — proving the whole context string is the key.
      recorder.recordMilestone(
        type: MilestoneType.firstWinWithLineage,
        runId: 'run-2',
        runNumber: 2,
        timestamp: at(2),
        contextId: 'a:b:c::d',
      );
      expect(recorder.state.milestones, hasLength(2));
    });

    test('an empty-string id is still a valid opaque key', () {
      final recorder =
          AlmanacRecorder()
            ..recordBuildSnapshot(buildRecord(runId: 'run-1', buildId: ''))
            ..recordBuildSnapshot(buildRecord(runId: 'run-1', buildId: 'b0'))
            ..recordBuildSnapshot(buildRecord(runId: 'run-1', buildId: ''));

      expect(recorder.state.builds, hasLength(2));
      expect(recorder.state.builds.map((b) => b.buildId).toList(), ['', 'b0']);
    });
  });
}
