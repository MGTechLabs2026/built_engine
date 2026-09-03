/// Shared record/snapshot builders for the Almanac recorder tests.
///
/// Every helper takes only opaque `String` ids and plain scalars, so a test
/// can express a relationship (`runId`, `phase`, `sequence`) as an explicit
/// argument and later assert it as an explicit field — never by parsing an id.
library;

import 'package:build_engine/src/plugins/almanac/almanac_models.dart';

/// An empty tome layout — the cheapest valid [TomeLayoutSnapshot].
TomeLayoutSnapshot emptyTome() => TomeLayoutSnapshot(slots: const []);

/// A one-slot tome layout holding [instanceId].
TomeLayoutSnapshot tomeWith({
  required String slotId,
  required String occupantKind,
  String? occupantRefId,
  String? instanceId,
}) => TomeLayoutSnapshot(
  width: 1,
  height: 1,
  slots: [
    TomeSlotSnapshot(
      slotId: slotId,
      occupantKind: occupantKind,
      occupantRefId: occupantRefId,
      instanceId: instanceId,
    ),
  ],
);

TechniqueInstanceSnapshot techniqueSnapshot({
  required String instanceId,
  required String baseFamilyId,
  String? styleId,
  List<String> descriptorIds = const [],
  Map<String, num> axisProfile = const {},
  TechniqueOrigin origin = TechniqueOrigin.base,
  int masteryAtSnapshot = 0,
}) => TechniqueInstanceSnapshot(
  instanceId: instanceId,
  baseFamilyId: baseFamilyId,
  styleId: styleId,
  descriptorIds: descriptorIds,
  axisProfile: axisProfile,
  origin: origin,
  masteryAtSnapshot: masteryAtSnapshot,
);

ItemInstanceSnapshot itemSnapshot({
  required String definitionId,
  String? instanceId,
  int itemClass = 1,
  Map<String, num> statBonuses = const {},
  Map<String, num> resolvedProperties = const {},
}) => ItemInstanceSnapshot(
  definitionId: definitionId,
  instanceId: instanceId,
  itemClass: itemClass,
  statBonuses: statBonuses,
  resolvedProperties: resolvedProperties,
);

/// A build record with a pre-computed (non-empty) DNA unless [dna] says
/// otherwise; pass `BuildDna(tokens: const [], signature: '')` to exercise the
/// recorder's DNA back-fill.
AlmanacBuildRecord buildRecord({
  required String runId,
  required String buildId,
  BuildPhase phase = BuildPhase.initial,
  int sequence = 0,
  String lineageId = 'lin-a',
  String physiqueId = 'phy-a',
  List<TechniqueInstanceSnapshot> techniques = const [],
  List<ItemInstanceSnapshot> items = const [],
  List<AffixSnapshot> affixes = const [],
  TomeLayoutSnapshot? tome,
  BuildPerformanceSnapshot? performance,
  BuildDna? dna,
}) => AlmanacBuildRecord(
  buildId: buildId,
  runId: runId,
  phase: phase,
  sequence: sequence,
  lineageId: lineageId,
  physiqueId: physiqueId,
  techniques: techniques,
  items: items,
  affixes: affixes,
  tome: tome ?? emptyTome(),
  performance: performance,
  dna: dna ?? BuildDna(tokens: const ['LIN-A', 'PHY-A'], signature: 'aaaaaaaa'),
);

/// A build record whose DNA is empty, so the recorder must compute it.
AlmanacBuildRecord buildRecordWithoutDna({
  required String runId,
  required String buildId,
  BuildPhase phase = BuildPhase.initial,
  int sequence = 0,
  String lineageId = 'lin-a',
  String physiqueId = 'phy-a',
  List<TechniqueInstanceSnapshot> techniques = const [],
  List<ItemInstanceSnapshot> items = const [],
  List<AffixSnapshot> affixes = const [],
  TomeLayoutSnapshot? tome,
}) => buildRecord(
  runId: runId,
  buildId: buildId,
  phase: phase,
  sequence: sequence,
  lineageId: lineageId,
  physiqueId: physiqueId,
  techniques: techniques,
  items: items,
  affixes: affixes,
  tome: tome,
  dna: BuildDna(tokens: const [], signature: ''),
);

AlmanacFightRecord fightRecord({
  required String runId,
  required String fightId,
  int sequence = 0,
  String name = 'Bandit',
  String enemyId = 'enemy-bandit',
  bool won = true,
  num playerHealthAfter = 10,
  int turnsUsed = 5,
}) => AlmanacFightRecord(
  fightId: fightId,
  runId: runId,
  sequence: sequence,
  name: name,
  enemyId: enemyId,
  won: won,
  playerHealthAfter: playerHealthAfter,
  turnsUsed: turnsUsed,
);

DiscoverySnapshot discoverySnapshot({
  String label = 'label',
  Map<String, Object?> values = const {},
}) => DiscoverySnapshot(label: label, values: values);

/// A fixed timestamp, so tests never depend on the wall clock.
DateTime at(int day) => DateTime.utc(2026, 1, day);

// -----------------------------------------------------------------------------
// Record builders (added for the Phase 5 query API tests). Additive only:
// every parameter is an opaque `String` id or a plain scalar so a test can
// state a relationship as an argument and assert it as an explicit field.
// -----------------------------------------------------------------------------

AlmanacRunRecord runRecord({
  required String runId,
  int runNumber = 1,
  int? seed,
  String lineageId = 'lin-a',
  String physiqueId = 'phy-a',
  DateTime? startedAt,
  DateTime? completedAt,
  RunOutcome outcome = RunOutcome.won,
  List<AlmanacFightRecord> fights = const [],
  List<String> discoveryIds = const [],
  List<TrainingObservation> trainingObservations = const [],
  String? finalBuildId,
  int enemiesDefeated = 0,
  int techniquesUsed = 0,
  int trainingSessions = 0,
}) => AlmanacRunRecord(
  runId: runId,
  runNumber: runNumber,
  seed: seed,
  lineageId: lineageId,
  physiqueId: physiqueId,
  startedAt: startedAt ?? at(1),
  completedAt: completedAt,
  outcome: outcome,
  fights: fights,
  discoveryIds: discoveryIds,
  trainingObservations: trainingObservations,
  finalBuildId: finalBuildId,
  enemiesDefeated: enemiesDefeated,
  techniquesUsed: techniquesUsed,
  trainingSessions: trainingSessions,
);

TechniqueUsageObservation usageObservation({
  required String usageEventId,
  required String runId,
  int runNumber = 1,
  required String instanceId,
}) => TechniqueUsageObservation(
  usageEventId: usageEventId,
  runId: runId,
  runNumber: runNumber,
  instanceId: instanceId,
);

/// A technique record; `totalUsage` defaults to the number of usage
/// observations and `runsUsed` defaults to their distinct run numbers.
AlmanacTechniqueRecord techniqueRecord({
  required String instanceId,
  String baseFamilyId = 'fam-a',
  String? styleId,
  List<String> descriptorIds = const [],
  Map<String, num> axisProfile = const {},
  String? discoveredRunId,
  int? discoveredRunNumber,
  int? masteryAtDiscovery,
  List<TechniqueUsageObservation> usageObservations = const [],
  int? totalUsage,
  List<int>? runsUsed,
  TechniqueOrigin origin = TechniqueOrigin.base,
}) => AlmanacTechniqueRecord(
  instanceId: instanceId,
  baseFamilyId: baseFamilyId,
  styleId: styleId,
  descriptorIds: descriptorIds,
  axisProfile: axisProfile,
  discoveredRunId: discoveredRunId,
  discoveredRunNumber: discoveredRunNumber,
  masteryAtDiscovery: masteryAtDiscovery,
  usageObservations: usageObservations,
  totalUsage: totalUsage ?? usageObservations.length,
  runsUsed:
      runsUsed ?? {for (final o in usageObservations) o.runNumber}.toList(),
  origin: origin,
);

TechniqueInspirationHistory inspirationHistory({
  required String resultInstanceId,
  String runId = 'run-1',
  String familyId = 'fam-a',
  List<String> descriptorIds = const [],
  List<String> inspirerInstanceIds = const [],
}) => TechniqueInspirationHistory(
  resultInstanceId: resultInstanceId,
  runId: runId,
  familyId: familyId,
  descriptorIds: descriptorIds,
  inspirerInstanceIds: inspirerInstanceIds,
);

AffixObservation affixObservation({
  required String affixEventId,
  required String runId,
  int runNumber = 1,
  String? lineageId,
}) => AffixObservation(
  affixEventId: affixEventId,
  runId: runId,
  runNumber: runNumber,
  lineageId: lineageId,
);

/// An affix record; `timesDiscovered` / `timesUsed` default to the length of
/// the matching observation ledger.
AlmanacAffixRecord affixRecord({
  required String affixId,
  List<AffixObservation> discoveryObservations = const [],
  List<AffixObservation> usageObservations = const [],
  int? timesDiscovered,
  int? timesUsed,
  String? firstDiscoveredRunId,
  List<String> associatedLineageIds = const [],
  AffixSnapshot? snapshot,
}) => AlmanacAffixRecord(
  affixId: affixId,
  discoveryObservations: discoveryObservations,
  usageObservations: usageObservations,
  timesDiscovered: timesDiscovered ?? discoveryObservations.length,
  timesUsed: timesUsed ?? usageObservations.length,
  firstDiscoveredRunId: firstDiscoveredRunId,
  associatedLineageIds: associatedLineageIds,
  snapshot: snapshot ?? AffixSnapshot(affixId: affixId, stat: 'atk', value: 1),
);

AlmanacDiscoveryRecord discoveryRecord({
  required String discoveryId,
  AlmanacDiscoveryType type = AlmanacDiscoveryType.technique,
  required String contentId,
  String? instanceId,
  String runId = 'run-1',
  int runNumber = 1,
  DateTime? timestamp,
  DiscoverySnapshot? snapshot,
}) => AlmanacDiscoveryRecord(
  discoveryId: discoveryId,
  type: type,
  contentId: contentId,
  instanceId: instanceId,
  runId: runId,
  runNumber: runNumber,
  timestamp: timestamp ?? at(1),
  snapshot: snapshot ?? discoverySnapshot(),
);
