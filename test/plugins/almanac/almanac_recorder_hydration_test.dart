/// Phase 4.0 — `AlmanacRecorder(AlmanacState initial)` constructor hydration.
///
/// Proves §5.1 items 1-6: replay through the same private insert paths,
/// preserved list ordering, projections recomputed from the ledgers, fail-fast
/// on a duplicated identity key, no retained reference from `initial`, and a
/// deeply-immutable `state` afterwards.
library;

import 'package:build_engine/src/plugins/almanac/almanac_models.dart';
import 'package:build_engine/src/plugins/almanac/almanac_recorder.dart';
import 'package:build_engine/src/plugins/almanac/almanac_serialization.dart';
import 'package:test/test.dart';

import 'support/almanac_fixtures.dart';

/// A well-formed persisted state: every one of the seven lists is populated,
/// every nested ledger is non-empty, and every projection agrees with its
/// ledger (so a hydrate → `state` round trip must be an identity).
AlmanacState _populated() {
  final run1 = AlmanacRunRecord(
    runId: 'run-1',
    runNumber: 1,
    seed: 77,
    lineageId: 'western',
    physiqueId: 'phy-a',
    startedAt: at(1),
    completedAt: at(2),
    outcome: RunOutcome.won,
    fights: [
      fightRecord(runId: 'run-1', fightId: 'f0', sequence: 0),
      fightRecord(runId: 'run-1', fightId: 'f1', sequence: 1, won: false),
    ],
    discoveryIds: const ['item:iron_sword'],
    trainingObservations: const [
      TrainingObservation(trainingEventId: 'tr0', runId: 'run-1', runNumber: 1),
    ],
    finalBuildId: 'b-final',
    enemiesDefeated: 1,
    techniquesUsed: 2,
    trainingSessions: 1,
  );
  final run2 = AlmanacRunRecord(
    runId: 'run-2',
    runNumber: 2,
    lineageId: 'eastern',
    physiqueId: 'phy-b',
    startedAt: at(3),
    outcome: RunOutcome.abandoned,
    fights: const [],
    discoveryIds: const [],
    trainingObservations: const [],
    enemiesDefeated: 0,
    techniquesUsed: 1,
    trainingSessions: 0,
  );
  return AlmanacState(
    runs: [run1, run2],
    builds: [
      buildRecord(runId: 'run-1', buildId: 'b-1'),
      buildRecord(
        runId: 'run-1',
        buildId: 'b-final',
        phase: BuildPhase.finalBuild,
        sequence: 3,
      ),
      buildRecord(runId: 'run-2', buildId: 'b-1', lineageId: 'eastern'),
    ],
    techniques: [
      AlmanacTechniqueRecord(
        instanceId: 'ti-1',
        baseFamilyId: 'fam-a',
        styleId: 'style-x',
        descriptorIds: const ['d1', 'd2'],
        axisProfile: const {'power': 3},
        discoveredRunId: 'run-1',
        discoveredRunNumber: 1,
        masteryAtDiscovery: 2,
        usageObservations: const [
          TechniqueUsageObservation(
            usageEventId: 'u0',
            runId: 'run-1',
            runNumber: 1,
            instanceId: 'ti-1',
          ),
          TechniqueUsageObservation(
            usageEventId: 'u1',
            runId: 'run-1',
            runNumber: 1,
            instanceId: 'ti-1',
          ),
          TechniqueUsageObservation(
            usageEventId: 'u0',
            runId: 'run-2',
            runNumber: 2,
            instanceId: 'ti-1',
          ),
        ],
        totalUsage: 3,
        runsUsed: const [1, 2],
        origin: TechniqueOrigin.inspired,
      ),
    ],
    inspirations: [
      TechniqueInspirationHistory(
        resultInstanceId: 'ti-1',
        runId: 'run-1',
        familyId: 'fam-a',
        descriptorIds: const ['d1', 'd2'],
        inspirerInstanceIds: const ['ti-9', 'ti-8'],
      ),
    ],
    affixes: [
      AlmanacAffixRecord(
        affixId: 'af-1',
        discoveryObservations: const [
          AffixObservation(
            affixEventId: 'ae0',
            runId: 'run-1',
            runNumber: 1,
            lineageId: 'western',
          ),
          AffixObservation(
            affixEventId: 'ae1',
            runId: 'run-2',
            runNumber: 2,
            lineageId: 'eastern',
          ),
        ],
        usageObservations: const [
          AffixObservation(
            affixEventId: 'ae2',
            runId: 'run-1',
            runNumber: 1,
            lineageId: 'western',
          ),
        ],
        timesDiscovered: 2,
        timesUsed: 1,
        firstDiscoveredRunId: 'run-1',
        associatedLineageIds: const ['western', 'eastern'],
        snapshot: const AffixSnapshot(
          affixId: 'af-1',
          stat: 'crit',
          value: 0.1,
          category: 'offensive',
        ),
      ),
    ],
    discoveries: [
      AlmanacDiscoveryRecord(
        discoveryId: 'item:iron_sword',
        type: AlmanacDiscoveryType.item,
        contentId: 'iron_sword',
        instanceId: 'item-inst-1',
        runId: 'run-1',
        runNumber: 1,
        timestamp: at(1),
        snapshot: discoverySnapshot(
          label: 'item',
          values: const {'itemClass': 2},
        ),
      ),
    ],
    milestones: [
      AlmanacMilestoneRecord(
        milestoneId: 'firstRun',
        type: MilestoneType.firstRun,
        runId: 'run-1',
        runNumber: 1,
        timestamp: at(1),
      ),
      AlmanacMilestoneRecord(
        milestoneId: 'firstWinWithLineage:western',
        type: MilestoneType.firstWinWithLineage,
        runId: 'run-1',
        runNumber: 1,
        timestamp: at(2),
        contextId: 'western',
      ),
    ],
  );
}

void main() {
  group('AlmanacRecorder hydration', () {
    test('an empty recorder starts with an empty state', () {
      expect(AlmanacRecorder().state, AlmanacState.empty());
    });

    test('round-trips a populated state, preserving list order', () {
      final initial = _populated();
      final hydrated = AlmanacRecorder(initial).state;

      expect(hydrated, initial);
      expect(
        hydrated.runs.map((r) => r.runId).toList(),
        initial.runs.map((r) => r.runId).toList(),
      );
      expect(
        hydrated.builds.map((b) => b.buildId).toList(),
        initial.builds.map((b) => b.buildId).toList(),
      );
      expect(
        hydrated.milestones.map((m) => m.milestoneId).toList(),
        initial.milestones.map((m) => m.milestoneId).toList(),
      );
      // Nested ledgers keep their element order too.
      expect(
        hydrated.techniques.single.usageObservations
            .map((o) => o.runId)
            .toList(),
        ['run-1', 'run-1', 'run-2'],
      );
      expect(hydrated.runs.first.fights.map((f) => f.sequence).toList(), [
        0,
        1,
      ]);
    });

    test('a second hydration of the recorder output is idempotent', () {
      final once = AlmanacRecorder(_populated()).state;
      expect(AlmanacRecorder(once).state, once);
    });

    test('retains no reference to the caller collections behind initial', () {
      final runs = <AlmanacRunRecord>[_populated().runs.first];
      final initial = AlmanacState(runs: runs);
      final recorder = AlmanacRecorder(initial);

      runs.add(_populated().runs.last);

      expect(recorder.state.runs, hasLength(1));
      expect(initial.runs, hasLength(1));
    });

    test('deep-copies a nested payload inside a hydrated discovery', () {
      // `DiscoverySnapshot` freezes only the top level of `values`, so a `List`
      // nested inside it is still the caller's until the recorder copies it.
      final nested = <String>['a'];
      final deeper = <String, Object?>{
        'inner': <String>['x'],
      };
      final initial = AlmanacState(
        discoveries: [
          AlmanacDiscoveryRecord(
            discoveryId: 'item:iron_sword',
            type: AlmanacDiscoveryType.item,
            contentId: 'iron_sword',
            runId: 'run-1',
            runNumber: 1,
            timestamp: at(1),
            snapshot: discoverySnapshot(
              values: <String, Object?>{'tags': nested, 'deeper': deeper},
            ),
          ),
        ],
      );
      final recorder = AlmanacRecorder(initial);

      nested.add('b');
      (deeper['inner']! as List<String>).add('y');

      expect(recorder.state.discoveries.single.snapshot.values, {
        'tags': ['a'],
        'deeper': {
          'inner': ['x'],
        },
      });
    });

    test('the state it hands back is deeply immutable', () {
      final state = AlmanacRecorder(_populated()).state;

      expect(() => state.runs.add(state.runs.first), throwsUnsupportedError);
      expect(() => state.runs.first.fights.clear(), throwsUnsupportedError);
      expect(
        () => state.techniques.first.descriptorIds.add('x'),
        throwsUnsupportedError,
      );
      expect(
        () => state.techniques.first.axisProfile['power'] = 9,
        throwsUnsupportedError,
      );
      expect(
        () => state.affixes.first.associatedLineageIds.add('x'),
        throwsUnsupportedError,
      );
      expect(
        () => state.builds.first.dna.tokens.add('x'),
        throwsUnsupportedError,
      );
    });

    test('normalises a projection that disagrees with its ledger', () {
      final base = _populated();
      final broken = AlmanacState(
        techniques: [
          AlmanacTechniqueRecord(
            instanceId: 'ti-1',
            baseFamilyId: 'fam-a',
            descriptorIds: const [],
            axisProfile: const {},
            usageObservations: base.techniques.single.usageObservations,
            totalUsage: 99,
            runsUsed: const [42],
            origin: TechniqueOrigin.base,
          ),
        ],
      );

      final technique = AlmanacRecorder(broken).state.techniques.single;

      expect(technique.usageObservations, hasLength(3));
      expect(technique.totalUsage, 3);
      expect(technique.runsUsed, [1, 2]);
    });

    test('normalises run projections that disagree with their ledgers', () {
      final broken = AlmanacState(
        runs: [
          AlmanacRunRecord(
            runId: 'run-1',
            runNumber: 1,
            lineageId: 'western',
            physiqueId: 'phy-a',
            startedAt: at(1),
            outcome: RunOutcome.abandoned,
            fights: [
              fightRecord(runId: 'run-1', fightId: 'f0'),
              fightRecord(runId: 'run-1', fightId: 'f1', won: false),
            ],
            discoveryIds: const [],
            trainingObservations: const [
              TrainingObservation(
                trainingEventId: 'tr0',
                runId: 'run-1',
                runNumber: 1,
              ),
            ],
            enemiesDefeated: 88,
            techniquesUsed: 88,
            trainingSessions: 88,
          ),
        ],
      );

      final run = AlmanacRecorder(broken).state.runs.single;

      expect(run.enemiesDefeated, 1);
      expect(run.techniquesUsed, 0);
      expect(run.trainingSessions, 1);
    });

    group('rejects a corrupt input', () {
      test('two run records sharing a runId (identical contents)', () {
        final run = _populated().runs.first;
        expect(
          () => AlmanacRecorder(AlmanacState(runs: [run, run])),
          throwsA(isA<AlmanacIntegrityException>()),
        );
      });

      test('two build records sharing (runId, buildId) — differing', () {
        expect(
          () => AlmanacRecorder(
            AlmanacState(
              builds: [
                buildRecord(runId: 'run-A', buildId: 'build-1'),
                buildRecord(
                  runId: 'run-A',
                  buildId: 'build-1',
                  sequence: 4,
                  phase: BuildPhase.postReward,
                ),
              ],
            ),
          ),
          throwsA(isA<AlmanacIntegrityException>()),
        );
      });

      test('two build records sharing (runId, buildId) — identical', () {
        final record = buildRecord(runId: 'run-A', buildId: 'build-1');
        expect(
          () => AlmanacRecorder(AlmanacState(builds: [record, record])),
          throwsA(isA<AlmanacIntegrityException>()),
        );
      });

      test('two technique records sharing an instanceId', () {
        final record = _populated().techniques.single;
        expect(
          () => AlmanacRecorder(AlmanacState(techniques: [record, record])),
          throwsA(isA<AlmanacIntegrityException>()),
        );
      });

      test('two inspirations sharing a resultInstanceId', () {
        final record = _populated().inspirations.single;
        expect(
          () => AlmanacRecorder(AlmanacState(inspirations: [record, record])),
          throwsA(isA<AlmanacIntegrityException>()),
        );
      });

      test('two affix records sharing an affixId', () {
        final record = _populated().affixes.single;
        expect(
          () => AlmanacRecorder(AlmanacState(affixes: [record, record])),
          throwsA(isA<AlmanacIntegrityException>()),
        );
      });

      test('two discoveries sharing a discoveryId', () {
        final record = _populated().discoveries.single;
        expect(
          () => AlmanacRecorder(AlmanacState(discoveries: [record, record])),
          throwsA(isA<AlmanacIntegrityException>()),
        );
      });

      test('two milestones sharing a milestoneId', () {
        final record = _populated().milestones.first;
        expect(
          () => AlmanacRecorder(AlmanacState(milestones: [record, record])),
          throwsA(isA<AlmanacIntegrityException>()),
        );
      });

      test('a fight ledger with two entries sharing a fightId', () {
        expect(
          () => AlmanacRecorder(
            AlmanacState(
              runs: [
                AlmanacRunRecord(
                  runId: 'run-1',
                  runNumber: 1,
                  lineageId: 'western',
                  physiqueId: 'phy-a',
                  startedAt: at(1),
                  outcome: RunOutcome.abandoned,
                  fights: [
                    fightRecord(runId: 'run-1', fightId: 'f0'),
                    fightRecord(runId: 'run-1', fightId: 'f0'),
                  ],
                  discoveryIds: const [],
                  trainingObservations: const [],
                  enemiesDefeated: 2,
                  techniquesUsed: 0,
                  trainingSessions: 0,
                ),
              ],
            ),
          ),
          throwsA(isA<AlmanacIntegrityException>()),
        );
      });

      test('a training ledger with two entries sharing a trainingEventId', () {
        const observation = TrainingObservation(
          trainingEventId: 'tr0',
          runId: 'run-1',
          runNumber: 1,
        );
        expect(
          () => AlmanacRecorder(
            AlmanacState(
              runs: [
                AlmanacRunRecord(
                  runId: 'run-1',
                  runNumber: 1,
                  lineageId: 'western',
                  physiqueId: 'phy-a',
                  startedAt: at(1),
                  outcome: RunOutcome.abandoned,
                  fights: const [],
                  discoveryIds: const [],
                  trainingObservations: const [observation, observation],
                  enemiesDefeated: 0,
                  techniquesUsed: 0,
                  trainingSessions: 2,
                ),
              ],
            ),
          ),
          throwsA(
            isA<AlmanacIntegrityException>().having(
              (e) => e.field,
              'field',
              'trainingEventId',
            ),
          ),
        );
      });

      test('an affix ledger with two entries sharing an affixEventId', () {
        const observation = AffixObservation(
          affixEventId: 'ae0',
          runId: 'run-1',
          runNumber: 1,
          lineageId: 'western',
        );
        expect(
          () => AlmanacRecorder(
            AlmanacState(
              affixes: [
                AlmanacAffixRecord(
                  affixId: 'af-1',
                  discoveryObservations: const [observation, observation],
                  usageObservations: const [],
                  timesDiscovered: 2,
                  timesUsed: 0,
                  firstDiscoveredRunId: 'run-1',
                  associatedLineageIds: const ['western'],
                  snapshot: const AffixSnapshot(
                    affixId: 'af-1',
                    stat: 'crit',
                    value: 0.1,
                  ),
                ),
              ],
            ),
          ),
          throwsA(
            isA<AlmanacIntegrityException>().having(
              (e) => e.field,
              'field',
              'affixEventId',
            ),
          ),
        );
      });

      test('a usage ledger with two entries sharing (runId, usageEventId)', () {
        const observation = TechniqueUsageObservation(
          usageEventId: 'u0',
          runId: 'run-1',
          runNumber: 1,
          instanceId: 'ti-1',
        );
        expect(
          () => AlmanacRecorder(
            AlmanacState(
              techniques: [
                AlmanacTechniqueRecord(
                  instanceId: 'ti-1',
                  baseFamilyId: 'fam-a',
                  descriptorIds: const [],
                  axisProfile: const {},
                  usageObservations: const [observation, observation],
                  totalUsage: 2,
                  runsUsed: const [1],
                  origin: TechniqueOrigin.base,
                ),
              ],
            ),
          ),
          throwsA(isA<AlmanacIntegrityException>()),
        );
      });
    });

    test('keeps two build records that share a buildId under two runIds', () {
      final state =
          AlmanacRecorder(
            AlmanacState(
              builds: [
                buildRecord(runId: 'run-A', buildId: 'build-1'),
                buildRecord(runId: 'run-B', buildId: 'build-1'),
              ],
            ),
          ).state;

      expect(state.builds, hasLength(2));
      expect(state.builds.map((b) => b.runId).toList(), ['run-A', 'run-B']);
      expect(state.builds.every((b) => b.buildId == 'build-1'), isTrue);
    });

    group('the sentinel-hardening ordering contract', () {
      // An observation delivered before its subject is declared opens a record
      // whose identity fields are still unknown. `AlmanacState` has no
      // representation for "unknown", so persisting in that window freezes a
      // sentinel, and the declaration that would have filled it becomes a
      // contradiction. This is the intended v1 contract (see the
      // `AlmanacRecorder` class doc), locked here so nobody "fixes" it by
      // silently overwriting an established value.
      const use = TechniqueUsageObservation(
        usageEventId: 'u0',
        runId: 'run-1',
        runNumber: 1,
        instanceId: 'ti-1',
      );

      void discover(AlmanacRecorder recorder) =>
          recorder.recordTechniqueDiscovered(
            instanceId: 'ti-1',
            baseFamilyId: 'fam-a',
            descriptorIds: const ['d1'],
            axisProfile: const {'power': 2},
            origin: TechniqueOrigin.base,
            runId: 'run-1',
            runNumber: 1,
            timestamp: at(1),
          );

      test('within one session, use-before-discover fills correctly', () {
        final recorder = AlmanacRecorder()..recordTechniqueUsed(use);
        discover(recorder);

        final technique = recorder.state.techniques.single;
        expect(technique.baseFamilyId, 'fam-a');
        expect(technique.descriptorIds, ['d1']);
        expect(technique.totalUsage, 1);
      });

      test('across a save boundary, the same sequence is a contradiction', () {
        final beforeSave = (AlmanacRecorder()..recordTechniqueUsed(use)).state;
        // The undeclared identity has already hardened into a sentinel.
        expect(beforeSave.techniques.single.baseFamilyId, '');

        final reloaded = AlmanacRecorder(
          AlmanacSerialization.decode(AlmanacSerialization.encode(beforeSave)),
        );

        expect(
          () => discover(reloaded),
          throwsA(
            isA<AlmanacIntegrityException>()
                .having((e) => e.field, 'field', 'baseFamilyId')
                .having((e) => e.established, 'established', '')
                .having((e) => e.rejected, 'rejected', 'fam-a'),
          ),
        );
        // The ledger the stub owns is intact either way.
        expect(reloaded.state.techniques.single.totalUsage, 1);
      });

      test('declaring identity first is safe across the save boundary', () {
        final first = AlmanacRecorder();
        discover(first);
        first.recordTechniqueUsed(use);

        final reloaded = AlmanacRecorder(
          AlmanacSerialization.decode(AlmanacSerialization.encode(first.state)),
        );
        // Re-delivering both is a no-op, not a contradiction.
        discover(reloaded);
        reloaded.recordTechniqueUsed(use);

        expect(reloaded.state, first.state);
        expect(reloaded.state.techniques.single.baseFamilyId, 'fam-a');
      });
    });

    test('carries the four diagnostic fields on the integrity exception', () {
      final record = _populated().milestones.first;
      Object? caught;
      try {
        AlmanacRecorder(AlmanacState(milestones: [record, record]));
      } on AlmanacIntegrityException catch (error) {
        caught = error;
      }

      final failure = caught! as AlmanacIntegrityException;
      expect(failure.record, contains('AlmanacMilestoneRecord'));
      expect(failure.field, isNotEmpty);
      expect(failure.rejected, isNotNull);
      expect(failure.toString(), contains('Almanac integrity'));
    });
  });
}
