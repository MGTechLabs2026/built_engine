/// Phase 4.4 — the recorder assumes NO global uniqueness for the opaque event
/// ids it is handed. `usageEventId`, `fightId`, `trainingEventId`, `buildId`
/// and `affixEventId` are unique only inside their structural key's domain, so
/// the same string under two different runs is two different things.
library;

import 'package:build_engine/src/plugins/almanac/almanac_models.dart';
import 'package:build_engine/src/plugins/almanac/almanac_recorder.dart';
import 'package:test/test.dart';

import 'support/almanac_fixtures.dart';

void main() {
  group('uniqueness domain', () {
    test('one usageEventId under two runIds is two observations', () {
      final recorder =
          AlmanacRecorder()
            ..recordTechniqueUsed(
              const TechniqueUsageObservation(
                usageEventId: 'action-8f3a91',
                runId: 'run-A',
                runNumber: 1,
                instanceId: 'ti-1',
              ),
            )
            ..recordTechniqueUsed(
              const TechniqueUsageObservation(
                usageEventId: 'action-8f3a91',
                runId: 'run-B',
                runNumber: 2,
                instanceId: 'ti-1',
              ),
            );

      final technique = recorder.state.techniques.single;
      expect(technique.usageObservations, hasLength(2));
      expect(technique.totalUsage, 2);
      expect(technique.runsUsed, [1, 2]);
      expect(technique.usageObservations.map((o) => o.runId).toList(), [
        'run-A',
        'run-B',
      ]);
    });

    test('the pair, not the bare string, decides idempotency', () {
      final recorder = AlmanacRecorder();
      for (final runId in ['run-A', 'run-B', 'run-A', 'run-B']) {
        recorder.recordTechniqueUsed(
          TechniqueUsageObservation(
            usageEventId: 'shared',
            runId: runId,
            runNumber: runId == 'run-A' ? 1 : 2,
            instanceId: 'ti-1',
          ),
        );
      }

      expect(recorder.state.techniques.single.totalUsage, 2);
    });

    test('one trainingEventId under two runIds is two observations', () {
      final recorder =
          AlmanacRecorder()
            ..recordTrainingSession(
              const TrainingObservation(
                trainingEventId: 'shared',
                runId: 'run-A',
                runNumber: 1,
              ),
            )
            ..recordTrainingSession(
              const TrainingObservation(
                trainingEventId: 'shared',
                runId: 'run-B',
                runNumber: 2,
              ),
            );

      final runs = recorder.state.runs;
      expect(runs, hasLength(2));
      expect(runs.map((r) => r.trainingSessions).toList(), [1, 1]);
      expect(runs.first.trainingObservations.single.runId, 'run-A');
    });

    test('one affixEventId under two affixIds is two observations', () {
      const snapshot = AffixSnapshot(affixId: 'x', stat: 'crit', value: 1);
      final recorder =
          AlmanacRecorder()
            ..recordAffixDiscovered(
              affixId: 'af-1',
              observation: const AffixObservation(
                affixEventId: 'shared',
                runId: 'run-1',
                runNumber: 1,
              ),
              snapshot: snapshot,
              timestamp: at(1),
            )
            ..recordAffixDiscovered(
              affixId: 'af-2',
              observation: const AffixObservation(
                affixEventId: 'shared',
                runId: 'run-1',
                runNumber: 1,
              ),
              snapshot: snapshot,
              timestamp: at(1),
            );

      expect(recorder.state.affixes, hasLength(2));
      expect(recorder.state.affixes.map((a) => a.timesDiscovered).toList(), [
        1,
        1,
      ]);
    });

    test('the discovery and usage ledgers are separate key domains', () {
      final recorder =
          AlmanacRecorder()
            ..recordAffixDiscovered(
              affixId: 'af-1',
              observation: const AffixObservation(
                affixEventId: 'shared',
                runId: 'run-1',
                runNumber: 1,
              ),
              snapshot: const AffixSnapshot(
                affixId: 'af-1',
                stat: 'crit',
                value: 1,
              ),
              timestamp: at(1),
            )
            ..recordAffixUsed(
              affixId: 'af-1',
              observation: const AffixObservation(
                affixEventId: 'shared',
                runId: 'run-1',
                runNumber: 1,
              ),
            );

      final affix = recorder.state.affixes.single;
      expect(affix.timesDiscovered, 1);
      expect(affix.timesUsed, 1);
    });

    test('the whole uniqueness domain survives a hydrate', () {
      final recorder =
          AlmanacRecorder()
            ..recordTechniqueUsed(
              const TechniqueUsageObservation(
                usageEventId: 'shared',
                runId: 'run-A',
                runNumber: 1,
                instanceId: 'ti-1',
              ),
            )
            ..recordTechniqueUsed(
              const TechniqueUsageObservation(
                usageEventId: 'shared',
                runId: 'run-B',
                runNumber: 2,
                instanceId: 'ti-1',
              ),
            );

      final rehydrated = AlmanacRecorder(recorder.state);
      expect(rehydrated.state, recorder.state);
      // ...and it is still idempotent afterwards.
      rehydrated.recordTechniqueUsed(
        const TechniqueUsageObservation(
          usageEventId: 'shared',
          runId: 'run-A',
          runNumber: 1,
          instanceId: 'ti-1',
        ),
      );
      expect(rehydrated.state.techniques.single.totalUsage, 2);
    });
  });
}
