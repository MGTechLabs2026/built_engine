/// Phase 4.3 — canonical technique history is identity-stable and monotonic.
///
/// A minted technique and its later inspiration converge on ONE record whose
/// `origin` only ever advances, in either delivery order; a lone inspiration
/// leaves the discovery-time fields unknown rather than inventing them.
library;

import 'package:build_engine/src/plugins/almanac/almanac_models.dart';
import 'package:build_engine/src/plugins/almanac/almanac_recorder.dart';
import 'package:test/test.dart';

import 'support/almanac_fixtures.dart';

void _mint(AlmanacRecorder recorder) => recorder.recordTechniqueDiscovered(
  instanceId: 'ti-1',
  baseFamilyId: 'fam-a',
  styleId: 'style-x',
  descriptorIds: ['d1', 'd2'],
  axisProfile: {'power': 3},
  origin: TechniqueOrigin.base,
  masteryAtDiscovery: 2,
  runId: 'run-1',
  runNumber: 1,
  timestamp: at(1),
);

void _inspire(AlmanacRecorder recorder) => recorder.recordTechniqueInspired(
  resultInstanceId: 'ti-1',
  runId: 'run-1',
  familyId: 'fam-a',
  descriptorIds: ['d1', 'd2'],
  inspirerInstanceIds: ['ti-9', 'ti-8'],
);

void main() {
  group('monotonic completion', () {
    test('minted then inspired converges on one inspired record', () {
      final recorder = AlmanacRecorder();
      _mint(recorder);
      _inspire(recorder);

      final state = recorder.state;
      expect(state.techniques, hasLength(1));
      final technique = state.techniques.single;
      expect(technique.instanceId, 'ti-1');
      expect(technique.origin, TechniqueOrigin.inspired);
      expect(technique.baseFamilyId, 'fam-a');
      expect(technique.styleId, 'style-x');
      expect(technique.descriptorIds, ['d1', 'd2']);
      expect(technique.masteryAtDiscovery, 2);
      expect(state.inspirations.single.inspirerInstanceIds, ['ti-9', 'ti-8']);
    });

    test('inspired then minted converges on the same one record', () {
      final recorder = AlmanacRecorder();
      _inspire(recorder);
      _mint(recorder);

      final state = recorder.state;
      expect(state.techniques, hasLength(1));
      final technique = state.techniques.single;
      // `base` arriving after `inspired` never walks the origin back.
      expect(technique.origin, TechniqueOrigin.inspired);
      expect(technique.styleId, 'style-x');
      expect(technique.masteryAtDiscovery, 2);
      expect(technique.discoveredRunId, 'run-1');
      expect(state.inspirations.single.inspirerInstanceIds, ['ti-9', 'ti-8']);
    });

    test('both orders produce structurally identical state', () {
      final forwards = AlmanacRecorder();
      _mint(forwards);
      _inspire(forwards);

      final backwards = AlmanacRecorder();
      _inspire(backwards);
      _mint(backwards);

      expect(backwards.state, forwards.state);
    });

    test('a lone inspiration leaves the discovery fields unknown', () {
      final recorder = AlmanacRecorder();
      _inspire(recorder);

      final technique = recorder.state.techniques.single;
      expect(technique.origin, TechniqueOrigin.inspired);
      expect(technique.baseFamilyId, 'fam-a');
      expect(technique.descriptorIds, ['d1', 'd2']);
      expect(technique.discoveredRunId, isNull);
      expect(technique.discoveredRunNumber, isNull);
      expect(technique.masteryAtDiscovery, isNull);
      expect(technique.styleId, isNull);
      // ...but the full ancestry is stored all the same.
      expect(recorder.state.inspirations.single.runId, 'run-1');
      expect(recorder.state.inspirations.single.familyId, 'fam-a');
    });

    test('a later discovery fills a field the first delivery left unknown', () {
      final recorder =
          AlmanacRecorder()
            ..recordTechniqueDiscovered(
              instanceId: 'ti-1',
              baseFamilyId: 'fam-a',
              descriptorIds: ['d1'],
              axisProfile: {'power': 1},
              origin: TechniqueOrigin.base,
              runId: 'run-1',
              runNumber: 1,
              timestamp: at(1),
            )
            ..recordTechniqueDiscovered(
              instanceId: 'ti-1',
              baseFamilyId: 'fam-a',
              styleId: 'style-x',
              descriptorIds: ['d1'],
              axisProfile: {'power': 1},
              origin: TechniqueOrigin.base,
              masteryAtDiscovery: 4,
              runId: 'run-1',
              runNumber: 1,
              timestamp: at(1),
            );

      final technique = recorder.state.techniques.single;
      expect(technique.styleId, 'style-x');
      expect(technique.masteryAtDiscovery, 4);
    });

    test(
      'a completed field yields a NEW record instance, never a mutation',
      () {
        final recorder = AlmanacRecorder();
        _mint(recorder);
        final before = recorder.state.techniques.single;

        _inspire(recorder);
        final after = recorder.state.techniques.single;

        expect(before.origin, TechniqueOrigin.base);
        expect(after.origin, TechniqueOrigin.inspired);
        expect(identical(before, after), isFalse);
      },
    );

    test('the monotonic history survives a hydrate', () {
      final recorder = AlmanacRecorder();
      _mint(recorder);
      _inspire(recorder);

      final rehydrated = AlmanacRecorder(recorder.state).state;
      expect(rehydrated.techniques.single.origin, TechniqueOrigin.inspired);
      expect(rehydrated, recorder.state);
    });
  });
}
