/// Almanac v1 — pure domain model.
///
/// This file holds only immutable value objects plus their JSON codecs. It
/// is a composition-module concern (`lib/src/plugins/almanac/`), never a
/// `GamePlugin`, and it imports Core only — no other plugin, no `dart:io`,
/// no `dart:convert` (the envelope + `jsonEncode`/`jsonDecode` live in the
/// serialization step). Every id is an opaque `String`: relationships are
/// stored as explicit fields, never recovered by parsing an id.
///
/// Deep immutability: every `List`/`Map` a record holds is copied into an
/// unmodifiable view in the constructor, so neither the caller's original
/// collection nor a collection read back off a record can mutate stored
/// state. Serialization follows the repo's module-local house style
/// (`Container.toJson` / `CombatantComponent.toJson`): a plain
/// `Map<String, dynamic> toJson()` and a `factory X.fromJson(...)` per
/// class, no second framework.
library;

// -----------------------------------------------------------------------------
// Value-object plumbing
// -----------------------------------------------------------------------------

/// Structural-equality base for every model below: two instances are equal
/// when they share a runtime type and have deeply-equal [props]. Keeps
/// hand-written `==`/`hashCode` out of ~25 classes.
abstract class _AlmanacValue {
  const _AlmanacValue();

  /// The ordered fields that define this value's identity.
  List<Object?> get props;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is _AlmanacValue &&
          other.runtimeType == runtimeType &&
          _deepEquals(props, other.props);

  @override
  int get hashCode => Object.hashAll(props.map(_deepHash));
}

/// Recursively compares JSON-like structures (`List`, `Set`, `Map`, scalars,
/// and nested [_AlmanacValue]s via their own `==`).
bool _deepEquals(Object? a, Object? b) {
  if (identical(a, b)) return true;
  if (a is List && b is List) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (!_deepEquals(a[i], b[i])) return false;
    }
    return true;
  }
  if (a is Set && b is Set) {
    if (a.length != b.length) return false;
    for (final element in a) {
      if (!b.any((other) => _deepEquals(element, other))) return false;
    }
    return true;
  }
  if (a is Map && b is Map) {
    if (a.length != b.length) return false;
    for (final key in a.keys) {
      if (!b.containsKey(key) || !_deepEquals(a[key], b[key])) return false;
    }
    return true;
  }
  return a == b;
}

/// Order-independent for `Map`/`Set`, order-dependent for `List`; consistent
/// with [_deepEquals].
int _deepHash(Object? value) {
  if (value is List) return Object.hashAll(value.map(_deepHash));
  if (value is Set) return Object.hashAllUnordered(value.map(_deepHash));
  if (value is Map) {
    return Object.hashAllUnordered(
      value.entries.map(
        (entry) => Object.hash(_deepHash(entry.key), _deepHash(entry.value)),
      ),
    );
  }
  return value.hashCode;
}

/// Recursively copies a JSON-like value into unmodifiable views: every nested
/// `Map` / `List` / `Set` is rebuilt as an unmodifiable copy at every depth,
/// scalars pass through. A caller that keeps a reference to a collection it
/// nested inside the input can therefore never mutate what the value object
/// ends up holding.
Object? _deepFreeze(Object? value) {
  if (value is Map) {
    return Map<Object?, Object?>.unmodifiable({
      for (final entry in value.entries) entry.key: _deepFreeze(entry.value),
    });
  }
  if (value is Set) {
    return Set<Object?>.unmodifiable(value.map(_deepFreeze));
  }
  if (value is List) {
    return List<Object?>.unmodifiable(value.map(_deepFreeze));
  }
  return value;
}

/// Resolves [raw] (an enum `.name` string) against [values]. Throws
/// [ArgumentError] on a missing, null, non-string, or unknown name —
/// matching the repo idiom of `ArgumentError` for invalid data
/// (`lib/src/tome/tome_service.dart:45`).
T _enumByName<T extends Enum>(List<T> values, Object? raw) {
  if (raw is String) {
    for (final value in values) {
      if (value.name == raw) return value;
    }
  }
  throw ArgumentError.value(raw, 'raw', 'unknown $T name');
}

List<String> _stringList(Object? raw) =>
    List<String>.unmodifiable((raw as List<dynamic>).cast<String>());

List<int> _intList(Object? raw) =>
    List<int>.unmodifiable((raw as List<dynamic>).cast<int>());

Map<String, num> _numMap(Object? raw) => Map<String, num>.unmodifiable(
  (raw as Map<String, dynamic>).map(
    (key, value) => MapEntry(key, value as num),
  ),
);

// -----------------------------------------------------------------------------
// Enums (§4.1)
// -----------------------------------------------------------------------------

enum RunOutcome { won, lost, abandoned }

/// Only `base` / `inspired` are produced in v1; `evolved` is reserved.
enum TechniqueOrigin { base, evolved, inspired }

enum BuildPhase { initial, postReward, postTraining, finalBuild }

enum AlmanacDiscoveryType { technique, techniqueVariant, item, affix, lineage }

enum MilestoneType {
  firstRun,
  firstVictory,
  firstTechniqueVariant,
  firstInspiredTechnique,
  firstAffix,
  firstWinWithLineage,
  firstSuccessfulBuild,
}

// -----------------------------------------------------------------------------
// Observation records (§4.2 / spec §5.6.1)
// -----------------------------------------------------------------------------

/// One recorded use of a technique instance in a run.
class TechniqueUsageObservation extends _AlmanacValue {
  const TechniqueUsageObservation({
    required this.usageEventId,
    required this.runId,
    required this.runNumber,
    required this.instanceId,
  });

  /// Opaque idempotency token for the usage event.
  final String usageEventId;

  /// Explicit relation to the owning run — never parsed out of an id.
  final String runId;
  final int runNumber;
  final String instanceId;

  Map<String, dynamic> toJson() => {
    'usageEventId': usageEventId,
    'runId': runId,
    'runNumber': runNumber,
    'instanceId': instanceId,
  };

  factory TechniqueUsageObservation.fromJson(Map<String, dynamic> json) =>
      TechniqueUsageObservation(
        usageEventId: json['usageEventId'] as String,
        runId: json['runId'] as String,
        runNumber: json['runNumber'] as int,
        instanceId: json['instanceId'] as String,
      );

  @override
  List<Object?> get props => [usageEventId, runId, runNumber, instanceId];
}

/// One recorded discovery or use of an affix in a run.
class AffixObservation extends _AlmanacValue {
  const AffixObservation({
    required this.affixEventId,
    required this.runId,
    required this.runNumber,
    this.lineageId,
  });

  /// Opaque idempotency token for the affix event.
  final String affixEventId;
  final String runId;
  final int runNumber;
  final String? lineageId;

  Map<String, dynamic> toJson() => {
    'affixEventId': affixEventId,
    'runId': runId,
    'runNumber': runNumber,
    if (lineageId != null) 'lineageId': lineageId,
  };

  factory AffixObservation.fromJson(Map<String, dynamic> json) =>
      AffixObservation(
        affixEventId: json['affixEventId'] as String,
        runId: json['runId'] as String,
        runNumber: json['runNumber'] as int,
        lineageId: json['lineageId'] as String?,
      );

  @override
  List<Object?> get props => [affixEventId, runId, runNumber, lineageId];
}

/// One recorded training session in a run.
class TrainingObservation extends _AlmanacValue {
  const TrainingObservation({
    required this.trainingEventId,
    required this.runId,
    required this.runNumber,
  });

  /// Opaque idempotency token for the training event.
  final String trainingEventId;
  final String runId;
  final int runNumber;

  Map<String, dynamic> toJson() => {
    'trainingEventId': trainingEventId,
    'runId': runId,
    'runNumber': runNumber,
  };

  factory TrainingObservation.fromJson(Map<String, dynamic> json) =>
      TrainingObservation(
        trainingEventId: json['trainingEventId'] as String,
        runId: json['runId'] as String,
        runNumber: json['runNumber'] as int,
      );

  @override
  List<Object?> get props => [trainingEventId, runId, runNumber];
}

// -----------------------------------------------------------------------------
// Snapshots (§4.3)
// -----------------------------------------------------------------------------

/// A technique instance frozen at a moment in a build.
class TechniqueInstanceSnapshot extends _AlmanacValue {
  TechniqueInstanceSnapshot({
    required this.instanceId,
    required this.baseFamilyId,
    this.styleId,
    required List<String> descriptorIds,
    required Map<String, num> axisProfile,
    required this.origin,
    required this.masteryAtSnapshot,
  }) : descriptorIds = List<String>.unmodifiable(descriptorIds),
       axisProfile = Map<String, num>.unmodifiable(axisProfile);

  final String instanceId;
  final String baseFamilyId;
  final String? styleId;
  final List<String> descriptorIds;
  final Map<String, num> axisProfile;
  final TechniqueOrigin origin;
  final int masteryAtSnapshot;

  Map<String, dynamic> toJson() => {
    'instanceId': instanceId,
    'baseFamilyId': baseFamilyId,
    if (styleId != null) 'styleId': styleId,
    'descriptorIds': descriptorIds.toList(),
    'axisProfile': {...axisProfile},
    'origin': origin.name,
    'masteryAtSnapshot': masteryAtSnapshot,
  };

  factory TechniqueInstanceSnapshot.fromJson(Map<String, dynamic> json) =>
      TechniqueInstanceSnapshot(
        instanceId: json['instanceId'] as String,
        baseFamilyId: json['baseFamilyId'] as String,
        styleId: json['styleId'] as String?,
        descriptorIds: _stringList(json['descriptorIds']),
        axisProfile: _numMap(json['axisProfile']),
        origin: _enumByName(TechniqueOrigin.values, json['origin']),
        masteryAtSnapshot: json['masteryAtSnapshot'] as int,
      );

  @override
  List<Object?> get props => [
    instanceId,
    baseFamilyId,
    styleId,
    descriptorIds,
    axisProfile,
    origin,
    masteryAtSnapshot,
  ];
}

/// An item instance frozen at a moment in a build.
class ItemInstanceSnapshot extends _AlmanacValue {
  ItemInstanceSnapshot({
    required this.definitionId,
    this.instanceId,
    required this.itemClass,
    required Map<String, num> statBonuses,
    required Map<String, num> resolvedProperties,
  }) : statBonuses = Map<String, num>.unmodifiable(statBonuses),
       resolvedProperties = Map<String, num>.unmodifiable(resolvedProperties);

  final String definitionId;
  final String? instanceId;
  final int itemClass;
  final Map<String, num> statBonuses;
  final Map<String, num> resolvedProperties;

  Map<String, dynamic> toJson() => {
    'definitionId': definitionId,
    if (instanceId != null) 'instanceId': instanceId,
    'itemClass': itemClass,
    'statBonuses': {...statBonuses},
    'resolvedProperties': {...resolvedProperties},
  };

  factory ItemInstanceSnapshot.fromJson(Map<String, dynamic> json) =>
      ItemInstanceSnapshot(
        definitionId: json['definitionId'] as String,
        instanceId: json['instanceId'] as String?,
        itemClass: json['itemClass'] as int,
        statBonuses: _numMap(json['statBonuses']),
        resolvedProperties: _numMap(json['resolvedProperties']),
      );

  @override
  List<Object?> get props => [
    definitionId,
    instanceId,
    itemClass,
    statBonuses,
    resolvedProperties,
  ];
}

/// A single affix frozen at a moment in a build.
class AffixSnapshot extends _AlmanacValue {
  const AffixSnapshot({
    required this.affixId,
    required this.stat,
    required this.value,
    this.category,
  });

  final String affixId;
  final String stat;
  final num value;
  final String? category;

  Map<String, dynamic> toJson() => {
    'affixId': affixId,
    'stat': stat,
    'value': value,
    if (category != null) 'category': category,
  };

  factory AffixSnapshot.fromJson(Map<String, dynamic> json) => AffixSnapshot(
    affixId: json['affixId'] as String,
    stat: json['stat'] as String,
    value: json['value'] as num,
    category: json['category'] as String?,
  );

  @override
  List<Object?> get props => [affixId, stat, value, category];
}

/// One slot of a tome layout. [occupantKind] is `'technique'`, `'item'`, or
/// `'empty'` (stored as an opaque string, not interpreted here).
class TomeSlotSnapshot extends _AlmanacValue {
  const TomeSlotSnapshot({
    required this.slotId,
    required this.occupantKind,
    this.occupantRefId,
    this.instanceId,
  });

  final String slotId;
  final String occupantKind;
  final String? occupantRefId;
  final String? instanceId;

  Map<String, dynamic> toJson() => {
    'slotId': slotId,
    'occupantKind': occupantKind,
    if (occupantRefId != null) 'occupantRefId': occupantRefId,
    if (instanceId != null) 'instanceId': instanceId,
  };

  factory TomeSlotSnapshot.fromJson(Map<String, dynamic> json) =>
      TomeSlotSnapshot(
        slotId: json['slotId'] as String,
        occupantKind: json['occupantKind'] as String,
        occupantRefId: json['occupantRefId'] as String?,
        instanceId: json['instanceId'] as String?,
      );

  @override
  List<Object?> get props => [slotId, occupantKind, occupantRefId, instanceId];
}

/// A tome's slot layout frozen at a moment in a build.
class TomeLayoutSnapshot extends _AlmanacValue {
  TomeLayoutSnapshot({
    this.width,
    this.height,
    required List<TomeSlotSnapshot> slots,
  }) : slots = List<TomeSlotSnapshot>.unmodifiable(slots);

  final int? width;
  final int? height;
  final List<TomeSlotSnapshot> slots;

  Map<String, dynamic> toJson() => {
    if (width != null) 'width': width,
    if (height != null) 'height': height,
    'slots': [for (final slot in slots) slot.toJson()],
  };

  factory TomeLayoutSnapshot.fromJson(Map<String, dynamic> json) =>
      TomeLayoutSnapshot(
        width: json['width'] as int?,
        height: json['height'] as int?,
        slots: List<TomeSlotSnapshot>.unmodifiable([
          for (final raw in json['slots'] as List<dynamic>)
            TomeSlotSnapshot.fromJson(raw as Map<String, dynamic>),
        ]),
      );

  @override
  List<Object?> get props => [width, height, slots];
}

/// Aggregate combat performance for a build.
class BuildPerformanceSnapshot extends _AlmanacValue {
  const BuildPerformanceSnapshot({
    required this.fightsWon,
    required this.fightsLost,
    required this.enemiesDefeated,
    this.avgTurnsUsed,
  });

  final int fightsWon;
  final int fightsLost;
  final int enemiesDefeated;
  final num? avgTurnsUsed;

  Map<String, dynamic> toJson() => {
    'fightsWon': fightsWon,
    'fightsLost': fightsLost,
    'enemiesDefeated': enemiesDefeated,
    if (avgTurnsUsed != null) 'avgTurnsUsed': avgTurnsUsed,
  };

  factory BuildPerformanceSnapshot.fromJson(Map<String, dynamic> json) =>
      BuildPerformanceSnapshot(
        fightsWon: json['fightsWon'] as int,
        fightsLost: json['fightsLost'] as int,
        enemiesDefeated: json['enemiesDefeated'] as int,
        avgTurnsUsed: json['avgTurnsUsed'] as num?,
      );

  @override
  List<Object?> get props => [
    fightsWon,
    fightsLost,
    enemiesDefeated,
    avgTurnsUsed,
  ];
}

/// A free-form labelled payload captured with a discovery. [values] holds
/// JSON-safe scalars/collections only, and is deep-frozen on construction —
/// every nested `List`/`Map`/`Set` is copied into an unmodifiable view at
/// every depth (via [_deepFreeze]), so the snapshot is fully immutable on its
/// own, independent of the recorder's separate ingress copy.
class DiscoverySnapshot extends _AlmanacValue {
  DiscoverySnapshot({required this.label, required Map<String, Object?> values})
    : values = Map<String, Object?>.unmodifiable({
        for (final entry in values.entries) entry.key: _deepFreeze(entry.value),
      });

  final String label;
  final Map<String, Object?> values;

  Map<String, dynamic> toJson() => {
    'label': label,
    'values': {...values},
  };

  factory DiscoverySnapshot.fromJson(Map<String, dynamic> json) =>
      DiscoverySnapshot(
        label: json['label'] as String,
        values: json['values'] as Map<String, dynamic>,
      );

  @override
  List<Object?> get props => [label, values];
}

/// A build "fingerprint" value object. The token/signature algorithm is a
/// later task; this only carries the result.
class BuildDna extends _AlmanacValue {
  BuildDna({required List<String> tokens, required this.signature})
    : tokens = List<String>.unmodifiable(tokens);

  final List<String> tokens;
  final String signature;

  Map<String, dynamic> toJson() => {
    'tokens': tokens.toList(),
    'signature': signature,
  };

  factory BuildDna.fromJson(Map<String, dynamic> json) => BuildDna(
    tokens: _stringList(json['tokens']),
    signature: json['signature'] as String,
  );

  @override
  List<Object?> get props => [tokens, signature];
}

// -----------------------------------------------------------------------------
// Canonical records (§4.4)
// -----------------------------------------------------------------------------

/// One fight within a run.
class AlmanacFightRecord extends _AlmanacValue {
  const AlmanacFightRecord({
    required this.fightId,
    required this.runId,
    required this.sequence,
    required this.name,
    required this.enemyId,
    required this.won,
    required this.playerHealthAfter,
    required this.turnsUsed,
  });

  /// Opaque idempotency token within `runs[runId].fights`.
  final String fightId;
  final String runId;
  final int sequence;
  final String name;
  final String enemyId;
  final bool won;
  final num playerHealthAfter;
  final int turnsUsed;

  Map<String, dynamic> toJson() => {
    'fightId': fightId,
    'runId': runId,
    'sequence': sequence,
    'name': name,
    'enemyId': enemyId,
    'won': won,
    'playerHealthAfter': playerHealthAfter,
    'turnsUsed': turnsUsed,
  };

  factory AlmanacFightRecord.fromJson(Map<String, dynamic> json) =>
      AlmanacFightRecord(
        fightId: json['fightId'] as String,
        runId: json['runId'] as String,
        sequence: json['sequence'] as int,
        name: json['name'] as String,
        enemyId: json['enemyId'] as String,
        won: json['won'] as bool,
        playerHealthAfter: json['playerHealthAfter'] as num,
        turnsUsed: json['turnsUsed'] as int,
      );

  @override
  List<Object?> get props => [
    fightId,
    runId,
    sequence,
    name,
    enemyId,
    won,
    playerHealthAfter,
    turnsUsed,
  ];
}

/// The canonical history of a single run. `seed` is optional replay
/// metadata that keys nothing; `enemiesDefeated` / `techniquesUsed` /
/// `trainingSessions` are derived projections.
class AlmanacRunRecord extends _AlmanacValue {
  AlmanacRunRecord({
    required this.runId,
    required this.runNumber,
    this.seed,
    required this.lineageId,
    required this.physiqueId,
    required this.startedAt,
    this.completedAt,
    required this.outcome,
    required List<AlmanacFightRecord> fights,
    required List<String> discoveryIds,
    required List<TrainingObservation> trainingObservations,
    this.finalBuildId,
    required this.enemiesDefeated,
    required this.techniquesUsed,
    required this.trainingSessions,
  }) : fights = List<AlmanacFightRecord>.unmodifiable(fights),
       discoveryIds = List<String>.unmodifiable(discoveryIds),
       trainingObservations = List<TrainingObservation>.unmodifiable(
         trainingObservations,
       );

  final String runId;
  final int runNumber;
  final int? seed;
  final String lineageId;
  final String physiqueId;
  final DateTime startedAt;
  final DateTime? completedAt;
  final RunOutcome outcome;
  final List<AlmanacFightRecord> fights;
  final List<String> discoveryIds;
  final List<TrainingObservation> trainingObservations;
  final String? finalBuildId;
  final int enemiesDefeated;
  final int techniquesUsed;
  final int trainingSessions;

  Map<String, dynamic> toJson() => {
    'runId': runId,
    'runNumber': runNumber,
    if (seed != null) 'seed': seed,
    'lineageId': lineageId,
    'physiqueId': physiqueId,
    'startedAt': startedAt.toIso8601String(),
    if (completedAt != null) 'completedAt': completedAt!.toIso8601String(),
    'outcome': outcome.name,
    'fights': [for (final fight in fights) fight.toJson()],
    'discoveryIds': discoveryIds.toList(),
    'trainingObservations': [
      for (final observation in trainingObservations) observation.toJson(),
    ],
    if (finalBuildId != null) 'finalBuildId': finalBuildId,
    'enemiesDefeated': enemiesDefeated,
    'techniquesUsed': techniquesUsed,
    'trainingSessions': trainingSessions,
  };

  factory AlmanacRunRecord.fromJson(Map<String, dynamic> json) =>
      AlmanacRunRecord(
        runId: json['runId'] as String,
        runNumber: json['runNumber'] as int,
        seed: json['seed'] as int?,
        lineageId: json['lineageId'] as String,
        physiqueId: json['physiqueId'] as String,
        startedAt: DateTime.parse(json['startedAt'] as String),
        completedAt:
            json['completedAt'] == null
                ? null
                : DateTime.parse(json['completedAt'] as String),
        outcome: _enumByName(RunOutcome.values, json['outcome']),
        fights: List<AlmanacFightRecord>.unmodifiable([
          for (final raw in json['fights'] as List<dynamic>)
            AlmanacFightRecord.fromJson(raw as Map<String, dynamic>),
        ]),
        discoveryIds: _stringList(json['discoveryIds']),
        trainingObservations: List<TrainingObservation>.unmodifiable([
          for (final raw in json['trainingObservations'] as List<dynamic>)
            TrainingObservation.fromJson(raw as Map<String, dynamic>),
        ]),
        finalBuildId: json['finalBuildId'] as String?,
        enemiesDefeated: json['enemiesDefeated'] as int,
        techniquesUsed: json['techniquesUsed'] as int,
        trainingSessions: json['trainingSessions'] as int,
      );

  @override
  List<Object?> get props => [
    runId,
    runNumber,
    seed,
    lineageId,
    physiqueId,
    startedAt,
    completedAt,
    outcome,
    fights,
    discoveryIds,
    trainingObservations,
    finalBuildId,
    enemiesDefeated,
    techniquesUsed,
    trainingSessions,
  ];
}

/// A build snapshot at one [BuildPhase] of a run.
class AlmanacBuildRecord extends _AlmanacValue {
  AlmanacBuildRecord({
    required this.buildId,
    required this.runId,
    required this.phase,
    required this.sequence,
    required this.lineageId,
    required this.physiqueId,
    required List<TechniqueInstanceSnapshot> techniques,
    required List<ItemInstanceSnapshot> items,
    required List<AffixSnapshot> affixes,
    required this.tome,
    this.performance,
    required this.dna,
  }) : techniques = List<TechniqueInstanceSnapshot>.unmodifiable(techniques),
       items = List<ItemInstanceSnapshot>.unmodifiable(items),
       affixes = List<AffixSnapshot>.unmodifiable(affixes);

  /// Opaque idempotency token.
  final String buildId;
  final String runId;
  final BuildPhase phase;
  final int sequence;
  final String lineageId;
  final String physiqueId;
  final List<TechniqueInstanceSnapshot> techniques;
  final List<ItemInstanceSnapshot> items;
  final List<AffixSnapshot> affixes;
  final TomeLayoutSnapshot tome;
  final BuildPerformanceSnapshot? performance;
  final BuildDna dna;

  Map<String, dynamic> toJson() => {
    'buildId': buildId,
    'runId': runId,
    'phase': phase.name,
    'sequence': sequence,
    'lineageId': lineageId,
    'physiqueId': physiqueId,
    'techniques': [for (final t in techniques) t.toJson()],
    'items': [for (final i in items) i.toJson()],
    'affixes': [for (final a in affixes) a.toJson()],
    'tome': tome.toJson(),
    if (performance != null) 'performance': performance!.toJson(),
    'dna': dna.toJson(),
  };

  factory AlmanacBuildRecord.fromJson(Map<String, dynamic> json) =>
      AlmanacBuildRecord(
        buildId: json['buildId'] as String,
        runId: json['runId'] as String,
        phase: _enumByName(BuildPhase.values, json['phase']),
        sequence: json['sequence'] as int,
        lineageId: json['lineageId'] as String,
        physiqueId: json['physiqueId'] as String,
        techniques: List<TechniqueInstanceSnapshot>.unmodifiable([
          for (final raw in json['techniques'] as List<dynamic>)
            TechniqueInstanceSnapshot.fromJson(raw as Map<String, dynamic>),
        ]),
        items: List<ItemInstanceSnapshot>.unmodifiable([
          for (final raw in json['items'] as List<dynamic>)
            ItemInstanceSnapshot.fromJson(raw as Map<String, dynamic>),
        ]),
        affixes: List<AffixSnapshot>.unmodifiable([
          for (final raw in json['affixes'] as List<dynamic>)
            AffixSnapshot.fromJson(raw as Map<String, dynamic>),
        ]),
        tome: TomeLayoutSnapshot.fromJson(json['tome'] as Map<String, dynamic>),
        performance:
            json['performance'] == null
                ? null
                : BuildPerformanceSnapshot.fromJson(
                  json['performance'] as Map<String, dynamic>,
                ),
        dna: BuildDna.fromJson(json['dna'] as Map<String, dynamic>),
      );

  @override
  List<Object?> get props => [
    buildId,
    runId,
    phase,
    sequence,
    lineageId,
    physiqueId,
    techniques,
    items,
    affixes,
    tome,
    performance,
    dna,
  ];
}

/// Canonical cross-run history of one technique instance.
/// `totalUsage` / `runsUsed` are derived projections.
class AlmanacTechniqueRecord extends _AlmanacValue {
  AlmanacTechniqueRecord({
    required this.instanceId,
    required this.baseFamilyId,
    this.styleId,
    required List<String> descriptorIds,
    required Map<String, num> axisProfile,
    this.discoveredRunId,
    this.discoveredRunNumber,
    this.masteryAtDiscovery,
    required List<TechniqueUsageObservation> usageObservations,
    required this.totalUsage,
    required List<int> runsUsed,
    required this.origin,
  }) : descriptorIds = List<String>.unmodifiable(descriptorIds),
       axisProfile = Map<String, num>.unmodifiable(axisProfile),
       usageObservations = List<TechniqueUsageObservation>.unmodifiable(
         usageObservations,
       ),
       runsUsed = List<int>.unmodifiable(runsUsed);

  final String instanceId;
  final String baseFamilyId;
  final String? styleId;
  final List<String> descriptorIds;
  final Map<String, num> axisProfile;
  final String? discoveredRunId;
  final int? discoveredRunNumber;
  final int? masteryAtDiscovery;
  final List<TechniqueUsageObservation> usageObservations;
  final int totalUsage;
  final List<int> runsUsed;
  final TechniqueOrigin origin;

  Map<String, dynamic> toJson() => {
    'instanceId': instanceId,
    'baseFamilyId': baseFamilyId,
    if (styleId != null) 'styleId': styleId,
    'descriptorIds': descriptorIds.toList(),
    'axisProfile': {...axisProfile},
    if (discoveredRunId != null) 'discoveredRunId': discoveredRunId,
    if (discoveredRunNumber != null) 'discoveredRunNumber': discoveredRunNumber,
    if (masteryAtDiscovery != null) 'masteryAtDiscovery': masteryAtDiscovery,
    'usageObservations': [
      for (final observation in usageObservations) observation.toJson(),
    ],
    'totalUsage': totalUsage,
    'runsUsed': runsUsed.toList(),
    'origin': origin.name,
  };

  factory AlmanacTechniqueRecord.fromJson(Map<String, dynamic> json) =>
      AlmanacTechniqueRecord(
        instanceId: json['instanceId'] as String,
        baseFamilyId: json['baseFamilyId'] as String,
        styleId: json['styleId'] as String?,
        descriptorIds: _stringList(json['descriptorIds']),
        axisProfile: _numMap(json['axisProfile']),
        discoveredRunId: json['discoveredRunId'] as String?,
        discoveredRunNumber: json['discoveredRunNumber'] as int?,
        masteryAtDiscovery: json['masteryAtDiscovery'] as int?,
        usageObservations: List<TechniqueUsageObservation>.unmodifiable([
          for (final raw in json['usageObservations'] as List<dynamic>)
            TechniqueUsageObservation.fromJson(raw as Map<String, dynamic>),
        ]),
        totalUsage: json['totalUsage'] as int,
        runsUsed: _intList(json['runsUsed']),
        origin: _enumByName(TechniqueOrigin.values, json['origin']),
      );

  @override
  List<Object?> get props => [
    instanceId,
    baseFamilyId,
    styleId,
    descriptorIds,
    axisProfile,
    discoveredRunId,
    discoveredRunNumber,
    masteryAtDiscovery,
    usageObservations,
    totalUsage,
    runsUsed,
    origin,
  ];
}

/// SP0b inspiration ancestry, stored verbatim from `TechniqueVariantInspired`
/// — order-preserving, never re-resolved.
class TechniqueInspirationHistory extends _AlmanacValue {
  TechniqueInspirationHistory({
    required this.resultInstanceId,
    required this.runId,
    required this.familyId,
    required List<String> descriptorIds,
    required List<String> inspirerInstanceIds,
  }) : descriptorIds = List<String>.unmodifiable(descriptorIds),
       inspirerInstanceIds = List<String>.unmodifiable(inspirerInstanceIds);

  final String resultInstanceId;
  final String runId;
  final String familyId;
  final List<String> descriptorIds;
  final List<String> inspirerInstanceIds;

  Map<String, dynamic> toJson() => {
    'resultInstanceId': resultInstanceId,
    'runId': runId,
    'familyId': familyId,
    'descriptorIds': descriptorIds.toList(),
    'inspirerInstanceIds': inspirerInstanceIds.toList(),
  };

  factory TechniqueInspirationHistory.fromJson(Map<String, dynamic> json) =>
      TechniqueInspirationHistory(
        resultInstanceId: json['resultInstanceId'] as String,
        runId: json['runId'] as String,
        familyId: json['familyId'] as String,
        descriptorIds: _stringList(json['descriptorIds']),
        inspirerInstanceIds: _stringList(json['inspirerInstanceIds']),
      );

  @override
  List<Object?> get props => [
    resultInstanceId,
    runId,
    familyId,
    descriptorIds,
    inspirerInstanceIds,
  ];
}

/// Canonical cross-run history of one affix. `timesDiscovered` / `timesUsed`
/// / `firstDiscoveredRunId` / `associatedLineageIds` are derived projections.
class AlmanacAffixRecord extends _AlmanacValue {
  AlmanacAffixRecord({
    required this.affixId,
    required List<AffixObservation> discoveryObservations,
    required List<AffixObservation> usageObservations,
    required this.timesDiscovered,
    required this.timesUsed,
    this.firstDiscoveredRunId,
    required List<String> associatedLineageIds,
    required this.snapshot,
  }) : discoveryObservations = List<AffixObservation>.unmodifiable(
         discoveryObservations,
       ),
       usageObservations = List<AffixObservation>.unmodifiable(
         usageObservations,
       ),
       associatedLineageIds = List<String>.unmodifiable(associatedLineageIds);

  final String affixId;
  final List<AffixObservation> discoveryObservations;
  final List<AffixObservation> usageObservations;
  final int timesDiscovered;
  final int timesUsed;
  final String? firstDiscoveredRunId;
  final List<String> associatedLineageIds;
  final AffixSnapshot snapshot;

  Map<String, dynamic> toJson() => {
    'affixId': affixId,
    'discoveryObservations': [
      for (final observation in discoveryObservations) observation.toJson(),
    ],
    'usageObservations': [
      for (final observation in usageObservations) observation.toJson(),
    ],
    'timesDiscovered': timesDiscovered,
    'timesUsed': timesUsed,
    if (firstDiscoveredRunId != null)
      'firstDiscoveredRunId': firstDiscoveredRunId,
    'associatedLineageIds': associatedLineageIds.toList(),
    'snapshot': snapshot.toJson(),
  };

  factory AlmanacAffixRecord.fromJson(Map<String, dynamic> json) =>
      AlmanacAffixRecord(
        affixId: json['affixId'] as String,
        discoveryObservations: List<AffixObservation>.unmodifiable([
          for (final raw in json['discoveryObservations'] as List<dynamic>)
            AffixObservation.fromJson(raw as Map<String, dynamic>),
        ]),
        usageObservations: List<AffixObservation>.unmodifiable([
          for (final raw in json['usageObservations'] as List<dynamic>)
            AffixObservation.fromJson(raw as Map<String, dynamic>),
        ]),
        timesDiscovered: json['timesDiscovered'] as int,
        timesUsed: json['timesUsed'] as int,
        firstDiscoveredRunId: json['firstDiscoveredRunId'] as String?,
        associatedLineageIds: _stringList(json['associatedLineageIds']),
        snapshot: AffixSnapshot.fromJson(
          json['snapshot'] as Map<String, dynamic>,
        ),
      );

  @override
  List<Object?> get props => [
    affixId,
    discoveryObservations,
    usageObservations,
    timesDiscovered,
    timesUsed,
    firstDiscoveredRunId,
    associatedLineageIds,
    snapshot,
  ];
}

/// A first-time discovery of some content, with a labelled snapshot payload.
class AlmanacDiscoveryRecord extends _AlmanacValue {
  const AlmanacDiscoveryRecord({
    required this.discoveryId,
    required this.type,
    required this.contentId,
    this.instanceId,
    required this.runId,
    required this.runNumber,
    required this.timestamp,
    required this.snapshot,
  });

  /// Opaque idempotency token.
  final String discoveryId;
  final AlmanacDiscoveryType type;
  final String contentId;
  final String? instanceId;
  final String runId;
  final int runNumber;
  final DateTime timestamp;
  final DiscoverySnapshot snapshot;

  Map<String, dynamic> toJson() => {
    'discoveryId': discoveryId,
    'type': type.name,
    'contentId': contentId,
    if (instanceId != null) 'instanceId': instanceId,
    'runId': runId,
    'runNumber': runNumber,
    'timestamp': timestamp.toIso8601String(),
    'snapshot': snapshot.toJson(),
  };

  factory AlmanacDiscoveryRecord.fromJson(Map<String, dynamic> json) =>
      AlmanacDiscoveryRecord(
        discoveryId: json['discoveryId'] as String,
        type: _enumByName(AlmanacDiscoveryType.values, json['type']),
        contentId: json['contentId'] as String,
        instanceId: json['instanceId'] as String?,
        runId: json['runId'] as String,
        runNumber: json['runNumber'] as int,
        timestamp: DateTime.parse(json['timestamp'] as String),
        snapshot: DiscoverySnapshot.fromJson(
          json['snapshot'] as Map<String, dynamic>,
        ),
      );

  @override
  List<Object?> get props => [
    discoveryId,
    type,
    contentId,
    instanceId,
    runId,
    runNumber,
    timestamp,
    snapshot,
  ];
}

/// A one-time meta achievement.
class AlmanacMilestoneRecord extends _AlmanacValue {
  const AlmanacMilestoneRecord({
    required this.milestoneId,
    required this.type,
    required this.runId,
    required this.runNumber,
    required this.timestamp,
    this.contextId,
  });

  /// Opaque idempotency token.
  final String milestoneId;
  final MilestoneType type;
  final String runId;
  final int runNumber;
  final DateTime timestamp;
  final String? contextId;

  Map<String, dynamic> toJson() => {
    'milestoneId': milestoneId,
    'type': type.name,
    'runId': runId,
    'runNumber': runNumber,
    'timestamp': timestamp.toIso8601String(),
    if (contextId != null) 'contextId': contextId,
  };

  factory AlmanacMilestoneRecord.fromJson(Map<String, dynamic> json) =>
      AlmanacMilestoneRecord(
        milestoneId: json['milestoneId'] as String,
        type: _enumByName(MilestoneType.values, json['type']),
        runId: json['runId'] as String,
        runNumber: json['runNumber'] as int,
        timestamp: DateTime.parse(json['timestamp'] as String),
        contextId: json['contextId'] as String?,
      );

  @override
  List<Object?> get props => [
    milestoneId,
    type,
    runId,
    runNumber,
    timestamp,
    contextId,
  ];
}

// -----------------------------------------------------------------------------
// Aggregate root (§4.5)
// -----------------------------------------------------------------------------

/// The whole persisted Almanac. [AlmanacState.empty] is the starting point;
/// every list field is copied into an unmodifiable view at construction, so
/// a caller can neither alias nor grow stored history.
class AlmanacState extends _AlmanacValue {
  AlmanacState({
    List<AlmanacRunRecord> runs = const [],
    List<AlmanacBuildRecord> builds = const [],
    List<AlmanacTechniqueRecord> techniques = const [],
    List<TechniqueInspirationHistory> inspirations = const [],
    List<AlmanacAffixRecord> affixes = const [],
    List<AlmanacDiscoveryRecord> discoveries = const [],
    List<AlmanacMilestoneRecord> milestones = const [],
  }) : runs = List<AlmanacRunRecord>.unmodifiable(runs),
       builds = List<AlmanacBuildRecord>.unmodifiable(builds),
       techniques = List<AlmanacTechniqueRecord>.unmodifiable(techniques),
       inspirations = List<TechniqueInspirationHistory>.unmodifiable(
         inspirations,
       ),
       affixes = List<AlmanacAffixRecord>.unmodifiable(affixes),
       discoveries = List<AlmanacDiscoveryRecord>.unmodifiable(discoveries),
       milestones = List<AlmanacMilestoneRecord>.unmodifiable(milestones);

  /// An Almanac with no recorded history.
  factory AlmanacState.empty() => AlmanacState();

  /// The model's on-disk schema version. Bumped only on a breaking change to
  /// the shape below; the persisted serialization envelope (Task 2) reads this
  /// and owns version negotiation — this class does not emit it in `toJson`.
  static const int almanacSchemaVersion = 1;

  final List<AlmanacRunRecord> runs;
  final List<AlmanacBuildRecord> builds;
  final List<AlmanacTechniqueRecord> techniques;
  final List<TechniqueInspirationHistory> inspirations;
  final List<AlmanacAffixRecord> affixes;
  final List<AlmanacDiscoveryRecord> discoveries;
  final List<AlmanacMilestoneRecord> milestones;

  Map<String, dynamic> toJson() => {
    'runs': [for (final record in runs) record.toJson()],
    'builds': [for (final record in builds) record.toJson()],
    'techniques': [for (final record in techniques) record.toJson()],
    'inspirations': [for (final record in inspirations) record.toJson()],
    'affixes': [for (final record in affixes) record.toJson()],
    'discoveries': [for (final record in discoveries) record.toJson()],
    'milestones': [for (final record in milestones) record.toJson()],
  };

  /// The constructor already copies every list into an unmodifiable view.
  factory AlmanacState.fromJson(Map<String, dynamic> json) => AlmanacState(
    runs: [
      for (final raw in json['runs'] as List<dynamic>)
        AlmanacRunRecord.fromJson(raw as Map<String, dynamic>),
    ],
    builds: [
      for (final raw in json['builds'] as List<dynamic>)
        AlmanacBuildRecord.fromJson(raw as Map<String, dynamic>),
    ],
    techniques: [
      for (final raw in json['techniques'] as List<dynamic>)
        AlmanacTechniqueRecord.fromJson(raw as Map<String, dynamic>),
    ],
    inspirations: [
      for (final raw in json['inspirations'] as List<dynamic>)
        TechniqueInspirationHistory.fromJson(raw as Map<String, dynamic>),
    ],
    affixes: [
      for (final raw in json['affixes'] as List<dynamic>)
        AlmanacAffixRecord.fromJson(raw as Map<String, dynamic>),
    ],
    discoveries: [
      for (final raw in json['discoveries'] as List<dynamic>)
        AlmanacDiscoveryRecord.fromJson(raw as Map<String, dynamic>),
    ],
    milestones: [
      for (final raw in json['milestones'] as List<dynamic>)
        AlmanacMilestoneRecord.fromJson(raw as Map<String, dynamic>),
    ],
  );

  @override
  List<Object?> get props => [
    runs,
    builds,
    techniques,
    inspirations,
    affixes,
    discoveries,
    milestones,
  ];
}
