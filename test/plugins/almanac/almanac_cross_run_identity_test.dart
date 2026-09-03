/// Phase 4.9 — a technique's identity is its `instanceId`, not its family.
///
/// The same base family rolled in two runs produces two instances and therefore
/// two independent canonical records; only a shared `instanceId` merges history.
library;

import 'package:build_engine/src/plugins/almanac/almanac_models.dart';
import 'package:build_engine/src/plugins/almanac/almanac_recorder.dart';
import 'package:test/test.dart';

import 'support/almanac_fixtures.dart';

void _discover(
  AlmanacRecorder recorder, {
  required String instanceId,
  required String runId,
  required int runNumber,
  String baseFamilyId = 'fam-a',
  List<String> descriptorIds = const ['d1'],
}) => recorder.recordTechniqueDiscovered(
  instanceId: instanceId,
  baseFamilyId: baseFamilyId,
  descriptorIds: descriptorIds,
  axisProfile: const {'power': 2},
  origin: TechniqueOrigin.base,
  runId: runId,
  runNumber: runNumber,
  timestamp: at(runNumber),
);

void main() {
  group('cross-run technique identity', () {
    test('one family, two runs, two instance ids gives two records', () {
      final recorder = AlmanacRecorder();
      _discover(recorder, instanceId: 'ti-1', runId: 'run-1', runNumber: 1);
      _discover(recorder, instanceId: 'ti-2', runId: 'run-2', runNumber: 2);

      final techniques = recorder.state.techniques;
      expect(techniques, hasLength(2));
      expect(techniques.map((t) => t.instanceId).toList(), ['ti-1', 'ti-2']);
      expect(techniques.every((t) => t.baseFamilyId == 'fam-a'), isTrue);
      expect(techniques.map((t) => t.discoveredRunId).toList(), [
        'run-1',
        'run-2',
      ]);
      expect(techniques.map((t) => t.discoveredRunNumber).toList(), [1, 2]);
    });

    test('their usage ledgers and projections stay separate', () {
      final recorder = AlmanacRecorder();
      _discover(recorder, instanceId: 'ti-1', runId: 'run-1', runNumber: 1);
      _discover(recorder, instanceId: 'ti-2', runId: 'run-2', runNumber: 2);
      recorder
        ..recordTechniqueUsed(
          const TechniqueUsageObservation(
            usageEventId: 'u0',
            runId: 'run-1',
            runNumber: 1,
            instanceId: 'ti-1',
          ),
        )
        ..recordTechniqueUsed(
          const TechniqueUsageObservation(
            usageEventId: 'u1',
            runId: 'run-1',
            runNumber: 1,
            instanceId: 'ti-1',
          ),
        )
        ..recordTechniqueUsed(
          const TechniqueUsageObservation(
            usageEventId: 'u0',
            runId: 'run-2',
            runNumber: 2,
            instanceId: 'ti-2',
          ),
        );

      final techniques = recorder.state.techniques;
      expect(techniques.map((t) => t.totalUsage).toList(), [2, 1]);
      expect(techniques.first.runsUsed, [1]);
      expect(techniques.last.runsUsed, [2]);
    });

    test('one instanceId spanning two runs is one record', () {
      final recorder = AlmanacRecorder();
      _discover(recorder, instanceId: 'ti-1', runId: 'run-1', runNumber: 1);
      recorder
        ..recordTechniqueUsed(
          const TechniqueUsageObservation(
            usageEventId: 'u0',
            runId: 'run-1',
            runNumber: 1,
            instanceId: 'ti-1',
          ),
        )
        ..recordTechniqueUsed(
          const TechniqueUsageObservation(
            usageEventId: 'u0',
            runId: 'run-2',
            runNumber: 2,
            instanceId: 'ti-1',
          ),
        );

      final technique = recorder.state.techniques.single;
      expect(technique.discoveredRunId, 'run-1');
      expect(technique.totalUsage, 2);
      expect(technique.runsUsed, [1, 2]);
    });

    test('a differing descriptor set under one instanceId is a conflict', () {
      final recorder = AlmanacRecorder();
      _discover(
        recorder,
        instanceId: 'ti-1',
        runId: 'run-1',
        runNumber: 1,
        descriptorIds: const ['d1'],
      );

      expect(
        () => _discover(
          recorder,
          instanceId: 'ti-1',
          runId: 'run-2',
          runNumber: 2,
          descriptorIds: const ['d2'],
        ),
        throwsA(isA<AlmanacIntegrityException>()),
      );
      expect(recorder.state.techniques.single.discoveredRunId, 'run-1');
    });

    test('cross-run identity survives a hydrate', () {
      final recorder = AlmanacRecorder();
      _discover(recorder, instanceId: 'ti-1', runId: 'run-1', runNumber: 1);
      _discover(recorder, instanceId: 'ti-2', runId: 'run-2', runNumber: 2);

      final rehydrated = AlmanacRecorder(recorder.state);
      expect(rehydrated.state, recorder.state);
      expect(rehydrated.state.techniques, hasLength(2));
    });
  });
}
