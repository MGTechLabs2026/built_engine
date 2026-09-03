/// Phase 4.8 — a milestone is earned exactly once, and its identity is read
/// from the explicit `type` + `contextId` fields.
///
/// The recorder FORMS `milestoneId` (`type.name`, optionally `:contextId`);
/// nothing ever takes it apart again, so no assertion below splits a string.
library;

import 'package:build_engine/src/plugins/almanac/almanac_models.dart';
import 'package:build_engine/src/plugins/almanac/almanac_recorder.dart';
import 'package:test/test.dart';

import 'support/almanac_fixtures.dart';

/// The milestones matching [type] (and [contextId] when given), read only from
/// explicit fields.
List<AlmanacMilestoneRecord> _matching(
  AlmanacRecorder recorder,
  MilestoneType type, {
  String? contextId,
}) => [
  for (final milestone in recorder.state.milestones)
    if (milestone.type == type &&
        (contextId == null || milestone.contextId == contextId))
      milestone,
];

void main() {
  group('milestone identity', () {
    test(
      'runs 4, 7 and 9 all winning Western earn one milestone, at run 4',
      () {
        final recorder = AlmanacRecorder();
        for (final runNumber in [4, 7, 9]) {
          recorder.evaluateStandardMilestones(
            runId: 'run-$runNumber',
            runNumber: runNumber,
            outcome: RunOutcome.won,
            lineageId: 'western',
            timestamp: at(runNumber),
          );
        }

        final earned = _matching(
          recorder,
          MilestoneType.firstWinWithLineage,
          contextId: 'western',
        );
        expect(earned, hasLength(1));
        expect(earned.single.runNumber, 4);
        expect(earned.single.runId, 'run-4');
        expect(earned.single.timestamp, at(4));
        expect(earned.single.contextId, 'western');
      },
    );

    test('a later qualifying run does not mutate the established record', () {
      final recorder =
          AlmanacRecorder()..evaluateStandardMilestones(
            runId: 'run-4',
            runNumber: 4,
            outcome: RunOutcome.won,
            lineageId: 'western',
            timestamp: at(4),
          );
      final before = recorder.state;

      recorder.evaluateStandardMilestones(
        runId: 'run-7',
        runNumber: 7,
        outcome: RunOutcome.won,
        lineageId: 'western',
        timestamp: at(7),
      );

      expect(recorder.state, before);
    });

    test('a different lineage earns its own scoped milestone', () {
      final recorder =
          AlmanacRecorder()
            ..evaluateStandardMilestones(
              runId: 'run-4',
              runNumber: 4,
              outcome: RunOutcome.won,
              lineageId: 'western',
              timestamp: at(4),
            )
            ..evaluateStandardMilestones(
              runId: 'run-6',
              runNumber: 6,
              outcome: RunOutcome.won,
              lineageId: 'eastern',
              timestamp: at(6),
            );

      final scoped = _matching(recorder, MilestoneType.firstWinWithLineage);
      expect(scoped, hasLength(2));
      expect(scoped.map((m) => m.contextId).toList(), ['western', 'eastern']);
      expect(scoped.map((m) => m.runNumber).toList(), [4, 6]);
    });

    test('firstRun is earned on the first evaluation, win or lose', () {
      final recorder =
          AlmanacRecorder()..evaluateStandardMilestones(
            runId: 'run-1',
            runNumber: 1,
            outcome: RunOutcome.lost,
            lineageId: 'western',
            timestamp: at(1),
          );

      expect(_matching(recorder, MilestoneType.firstRun), hasLength(1));
      expect(_matching(recorder, MilestoneType.firstVictory), isEmpty);
      expect(_matching(recorder, MilestoneType.firstWinWithLineage), isEmpty);
    });

    test('firstVictory waits for a won run, then never moves', () {
      final recorder =
          AlmanacRecorder()
            ..evaluateStandardMilestones(
              runId: 'run-1',
              runNumber: 1,
              outcome: RunOutcome.lost,
              lineageId: 'western',
              timestamp: at(1),
            )
            ..evaluateStandardMilestones(
              runId: 'run-2',
              runNumber: 2,
              outcome: RunOutcome.won,
              lineageId: 'western',
              timestamp: at(2),
            )
            ..evaluateStandardMilestones(
              runId: 'run-3',
              runNumber: 3,
              outcome: RunOutcome.won,
              lineageId: 'western',
              timestamp: at(3),
            );

      final victory = _matching(recorder, MilestoneType.firstVictory);
      expect(victory, hasLength(1));
      expect(victory.single.runNumber, 2);
    });

    test('firstSuccessfulBuild is scoped to the winning final build', () {
      final recorder =
          AlmanacRecorder()..evaluateStandardMilestones(
            runId: 'run-2',
            runNumber: 2,
            outcome: RunOutcome.won,
            lineageId: 'western',
            finalBuildId: 'b-final',
            timestamp: at(2),
          );

      final earned = _matching(recorder, MilestoneType.firstSuccessfulBuild);
      expect(earned, hasLength(1));
      expect(earned.single.contextId, 'b-final');
      expect(earned.single.runId, 'run-2');
    });

    test('a loss earns no build milestone even with a final build id', () {
      final recorder =
          AlmanacRecorder()..evaluateStandardMilestones(
            runId: 'run-1',
            runNumber: 1,
            outcome: RunOutcome.lost,
            lineageId: 'western',
            finalBuildId: 'b-final',
            timestamp: at(1),
          );

      expect(_matching(recorder, MilestoneType.firstSuccessfulBuild), isEmpty);
    });

    test('content-conditioned milestones follow the recorded history', () {
      final recorder =
          AlmanacRecorder()..evaluateStandardMilestones(
            runId: 'run-1',
            runNumber: 1,
            outcome: RunOutcome.lost,
            lineageId: 'western',
            timestamp: at(1),
          );
      expect(_matching(recorder, MilestoneType.firstAffix), isEmpty);
      expect(_matching(recorder, MilestoneType.firstTechniqueVariant), isEmpty);
      expect(
        _matching(recorder, MilestoneType.firstInspiredTechnique),
        isEmpty,
      );

      recorder
        ..recordAffixDiscovered(
          affixId: 'af-1',
          observation: const AffixObservation(
            affixEventId: 'ae0',
            runId: 'run-2',
            runNumber: 2,
          ),
          snapshot: const AffixSnapshot(
            affixId: 'af-1',
            stat: 'crit',
            value: 1,
          ),
          timestamp: at(2),
        )
        ..recordTechniqueInspired(
          resultInstanceId: 'ti-new',
          runId: 'run-2',
          familyId: 'fam-a',
          descriptorIds: ['d1'],
          inspirerInstanceIds: ['ti-a'],
        )
        ..recordDiscovery(
          AlmanacDiscoveryRecord(
            discoveryId: 'techniqueVariant:ti-new',
            type: AlmanacDiscoveryType.techniqueVariant,
            contentId: 'fam-a',
            instanceId: 'ti-new',
            runId: 'run-2',
            runNumber: 2,
            timestamp: at(2),
            snapshot: discoverySnapshot(label: 'variant'),
          ),
        )
        ..evaluateStandardMilestones(
          runId: 'run-2',
          runNumber: 2,
          outcome: RunOutcome.lost,
          lineageId: 'western',
          timestamp: at(2),
        );

      for (final type in [
        MilestoneType.firstAffix,
        MilestoneType.firstTechniqueVariant,
        MilestoneType.firstInspiredTechnique,
      ]) {
        final earned = _matching(recorder, type);
        expect(earned, hasLength(1), reason: '$type');
        expect(earned.single.runNumber, 2, reason: '$type');
        expect(earned.single.contextId, isNull, reason: '$type');
      }
    });

    test('an explicit recordMilestone is idempotent by the same identity', () {
      final recorder =
          AlmanacRecorder()
            ..recordMilestone(
              type: MilestoneType.firstWinWithLineage,
              runId: 'run-4',
              runNumber: 4,
              timestamp: at(4),
              contextId: 'western',
            )
            ..recordMilestone(
              type: MilestoneType.firstWinWithLineage,
              runId: 'run-7',
              runNumber: 7,
              timestamp: at(7),
              contextId: 'western',
            );

      expect(recorder.state.milestones, hasLength(1));
      expect(recorder.state.milestones.single.runNumber, 4);
    });

    test('milestones survive a hydrate and stay idempotent', () {
      final recorder =
          AlmanacRecorder()..evaluateStandardMilestones(
            runId: 'run-4',
            runNumber: 4,
            outcome: RunOutcome.won,
            lineageId: 'western',
            finalBuildId: 'b-final',
            timestamp: at(4),
          );

      final rehydrated = AlmanacRecorder(recorder.state)
        ..evaluateStandardMilestones(
          runId: 'run-9',
          runNumber: 9,
          outcome: RunOutcome.won,
          lineageId: 'western',
          finalBuildId: 'b-final',
          timestamp: at(9),
        );

      expect(rehydrated.state, recorder.state);
      expect(
        _matching(
          rehydrated,
          MilestoneType.firstWinWithLineage,
          contextId: 'western',
        ).single.runNumber,
        4,
      );
    });
  });
}
