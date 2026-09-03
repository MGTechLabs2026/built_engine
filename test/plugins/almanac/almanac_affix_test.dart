/// Phase 4.5 — one affix accumulates observations across runs into a single
/// record whose counters and lineage union are projections of the ledgers.
library;

import 'package:build_engine/src/plugins/almanac/almanac_models.dart';
import 'package:build_engine/src/plugins/almanac/almanac_recorder.dart';
import 'package:test/test.dart';

import 'support/almanac_fixtures.dart';

const AffixSnapshot _snapshot = AffixSnapshot(
  affixId: 'af-1',
  stat: 'crit',
  value: 0.1,
  category: 'offensive',
);

AffixObservation _seen(
  String affixEventId, {
  String runId = 'run-1',
  int runNumber = 1,
  String? lineageId,
}) => AffixObservation(
  affixEventId: affixEventId,
  runId: runId,
  runNumber: runNumber,
  lineageId: lineageId,
);

void main() {
  group('affix history', () {
    test('three discoveries under one affixId make one record', () {
      final recorder = AlmanacRecorder();
      for (final observation in [
        _seen('ae-0f21', lineageId: 'western'),
        _seen('ae-71bc', runId: 'run-2', runNumber: 2, lineageId: 'eastern'),
        _seen('ae-c390', runId: 'run-3', runNumber: 3, lineageId: 'western'),
      ]) {
        recorder.recordAffixDiscovered(
          affixId: 'af-1',
          observation: observation,
          snapshot: _snapshot,
          timestamp: at(1),
        );
      }

      final affix = recorder.state.affixes.single;
      expect(affix.affixId, 'af-1');
      expect(affix.timesDiscovered, 3);
      expect(affix.discoveryObservations, hasLength(3));
      expect(affix.associatedLineageIds, ['western', 'eastern']);
      expect(affix.firstDiscoveredRunId, 'run-1');
      expect(affix.snapshot, _snapshot);
    });

    test('firstDiscoveredRunId is the observation with the smallest runNumber, '
        'not the first delivered', () {
      final recorder = AlmanacRecorder();
      // Delivered out of runNumber order: 3, then 1, then 2.
      for (final observation in [
        _seen('ae-run3', runId: 'run-3', runNumber: 3, lineageId: 'western'),
        _seen('ae-run1', runId: 'run-1', runNumber: 1, lineageId: 'western'),
        _seen('ae-run2', runId: 'run-2', runNumber: 2, lineageId: 'eastern'),
      ]) {
        recorder.recordAffixDiscovered(
          affixId: 'af-1',
          observation: observation,
          snapshot: _snapshot,
          timestamp: at(1),
        );
      }

      expect(recorder.state.affixes.single.firstDiscoveredRunId, 'run-1');
    });

    test('repeating an affixEventId leaves the record unchanged', () {
      final recorder =
          AlmanacRecorder()
            ..recordAffixDiscovered(
              affixId: 'af-1',
              observation: _seen('ae-0f21', lineageId: 'western'),
              snapshot: _snapshot,
              timestamp: at(1),
            )
            ..recordAffixDiscovered(
              affixId: 'af-1',
              observation: _seen('ae-71bc', lineageId: 'western'),
              snapshot: _snapshot,
              timestamp: at(1),
            );
      final before = recorder.state;

      recorder.recordAffixDiscovered(
        affixId: 'af-1',
        observation: _seen('ae-0f21', lineageId: 'western'),
        snapshot: _snapshot,
        timestamp: at(2),
      );

      expect(recorder.state, before);
      expect(recorder.state.affixes.single.timesDiscovered, 2);
    });

    test('uses are counted on their own ledger', () {
      final recorder =
          AlmanacRecorder()
            ..recordAffixDiscovered(
              affixId: 'af-1',
              observation: _seen('ae-0f21', lineageId: 'western'),
              snapshot: _snapshot,
              timestamp: at(1),
            )
            ..recordAffixUsed(
              affixId: 'af-1',
              observation: _seen('au-1', lineageId: 'western'),
            )
            ..recordAffixUsed(
              affixId: 'af-1',
              observation: _seen('au-2', runId: 'run-2', runNumber: 2),
            )
            ..recordAffixUsed(
              affixId: 'af-1',
              observation: _seen('au-1', lineageId: 'western'),
            );

      final affix = recorder.state.affixes.single;
      expect(affix.timesDiscovered, 1);
      expect(affix.timesUsed, 2);
      expect(affix.usageObservations.map((o) => o.runId).toList(), [
        'run-1',
        'run-2',
      ]);
    });

    test('a use seen before any discovery still records the affix', () {
      final recorder =
          AlmanacRecorder()..recordAffixUsed(
            affixId: 'af-1',
            observation: _seen('au-1', lineageId: 'eastern'),
          );

      final affix = recorder.state.affixes.single;
      expect(affix.timesUsed, 1);
      expect(affix.timesDiscovered, 0);
      expect(affix.firstDiscoveredRunId, isNull);
      expect(affix.associatedLineageIds, ['eastern']);
    });

    test('a later discovery fills the snapshot a use left unknown', () {
      final recorder =
          AlmanacRecorder()
            ..recordAffixUsed(affixId: 'af-1', observation: _seen('au-1'))
            ..recordAffixDiscovered(
              affixId: 'af-1',
              observation: _seen('ae-0f21'),
              snapshot: _snapshot,
              timestamp: at(1),
            );

      expect(recorder.state.affixes.single.snapshot, _snapshot);
    });

    test('lineage ids union without duplicates, in first-seen order', () {
      final recorder =
          AlmanacRecorder()
            ..recordAffixDiscovered(
              affixId: 'af-1',
              observation: _seen('ae-0', lineageId: 'eastern'),
              snapshot: _snapshot,
              timestamp: at(1),
            )
            ..recordAffixUsed(
              affixId: 'af-1',
              observation: _seen('au-0', lineageId: 'western'),
            )
            ..recordAffixUsed(
              affixId: 'af-1',
              observation: _seen('au-1', lineageId: 'eastern'),
            )
            // An observation with no lineage contributes nothing.
            ..recordAffixUsed(affixId: 'af-1', observation: _seen('au-2'));

      expect(recorder.state.affixes.single.associatedLineageIds, [
        'eastern',
        'western',
      ]);
    });

    test('two affixes stay two records in first-seen order', () {
      final recorder =
          AlmanacRecorder()
            ..recordAffixDiscovered(
              affixId: 'af-2',
              observation: _seen('ae-0'),
              snapshot: const AffixSnapshot(
                affixId: 'af-2',
                stat: 'haste',
                value: 2,
              ),
              timestamp: at(1),
            )
            ..recordAffixDiscovered(
              affixId: 'af-1',
              observation: _seen('ae-1'),
              snapshot: _snapshot,
              timestamp: at(1),
            );

      expect(recorder.state.affixes.map((a) => a.affixId).toList(), [
        'af-2',
        'af-1',
      ]);
    });

    test('the affix projections survive a hydrate', () {
      final recorder =
          AlmanacRecorder()
            ..recordAffixDiscovered(
              affixId: 'af-1',
              observation: _seen('ae-0', lineageId: 'western'),
              snapshot: _snapshot,
              timestamp: at(1),
            )
            ..recordAffixUsed(
              affixId: 'af-1',
              observation: _seen('au-0', lineageId: 'eastern'),
            );

      final rehydrated = AlmanacRecorder(recorder.state);
      expect(rehydrated.state, recorder.state);
      expect(rehydrated.state.affixes.single.associatedLineageIds, [
        'western',
        'eastern',
      ]);
    });
  });
}
