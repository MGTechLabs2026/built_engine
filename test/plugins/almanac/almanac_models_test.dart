import 'package:build_engine/src/plugins/almanac/almanac_models.dart';
import 'package:test/test.dart';

/// Builds a fully-populated [AlmanacState] whose every record type,
/// snapshot, and observation is non-trivially filled in. Shared by the
/// round-trip and equality tests.
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
  final affixSnapshot = const AffixSnapshot(
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
  group('_enumByName (via *.fromJson enum parsing)', () {
    test('round-trips every enum value by .name', () {
      for (final value in RunOutcome.values) {
        final json =
            AlmanacRunRecord(
              runId: 'r',
              runNumber: 0,
              lineageId: 'l',
              physiqueId: 'p',
              startedAt: DateTime.parse('2026-01-01T00:00:00.000Z'),
              outcome: value,
              fights: const [],
              discoveryIds: const [],
              trainingObservations: const [],
              enemiesDefeated: 0,
              techniquesUsed: 0,
              trainingSessions: 0,
            ).toJson();
        expect(AlmanacRunRecord.fromJson(json).outcome, value);
      }
    });

    test('throws ArgumentError on an unknown enum name', () {
      final json = _milestoneJson()..['type'] = 'notARealMilestone';
      expect(() => AlmanacMilestoneRecord.fromJson(json), throwsArgumentError);
    });

    test('throws ArgumentError on a missing / null enum name', () {
      final json = _milestoneJson()..remove('type');
      expect(() => AlmanacMilestoneRecord.fromJson(json), throwsArgumentError);

      final nulled = _milestoneJson()..['type'] = null;
      expect(
        () => AlmanacMilestoneRecord.fromJson(nulled),
        throwsArgumentError,
      );
    });
  });

  group('per-record toJson/fromJson round-trip', () {
    test('TechniqueUsageObservation', () {
      const original = TechniqueUsageObservation(
        usageEventId: 'u1',
        runId: 'r1',
        runNumber: 2,
        instanceId: 'i1',
      );
      expect(
        TechniqueUsageObservation.fromJson(original.toJson()),
        equals(original),
      );
    });

    test('AffixObservation with and without lineageId', () {
      const withLineage = AffixObservation(
        affixEventId: 'e1',
        runId: 'r1',
        runNumber: 1,
        lineageId: 'lin-1',
      );
      const withoutLineage = AffixObservation(
        affixEventId: 'e2',
        runId: 'r1',
        runNumber: 1,
      );
      expect(
        AffixObservation.fromJson(withLineage.toJson()),
        equals(withLineage),
      );
      expect(
        AffixObservation.fromJson(withoutLineage.toJson()),
        equals(withoutLineage),
      );
      expect(withoutLineage.toJson().containsKey('lineageId'), isFalse);
    });

    test('TrainingObservation', () {
      const original = TrainingObservation(
        trainingEventId: 't1',
        runId: 'r1',
        runNumber: 3,
      );
      expect(TrainingObservation.fromJson(original.toJson()), equals(original));
    });

    test('TechniqueInstanceSnapshot', () {
      final original = TechniqueInstanceSnapshot(
        instanceId: 'ti',
        baseFamilyId: 'fam',
        styleId: 'style',
        descriptorIds: ['a', 'b'],
        axisProfile: {'x': 1, 'y': 2.5},
        origin: TechniqueOrigin.base,
        masteryAtSnapshot: 0,
      );
      expect(
        TechniqueInstanceSnapshot.fromJson(original.toJson()),
        equals(original),
      );
    });

    test('ItemInstanceSnapshot', () {
      final original = ItemInstanceSnapshot(
        definitionId: 'def',
        itemClass: 1,
        statBonuses: {'atk': 2},
        resolvedProperties: {'w': 0.5},
      );
      expect(
        ItemInstanceSnapshot.fromJson(original.toJson()),
        equals(original),
      );
      expect(original.toJson().containsKey('instanceId'), isFalse);
    });

    test('AffixSnapshot', () {
      const original = AffixSnapshot(affixId: 'af', stat: 's', value: 9);
      expect(AffixSnapshot.fromJson(original.toJson()), equals(original));
    });

    test('TomeSlotSnapshot', () {
      const original = TomeSlotSnapshot(
        slotId: 's',
        occupantKind: 'item',
        occupantRefId: 'def',
        instanceId: 'inst',
      );
      expect(TomeSlotSnapshot.fromJson(original.toJson()), equals(original));
    });

    test('TomeLayoutSnapshot', () {
      final original = TomeLayoutSnapshot(
        slots: [const TomeSlotSnapshot(slotId: 's0', occupantKind: 'empty')],
      );
      expect(TomeLayoutSnapshot.fromJson(original.toJson()), equals(original));
      expect(original.toJson().containsKey('width'), isFalse);
    });

    test('BuildPerformanceSnapshot', () {
      const original = BuildPerformanceSnapshot(
        fightsWon: 2,
        fightsLost: 0,
        enemiesDefeated: 5,
        avgTurnsUsed: 4.2,
      );
      expect(
        BuildPerformanceSnapshot.fromJson(original.toJson()),
        equals(original),
      );
    });

    test('DiscoverySnapshot with nested collections', () {
      final original = DiscoverySnapshot(
        label: 'l',
        values: {
          'a': 1,
          'b': ['x', 'y'],
          'c': {'deep': true},
        },
      );
      expect(DiscoverySnapshot.fromJson(original.toJson()), equals(original));
    });

    test('BuildDna', () {
      final original = BuildDna(tokens: ['a', 'b'], signature: 'sig');
      expect(BuildDna.fromJson(original.toJson()), equals(original));
    });

    test('AlmanacFightRecord', () {
      const original = AlmanacFightRecord(
        fightId: 'f',
        runId: 'r',
        sequence: 1,
        name: 'n',
        enemyId: 'e',
        won: false,
        playerHealthAfter: 0,
        turnsUsed: 9,
      );
      expect(AlmanacFightRecord.fromJson(original.toJson()), equals(original));
    });

    test('AlmanacRunRecord with seed present', () {
      final original = _populatedState().runs.single;
      expect(original.seed, 12345);
      expect(AlmanacRunRecord.fromJson(original.toJson()), equals(original));
    });

    test('AlmanacRunRecord with seed absent', () {
      final original = AlmanacRunRecord(
        runId: 'r',
        runNumber: 4,
        lineageId: 'l',
        physiqueId: 'p',
        startedAt: DateTime.parse('2026-05-05T00:00:00.000Z'),
        outcome: RunOutcome.abandoned,
        fights: const [],
        discoveryIds: const [],
        trainingObservations: const [],
        enemiesDefeated: 0,
        techniquesUsed: 0,
        trainingSessions: 0,
      );
      final json = original.toJson();
      expect(json.containsKey('seed'), isFalse);
      expect(json.containsKey('completedAt'), isFalse);
      expect(json.containsKey('finalBuildId'), isFalse);
      final decoded = AlmanacRunRecord.fromJson(json);
      expect(decoded, equals(original));
      expect(decoded.seed, isNull);
      expect(decoded.completedAt, isNull);
    });

    test('AlmanacBuildRecord', () {
      final original = _populatedState().builds.single;
      expect(AlmanacBuildRecord.fromJson(original.toJson()), equals(original));
    });

    test('AlmanacTechniqueRecord', () {
      final original = _populatedState().techniques.single;
      expect(
        AlmanacTechniqueRecord.fromJson(original.toJson()),
        equals(original),
      );
    });

    test('AlmanacTechniqueRecord with nullable discovery fields absent', () {
      final original = AlmanacTechniqueRecord(
        instanceId: 'ti',
        baseFamilyId: 'fam',
        descriptorIds: const [],
        axisProfile: const {},
        usageObservations: const [],
        totalUsage: 0,
        runsUsed: const [],
        origin: TechniqueOrigin.base,
      );
      final json = original.toJson();
      expect(json.containsKey('discoveredRunId'), isFalse);
      expect(json.containsKey('discoveredRunNumber'), isFalse);
      expect(json.containsKey('masteryAtDiscovery'), isFalse);
      expect(AlmanacTechniqueRecord.fromJson(json), equals(original));
    });

    test('TechniqueInspirationHistory', () {
      final original = _populatedState().inspirations.single;
      expect(
        TechniqueInspirationHistory.fromJson(original.toJson()),
        equals(original),
      );
    });

    test('AlmanacAffixRecord', () {
      final original = _populatedState().affixes.single;
      expect(AlmanacAffixRecord.fromJson(original.toJson()), equals(original));
    });

    test('AlmanacDiscoveryRecord', () {
      final original = _populatedState().discoveries.single;
      expect(
        AlmanacDiscoveryRecord.fromJson(original.toJson()),
        equals(original),
      );
    });

    test('AlmanacMilestoneRecord', () {
      final original = _populatedState().milestones.single;
      expect(
        AlmanacMilestoneRecord.fromJson(original.toJson()),
        equals(original),
      );
    });
  });

  group('AlmanacState', () {
    test('empty() has no history and round-trips', () {
      final empty = AlmanacState.empty();
      expect(empty.runs, isEmpty);
      expect(empty.milestones, isEmpty);
      expect(AlmanacState.fromJson(empty.toJson()), equals(empty));
    });

    test('almanacSchemaVersion is 1 and is emitted', () {
      expect(AlmanacState.almanacSchemaVersion, 1);
      expect(AlmanacState.empty().toJson()['almanacSchemaVersion'], 1);
    });

    test('fully-populated state round-trips to a structurally equal value', () {
      final original = _populatedState();
      final decoded = AlmanacState.fromJson(original.toJson());
      expect(decoded, equals(original));
      expect(decoded.hashCode, equals(original.hashCode));
    });

    test('a re-decoded state equals the first decode', () {
      final once = AlmanacState.fromJson(_populatedState().toJson());
      final twice = AlmanacState.fromJson(once.toJson());
      expect(twice, equals(once));
    });
  });

  group('deep immutability', () {
    test(
      'constructor copies a mutable list: later source mutation is ignored',
      () {
        final descriptors = ['a', 'b'];
        final snapshot = TechniqueInstanceSnapshot(
          instanceId: 'ti',
          baseFamilyId: 'fam',
          descriptorIds: descriptors,
          axisProfile: const {},
          origin: TechniqueOrigin.base,
          masteryAtSnapshot: 0,
        );
        descriptors.add('c');
        expect(snapshot.descriptorIds, ['a', 'b']);
      },
    );

    test(
      'constructor copies a mutable map: later source mutation is ignored',
      () {
        final axes = <String, num>{'x': 1};
        final snapshot = TechniqueInstanceSnapshot(
          instanceId: 'ti',
          baseFamilyId: 'fam',
          descriptorIds: const [],
          axisProfile: axes,
          origin: TechniqueOrigin.base,
          masteryAtSnapshot: 0,
        );
        axes['y'] = 2;
        expect(snapshot.axisProfile, {'x': 1});
      },
    );

    test('a list read back off a record is unmodifiable', () {
      final snapshot = TechniqueInstanceSnapshot(
        instanceId: 'ti',
        baseFamilyId: 'fam',
        descriptorIds: ['a'],
        axisProfile: const {},
        origin: TechniqueOrigin.base,
        masteryAtSnapshot: 0,
      );
      expect(() => snapshot.descriptorIds.add('b'), throwsUnsupportedError);
    });

    test('a map read back off a record is unmodifiable', () {
      final snapshot = TechniqueInstanceSnapshot(
        instanceId: 'ti',
        baseFamilyId: 'fam',
        descriptorIds: const [],
        axisProfile: {'x': 1},
        origin: TechniqueOrigin.base,
        masteryAtSnapshot: 0,
      );
      expect(() => snapshot.axisProfile['y'] = 2, throwsUnsupportedError);
    });

    test(
      'nested lists survive an encode/decode round-trip as unmodifiable',
      () {
        final decoded = AlmanacState.fromJson(_populatedState().toJson());
        expect(
          () => decoded.runs.add(decoded.runs.first),
          throwsUnsupportedError,
        );
        expect(
          () => decoded.runs.first.fights.add(decoded.runs.first.fights.first),
          throwsUnsupportedError,
        );
        expect(
          () => decoded.builds.first.techniques.first.descriptorIds.add('z'),
          throwsUnsupportedError,
        );
      },
    );

    test(
      'mutating a collection read off a decoded record leaves state intact',
      () {
        final original = _populatedState();
        final decoded = AlmanacState.fromJson(original.toJson());
        // Reading, copying, and mutating the copy must not touch the record.
        final copy = decoded.runs.first.discoveryIds.toList()..add('extra');
        expect(copy.length, 2);
        expect(decoded, equals(original));
      },
    );
  });
}

Map<String, dynamic> _milestoneJson() =>
    AlmanacMilestoneRecord(
      milestoneId: 'ms',
      type: MilestoneType.firstRun,
      runId: 'r',
      runNumber: 0,
      timestamp: DateTime.parse('2026-01-01T00:00:00.000Z'),
    ).toJson();
