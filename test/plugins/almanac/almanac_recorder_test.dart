/// Phase 4.1 / 4.9 — the recorder's run lifecycle and its whole-surface
/// happy path, plus the projection-vs-ledger invariant after an arbitrary
/// event sequence.
library;

import 'package:build_engine/src/plugins/almanac/almanac_models.dart';
import 'package:build_engine/src/plugins/almanac/almanac_recorder.dart';
import 'package:test/test.dart';

import 'support/almanac_fixtures.dart';

void main() {
  group('run lifecycle', () {
    test('begin then complete yields one fully-formed run record', () {
      final recorder =
          AlmanacRecorder()
            ..beginRun(
              runId: 'run-1',
              runNumber: 1,
              seed: 42,
              lineageId: 'western',
              physiqueId: 'phy-a',
              startedAt: at(1),
            )
            ..completeRun(
              runId: 'run-1',
              completedAt: at(2),
              outcome: RunOutcome.won,
              finalBuildId: 'b-final',
            );

      final run = recorder.state.runs.single;
      expect(run.runId, 'run-1');
      expect(run.runNumber, 1);
      expect(run.seed, 42);
      expect(run.lineageId, 'western');
      expect(run.physiqueId, 'phy-a');
      expect(run.startedAt, at(1));
      expect(run.completedAt, at(2));
      expect(run.outcome, RunOutcome.won);
      expect(run.finalBuildId, 'b-final');
    });

    test('an in-flight run reads as not-yet-completed', () {
      final recorder =
          AlmanacRecorder()..beginRun(
            runId: 'run-1',
            runNumber: 1,
            lineageId: 'western',
            physiqueId: 'phy-a',
            startedAt: at(1),
          );

      final run = recorder.state.runs.single;
      expect(run.completedAt, isNull);
      expect(run.finalBuildId, isNull);
      expect(run.seed, isNull);
    });

    test('beginRun twice with the same values records one run', () {
      final recorder = AlmanacRecorder();
      for (var i = 0; i < 2; i++) {
        recorder.beginRun(
          runId: 'run-1',
          runNumber: 1,
          seed: 42,
          lineageId: 'western',
          physiqueId: 'phy-a',
          startedAt: at(1),
        );
      }

      expect(recorder.state.runs, hasLength(1));
      expect(recorder.state.runs.single.runNumber, 1);
    });

    test('a later beginRun fills a field that was still unknown', () {
      final recorder =
          AlmanacRecorder()
            ..beginRun(
              runId: 'run-1',
              runNumber: 1,
              lineageId: 'western',
              physiqueId: 'phy-a',
              startedAt: at(1),
            )
            ..beginRun(
              runId: 'run-1',
              runNumber: 1,
              seed: 42,
              lineageId: 'western',
              physiqueId: 'phy-a',
              startedAt: at(1),
            );

      expect(recorder.state.runs.single.seed, 42);
    });

    test('a conflicting beginRun field is refused and the first is kept', () {
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
          runNumber: 1,
          lineageId: 'eastern',
          physiqueId: 'phy-a',
          startedAt: at(1),
        ),
        throwsA(
          isA<AlmanacIntegrityException>()
              .having((e) => e.field, 'field', 'lineageId')
              .having((e) => e.established, 'established', 'western')
              .having((e) => e.rejected, 'rejected', 'eastern'),
        ),
      );
      expect(recorder.state.runs.single.lineageId, 'western');
    });

    test('a conflicting completeRun is refused and the first outcome kept', () {
      final recorder =
          AlmanacRecorder()
            ..beginRun(
              runId: 'run-1',
              runNumber: 1,
              lineageId: 'western',
              physiqueId: 'phy-a',
              startedAt: at(1),
            )
            ..completeRun(
              runId: 'run-1',
              completedAt: at(2),
              outcome: RunOutcome.won,
            );

      expect(
        () => recorder.completeRun(
          runId: 'run-1',
          completedAt: at(2),
          outcome: RunOutcome.lost,
        ),
        throwsA(isA<AlmanacIntegrityException>()),
      );
      expect(recorder.state.runs.single.outcome, RunOutcome.won);
    });

    test('completeRun twice with the same values is a no-op', () {
      final recorder =
          AlmanacRecorder()..beginRun(
            runId: 'run-1',
            runNumber: 1,
            lineageId: 'western',
            physiqueId: 'phy-a',
            startedAt: at(1),
          );
      for (var i = 0; i < 2; i++) {
        recorder.completeRun(
          runId: 'run-1',
          completedAt: at(2),
          outcome: RunOutcome.won,
          finalBuildId: 'b-final',
        );
      }

      expect(recorder.state.runs, hasLength(1));
      expect(recorder.state.runs.single.finalBuildId, 'b-final');
    });

    test('two runs stay separate and keep their insertion order', () {
      final recorder =
          AlmanacRecorder()
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
              lineageId: 'eastern',
              physiqueId: 'phy-b',
              startedAt: at(2),
            )
            ..completeRun(
              runId: 'run-1',
              completedAt: at(3),
              outcome: RunOutcome.lost,
            );

      final runs = recorder.state.runs;
      expect(runs.map((r) => r.runId).toList(), ['run-1', 'run-2']);
      expect(runs.first.outcome, RunOutcome.lost);
      expect(runs.last.outcome, RunOutcome.abandoned);
      expect(runs.last.completedAt, isNull);
    });
  });

  group('whole surface', () {
    /// Drives every public `record…` entry point once, in an order that mixes
    /// runs, so the resulting state exercises the full materialiser.
    AlmanacRecorder driveEverything() {
      final recorder =
          AlmanacRecorder()
            ..beginRun(
              runId: 'run-1',
              runNumber: 1,
              seed: 7,
              lineageId: 'western',
              physiqueId: 'phy-a',
              startedAt: at(1),
            )
            ..recordFight(
              runId: 'run-1',
              fightId: 'f0',
              sequence: 0,
              name: 'Bandit',
              enemyId: 'enemy-bandit',
              won: true,
              playerHealthAfter: 12,
              turnsUsed: 5,
            )
            ..recordFight(
              runId: 'run-1',
              fightId: 'f1',
              sequence: 1,
              name: 'Bandit',
              enemyId: 'enemy-bandit',
              won: false,
              playerHealthAfter: 0,
              turnsUsed: 5,
            )
            ..recordTechniqueDiscovered(
              instanceId: 'ti-1',
              baseFamilyId: 'fam-a',
              styleId: 'style-x',
              descriptorIds: ['d1'],
              axisProfile: {'power': 2},
              origin: TechniqueOrigin.base,
              masteryAtDiscovery: 1,
              runId: 'run-1',
              runNumber: 1,
              timestamp: at(1),
            )
            ..recordTechniqueUsed(
              const TechniqueUsageObservation(
                usageEventId: 'u0',
                runId: 'run-1',
                runNumber: 1,
                instanceId: 'ti-1',
              ),
            )
            ..recordTechniqueInspired(
              resultInstanceId: 'ti-2',
              runId: 'run-1',
              familyId: 'fam-a',
              descriptorIds: ['d1', 'd2'],
              inspirerInstanceIds: ['ti-1'],
            )
            ..recordItemDiscovered(
              definitionId: 'iron_sword',
              instanceId: 'item-inst-1',
              runId: 'run-1',
              runNumber: 1,
              timestamp: at(1),
              snapshot: discoverySnapshot(label: 'item'),
            )
            ..recordAffixDiscovered(
              affixId: 'af-1',
              observation: const AffixObservation(
                affixEventId: 'ae0',
                runId: 'run-1',
                runNumber: 1,
                lineageId: 'western',
              ),
              snapshot: const AffixSnapshot(
                affixId: 'af-1',
                stat: 'crit',
                value: 0.1,
                category: 'offensive',
              ),
              timestamp: at(1),
            )
            ..recordAffixUsed(
              affixId: 'af-1',
              observation: const AffixObservation(
                affixEventId: 'ae1',
                runId: 'run-1',
                runNumber: 1,
                lineageId: 'western',
              ),
            )
            ..recordTrainingSession(
              const TrainingObservation(
                trainingEventId: 'tr0',
                runId: 'run-1',
                runNumber: 1,
              ),
            )
            ..recordBuildSnapshot(
              buildRecord(runId: 'run-1', buildId: 'b-final'),
            )
            ..recordDiscovery(
              AlmanacDiscoveryRecord(
                discoveryId: 'lineage:western',
                type: AlmanacDiscoveryType.lineage,
                contentId: 'western',
                runId: 'run-1',
                runNumber: 1,
                timestamp: at(1),
                snapshot: discoverySnapshot(label: 'lineage'),
              ),
            )
            ..recordMilestone(
              type: MilestoneType.firstRun,
              runId: 'run-1',
              runNumber: 1,
              timestamp: at(1),
            )
            ..completeRun(
              runId: 'run-1',
              completedAt: at(2),
              outcome: RunOutcome.won,
              finalBuildId: 'b-final',
            );
      recorder.evaluateStandardMilestones(
        runId: 'run-1',
        runNumber: 1,
        outcome: RunOutcome.won,
        lineageId: 'western',
        finalBuildId: 'b-final',
        timestamp: at(2),
      );
      return recorder;
    }

    test('every entry point lands in the state exactly once', () {
      final state = driveEverything().state;

      expect(state.runs, hasLength(1));
      expect(state.runs.single.fights, hasLength(2));
      expect(state.runs.single.trainingObservations, hasLength(1));
      expect(state.builds, hasLength(1));
      expect(state.techniques.map((t) => t.instanceId).toList(), [
        'ti-1',
        'ti-2',
      ]);
      expect(state.inspirations, hasLength(1));
      expect(state.affixes, hasLength(1));
      expect(state.discoveries.map((d) => d.discoveryId).toList(), [
        'techniqueVariant:ti-1',
        'item:iron_sword',
        'lineage:western',
      ]);
      expect(state.milestones, isNotEmpty);
    });

    test('projections equal a fresh recompute from the ledgers', () {
      final state = driveEverything().state;

      final run = state.runs.single;
      expect(run.enemiesDefeated, run.fights.where((f) => f.won).length);
      expect(run.trainingSessions, run.trainingObservations.length);
      expect(
        run.techniquesUsed,
        state.techniques.fold<int>(
          0,
          (total, t) =>
              total +
              t.usageObservations.where((o) => o.runId == run.runId).length,
        ),
      );
      for (final technique in state.techniques) {
        expect(technique.totalUsage, technique.usageObservations.length);
        expect(
          technique.runsUsed,
          technique.usageObservations.map((o) => o.runNumber).toSet().toList(),
        );
      }
      for (final affix in state.affixes) {
        expect(affix.timesDiscovered, affix.discoveryObservations.length);
        expect(affix.timesUsed, affix.usageObservations.length);
      }
    });

    test('replaying the whole sequence twice changes nothing', () {
      final once = driveEverything().state;
      final twice = driveEverything().state;
      expect(twice, once);

      // And a hydrate of the result is a fixed point.
      expect(AlmanacRecorder(once).state, once);
    });

    test('the run index links the discoveries recorded during it', () {
      final run = driveEverything().state.runs.single;
      expect(run.discoveryIds, [
        'techniqueVariant:ti-1',
        'item:iron_sword',
        'lineage:western',
      ]);
    });
  });

  group('training sessions', () {
    test('two distinct training ids in one run count twice', () {
      final recorder =
          AlmanacRecorder()
            ..recordTrainingSession(
              const TrainingObservation(
                trainingEventId: 'tr0',
                runId: 'run-1',
                runNumber: 1,
              ),
            )
            ..recordTrainingSession(
              const TrainingObservation(
                trainingEventId: 'tr1',
                runId: 'run-1',
                runNumber: 1,
              ),
            )
            ..recordTrainingSession(
              const TrainingObservation(
                trainingEventId: 'tr0',
                runId: 'run-1',
                runNumber: 1,
              ),
            );

      final run = recorder.state.runs.single;
      expect(run.trainingObservations, hasLength(2));
      expect(run.trainingSessions, 2);
      expect(run.trainingObservations.map((o) => o.trainingEventId).toList(), [
        'tr0',
        'tr1',
      ]);
    });
  });

  group('discoveries', () {
    AlmanacDiscoveryRecord techniqueDiscovery({
      required String runId,
      required int runNumber,
      required DateTime timestamp,
    }) => AlmanacDiscoveryRecord(
      discoveryId: 'technique:fam-a',
      type: AlmanacDiscoveryType.technique,
      contentId: 'fam-a',
      runId: runId,
      runNumber: runNumber,
      timestamp: timestamp,
      snapshot: discoverySnapshot(label: 'technique'),
    );

    test('the first sighting is canonical; a later run adds nothing', () {
      final recorder =
          AlmanacRecorder()
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
            ..recordDiscovery(
              techniqueDiscovery(
                runId: 'run-1',
                runNumber: 1,
                timestamp: at(1),
              ),
            )
            ..recordDiscovery(
              techniqueDiscovery(
                runId: 'run-2',
                runNumber: 2,
                timestamp: at(2),
              ),
            );

      final discovery = recorder.state.discoveries.single;
      expect(discovery.runId, 'run-1');
      expect(discovery.runNumber, 1);
      expect(discovery.timestamp, at(1));
      // Only the run that first saw it carries the back-reference.
      expect(recorder.state.runs.first.discoveryIds, ['technique:fam-a']);
      expect(recorder.state.runs.last.discoveryIds, isEmpty);
    });

    test('a discovery recorded before beginRun still back-links to it', () {
      final recorder =
          AlmanacRecorder()
            ..recordDiscovery(
              techniqueDiscovery(
                runId: 'run-1',
                runNumber: 1,
                timestamp: at(1),
              ),
            )
            ..beginRun(
              runId: 'run-1',
              runNumber: 1,
              lineageId: 'western',
              physiqueId: 'phy-a',
              startedAt: at(1),
            );

      final run = recorder.state.runs.single;
      expect(run.runId, 'run-1');
      expect(run.lineageId, 'western');
      // Design point 8 is unconditional: the back-link is not lost just
      // because the run had not been opened yet.
      expect(run.discoveryIds, ['technique:fam-a']);
    });

    test('recordItemDiscovered keeps type and contentId as real fields', () {
      final recorder =
          AlmanacRecorder()..recordItemDiscovered(
            definitionId: 'iron_sword',
            instanceId: 'item-inst-1',
            runId: 'run-1',
            runNumber: 1,
            timestamp: at(1),
            snapshot: discoverySnapshot(
              label: 'item',
              values: const {'itemClass': 2},
            ),
          );

      final discovery = recorder.state.discoveries.single;
      expect(discovery.type, AlmanacDiscoveryType.item);
      expect(discovery.contentId, 'iron_sword');
      expect(discovery.instanceId, 'item-inst-1');
      expect(discovery.runId, 'run-1');
      expect(discovery.snapshot.values, {'itemClass': 2});
    });

    test('the same item definition discovered twice records once', () {
      final recorder = AlmanacRecorder();
      for (var i = 0; i < 2; i++) {
        recorder.recordItemDiscovered(
          definitionId: 'iron_sword',
          runId: 'run-$i',
          runNumber: i,
          timestamp: at(1),
          snapshot: discoverySnapshot(label: 'item'),
        );
      }

      expect(recorder.state.discoveries, hasLength(1));
      expect(recorder.state.discoveries.single.runId, 'run-0');
    });

    test('a nested snapshot payload is copied on ingress', () {
      final nested = <String>['a'];
      final values = <String, Object?>{'tags': nested};
      final recorder =
          AlmanacRecorder()..recordItemDiscovered(
            definitionId: 'iron_sword',
            runId: 'run-1',
            runNumber: 1,
            timestamp: at(1),
            snapshot: discoverySnapshot(values: values),
          );

      nested.add('b');

      expect(recorder.state.discoveries.single.snapshot.values, {
        'tags': ['a'],
      });
    });
  });
}
