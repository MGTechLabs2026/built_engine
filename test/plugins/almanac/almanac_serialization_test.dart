import 'package:build_engine/src/plugins/almanac/almanac_models.dart';
import 'package:build_engine/src/plugins/almanac/almanac_serialization.dart';
import 'package:test/test.dart';

/// A genuinely-populated [AlmanacState]: every one of the seven record lists
/// has at least one entry, every nested observation ledger is non-empty, and
/// each nullable field is exercised both null and non-null —
/// - `seed`: set on `run-1`, absent on `run-2`;
/// - `completedAt` / `finalBuildId`: set on `run-1`, absent on `run-2`;
/// - `discoveredRunId` / `discoveredRunNumber` / `masteryAtDiscovery`: set on
///   `ti-1`, absent on `ti-2`.
AlmanacState _populatedState() {
  final techniqueSnapshot = TechniqueInstanceSnapshot(
    instanceId: 'ti-1',
    baseFamilyId: 'fam-a',
    styleId: 'style-x',
    descriptorIds: ['d1', 'd2'],
    axisProfile: {'power': 3, 'speed': 1.5},
    origin: TechniqueOrigin.inspired,
    masteryAtSnapshot: 4,
  );
  final itemSnapshot = ItemInstanceSnapshot(
    definitionId: 'item-def-1',
    instanceId: 'item-inst-1',
    itemClass: 2,
    statBonuses: {'atk': 5},
    resolvedProperties: {'weight': 1.25},
  );
  const affixSnapshot = AffixSnapshot(
    affixId: 'af-1',
    stat: 'crit',
    value: 0.1,
    category: 'offensive',
  );
  final tome = TomeLayoutSnapshot(
    width: 3,
    height: 2,
    slots: [
      const TomeSlotSnapshot(
        slotId: 's0',
        occupantKind: 'technique',
        occupantRefId: 'fam-a',
        instanceId: 'ti-1',
      ),
      const TomeSlotSnapshot(slotId: 's1', occupantKind: 'empty'),
    ],
  );
  final dna = BuildDna(tokens: ['t-a', 't-b', 't-c'], signature: 'sig-abc');

  return AlmanacState(
    runs: [
      AlmanacRunRecord(
        runId: 'run-1',
        runNumber: 1,
        seed: 12345,
        lineageId: 'lin-1',
        physiqueId: 'phy-1',
        startedAt: DateTime.parse('2026-09-03T10:00:00.000Z'),
        completedAt: DateTime.parse('2026-09-03T10:45:00.000Z'),
        outcome: RunOutcome.won,
        fights: [
          const AlmanacFightRecord(
            fightId: 'fight-1',
            runId: 'run-1',
            sequence: 0,
            name: 'Ambush',
            enemyId: 'enemy-1',
            won: true,
            playerHealthAfter: 18.5,
            turnsUsed: 6,
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
        enemiesDefeated: 3,
        techniquesUsed: 7,
        trainingSessions: 1,
      ),
      AlmanacRunRecord(
        runId: 'run-2',
        runNumber: 2,
        lineageId: 'lin-1',
        physiqueId: 'phy-1',
        startedAt: DateTime.parse('2026-09-03T11:00:00.000Z'),
        outcome: RunOutcome.abandoned,
        fights: const [],
        discoveryIds: const [],
        trainingObservations: [
          const TrainingObservation(
            trainingEventId: 'train-2',
            runId: 'run-2',
            runNumber: 2,
          ),
        ],
        enemiesDefeated: 0,
        techniquesUsed: 0,
        trainingSessions: 1,
      ),
    ],
    builds: [
      AlmanacBuildRecord(
        buildId: 'build-1',
        runId: 'run-1',
        phase: BuildPhase.finalBuild,
        sequence: 2,
        lineageId: 'lin-1',
        physiqueId: 'phy-1',
        techniques: [techniqueSnapshot],
        items: [itemSnapshot],
        affixes: [affixSnapshot],
        tome: tome,
        performance: const BuildPerformanceSnapshot(
          fightsWon: 3,
          fightsLost: 1,
          enemiesDefeated: 3,
          avgTurnsUsed: 5.75,
        ),
        dna: dna,
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
        totalUsage: 7,
        runsUsed: [1],
        origin: TechniqueOrigin.inspired,
      ),
      AlmanacTechniqueRecord(
        instanceId: 'ti-2',
        baseFamilyId: 'fam-b',
        descriptorIds: const [],
        axisProfile: const {},
        usageObservations: [
          const TechniqueUsageObservation(
            usageEventId: 'use-2',
            runId: 'run-2',
            runNumber: 2,
            instanceId: 'ti-2',
          ),
        ],
        totalUsage: 1,
        runsUsed: [2],
        origin: TechniqueOrigin.base,
      ),
    ],
    inspirations: [
      TechniqueInspirationHistory(
        resultInstanceId: 'ti-1',
        runId: 'run-1',
        familyId: 'fam-a',
        descriptorIds: ['d1', 'd2'],
        inspirerInstanceIds: ['ti-src-1', 'ti-src-2'],
      ),
    ],
    affixes: [
      AlmanacAffixRecord(
        affixId: 'af-1',
        discoveryObservations: [
          const AffixObservation(
            affixEventId: 'afe-1',
            runId: 'run-1',
            runNumber: 1,
            lineageId: 'lin-1',
          ),
        ],
        usageObservations: [
          const AffixObservation(
            affixEventId: 'afe-2',
            runId: 'run-1',
            runNumber: 1,
          ),
        ],
        timesDiscovered: 1,
        timesUsed: 4,
        firstDiscoveredRunId: 'run-1',
        associatedLineageIds: ['lin-1'],
        snapshot: affixSnapshot,
      ),
    ],
    discoveries: [
      AlmanacDiscoveryRecord(
        discoveryId: 'disc-1',
        type: AlmanacDiscoveryType.techniqueVariant,
        contentId: 'fam-a',
        instanceId: 'ti-1',
        runId: 'run-1',
        runNumber: 1,
        timestamp: DateTime.parse('2026-09-03T10:20:00.000Z'),
        snapshot: DiscoverySnapshot(
          label: 'Inspired variant',
          values: {
            'familyId': 'fam-a',
            'descriptorIds': ['d1', 'd2'],
            'nested': {'k': 1},
          },
        ),
      ),
    ],
    milestones: [
      AlmanacMilestoneRecord(
        milestoneId: 'ms-1',
        type: MilestoneType.firstInspiredTechnique,
        runId: 'run-1',
        runNumber: 1,
        timestamp: DateTime.parse('2026-09-03T10:20:01.000Z'),
        contextId: 'ti-1',
      ),
    ],
  );
}

void main() {
  group('AlmanacSerialization', () {
    test(
      'stateToJson -> stateFromJson round-trips a fully-populated state',
      () {
        final original = _populatedState();
        final restored = AlmanacSerialization.stateFromJson(
          AlmanacSerialization.stateToJson(original),
        );
        expect(restored, original);
      },
    );

    test('encode -> decode round-trips a fully-populated state', () {
      final original = _populatedState();
      final restored = AlmanacSerialization.decode(
        AlmanacSerialization.encode(original),
      );
      expect(restored, original);
    });

    test(
      'the populated fixture exercises seed and nullable fields both ways',
      () {
        final state = _populatedState();
        expect(state.runs[0].seed, isNotNull);
        expect(state.runs[1].seed, isNull);
        expect(state.runs[0].completedAt, isNotNull);
        expect(state.runs[1].completedAt, isNull);
        expect(state.runs[0].finalBuildId, isNotNull);
        expect(state.runs[1].finalBuildId, isNull);
        expect(state.techniques[0].discoveredRunId, isNotNull);
        expect(state.techniques[1].discoveredRunId, isNull);
      },
    );

    test('stateToJson stamps almanacSchemaVersion 1', () {
      expect(AlmanacSerialization.schemaVersion, 1);
      expect(
        AlmanacSerialization.stateToJson(
          _populatedState(),
        )['almanacSchemaVersion'],
        1,
      );
    });

    test('the model body carries no version key of its own', () {
      expect(
        _populatedState().toJson().containsKey('almanacSchemaVersion'),
        isFalse,
      );
    });

    test('stateFromJson throws on a newer schema version', () {
      final body = _populatedState().toJson();
      Object? caught;
      try {
        AlmanacSerialization.stateFromJson({
          'almanacSchemaVersion': 2,
          ...body,
        });
      } catch (error) {
        caught = error;
      }
      expect(caught, isA<AlmanacSchemaVersionError>());
      final error = caught! as AlmanacSchemaVersionError;
      expect(error.found, 2);
      expect(error.expected, 1);
    });

    test(
      'stateFromJson throws when the version key is absent (found null)',
      () {
        final body = _populatedState().toJson();
        expect(body.containsKey('almanacSchemaVersion'), isFalse);
        Object? caught;
        try {
          AlmanacSerialization.stateFromJson(body);
        } catch (error) {
          caught = error;
        }
        expect(caught, isA<AlmanacSchemaVersionError>());
        expect((caught! as AlmanacSchemaVersionError).found, isNull);
      },
    );

    test('decode fails loud on malformed JSON', () {
      expect(
        () => AlmanacSerialization.decode('not json{'),
        throwsA(isA<FormatException>()),
      );
    });

    test('decode fails loud when the top level is not a JSON object', () {
      expect(
        () => AlmanacSerialization.decode('[1,2,3]'),
        throwsA(isA<TypeError>()),
      );
    });

    test('decode(encode(empty)) equals AlmanacState.empty()', () {
      expect(
        AlmanacSerialization.decode(
          AlmanacSerialization.encode(AlmanacState.empty()),
        ),
        AlmanacState.empty(),
      );
    });
  });
}
