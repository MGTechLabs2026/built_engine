/// Phase 4.3 — SP0b ancestry is stored verbatim and order-preserving, and a
/// re-delivered `TechniqueVariantInspired` yields exactly one history record.
///
/// The recorder takes the payload as given: no RNG, no re-resolution, no query
/// back into technique state.
library;

import 'package:build_engine/src/plugins/almanac/almanac_models.dart';
import 'package:build_engine/src/plugins/almanac/almanac_recorder.dart';
import 'package:test/test.dart';

void main() {
  group('inspiration ancestry', () {
    test('stores the payload verbatim, preserving list order', () {
      final recorder =
          AlmanacRecorder()..recordTechniqueInspired(
            resultInstanceId: 'ti-new',
            runId: 'run-1',
            familyId: 'fam-a',
            descriptorIds: ['d3', 'd1', 'd2'],
            inspirerInstanceIds: ['ti-c', 'ti-a', 'ti-b'],
          );

      final history = recorder.state.inspirations.single;
      expect(history.resultInstanceId, 'ti-new');
      expect(history.runId, 'run-1');
      expect(history.familyId, 'fam-a');
      expect(history.descriptorIds, ['d3', 'd1', 'd2']);
      expect(history.inspirerInstanceIds, ['ti-c', 'ti-a', 'ti-b']);
    });

    test('a duplicate delivery yields one history and one technique', () {
      final recorder = AlmanacRecorder();
      for (var i = 0; i < 3; i++) {
        recorder.recordTechniqueInspired(
          resultInstanceId: 'ti-new',
          runId: 'run-1',
          familyId: 'fam-a',
          descriptorIds: ['d1'],
          inspirerInstanceIds: ['ti-a', 'ti-b'],
        );
      }

      expect(recorder.state.inspirations, hasLength(1));
      expect(recorder.state.techniques, hasLength(1));
      expect(recorder.state.techniques.single.origin, TechniqueOrigin.inspired);
    });

    test('the ancestry does not create records for the inspirers', () {
      final recorder =
          AlmanacRecorder()..recordTechniqueInspired(
            resultInstanceId: 'ti-new',
            runId: 'run-1',
            familyId: 'fam-a',
            descriptorIds: ['d1'],
            inspirerInstanceIds: ['ti-a', 'ti-b'],
          );

      // Only the RESULT gets a technique record; the inspirers are references
      // stored verbatim, not entities the recorder invents.
      expect(recorder.state.techniques.map((t) => t.instanceId).toList(), [
        'ti-new',
      ]);
    });

    test('two inspirations in one run are two independent histories', () {
      final recorder =
          AlmanacRecorder()
            ..recordTechniqueInspired(
              resultInstanceId: 'ti-x',
              runId: 'run-1',
              familyId: 'fam-a',
              descriptorIds: ['d1'],
              inspirerInstanceIds: ['ti-a'],
            )
            ..recordTechniqueInspired(
              resultInstanceId: 'ti-y',
              runId: 'run-1',
              familyId: 'fam-b',
              descriptorIds: ['d2'],
              inspirerInstanceIds: ['ti-b'],
            );

      final histories = recorder.state.inspirations;
      expect(histories.map((h) => h.resultInstanceId).toList(), [
        'ti-x',
        'ti-y',
      ]);
      expect(histories.map((h) => h.familyId).toList(), ['fam-a', 'fam-b']);
    });

    test('the ancestry list the caller passed is copied on ingress', () {
      final inspirers = <String>['ti-a'];
      final descriptors = <String>['d1'];
      final recorder =
          AlmanacRecorder()..recordTechniqueInspired(
            resultInstanceId: 'ti-new',
            runId: 'run-1',
            familyId: 'fam-a',
            descriptorIds: descriptors,
            inspirerInstanceIds: inspirers,
          );

      inspirers.add('ti-b');
      descriptors.add('d2');

      expect(recorder.state.inspirations.single.inspirerInstanceIds, ['ti-a']);
      expect(recorder.state.inspirations.single.descriptorIds, ['d1']);
      expect(recorder.state.techniques.single.descriptorIds, ['d1']);
    });

    test('ancestry survives a save-shaped hydrate round trip', () {
      final recorder =
          AlmanacRecorder()..recordTechniqueInspired(
            resultInstanceId: 'ti-new',
            runId: 'run-1',
            familyId: 'fam-a',
            descriptorIds: ['d1', 'd2'],
            inspirerInstanceIds: ['ti-a', 'ti-b'],
          );

      final rehydrated = AlmanacRecorder(recorder.state);
      expect(rehydrated.state, recorder.state);
      expect(rehydrated.state.inspirations.single.inspirerInstanceIds, [
        'ti-a',
        'ti-b',
      ]);
    });
  });
}
