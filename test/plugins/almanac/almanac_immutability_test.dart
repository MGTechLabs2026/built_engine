/// Phase 4.9 — deep immutability in both directions (§7).
///
/// Ingress: a caller mutating its own `List` / `Map` after a `record…` call
/// cannot reach stored history. Egress: a caller mutating a collection read
/// back off `state` cannot reach the recorder's internals. And a monotonic
/// completion produces a NEW record instance rather than mutating the one a
/// caller already holds.
library;

import 'package:build_engine/src/plugins/almanac/almanac_models.dart';
import 'package:build_engine/src/plugins/almanac/almanac_queries.dart';
import 'package:build_engine/src/plugins/almanac/almanac_recorder.dart';
import 'package:test/test.dart';

import 'support/almanac_fixtures.dart';

void main() {
  group('ingress copies', () {
    test('a mutated descriptorIds source leaves the technique untouched', () {
      final descriptors = <String>['d1'];
      final axis = <String, num>{'power': 1};
      final recorder =
          AlmanacRecorder()..recordTechniqueDiscovered(
            instanceId: 'ti-1',
            baseFamilyId: 'fam-a',
            descriptorIds: descriptors,
            axisProfile: axis,
            origin: TechniqueOrigin.base,
            runId: 'run-1',
            runNumber: 1,
            timestamp: at(1),
          );

      descriptors.add('d2');
      axis['power'] = 99;
      axis['speed'] = 3;

      final technique = recorder.state.techniques.single;
      expect(technique.descriptorIds, ['d1']);
      expect(technique.axisProfile, {'power': 1});
    });

    test('a mutated build snapshot source leaves the build untouched', () {
      final affixes = <AffixSnapshot>[
        const AffixSnapshot(affixId: 'af-1', stat: 'crit', value: 1),
      ];
      final recorder =
          AlmanacRecorder()..recordBuildSnapshot(
            buildRecord(runId: 'run-1', buildId: 'b0', affixes: affixes),
          );

      affixes.add(
        const AffixSnapshot(affixId: 'af-2', stat: 'haste', value: 2),
      );

      expect(recorder.state.builds.single.affixes, hasLength(1));
    });

    test('a mutated discovery payload leaves the discovery untouched', () {
      final tags = <String>['a'];
      final nested = <String, Object?>{
        'depth': <String>['x'],
      };
      final values = <String, Object?>{'tags': tags, 'nested': nested};
      final recorder =
          AlmanacRecorder()..recordDiscovery(
            AlmanacDiscoveryRecord(
              discoveryId: 'item:iron_sword',
              type: AlmanacDiscoveryType.item,
              contentId: 'iron_sword',
              runId: 'run-1',
              runNumber: 1,
              timestamp: at(1),
              snapshot: discoverySnapshot(values: values),
            ),
          );

      tags.add('b');
      (nested['depth']! as List<String>).add('y');
      values['extra'] = 1;

      final stored = recorder.state.discoveries.single.snapshot;
      expect(stored.values, {
        'tags': ['a'],
        'nested': {
          'depth': ['x'],
        },
      });
    });

    test('a mutated inspirer list leaves the ancestry untouched', () {
      final inspirers = <String>['ti-a'];
      final recorder =
          AlmanacRecorder()..recordTechniqueInspired(
            resultInstanceId: 'ti-new',
            runId: 'run-1',
            familyId: 'fam-a',
            descriptorIds: const ['d1'],
            inspirerInstanceIds: inspirers,
          );

      inspirers.add('ti-b');

      expect(recorder.state.inspirations.single.inspirerInstanceIds, ['ti-a']);
    });
  });

  group('egress copies', () {
    AlmanacRecorder populated() =>
        AlmanacRecorder()
          ..beginRun(
            runId: 'run-1',
            runNumber: 1,
            lineageId: 'western',
            physiqueId: 'phy-a',
            startedAt: at(1),
          )
          ..recordFight(
            runId: 'run-1',
            fightId: 'e0',
            sequence: 0,
            name: 'Bandit',
            enemyId: 'enemy-bandit',
            won: true,
            playerHealthAfter: 10,
            turnsUsed: 5,
          )
          ..recordTechniqueDiscovered(
            instanceId: 'ti-1',
            baseFamilyId: 'fam-a',
            descriptorIds: const ['d1'],
            axisProfile: const {'power': 1},
            origin: TechniqueOrigin.base,
            runId: 'run-1',
            runNumber: 1,
            timestamp: at(1),
          )
          ..recordBuildSnapshot(buildRecord(runId: 'run-1', buildId: 'b0'));

    test('every list read off state refuses mutation', () {
      final state = populated().state;

      expect(() => state.runs.clear(), throwsUnsupportedError);
      expect(() => state.builds.clear(), throwsUnsupportedError);
      expect(() => state.techniques.clear(), throwsUnsupportedError);
      expect(() => state.runs.single.fights.clear(), throwsUnsupportedError);
      expect(
        () => state.runs.single.discoveryIds.add('x'),
        throwsUnsupportedError,
      );
      expect(
        () => state.techniques.single.usageObservations.clear(),
        throwsUnsupportedError,
      );
      expect(
        () => state.techniques.single.runsUsed.add(9),
        throwsUnsupportedError,
      );
    });

    test('a rejected mutation leaves the recorder internals intact', () {
      final recorder = populated();
      final state = recorder.state;

      try {
        state.runs.single.fights.clear();
      } on UnsupportedError {
        // expected
      }

      expect(recorder.state.runs.single.fights, hasLength(1));
      expect(recorder.state, state);
    });

    test('two reads of state are independent snapshots', () {
      final recorder = populated();
      final first = recorder.state;

      recorder.recordFight(
        runId: 'run-1',
        fightId: 'e1',
        sequence: 1,
        name: 'Bandit',
        enemyId: 'enemy-bandit',
        won: false,
        playerHealthAfter: 0,
        turnsUsed: 5,
      );

      expect(first.runs.single.fights, hasLength(1));
      expect(recorder.state.runs.single.fights, hasLength(2));
      expect(first.runs.single.enemiesDefeated, 1);
    });
  });

  group('AlmanacQueries egress', () {
    AlmanacRecorder populated() =>
        AlmanacRecorder()
          ..beginRun(
            runId: 'run-1',
            runNumber: 1,
            lineageId: 'western',
            physiqueId: 'phy-a',
            startedAt: at(1),
          )
          ..recordBuildSnapshot(buildRecord(runId: 'run-1', buildId: 'b0'))
          ..recordTechniqueDiscovered(
            instanceId: 'ti-1',
            baseFamilyId: 'fam-a',
            descriptorIds: const ['d1'],
            axisProfile: const {'power': 1},
            origin: TechniqueOrigin.base,
            runId: 'run-1',
            runNumber: 1,
            timestamp: at(1),
          );

    test('a List returned by a query cannot reach the AlmanacState', () {
      final recorder = populated();
      final state = recorder.state;
      final runs = AlmanacQueries(state).getRunHistory();

      expect(() => runs.add(runs.first), throwsUnsupportedError);
      // The state — and a fresh query over it — are untouched.
      expect(recorder.state, equals(state));
      expect(
        AlmanacQueries(recorder.state).getRunHistory(),
        equals(state.runs),
      );
    });

    test('a Map returned by discoveryCompletion cannot reach the state', () {
      final recorder = populated();
      final before = recorder.state;
      final completion = AlmanacQueries(before).discoveryCompletion(
        known: const {
          AlmanacDiscoveryType.technique: {'fam-a'},
        },
      );

      expect(
        () =>
            completion[AlmanacDiscoveryType.item] = const DiscoveryCompletion(
              discovered: 0,
              total: 0,
              fraction: 0,
            ),
        throwsUnsupportedError,
      );
      expect(recorder.state, equals(before));
    });

    test(
      'a technique read via getTechniqueHistory before a monotonic '
      'completion is left unchanged; the new read carries the completed field',
      () {
        final recorder = populated();
        final before =
            AlmanacQueries(recorder.state).getTechniqueHistory('ti-1')!;

        recorder.recordTechniqueInspired(
          resultInstanceId: 'ti-1',
          runId: 'run-1',
          familyId: 'fam-a',
          descriptorIds: const ['d1'],
          inspirerInstanceIds: const ['ti-a'],
        );
        final after =
            AlmanacQueries(recorder.state).getTechniqueHistory('ti-1')!;

        expect(before.origin, TechniqueOrigin.base);
        expect(after.origin, TechniqueOrigin.inspired);
        expect(identical(before, after), isFalse);
      },
    );
  });

  group('completion is not mutation', () {
    test('a filled field yields a new instance, the old one is unchanged', () {
      final recorder =
          AlmanacRecorder()..recordTechniqueDiscovered(
            instanceId: 'ti-1',
            baseFamilyId: 'fam-a',
            descriptorIds: const ['d1'],
            axisProfile: const {},
            origin: TechniqueOrigin.base,
            runId: 'run-1',
            runNumber: 1,
            timestamp: at(1),
          );
      final before = recorder.state.techniques.single;

      recorder.recordTechniqueInspired(
        resultInstanceId: 'ti-1',
        runId: 'run-1',
        familyId: 'fam-a',
        descriptorIds: const ['d1'],
        inspirerInstanceIds: const ['ti-a'],
      );

      expect(before.origin, TechniqueOrigin.base);
      expect(recorder.state.techniques.single.origin, TechniqueOrigin.inspired);
      expect(identical(before, recorder.state.techniques.single), isFalse);
    });

    test('a run record held from before completion is unchanged', () {
      final recorder =
          AlmanacRecorder()..beginRun(
            runId: 'run-1',
            runNumber: 1,
            lineageId: 'western',
            physiqueId: 'phy-a',
            startedAt: at(1),
          );
      final before = recorder.state.runs.single;

      recorder.completeRun(
        runId: 'run-1',
        completedAt: at(2),
        outcome: RunOutcome.won,
      );

      expect(before.completedAt, isNull);
      expect(before.outcome, RunOutcome.abandoned);
      expect(recorder.state.runs.single.outcome, RunOutcome.won);
    });
  });
}
