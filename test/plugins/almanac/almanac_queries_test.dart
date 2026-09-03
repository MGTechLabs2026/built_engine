/// Phase 5.1 / 5.4 — the read-only query API over one `AlmanacState`.
///
/// Every relationship is asserted through an explicit field (`b.runId`,
/// `observation.runId`, `d.type`); no test here splits, slices, or
/// prefix-matches an id.
library;

import 'package:build_engine/src/plugins/almanac/almanac_models.dart';
import 'package:build_engine/src/plugins/almanac/almanac_queries.dart';
import 'package:test/test.dart';

import 'support/almanac_fixtures.dart';

/// A hand-built state exercising every list and record type. Run `run-A` uses
/// technique `ti-1`; run `run-B` does not. Discoveries are appended in a known
/// order so `getRecentDiscoveries` has something to slice.
AlmanacState _state() => AlmanacState(
  runs: [
    runRecord(
      runId: 'run-A',
      runNumber: 1,
      lineageId: 'lin-x',
      physiqueId: 'phy-1',
      outcome: RunOutcome.won,
    ),
    runRecord(
      runId: 'run-B',
      runNumber: 2,
      lineageId: 'lin-y',
      physiqueId: 'phy-2',
      outcome: RunOutcome.lost,
    ),
    runRecord(
      runId: 'run-C',
      runNumber: 3,
      lineageId: 'lin-x',
      physiqueId: 'phy-1',
      outcome: RunOutcome.abandoned,
    ),
  ],
  builds: [
    buildRecord(
      runId: 'run-A',
      buildId: 'build-1',
      lineageId: 'lin-x',
      physiqueId: 'phy-1',
      techniques: [
        techniqueSnapshot(instanceId: 'ti-1', baseFamilyId: 'fam-a'),
      ],
    ),
    buildRecord(
      runId: 'run-A',
      buildId: 'build-2',
      phase: BuildPhase.finalBuild,
      sequence: 1,
      lineageId: 'lin-x',
      physiqueId: 'phy-1',
    ),
    // Same buildId string as run-A's first build, different run.
    buildRecord(
      runId: 'run-B',
      buildId: 'build-1',
      lineageId: 'lin-y',
      physiqueId: 'phy-2',
    ),
  ],
  techniques: [
    techniqueRecord(
      instanceId: 'ti-1',
      baseFamilyId: 'fam-a',
      usageObservations: [
        // usageEventId deliberately does NOT contain the runId text.
        usageObservation(
          usageEventId: 'x9',
          runId: 'run-A',
          instanceId: 'ti-1',
        ),
        usageObservation(
          usageEventId: 'x12',
          runId: 'run-A',
          instanceId: 'ti-1',
        ),
      ],
      totalUsage: 5,
    ),
    techniqueRecord(instanceId: 'ti-2', baseFamilyId: 'fam-b', totalUsage: 9),
    techniqueRecord(instanceId: 'ti-3', baseFamilyId: 'fam-c', totalUsage: 5),
  ],
  inspirations: [
    inspirationHistory(
      resultInstanceId: 'ti-3',
      runId: 'run-A',
      inspirerInstanceIds: const ['ti-1', 'ti-2'],
    ),
    inspirationHistory(
      resultInstanceId: 'ti-3',
      runId: 'run-C',
      inspirerInstanceIds: const ['ti-2'],
    ),
    inspirationHistory(
      resultInstanceId: 'ti-9',
      runId: 'run-B',
      inspirerInstanceIds: const ['ti-1'],
    ),
  ],
  affixes: [
    affixRecord(affixId: 'af-1', timesUsed: 3),
    affixRecord(affixId: 'af-2', timesUsed: 7),
    affixRecord(affixId: 'af-3', timesUsed: 3),
  ],
  discoveries: [
    discoveryRecord(
      discoveryId: 'd1',
      type: AlmanacDiscoveryType.technique,
      contentId: 'fam-a',
      runId: 'run-A',
    ),
    discoveryRecord(
      discoveryId: 'd2',
      type: AlmanacDiscoveryType.item,
      contentId: 'item-sword',
      runId: 'run-A',
    ),
    discoveryRecord(
      discoveryId: 'd3',
      type: AlmanacDiscoveryType.technique,
      contentId: 'fam-b',
      runId: 'run-B',
    ),
    discoveryRecord(
      discoveryId: 'd4',
      type: AlmanacDiscoveryType.affix,
      contentId: 'af-1',
      runId: 'run-C',
    ),
    discoveryRecord(
      discoveryId: 'd5',
      type: AlmanacDiscoveryType.technique,
      // Duplicate contentId — must not double-count.
      contentId: 'fam-a',
      runId: 'run-C',
    ),
  ],
  milestones: const [],
);

void main() {
  final queries = AlmanacQueries(_state());

  group('run getters', () {
    test('getRunHistory is every run in insertion order', () {
      expect(queries.getRunHistory().map((r) => r.runId), [
        'run-A',
        'run-B',
        'run-C',
      ]);
    });

    test('getRun hit + miss', () {
      expect(queries.getRun('run-B')?.runId, 'run-B');
      expect(queries.getRun('run-Z'), isNull);
    });

    test('getRunsForPhysique matches the explicit physiqueId field', () {
      expect(queries.getRunsForPhysique('phy-1').map((r) => r.runId), [
        'run-A',
        'run-C',
      ]);
      expect(queries.getRunsForPhysique('phy-none'), isEmpty);
    });

    test('getLineageHistory / getRunsForLineage agree and match lineageId', () {
      final history = queries.getLineageHistory('lin-x');
      final forLineage = queries.getRunsForLineage('lin-x');
      expect(history.map((r) => r.runId), ['run-A', 'run-C']);
      expect(forLineage.map((r) => r.runId), ['run-A', 'run-C']);
      expect(queries.getRunsForLineage('lin-missing'), isEmpty);
    });
  });

  group('build getters', () {
    test('getBuildHistory is every build in insertion order', () {
      expect(queries.getBuildHistory().map((b) => b.buildId), [
        'build-1',
        'build-2',
        'build-1',
      ]);
    });

    test(
      'getBuild matches the composite (runId, buildId), not buildId alone',
      () {
        final a = queries.getBuild('run-A', 'build-1');
        final b = queries.getBuild('run-B', 'build-1');
        expect(a, isNotNull);
        expect(b, isNotNull);
        expect(a!.runId, 'run-A');
        expect(b!.runId, 'run-B');
        expect(identical(a, b), isFalse);
        expect(a == b, isFalse);
      },
    );

    test('getBuild miss on a wrong pairing', () {
      expect(queries.getBuild('run-B', 'build-2'), isNull);
      expect(queries.getBuild('run-Z', 'build-1'), isNull);
    });

    test('getBuildsForRun matches the explicit runId field', () {
      expect(queries.getBuildsForRun('run-A').map((b) => b.buildId), [
        'build-1',
        'build-2',
      ]);
      expect(queries.getBuildsForRun('run-B').map((b) => b.buildId), [
        'build-1',
      ]);
      expect(queries.getBuildsForRun('run-none'), isEmpty);
    });
  });

  group('technique getters', () {
    test('getTechniqueHistory hit + miss', () {
      expect(queries.getTechniqueHistory('ti-1')?.instanceId, 'ti-1');
      expect(queries.getTechniqueHistory('ti-nope'), isNull);
    });

    test(
      'getTechniqueInspirations returns every history for the result id',
      () {
        final forTi3 = queries.getTechniqueInspirations('ti-3');
        expect(forTi3, hasLength(2));
        expect(forTi3.every((h) => h.resultInstanceId == 'ti-3'), isTrue);
        expect(forTi3.map((h) => h.runId), ['run-A', 'run-C']);
        expect(queries.getTechniqueInspirations('ti-1'), isEmpty);
      },
    );

    test(
      'getRunsUsingTechnique matches observation.runId (opaque usageEventId)',
      () {
        final runs = queries.getRunsUsingTechnique('ti-1');
        expect(runs.map((r) => r.runId), ['run-A']);
        // The proof: the usage events are 'x9' / 'x12' — neither contains
        // 'run-A' — yet the run still resolves through the explicit field.
        final observed = queries
            .getTechniqueHistory('ti-1')!
            .usageObservations
            .map((o) => o.usageEventId);
        expect(observed, ['x9', 'x12']);
      },
    );

    test(
      'getRunsUsingTechnique is empty for an unknown / unused technique',
      () {
        expect(queries.getRunsUsingTechnique('ti-2'), isEmpty);
        expect(queries.getRunsUsingTechnique('ti-unknown'), isEmpty);
      },
    );

    test('getBuildsUsingTechnique scans the snapshot list by instanceId', () {
      expect(queries.getBuildsUsingTechnique('ti-1').map((b) => b.buildId), [
        'build-1',
      ]);
      expect(queries.getBuildsUsingTechnique('ti-absent'), isEmpty);
    });
  });

  group('affix + discovery getters', () {
    test('getAffixHistory hit + miss', () {
      expect(queries.getAffixHistory('af-2')?.affixId, 'af-2');
      expect(queries.getAffixHistory('af-none'), isNull);
    });

    test('getDiscoveries is every discovery in insertion order', () {
      expect(queries.getDiscoveries().map((d) => d.discoveryId), [
        'd1',
        'd2',
        'd3',
        'd4',
        'd5',
      ]);
    });

    test('getRecentDiscoveries returns the last N by insertion order', () {
      expect(queries.getRecentDiscoveries(limit: 2).map((d) => d.discoveryId), [
        'd4',
        'd5',
      ]);
      expect(
        queries.getRecentDiscoveries(limit: 99).map((d) => d.discoveryId),
        ['d1', 'd2', 'd3', 'd4', 'd5'],
      );
      expect(queries.getRecentDiscoveries(limit: 0), isEmpty);
    });
  });

  group('aggregates', () {
    // MapEntry has no value `==`; compare as (key, value) records instead.
    List<(String, int)> pairs(List<MapEntry<String, int>> es) => [
      for (final e in es) (e.key, e.value),
    ];

    test('mostUsedTechniques orders by (count desc, id asc) and caps', () {
      expect(pairs(queries.mostUsedTechniques()), [
        ('ti-2', 9),
        ('ti-1', 5),
        ('ti-3', 5),
      ]);
      expect(pairs(queries.mostUsedTechniques(limit: 1)), [('ti-2', 9)]);
      expect(queries.mostUsedTechniques(limit: 0), isEmpty);
    });

    test('mostUsedAffixes orders by (count desc, id asc) and caps', () {
      expect(pairs(queries.mostUsedAffixes()), [
        ('af-2', 7),
        ('af-1', 3),
        ('af-3', 3),
      ]);
      expect(pairs(queries.mostUsedAffixes(limit: 2)), [
        ('af-2', 7),
        ('af-1', 3),
      ]);
    });

    test('discoveryCompletion counts distinct contentIds per type', () {
      final completion = queries.discoveryCompletion(
        known: {
          AlmanacDiscoveryType.technique: {'fam-a', 'fam-b', 'fam-c', 'fam-d'},
          AlmanacDiscoveryType.item: {'item-sword', 'item-staff'},
          AlmanacDiscoveryType.lineage: <String>{},
        },
      );

      // fam-a appears twice in discoveries -> still one distinct contentId.
      expect(completion[AlmanacDiscoveryType.technique]!.discovered, 2);
      expect(completion[AlmanacDiscoveryType.technique]!.total, 4);
      expect(completion[AlmanacDiscoveryType.technique]!.fraction, 0.5);

      expect(completion[AlmanacDiscoveryType.item]!.discovered, 1);
      expect(completion[AlmanacDiscoveryType.item]!.total, 2);
      expect(completion[AlmanacDiscoveryType.item]!.fraction, 0.5);

      // total 0 -> fraction 0.0, never a divide-by-zero.
      expect(completion[AlmanacDiscoveryType.lineage]!.total, 0);
      expect(completion[AlmanacDiscoveryType.lineage]!.discovered, 0);
      expect(completion[AlmanacDiscoveryType.lineage]!.fraction, 0.0);

      // Only the requested keys come back.
      expect(completion.keys, {
        AlmanacDiscoveryType.technique,
        AlmanacDiscoveryType.item,
        AlmanacDiscoveryType.lineage,
      });
    });
  });

  group('purity + determinism', () {
    test('every list getter returns an unmodifiable list', () {
      expect(
        () => queries.getRunHistory().add(runRecord(runId: 'x')),
        throwsUnsupportedError,
      );
      expect(() => queries.getBuildHistory().clear(), throwsUnsupportedError);
      expect(
        () => queries.getDiscoveries().removeLast(),
        throwsUnsupportedError,
      );
      expect(
        () => queries.mostUsedTechniques().add(const MapEntry('z', 0)),
        throwsUnsupportedError,
      );
      expect(
        () =>
            queries.discoveryCompletion(known: const {})[AlmanacDiscoveryType
                .item] = const DiscoveryCompletion(
              discovered: 0,
              total: 0,
              fraction: 0,
            ),
        throwsUnsupportedError,
      );
    });

    test('two calls on the same state produce identical lists and order', () {
      final q = AlmanacQueries(_state());

      expect(
        q.getRunHistory().map((r) => r.runId).toList(),
        q.getRunHistory().map((r) => r.runId).toList(),
      );
      expect(
        q.getBuildHistory().map((b) => b.buildId).toList(),
        q.getBuildHistory().map((b) => b.buildId).toList(),
      );
      expect(
        q.getDiscoveries().map((d) => d.discoveryId).toList(),
        q.getDiscoveries().map((d) => d.discoveryId).toList(),
      );
      expect(
        q.getRecentDiscoveries(limit: 3).map((d) => d.discoveryId).toList(),
        q.getRecentDiscoveries(limit: 3).map((d) => d.discoveryId).toList(),
      );
      expect(
        q.getRunsUsingTechnique('ti-1').map((r) => r.runId).toList(),
        q.getRunsUsingTechnique('ti-1').map((r) => r.runId).toList(),
      );
      expect(
        q.getBuildsUsingTechnique('ti-1').map((b) => b.buildId).toList(),
        q.getBuildsUsingTechnique('ti-1').map((b) => b.buildId).toList(),
      );
      expect(
        q.getRunsForLineage('lin-x').map((r) => r.runId).toList(),
        q.getRunsForLineage('lin-x').map((r) => r.runId).toList(),
      );
      expect(
        q.getRunsForPhysique('phy-1').map((r) => r.runId).toList(),
        q.getRunsForPhysique('phy-1').map((r) => r.runId).toList(),
      );
      expect(
        q.getBuildsForRun('run-A').map((b) => b.buildId).toList(),
        q.getBuildsForRun('run-A').map((b) => b.buildId).toList(),
      );
      expect(
        q.getTechniqueInspirations('ti-3').map((h) => h.runId).toList(),
        q.getTechniqueInspirations('ti-3').map((h) => h.runId).toList(),
      );
      expect(
        [for (final e in q.mostUsedTechniques()) (e.key, e.value)],
        [for (final e in q.mostUsedTechniques()) (e.key, e.value)],
      );
      expect(
        [for (final e in q.mostUsedAffixes()) (e.key, e.value)],
        [for (final e in q.mostUsedAffixes()) (e.key, e.value)],
      );
    });

    test('an empty state yields empty results, never a throw', () {
      final q = AlmanacQueries(AlmanacState.empty());
      expect(q.getRunHistory(), isEmpty);
      expect(q.getRun('anything'), isNull);
      expect(q.getBuild('r', 'b'), isNull);
      expect(q.getRecentDiscoveries(), isEmpty);
      expect(q.mostUsedTechniques(), isEmpty);
      expect(q.getRunsUsingTechnique('ti'), isEmpty);
      expect(
        q.lineageStatistics('lin'),
        const LineageStatistics(
          runs: 0,
          wins: 0,
          losses: 0,
          techniquesDiscovered: 0,
          itemsDiscovered: 0,
          affixesDiscovered: 0,
          buildsUsed: 0,
          physiquesUsed: 0,
        ),
      );
    });
  });
}
