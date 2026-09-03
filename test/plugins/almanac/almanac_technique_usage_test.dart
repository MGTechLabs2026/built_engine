/// Phase 4.4 — technique usage is an append-only ledger keyed structurally by
/// `(runId, usageEventId)`, and `totalUsage` / `runsUsed` / `techniquesUsed`
/// are projections recomputed from it.
///
/// Idempotency must survive persistence, so one case delivers the same
/// observation either side of a real `encode` → `decode` → hydrate round trip.
library;

import 'package:build_engine/src/plugins/almanac/almanac_models.dart';
import 'package:build_engine/src/plugins/almanac/almanac_recorder.dart';
import 'package:build_engine/src/plugins/almanac/almanac_serialization.dart';
import 'package:test/test.dart';

import 'support/almanac_fixtures.dart';

TechniqueUsageObservation _use(
  String usageEventId, {
  String runId = 'run-1',
  int runNumber = 1,
  String instanceId = 'ti-1',
}) => TechniqueUsageObservation(
  usageEventId: usageEventId,
  runId: runId,
  runNumber: runNumber,
  instanceId: instanceId,
);

AlmanacRecorder _withTechnique() =>
    AlmanacRecorder()..recordTechniqueDiscovered(
      instanceId: 'ti-1',
      baseFamilyId: 'fam-a',
      descriptorIds: const [],
      axisProfile: const {},
      origin: TechniqueOrigin.base,
      runId: 'run-1',
      runNumber: 1,
      timestamp: at(1),
    );

void main() {
  group('technique usage', () {
    test('two distinct usage ids in one run count twice, one run used', () {
      final recorder =
          _withTechnique()
            ..recordTechniqueUsed(_use('u0'))
            ..recordTechniqueUsed(_use('u1'));

      final technique = recorder.state.techniques.single;
      expect(technique.usageObservations, hasLength(2));
      expect(technique.totalUsage, 2);
      expect(technique.runsUsed, [1]);
    });

    test('a replayed usageEventId counts once', () {
      final recorder =
          _withTechnique()
            ..recordTechniqueUsed(_use('u0'))
            ..recordTechniqueUsed(_use('u1'))
            ..recordTechniqueUsed(_use('u0'));

      expect(recorder.state.techniques.single.totalUsage, 2);
    });

    test('usage across two runs lists both run numbers once each', () {
      final recorder =
          _withTechnique()
            ..recordTechniqueUsed(_use('u0'))
            ..recordTechniqueUsed(_use('u1', runId: 'run-2', runNumber: 2))
            ..recordTechniqueUsed(_use('u2', runId: 'run-2', runNumber: 2));

      final technique = recorder.state.techniques.single;
      expect(technique.totalUsage, 3);
      expect(technique.runsUsed, [1, 2]);
    });

    test('totalUsage always equals the ledger length', () {
      final recorder = _withTechnique();
      for (final id in ['u0', 'u1', 'u2', 'u0', 'u1']) {
        recorder.recordTechniqueUsed(_use(id));
      }

      final technique = recorder.state.techniques.single;
      expect(technique.totalUsage, technique.usageObservations.length);
      expect(technique.totalUsage, 3);
    });

    test("a run's techniquesUsed counts the observations bound to it", () {
      final recorder =
          _withTechnique()
            ..beginRun(
              runId: 'run-1',
              runNumber: 1,
              lineageId: 'western',
              physiqueId: 'phy-a',
              startedAt: at(1),
            )
            ..beginRun(
              runId: 'run-2',
              runNumber: 2,
              lineageId: 'western',
              physiqueId: 'phy-a',
              startedAt: at(2),
            )
            ..recordTechniqueUsed(_use('u0'))
            ..recordTechniqueUsed(_use('u1'))
            ..recordTechniqueUsed(_use('u2', runId: 'run-2', runNumber: 2));

      final state = recorder.state;
      final observations = state.techniques.single.usageObservations;
      expect(
        state.runs.first.techniquesUsed,
        observations.where((o) => o.runId == 'run-1').length,
      );
      expect(state.runs.first.techniquesUsed, 2);
      expect(state.runs.last.techniquesUsed, 1);
    });

    test('two techniques keep independent ledgers', () {
      final recorder =
          _withTechnique()
            ..recordTechniqueDiscovered(
              instanceId: 'ti-2',
              baseFamilyId: 'fam-b',
              descriptorIds: const [],
              axisProfile: const {},
              origin: TechniqueOrigin.base,
              runId: 'run-1',
              runNumber: 1,
              timestamp: at(1),
            )
            // The SAME opaque usage id, in the same run, on a different instance.
            ..recordTechniqueUsed(_use('u0'))
            ..recordTechniqueUsed(_use('u0', instanceId: 'ti-2'));

      final techniques = recorder.state.techniques;
      expect(techniques.map((t) => t.totalUsage).toList(), [1, 1]);
      expect(
        techniques.map((t) => t.usageObservations.single.instanceId).toList(),
        ['ti-1', 'ti-2'],
      );
    });

    test('usage for a technique never discovered still records', () {
      final recorder = AlmanacRecorder()..recordTechniqueUsed(_use('u0'));

      final technique = recorder.state.techniques.single;
      expect(technique.instanceId, 'ti-1');
      expect(technique.totalUsage, 1);
      expect(technique.discoveredRunId, isNull);
    });

    test('idempotency survives a save → load between deliveries', () {
      final first = _withTechnique()..recordTechniqueUsed(_use('u0'));

      // Persist and reload exactly as the repository would.
      final reloaded = AlmanacRecorder(
        AlmanacSerialization.decode(AlmanacSerialization.encode(first.state)),
      );
      expect(reloaded.state.techniques.single.totalUsage, 1);

      // Re-deliver the very same observation on the far side of the round trip.
      reloaded.recordTechniqueUsed(_use('u0'));

      final technique = reloaded.state.techniques.single;
      expect(technique.totalUsage, 1);
      expect(technique.usageObservations, hasLength(1));
      expect(technique.runsUsed, [1]);
    });

    test('a new observation after a save → load appends normally', () {
      final first = _withTechnique()..recordTechniqueUsed(_use('u0'));
      final reloaded = AlmanacRecorder(
        AlmanacSerialization.decode(AlmanacSerialization.encode(first.state)),
      )..recordTechniqueUsed(_use('u1', runId: 'run-2', runNumber: 2));

      final technique = reloaded.state.techniques.single;
      expect(technique.totalUsage, 2);
      expect(technique.runsUsed, [1, 2]);
    });
  });
}
