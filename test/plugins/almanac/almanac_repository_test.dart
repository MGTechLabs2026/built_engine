import 'dart:io';

import 'package:build_engine/almanac.dart' as barrel;
import 'package:build_engine/src/plugins/almanac/almanac_file_repository.dart';
import 'package:build_engine/src/plugins/almanac/almanac_models.dart';
import 'package:build_engine/src/plugins/almanac/almanac_repository.dart';
import 'package:build_engine/src/plugins/almanac/almanac_serialization.dart';
import 'package:test/test.dart';

/// A modestly-populated [AlmanacState] — every list on the state is either
/// exercised or deliberately empty, one nested ledger is non-empty, `seed`
/// and the nullable run fields are set. Enough that a round-trip proves real
/// JSON traversal, not just `empty()`.
AlmanacState _populatedState() => AlmanacState(
  runs: [
    AlmanacRunRecord(
      runId: 'run-1',
      runNumber: 1,
      seed: 4242,
      lineageId: 'lin-1',
      physiqueId: 'phy-1',
      startedAt: DateTime.parse('2026-09-03T10:00:00.000Z'),
      completedAt: DateTime.parse('2026-09-03T10:30:00.000Z'),
      outcome: RunOutcome.won,
      fights: [
        const AlmanacFightRecord(
          fightId: 'fight-1',
          runId: 'run-1',
          sequence: 0,
          name: 'Ambush',
          enemyId: 'enemy-1',
          won: true,
          playerHealthAfter: 12.5,
          turnsUsed: 4,
        ),
      ],
      discoveryIds: ['disc-1'],
      trainingObservations: [
        const TrainingObservation(
          trainingEventId: 'train-1',
          runId: 'run-1',
          runNumber: 1,
        ),
      ],
      finalBuildId: 'build-1',
      enemiesDefeated: 2,
      techniquesUsed: 5,
      trainingSessions: 1,
    ),
  ],
  techniques: [
    AlmanacTechniqueRecord(
      instanceId: 'ti-1',
      baseFamilyId: 'fam-a',
      styleId: 'style-x',
      descriptorIds: ['d1', 'd2'],
      axisProfile: {'power': 3, 'speed': 1.5},
      discoveredRunId: 'run-1',
      discoveredRunNumber: 1,
      masteryAtDiscovery: 2,
      usageObservations: [
        const TechniqueUsageObservation(
          usageEventId: 'use-1',
          runId: 'run-1',
          runNumber: 1,
          instanceId: 'ti-1',
        ),
      ],
      totalUsage: 5,
      runsUsed: [1],
      origin: TechniqueOrigin.inspired,
    ),
  ],
  milestones: [
    AlmanacMilestoneRecord(
      milestoneId: 'ms-1',
      type: MilestoneType.firstInspiredTechnique,
      runId: 'run-1',
      runNumber: 1,
      timestamp: DateTime.parse('2026-09-03T10:20:00.000Z'),
      contextId: 'ti-1',
    ),
  ],
);

void main() {
  group('InMemoryAlmanacRepository', () {
    test('save(state) then load() returns a structurally-equal state', () {
      final repo = InMemoryAlmanacRepository();
      final state = _populatedState();
      repo.save(state);
      expect(repo.load(), state);
    });

    test('a fresh repo load() returns AlmanacState.empty()', () {
      expect(InMemoryAlmanacRepository().load(), AlmanacState.empty());
    });

    test('the constructor seed is returned until the first save', () {
      final seeded = _populatedState();
      final repo = InMemoryAlmanacRepository(seeded);
      expect(repo.load(), seeded);
      repo.save(AlmanacState.empty());
      expect(repo.load(), AlmanacState.empty());
    });

    test('the neutral barrel re-exports the repository interface + impl', () {
      // Everything here is reached through `package:build_engine/almanac.dart`
      // only — proof the web-safe barrel actually surfaces the repository
      // contract and its in-memory implementation.
      final barrel.AlmanacRepository repo = barrel.InMemoryAlmanacRepository();
      repo.save(barrel.AlmanacState.empty());
      expect(repo.load(), barrel.AlmanacState.empty());

      final seeded = barrel.InMemoryAlmanacRepository(_populatedState());
      expect(seeded.load(), _populatedState());
    });

    test('the interface exposes only whole-state load/save', () {
      // A compile-time assertion: only `load()` / `save(state)` type-check.
      // No `saveRun` / `appendFight` / field-level persistence method exists.
      final AlmanacRepository repo = InMemoryAlmanacRepository();
      final AlmanacState Function() load = repo.load;
      final void Function(AlmanacState) save = repo.save;
      expect(load, isNotNull);
      expect(save, isNotNull);
    });
  });

  group('JsonFileAlmanacRepository', () {
    late Directory dir;

    setUp(() {
      dir = Directory.systemTemp.createTempSync('almanac_repo_test_');
    });

    tearDown(() {
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    });

    test('save then load round-trips a populated state', () {
      final repo = JsonFileAlmanacRepository(File('${dir.path}/almanac.json'));
      final state = _populatedState();
      repo.save(state);
      expect(repo.load(), state);
    });

    test('load() on a non-existent path returns AlmanacState.empty()', () {
      final repo = JsonFileAlmanacRepository(
        File('${dir.path}/does_not_exist.json'),
      );
      expect(repo.load(), AlmanacState.empty());
    });

    test('save creates missing parent directories', () {
      final file = File('${dir.path}/nested/deep/almanac.json');
      expect(file.parent.existsSync(), isFalse);
      JsonFileAlmanacRepository(file).save(_populatedState());
      expect(file.existsSync(), isTrue);
      expect(JsonFileAlmanacRepository(file).load(), _populatedState());
    });

    test('no <path>.tmp file remains after a successful save', () {
      final file = File('${dir.path}/almanac.json');
      JsonFileAlmanacRepository(file).save(_populatedState());
      expect(File('${file.path}.tmp').existsSync(), isFalse);
    });

    test('save persists exactly AlmanacSerialization.encode(state)', () {
      final file = File('${dir.path}/almanac.json');
      final state = _populatedState();
      JsonFileAlmanacRepository(file).save(state);
      expect(file.readAsStringSync(), AlmanacSerialization.encode(state));
    });

    test('save overwrites a prior complete file', () {
      final file = File('${dir.path}/almanac.json');
      final repo = JsonFileAlmanacRepository(file);
      repo.save(_populatedState());
      repo.save(AlmanacState.empty());
      expect(repo.load(), AlmanacState.empty());
      expect(File('${file.path}.tmp').existsSync(), isFalse);
    });

    test(
      'a save whose serialization throws leaves the prior file intact, no .tmp',
      () {
        final file = File('${dir.path}/almanac.json');
        final repo = JsonFileAlmanacRepository(file);
        final stateA = _populatedState();
        repo.save(stateA);

        // `_BrokenState.toJson` throws, so `AlmanacSerialization.encode` — the
        // first statement of `save`, before any filesystem call — fails and no
        // file is touched.
        expect(() => repo.save(_BrokenState()), throwsA(isA<StateError>()));

        expect(repo.load(), stateA);
        expect(File('${file.path}.tmp').existsSync(), isFalse);
      },
    );
  });
}

/// An [AlmanacState] whose `toJson` throws — exercises the serialize-before-write
/// ordering without any `@visibleForTesting` seam in production code.
class _BrokenState extends AlmanacState {
  _BrokenState() : super();

  @override
  Map<String, dynamic> toJson() => throw StateError('serialization boom');
}
