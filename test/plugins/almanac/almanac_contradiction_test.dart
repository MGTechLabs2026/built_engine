/// Phase 4.3 — a contradicting write is refused and the established value is
/// retained. Never a silent overwrite, never a merge, never a recovery.
library;

import 'package:build_engine/src/plugins/almanac/almanac_models.dart';
import 'package:build_engine/src/plugins/almanac/almanac_recorder.dart';
import 'package:test/test.dart';

import 'support/almanac_fixtures.dart';

void main() {
  group('contradiction', () {
    test('conflicting descriptorIds for one instanceId are refused', () {
      final recorder =
          AlmanacRecorder()..recordTechniqueDiscovered(
            instanceId: 'ti-1',
            baseFamilyId: 'fam-a',
            descriptorIds: ['d1', 'd2'],
            axisProfile: {'power': 3},
            origin: TechniqueOrigin.base,
            runId: 'run-1',
            runNumber: 1,
            timestamp: at(1),
          );

      expect(
        () => recorder.recordTechniqueDiscovered(
          instanceId: 'ti-1',
          baseFamilyId: 'fam-a',
          descriptorIds: ['d1', 'd9'],
          axisProfile: {'power': 3},
          origin: TechniqueOrigin.base,
          runId: 'run-1',
          runNumber: 1,
          timestamp: at(1),
        ),
        throwsA(
          isA<AlmanacIntegrityException>()
              .having((e) => e.field, 'field', 'descriptorIds')
              .having((e) => e.record, 'record', contains('instanceId=ti-1'))
              .having((e) => e.established, 'established', ['d1', 'd2'])
              .having((e) => e.rejected, 'rejected', ['d1', 'd9']),
        ),
      );
      expect(recorder.state.techniques.single.descriptorIds, ['d1', 'd2']);
    });

    test('descriptor order is part of the value, not a set', () {
      final recorder =
          AlmanacRecorder()..recordTechniqueDiscovered(
            instanceId: 'ti-1',
            baseFamilyId: 'fam-a',
            descriptorIds: ['d1', 'd2'],
            axisProfile: const {},
            origin: TechniqueOrigin.base,
            runId: 'run-1',
            runNumber: 1,
            timestamp: at(1),
          );

      expect(
        () => recorder.recordTechniqueDiscovered(
          instanceId: 'ti-1',
          baseFamilyId: 'fam-a',
          descriptorIds: ['d2', 'd1'],
          axisProfile: const {},
          origin: TechniqueOrigin.base,
          runId: 'run-1',
          runNumber: 1,
          timestamp: at(1),
        ),
        throwsA(isA<AlmanacIntegrityException>()),
      );
      expect(recorder.state.techniques.single.descriptorIds, ['d1', 'd2']);
    });

    test('a conflicting axisProfile is refused', () {
      final recorder =
          AlmanacRecorder()..recordTechniqueDiscovered(
            instanceId: 'ti-1',
            baseFamilyId: 'fam-a',
            descriptorIds: const [],
            axisProfile: {'power': 3},
            origin: TechniqueOrigin.base,
            runId: 'run-1',
            runNumber: 1,
            timestamp: at(1),
          );

      expect(
        () => recorder.recordTechniqueDiscovered(
          instanceId: 'ti-1',
          baseFamilyId: 'fam-a',
          descriptorIds: const [],
          axisProfile: {'power': 4},
          origin: TechniqueOrigin.base,
          runId: 'run-1',
          runNumber: 1,
          timestamp: at(1),
        ),
        throwsA(
          isA<AlmanacIntegrityException>().having(
            (e) => e.field,
            'field',
            'axisProfile',
          ),
        ),
      );
      expect(recorder.state.techniques.single.axisProfile, {'power': 3});
    });

    test('conflicting inspirerInstanceIds are refused, ancestry kept', () {
      final recorder =
          AlmanacRecorder()..recordTechniqueInspired(
            resultInstanceId: 'ti-1',
            runId: 'run-1',
            familyId: 'fam-a',
            descriptorIds: ['d1'],
            inspirerInstanceIds: ['ti-9', 'ti-8'],
          );

      expect(
        () => recorder.recordTechniqueInspired(
          resultInstanceId: 'ti-1',
          runId: 'run-1',
          familyId: 'fam-a',
          descriptorIds: ['d1'],
          inspirerInstanceIds: ['ti-8', 'ti-9'],
        ),
        throwsA(
          isA<AlmanacIntegrityException>().having(
            (e) => e.field,
            'field',
            'inspirerInstanceIds',
          ),
        ),
      );
      expect(recorder.state.inspirations.single.inspirerInstanceIds, [
        'ti-9',
        'ti-8',
      ]);
      expect(recorder.state.inspirations, hasLength(1));
    });

    test('a refused inspiration leaves the technique record untouched', () {
      final recorder =
          AlmanacRecorder()..recordTechniqueInspired(
            resultInstanceId: 'ti-1',
            runId: 'run-1',
            familyId: 'fam-a',
            descriptorIds: ['d1'],
            inspirerInstanceIds: ['ti-9'],
          );
      final before = recorder.state;

      expect(
        () => recorder.recordTechniqueInspired(
          resultInstanceId: 'ti-1',
          runId: 'run-2',
          familyId: 'fam-a',
          descriptorIds: ['d1'],
          inspirerInstanceIds: ['ti-9'],
        ),
        throwsA(
          isA<AlmanacIntegrityException>().having(
            (e) => e.field,
            'field',
            'runId',
          ),
        ),
      );
      expect(recorder.state, before);
    });

    test('a conflicting build snapshot for an existing key is refused', () {
      final established = buildRecord(
        runId: 'run-A',
        buildId: 'build-1',
        techniques: [
          techniqueSnapshot(instanceId: 'ti-1', baseFamilyId: 'fam-a'),
        ],
      );
      final recorder = AlmanacRecorder()..recordBuildSnapshot(established);

      expect(
        () => recorder.recordBuildSnapshot(
          buildRecord(
            runId: 'run-A',
            buildId: 'build-1',
            techniques: [
              techniqueSnapshot(instanceId: 'ti-2', baseFamilyId: 'fam-b'),
            ],
          ),
        ),
        throwsA(
          isA<AlmanacIntegrityException>()
              .having((e) => e.field, 'field', 'techniques')
              .having((e) => e.record, 'record', contains('runId=run-A'))
              .having((e) => e.record, 'record', contains('buildId=build-1')),
        ),
      );
      expect(recorder.state.builds.single, established);
    });

    test('a conflicting affix snapshot for an existing affixId is refused', () {
      final recorder =
          AlmanacRecorder()..recordAffixDiscovered(
            affixId: 'af-1',
            observation: const AffixObservation(
              affixEventId: 'ae0',
              runId: 'run-1',
              runNumber: 1,
            ),
            snapshot: const AffixSnapshot(
              affixId: 'af-1',
              stat: 'crit',
              value: 0.1,
            ),
            timestamp: at(1),
          );

      expect(
        () => recorder.recordAffixDiscovered(
          affixId: 'af-1',
          observation: const AffixObservation(
            affixEventId: 'ae1',
            runId: 'run-1',
            runNumber: 1,
          ),
          snapshot: const AffixSnapshot(
            affixId: 'af-1',
            stat: 'crit',
            value: 0.9,
          ),
          timestamp: at(1),
        ),
        throwsA(
          isA<AlmanacIntegrityException>().having(
            (e) => e.field,
            'field',
            'snapshot',
          ),
        ),
      );
      final affix = recorder.state.affixes.single;
      expect(affix.snapshot.value, 0.1);
      // The refused call appended nothing either.
      expect(affix.timesDiscovered, 1);
    });

    test('the exception message names the record, field and both values', () {
      final recorder =
          AlmanacRecorder()..beginRun(
            runId: 'run-1',
            runNumber: 1,
            lineageId: 'western',
            physiqueId: 'phy-a',
            startedAt: at(1),
          );

      expect(
        () => recorder.beginRun(
          runId: 'run-1',
          runNumber: 2,
          lineageId: 'western',
          physiqueId: 'phy-a',
          startedAt: at(1),
        ),
        throwsA(
          isA<AlmanacIntegrityException>().having(
            (e) => e.toString(),
            'toString',
            allOf(
              contains('AlmanacRunRecord(runId=run-1)'),
              contains('runNumber'),
              contains('already 1'),
              contains('with 2'),
            ),
          ),
        ),
      );
    });
  });
}
