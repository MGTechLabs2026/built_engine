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
