/// Almanac v1 — the identity-keyed, monotonic recorder.
///
/// The recorder is the only writer of canonical Almanac history. It is a pure
/// in-memory value transformer: it imports the domain model and the build-DNA
/// projection and nothing else — no file or JSON library, no randomness, no
/// plugin context, component store, event bus, or repository. Every input is a
/// `String` / `num` / `bool` / `DateTime` or one of the model value objects,
/// and every id is opaque: a relationship is always a stored explicit field,
/// never something recovered by parsing an id.
///
/// Three invariants shape the whole file:
///
/// * **Identity-keyed idempotency (§6).** Every concern has one key. Single
///   keys (`runId`, `instanceId`, `affixId`, `discoveryId`, `milestoneId`,
///   `resultInstanceId`) compare by whole-string equality; composite keys —
///   `(runId, buildId)`, `(runId, usageEventId)`, `(runId, fightId)`,
///   `(affixId, affixEventId)`, `(runId, trainingEventId)` — are *structural*
///   value keys compared field by field. No key is ever built by string
///   concatenation and no key is ever parsed.
/// * **Monotonic completion (§5).** A field is write-once, monotonic
///   ([TechniqueOrigin] only ever advances), an append-only ledger, or a
///   derived projection. A later observation may fill a field that is still
///   unknown; it may never overwrite one that is set — that raises
///   [AlmanacIntegrityException] and the established value is retained.
/// * **Deep immutability (§7).** Every `List` / `Map` crossing into the
///   recorder is copied on ingress, recursively; the recorder never mutates a
///   stored record (it replaces the map entry with a rebuilt instance); and
///   [AlmanacRecorder.state] hands back records whose collections are
///   unmodifiable.
///
/// Insertion order is preserved throughout: Dart map literals are
/// `LinkedHashMap`s, which keep a key's original position across re-assignment,
/// so [AlmanacRecorder.state] materialises its seven lists in first-seen order.
library;

import 'almanac_build_dna.dart';
import 'almanac_models.dart';

/// Raised when a write would contradict established canonical history — a
/// duplicate identity key carrying different contents, or a second value for a
/// write-once field. Fail-loud: the recorder never merges, never recovers, and
/// never silently overwrites.
///
/// Also raised during constructor hydration for a *byte-identical* duplicate
/// identity key, because a well-formed persisted state never holds two records
/// for one identity (§5.1).
class AlmanacIntegrityException implements Exception {
  AlmanacIntegrityException({
    required this.record,
    required this.field,
    required this.established,
    required this.rejected,
  });

  /// The offending record, labelled by its identity —
  /// e.g. `'AlmanacTechniqueRecord(instanceId=ti-1)'`.
  final String record;

  /// The field that would have been overwritten — e.g. `'descriptorIds'`.
  final String field;

  /// The value already recorded, which is kept.
  final Object? established;

  /// The value that was refused.
  final Object? rejected;

  @override
  String toString() =>
      'Almanac integrity: $record.$field is already $established; '
      'refusing to overwrite with $rejected';
}

/// The structural identity of a build snapshot. A Dart record gives value
/// equality and `hashCode` over both fields for free, so a map lookup compares
/// `runId` and `buildId` field by field. Two runs that happen to reuse the same
/// opaque `buildId` string are therefore two distinct records (§6).
typedef _BuildKey = ({String runId, String buildId});

/// The structural identity of a technique-usage observation. A usage ledger
/// spans runs, so the bare `usageEventId` is not enough (§6).
typedef _UsageKey = ({String runId, String usageEventId});

/// The mutable working copy of one run. `fights` and `trainingObservations`
/// are keyed within the run, which *is* the structural `(runId, fightId)` /
/// `(runId, trainingEventId)` pair.
class _RunEntry {
  _RunEntry(this.runId);

  final String runId;
  int? runNumber;
  int? seed;
  String? lineageId;
  String? physiqueId;
  DateTime? startedAt;
  DateTime? completedAt;
  RunOutcome? outcome;
  String? finalBuildId;
  final Map<String, AlmanacFightRecord> fights = <String, AlmanacFightRecord>{};
  final Map<String, TrainingObservation> training =
      <String, TrainingObservation>{};
  final List<String> discoveryIds = <String>[];
}

/// The mutable working copy of one technique instance's cross-run history.
class _TechniqueEntry {
  _TechniqueEntry(this.instanceId);

  final String instanceId;
  String? baseFamilyId;
  String? styleId;
  List<String>? descriptorIds;
  Map<String, num>? axisProfile;
  String? discoveredRunId;
  int? discoveredRunNumber;
  int? masteryAtDiscovery;
  TechniqueOrigin? origin;
  final Map<_UsageKey, TechniqueUsageObservation> usage =
      <_UsageKey, TechniqueUsageObservation>{};
}

/// The mutable working copy of one affix's cross-run history. The two ledgers
/// are independent key domains, each keyed by `affixEventId` within this affix
/// — structurally the `(affixId, affixEventId)` pair.
class _AffixEntry {
  _AffixEntry(this.affixId);

  final String affixId;
  AffixSnapshot? snapshot;
  final Map<String, AffixObservation> discoveries =
      <String, AffixObservation>{};
  final Map<String, AffixObservation> usage = <String, AffixObservation>{};
}

/// Records canonical, cross-run Almanac history.
///
/// Construct it empty for a fresh Almanac, or pass a persisted [AlmanacState]
/// to hydrate (§5.1). Every public `record…` method and the constructor's
/// hydration replay route through the same private insert paths, so a hydrated
/// recorder enforces exactly the same invariants as a fresh one.
///
/// ## Ordering contract across a save boundary
///
/// Within one session the recorder is **order-independent**: an observation
/// naming a subject that has not been declared yet (a use before its discovery,
/// a fight before its `beginRun`) opens a record whose identity fields are
/// still unknown, and the later declaration fills them through the ordinary
/// monotonic path.
///
/// That tolerance does **not** survive persistence. [AlmanacState] and the
/// model records it holds have no representation for "unknown", so
/// [AlmanacRecorder.state] materialises an undeclared field as a sentinel —
/// `''` for `lineageId` / `baseFamilyId`, `0` for `runNumber`,
/// [RunOutcome.abandoned], [TechniqueOrigin.base], a zero-valued
/// [AffixSnapshot], the Unix epoch for `startedAt`. Once that state is saved
/// and hydrated back, the sentinel is indistinguishable from a real value, so
/// the declaration that would have filled it is instead a **contradiction** and
/// raises [AlmanacIntegrityException].
///
/// So: a caller that persists mid-run MUST establish an identity —
/// [beginRun] / [recordTechniqueDiscovered] / [recordAffixDiscovered] — before
/// recording an observation against it, whenever a real identity-fill for that
/// subject may still arrive after a hydrate. The headless bridge already
/// satisfies this (`Minted` precedes `ActionCompleted`; `setRunProfile` →
/// `beginRun` precedes any fight or training observation), and this is the
/// intended v1 contract rather than a bug to work around: widening the model to
/// nullable identity fields, or dropping stub records (they own ledgers that
/// must survive), are both out of scope for v1.
class AlmanacRecorder {
  /// Rebuilds every identity index by **replaying** [initial]'s seven record
  /// lists, in list order, through the private insert paths — never by
  /// retaining one of its collections. Nested collections are copied on the way
  /// in, projections are recomputed from the ledgers (a persisted projection
  /// that disagrees with its ledger is normalised, not rejected), and a
  /// duplicated identity key — identical contents included — throws
  /// [AlmanacIntegrityException].
  AlmanacRecorder([AlmanacState? initial]) {
    // `AlmanacState`'s constructor is not const, so the empty default is built
    // here rather than in the parameter list.
    final AlmanacState source = initial ?? AlmanacState.empty();
    _hydrating = true;
    try {
      for (final AlmanacRunRecord run in source.runs) {
        _upsertRun(
          runId: run.runId,
          runNumber: run.runNumber,
          seed: run.seed,
          lineageId: run.lineageId,
          physiqueId: run.physiqueId,
          startedAt: run.startedAt,
          completedAt: run.completedAt,
          outcome: run.outcome,
          finalBuildId: run.finalBuildId,
        );
        for (final AlmanacFightRecord fight in run.fights) {
          _addFight(fight);
        }
        for (final TrainingObservation observation
            in run.trainingObservations) {
          _addTrainingObservation(observation);
        }
        for (final String discoveryId in run.discoveryIds) {
          _linkDiscoveryToRun(run.runId, discoveryId);
        }
      }
      for (final AlmanacBuildRecord build in source.builds) {
        _upsertBuild(build);
      }
      for (final AlmanacTechniqueRecord technique in source.techniques) {
        _upsertTechnique(
          instanceId: technique.instanceId,
          baseFamilyId: technique.baseFamilyId,
          styleId: technique.styleId,
          descriptorIds: technique.descriptorIds,
          axisProfile: technique.axisProfile,
          discoveredRunId: technique.discoveredRunId,
          discoveredRunNumber: technique.discoveredRunNumber,
          masteryAtDiscovery: technique.masteryAtDiscovery,
          origin: technique.origin,
        );
        for (final TechniqueUsageObservation observation
            in technique.usageObservations) {
          _consumeUsageObservation(observation);
        }
      }
      for (final TechniqueInspirationHistory history in source.inspirations) {
        _upsertInspiration(history);
      }
      for (final AlmanacAffixRecord affix in source.affixes) {
        _upsertAffix(affixId: affix.affixId, snapshot: affix.snapshot);
        for (final AffixObservation observation
            in affix.discoveryObservations) {
          _addAffixObservation(affix.affixId, observation, discovered: true);
        }
        for (final AffixObservation observation in affix.usageObservations) {
          _addAffixObservation(affix.affixId, observation, discovered: false);
        }
      }
      for (final AlmanacDiscoveryRecord discovery in source.discoveries) {
        _upsertDiscovery(discovery);
      }
      for (final AlmanacMilestoneRecord milestone in source.milestones) {
        _upsertMilestone(milestone);
      }
    } finally {
      _hydrating = false;
    }
  }

  /// The stand-in for an unknown `DateTime` on a record built from an
  /// out-of-order observation (a fight recorded before its run began).
  static final DateTime _unknownTime = DateTime.fromMillisecondsSinceEpoch(
    0,
    isUtc: true,
  );

  /// True only while the constructor replays a persisted state. In that mode a
  /// duplicated identity key is corrupt input and throws even when the contents
  /// are byte-identical; during a live `record…` call the same resubmission is
  /// a silent no-op (§5.1 item 4).
  bool _hydrating = false;

  final Map<String, _RunEntry> _runs = <String, _RunEntry>{};
  final Map<_BuildKey, AlmanacBuildRecord> _builds =
      <_BuildKey, AlmanacBuildRecord>{};
  final Map<String, _TechniqueEntry> _techniques = <String, _TechniqueEntry>{};
  final Map<String, TechniqueInspirationHistory> _inspirations =
      <String, TechniqueInspirationHistory>{};
  final Map<String, _AffixEntry> _affixes = <String, _AffixEntry>{};
  final Map<String, AlmanacDiscoveryRecord> _discoveries =
      <String, AlmanacDiscoveryRecord>{};
  final Map<String, AlmanacMilestoneRecord> _milestones =
      <String, AlmanacMilestoneRecord>{};

  // ---------------------------------------------------------------------------
  // Egress
  // ---------------------------------------------------------------------------

  /// The canonical history, materialised from the identity-indexed maps in
  /// first-seen insertion order. Every projection is recomputed here from its
  /// ledger, and every collection the records hold is unmodifiable.
  AlmanacState get state {
    // One pass over the usage ledgers feeds every run's `techniquesUsed`.
    final Map<String, int> usesByRun = <String, int>{};
    for (final _TechniqueEntry technique in _techniques.values) {
      for (final TechniqueUsageObservation observation
          in technique.usage.values) {
        usesByRun[observation.runId] = (usesByRun[observation.runId] ?? 0) + 1;
      }
    }
    return _materialise(usesByRun);
  }

  AlmanacState _materialise(Map<String, int> usesByRun) => AlmanacState(
    runs: [
      for (final _RunEntry entry in _runs.values)
        _runRecord(entry, usesByRun[entry.runId] ?? 0),
    ],
    builds: _builds.values.toList(),
    techniques: [
      for (final _TechniqueEntry entry in _techniques.values)
        _techniqueRecord(entry),
    ],
    inspirations: _inspirations.values.toList(),
    affixes: [
      for (final _AffixEntry entry in _affixes.values) _affixRecord(entry),
    ],
    discoveries: _discoveries.values.toList(),
    milestones: _milestones.values.toList(),
  );

  // ---------------------------------------------------------------------------
  // Runs
  // ---------------------------------------------------------------------------

  /// Opens (or completes) the canonical record for [runId]. Calling it twice
  /// with the same values is a no-op; a conflicting value for an already-set
  /// field throws [AlmanacIntegrityException].
  void beginRun({
    required String runId,
    required int runNumber,
    int? seed,
    required String lineageId,
    required String physiqueId,
    required DateTime startedAt,
  }) => _upsertRun(
    runId: runId,
    runNumber: runNumber,
    seed: seed,
    lineageId: lineageId,
    physiqueId: physiqueId,
    startedAt: startedAt,
  );

  /// Fills in a run's completion fields. Write-once: a second call with
  /// different values throws.
  void completeRun({
    required String runId,
    required DateTime completedAt,
    required RunOutcome outcome,
    String? finalBuildId,
  }) => _upsertRun(
    runId: runId,
    completedAt: completedAt,
    outcome: outcome,
    finalBuildId: finalBuildId,
  );

  /// Appends a fight to `runs[runId].fights`, keyed structurally by
  /// `(runId, fightId)`. Re-delivering the same fight is a no-op; a conflicting
  /// payload at the same key throws.
  void recordFight({
    required String runId,
    required String fightId,
    required int sequence,
    required String name,
    required String enemyId,
    required bool won,
    required num playerHealthAfter,
    required int turnsUsed,
  }) => _addFight(
    AlmanacFightRecord(
      fightId: fightId,
      runId: runId,
      sequence: sequence,
      name: name,
      enemyId: enemyId,
      won: won,
      playerHealthAfter: playerHealthAfter,
      turnsUsed: turnsUsed,
    ),
  );

  void _upsertRun({
    required String runId,
    int? runNumber,
    int? seed,
    String? lineageId,
    String? physiqueId,
    DateTime? startedAt,
    DateTime? completedAt,
    RunOutcome? outcome,
    String? finalBuildId,
  }) {
    final _RunEntry? existing = _runs[runId];
    if (_hydrating && existing != null) {
      _rejectHydrationDuplicate(
        'AlmanacRunRecord(runId=$runId)',
        'runId',
        'the run already hydrated under $runId',
      );
    }
    final _RunEntry entry = existing ?? _RunEntry(runId);
    final String label = 'AlmanacRunRecord(runId=$runId)';

    // Every field is validated before any of them is committed, so a refused
    // write leaves the established record exactly as it was.
    final int? mergedNumber = _fill(
      label,
      'runNumber',
      entry.runNumber,
      runNumber,
    );
    final int? mergedSeed = _fill(label, 'seed', entry.seed, seed);
    final String? mergedLineage = _fill(
      label,
      'lineageId',
      entry.lineageId,
      lineageId,
    );
    final String? mergedPhysique = _fill(
      label,
      'physiqueId',
      entry.physiqueId,
      physiqueId,
    );
    final DateTime? mergedStart = _fill(
      label,
      'startedAt',
      entry.startedAt,
      startedAt,
    );
    final DateTime? mergedEnd = _fill(
      label,
      'completedAt',
      entry.completedAt,
      completedAt,
    );
    final RunOutcome? mergedOutcome = _fill(
      label,
      'outcome',
      entry.outcome,
      outcome,
    );
    final String? mergedFinalBuild = _fill(
      label,
      'finalBuildId',
      entry.finalBuildId,
      finalBuildId,
    );

    entry.runNumber = mergedNumber;
    entry.seed = mergedSeed;
    entry.lineageId = mergedLineage;
    entry.physiqueId = mergedPhysique;
    entry.startedAt = mergedStart;
    entry.completedAt = mergedEnd;
    entry.outcome = mergedOutcome;
    entry.finalBuildId = mergedFinalBuild;
    _runs[runId] = entry;
  }

  void _addFight(AlmanacFightRecord fight) => _putUnique(
    _runEntry(fight.runId).fights,
    fight.fightId,
    fight,
    label: 'AlmanacFightRecord(runId=${fight.runId},fightId=${fight.fightId})',
    identityField: 'fightId',
    json: (AlmanacFightRecord record) => record.toJson(),
  );

  void _addTrainingObservation(TrainingObservation observation) =>
      _appendUnique(
        _runEntry(observation.runId).training,
        observation.trainingEventId,
        observation,
        label:
            'TrainingObservation(runId=${observation.runId},'
            'trainingEventId=${observation.trainingEventId})',
        identityField: 'trainingEventId',
      );

  /// Indexes [discoveryId] under its run. The run entry is created on demand,
  /// exactly as [_addFight] and [_addTrainingObservation] do, so a discovery
  /// observed before its `beginRun` still gets its back-link — design point 8
  /// is unconditional, and nothing re-links later.
  void _linkDiscoveryToRun(String runId, String discoveryId) {
    final _RunEntry entry = _runEntry(runId);
    if (entry.discoveryIds.contains(discoveryId)) return;
    entry.discoveryIds.add(discoveryId);
  }

  _RunEntry _runEntry(String runId) =>
      _runs.putIfAbsent(runId, () => _RunEntry(runId));

  AlmanacRunRecord _runRecord(_RunEntry entry, int techniquesUsed) {
    final List<AlmanacFightRecord> fights = entry.fights.values.toList();
    return AlmanacRunRecord(
      runId: entry.runId,
      runNumber: entry.runNumber ?? 0,
      seed: entry.seed,
      lineageId: entry.lineageId ?? '',
      physiqueId: entry.physiqueId ?? '',
      startedAt: entry.startedAt ?? _unknownTime,
      completedAt: entry.completedAt,
      outcome: entry.outcome ?? RunOutcome.abandoned,
      fights: fights,
      discoveryIds: entry.discoveryIds,
      trainingObservations: entry.training.values.toList(),
      finalBuildId: entry.finalBuildId,
      enemiesDefeated: fights.where((AlmanacFightRecord f) => f.won).length,
      // How many technique-usage observations name this run — a projection
      // over the usage ledgers, never an independently bumped counter.
      techniquesUsed: techniquesUsed,
      trainingSessions: entry.training.length,
    );
  }

  // ---------------------------------------------------------------------------
  // Builds
  // ---------------------------------------------------------------------------

  /// Stores a build snapshot under the structural `(runId, buildId)` key. A
  /// byte-identical resubmission is a silent no-op; a different payload at the
  /// same key throws. [AlmanacBuildRecord.dna] is computed here only when the
  /// caller supplied an empty one.
  void recordBuildSnapshot(AlmanacBuildRecord record) => _upsertBuild(record);

  void _upsertBuild(AlmanacBuildRecord record) {
    final AlmanacBuildRecord candidate = _withDna(record);
    _putUnique(
      _builds,
      (runId: candidate.runId, buildId: candidate.buildId),
      candidate,
      label:
          'AlmanacBuildRecord(runId=${candidate.runId},'
          'buildId=${candidate.buildId})',
      identityField: 'buildId',
      json: (AlmanacBuildRecord value) => value.toJson(),
    );
  }

  /// Back-fills the derived build DNA when the caller left it empty. Idempotent:
  /// a computed DNA always carries at least the lineage and physique tokens, so
  /// a second pass short-circuits.
  AlmanacBuildRecord _withDna(AlmanacBuildRecord record) {
    if (record.dna.tokens.isNotEmpty) return record;
    return AlmanacBuildRecord(
      buildId: record.buildId,
      runId: record.runId,
      phase: record.phase,
      sequence: record.sequence,
      lineageId: record.lineageId,
      physiqueId: record.physiqueId,
      techniques: record.techniques,
      items: record.items,
      affixes: record.affixes,
      tome: record.tome,
      performance: record.performance,
      dna: buildDna(
        lineageId: record.lineageId,
        physiqueId: record.physiqueId,
        techniqueFamilies: [
          for (final TechniqueInstanceSnapshot t in record.techniques)
            t.baseFamilyId,
        ],
        itemIds: [
          for (final ItemInstanceSnapshot i in record.items) i.definitionId,
        ],
        affixCategories: [
          for (final AffixSnapshot a in record.affixes)
            if (a.category != null) a.category!,
        ],
        axisProfiles: [
          for (final TechniqueInstanceSnapshot t in record.techniques)
            t.axisProfile,
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Techniques
  // ---------------------------------------------------------------------------

  /// Records the first sighting of a technique instance. Re-delivering it is a
  /// no-op; a conflicting value for an already-set field throws.
  ///
  /// Folds the technique entry, then emits the `techniqueVariant` discovery row
  /// (§7.1) keyed on the instance — a personalized variant is a distinct
  /// historical discovery and is never collapsed onto its base family. The
  /// technique fold runs first so a conflicting field rejects the write before
  /// any row is emitted. `timestamp` flows into that emitted discovery row;
  /// [AlmanacTechniqueRecord] itself carries no timestamp, and
  /// `discoveredRunId` / `discoveredRunNumber` are the run context the technique
  /// history keeps.
  void recordTechniqueDiscovered({
    required String instanceId,
    required String baseFamilyId,
    String? styleId,
    required List<String> descriptorIds,
    required Map<String, num> axisProfile,
    required TechniqueOrigin origin,
    int? masteryAtDiscovery,
    required String runId,
    required int runNumber,
    required DateTime timestamp,
  }) {
    _upsertTechnique(
      instanceId: instanceId,
      baseFamilyId: baseFamilyId,
      styleId: styleId,
      descriptorIds: descriptorIds,
      axisProfile: axisProfile,
      discoveredRunId: runId,
      discoveredRunNumber: runNumber,
      masteryAtDiscovery: masteryAtDiscovery,
      origin: origin,
    );
    _upsertDiscovery(
      AlmanacDiscoveryRecord(
        discoveryId: _discoveryId(
          AlmanacDiscoveryType.techniqueVariant,
          instanceId,
        ),
        type: AlmanacDiscoveryType.techniqueVariant,
        contentId: instanceId,
        instanceId: instanceId,
        runId: runId,
        runNumber: runNumber,
        timestamp: timestamp,
        snapshot: DiscoverySnapshot(
          label: baseFamilyId,
          values: <String, Object?>{
            'baseFamilyId': baseFamilyId,
            if (styleId != null) 'styleId': styleId,
            'descriptorIds': [...descriptorIds],
            'axisProfile': {...axisProfile},
            'origin': origin.name,
          },
        ),
      ),
    );
  }

  /// Appends one technique use, keyed structurally by
  /// `(runId, usageEventId)` — the same opaque `usageEventId` under two runs is
  /// two observations. Re-delivering the same pair counts once.
  void recordTechniqueUsed(TechniqueUsageObservation observation) =>
      _consumeUsageObservation(observation);

  /// Stores SP0b ancestry verbatim and advances the resulting instance's
  /// [TechniqueOrigin] to `inspired`. Ancestry order is preserved; nothing is
  /// re-resolved and no RNG is consulted.
  void recordTechniqueInspired({
    required String resultInstanceId,
    required String runId,
    required String familyId,
    required List<String> descriptorIds,
    required List<String> inspirerInstanceIds,
  }) {
    // Merge the technique first (pure, throws on contradiction) so a rejected
    // write leaves neither map touched.
    final _TechniqueEntry merged = _mergeTechnique(
      instanceId: resultInstanceId,
      baseFamilyId: familyId,
      descriptorIds: descriptorIds,
      origin: TechniqueOrigin.inspired,
    );
    _upsertInspiration(
      TechniqueInspirationHistory(
        resultInstanceId: resultInstanceId,
        runId: runId,
        familyId: familyId,
        descriptorIds: descriptorIds,
        inspirerInstanceIds: inspirerInstanceIds,
      ),
    );
    _techniques[resultInstanceId] = merged;
  }

  void _upsertTechnique({
    required String instanceId,
    String? baseFamilyId,
    String? styleId,
    List<String>? descriptorIds,
    Map<String, num>? axisProfile,
    String? discoveredRunId,
    int? discoveredRunNumber,
    int? masteryAtDiscovery,
    TechniqueOrigin? origin,
  }) {
    if (_hydrating && _techniques.containsKey(instanceId)) {
      _rejectHydrationDuplicate(
        'AlmanacTechniqueRecord(instanceId=$instanceId)',
        'instanceId',
        'the technique already hydrated under $instanceId',
      );
    }
    _techniques[instanceId] = _mergeTechnique(
      instanceId: instanceId,
      baseFamilyId: baseFamilyId,
      styleId: styleId,
      descriptorIds: descriptorIds,
      axisProfile: axisProfile,
      discoveredRunId: discoveredRunId,
      discoveredRunNumber: discoveredRunNumber,
      masteryAtDiscovery: masteryAtDiscovery,
      origin: origin,
    );
  }

  /// Folds the incoming fields into a **fresh** entry for [instanceId] — the
  /// established one is never mutated, so a throw anywhere in the merge leaves
  /// the recorder untouched and the caller decides when to commit. The
  /// append-only usage ledger is carried across in order.
  _TechniqueEntry _mergeTechnique({
    required String instanceId,
    String? baseFamilyId,
    String? styleId,
    List<String>? descriptorIds,
    Map<String, num>? axisProfile,
    String? discoveredRunId,
    int? discoveredRunNumber,
    int? masteryAtDiscovery,
    TechniqueOrigin? origin,
  }) {
    final _TechniqueEntry? entry = _techniques[instanceId];
    final String label = 'AlmanacTechniqueRecord(instanceId=$instanceId)';

    final _TechniqueEntry merged = _TechniqueEntry(instanceId);
    merged.baseFamilyId = _fill(
      label,
      'baseFamilyId',
      entry?.baseFamilyId,
      baseFamilyId,
    );
    merged.styleId = _fill(label, 'styleId', entry?.styleId, styleId);
    merged.descriptorIds = _fill(
      label,
      'descriptorIds',
      entry?.descriptorIds,
      // §7 ingress: the caller's list is copied before it is ever stored.
      descriptorIds == null ? null : List<String>.unmodifiable(descriptorIds),
    );
    merged.axisProfile = _fill(
      label,
      'axisProfile',
      entry?.axisProfile,
      axisProfile == null ? null : Map<String, num>.unmodifiable(axisProfile),
    );
    merged.discoveredRunId = _fill(
      label,
      'discoveredRunId',
      entry?.discoveredRunId,
      discoveredRunId,
    );
    merged.discoveredRunNumber = _fill(
      label,
      'discoveredRunNumber',
      entry?.discoveredRunNumber,
      discoveredRunNumber,
    );
    merged.masteryAtDiscovery = _fill(
      label,
      'masteryAtDiscovery',
      entry?.masteryAtDiscovery,
      masteryAtDiscovery,
    );
    merged.origin = _advanceOrigin(entry?.origin, origin);
    if (entry != null) merged.usage.addAll(entry.usage);
    return merged;
  }

  /// [TechniqueOrigin] is monotonic, never contradictory: it only ever advances
  /// `base` → `evolved` → `inspired`, so `base` arriving after `inspired` is
  /// ignored rather than rejected.
  TechniqueOrigin? _advanceOrigin(
    TechniqueOrigin? established,
    TechniqueOrigin? incoming,
  ) {
    if (incoming == null) return established;
    if (established == null) return incoming;
    return incoming.index > established.index ? incoming : established;
  }

  void _consumeUsageObservation(TechniqueUsageObservation observation) {
    final _TechniqueEntry entry = _techniques.putIfAbsent(
      observation.instanceId,
      () => _TechniqueEntry(observation.instanceId),
    );
    _appendUnique(
      entry.usage,
      (runId: observation.runId, usageEventId: observation.usageEventId),
      observation,
      label:
          'TechniqueUsageObservation(runId=${observation.runId},'
          'usageEventId=${observation.usageEventId})',
      identityField: 'usageEventId',
    );
  }

  void _upsertInspiration(TechniqueInspirationHistory history) => _putUnique(
    _inspirations,
    history.resultInstanceId,
    history,
    label:
        'TechniqueInspirationHistory('
        'resultInstanceId=${history.resultInstanceId})',
    identityField: 'resultInstanceId',
    json: (TechniqueInspirationHistory value) => value.toJson(),
  );

  AlmanacTechniqueRecord _techniqueRecord(_TechniqueEntry entry) {
    final List<TechniqueUsageObservation> observations =
        entry.usage.values.toList();
    final List<int> runsUsed = <int>[];
    for (final TechniqueUsageObservation observation in observations) {
      if (!runsUsed.contains(observation.runNumber)) {
        runsUsed.add(observation.runNumber);
      }
    }
    return AlmanacTechniqueRecord(
      instanceId: entry.instanceId,
      baseFamilyId: entry.baseFamilyId ?? '',
      styleId: entry.styleId,
      descriptorIds: entry.descriptorIds ?? const <String>[],
      axisProfile: entry.axisProfile ?? const <String, num>{},
      discoveredRunId: entry.discoveredRunId,
      discoveredRunNumber: entry.discoveredRunNumber,
      masteryAtDiscovery: entry.masteryAtDiscovery,
      usageObservations: observations,
      totalUsage: observations.length,
      runsUsed: runsUsed,
      origin: entry.origin ?? TechniqueOrigin.base,
    );
  }

  // ---------------------------------------------------------------------------
  // Affixes
  // ---------------------------------------------------------------------------

  /// Records one affix discovery, keyed structurally by
  /// `(affixId, affixEventId)`. [timestamp] is accepted for symmetry with the
  /// other discovery entry points; [AlmanacAffixRecord] keeps no timestamp of
  /// its own — the observation ledgers carry the run context.
  void recordAffixDiscovered({
    required String affixId,
    required AffixObservation observation,
    required AffixSnapshot snapshot,
    required DateTime timestamp,
  }) {
    _upsertAffix(affixId: affixId, snapshot: snapshot);
    _addAffixObservation(affixId, observation, discovered: true);
  }

  /// Records one affix use, keyed structurally by `(affixId, affixEventId)`.
  void recordAffixUsed({
    required String affixId,
    required AffixObservation observation,
  }) {
    _upsertAffix(affixId: affixId);
    _addAffixObservation(affixId, observation, discovered: false);
  }

  void _upsertAffix({required String affixId, AffixSnapshot? snapshot}) {
    final _AffixEntry? existing = _affixes[affixId];
    if (_hydrating && existing != null) {
      _rejectHydrationDuplicate(
        'AlmanacAffixRecord(affixId=$affixId)',
        'affixId',
        'the affix already hydrated under $affixId',
      );
    }
    final _AffixEntry entry = existing ?? _AffixEntry(affixId);
    entry.snapshot = _fill(
      'AlmanacAffixRecord(affixId=$affixId)',
      'snapshot',
      entry.snapshot,
      snapshot,
    );
    _affixes[affixId] = entry;
  }

  void _addAffixObservation(
    String affixId,
    AffixObservation observation, {
    required bool discovered,
  }) {
    final _AffixEntry entry = _affixes.putIfAbsent(
      affixId,
      () => _AffixEntry(affixId),
    );
    _appendUnique(
      discovered ? entry.discoveries : entry.usage,
      observation.affixEventId,
      observation,
      label:
          'AffixObservation(affixId=$affixId,'
          'affixEventId=${observation.affixEventId})',
      identityField: 'affixEventId',
    );
  }

  AlmanacAffixRecord _affixRecord(_AffixEntry entry) {
    final List<AffixObservation> discoveries =
        entry.discoveries.values.toList();
    final List<AffixObservation> usage = entry.usage.values.toList();
    final List<String> lineageIds = <String>[];
    for (final AffixObservation observation in [...discoveries, ...usage]) {
      final String? lineageId = observation.lineageId;
      if (lineageId != null && !lineageIds.contains(lineageId)) {
        lineageIds.add(lineageId);
      }
    }
    return AlmanacAffixRecord(
      affixId: entry.affixId,
      discoveryObservations: discoveries,
      usageObservations: usage,
      timesDiscovered: discoveries.length,
      timesUsed: usage.length,
      // §5.6/§7.1: the discovery observation with the smallest `runNumber`
      // (not merely the first delivered). `reduce` keeps `a` on a tie, so the
      // earlier-inserted observation wins a `runNumber` draw.
      firstDiscoveredRunId:
          discoveries.isEmpty
              ? null
              : discoveries
                  .reduce((a, b) => b.runNumber < a.runNumber ? b : a)
                  .runId,
      associatedLineageIds: lineageIds,
      snapshot:
          entry.snapshot ??
          AffixSnapshot(affixId: entry.affixId, stat: '', value: 0),
    );
  }

  // ---------------------------------------------------------------------------
  // Training, discoveries, milestones
  // ---------------------------------------------------------------------------

  /// Appends one training session to `runs[runId].trainingObservations`, keyed
  /// structurally by `(runId, trainingEventId)`.
  void recordTrainingSession(TrainingObservation observation) =>
      _addTrainingObservation(observation);

  /// Records a first-seen discovery. The first write is canonical: a later
  /// encounter of the same [AlmanacDiscoveryRecord.discoveryId] adds nothing.
  void recordDiscovery(AlmanacDiscoveryRecord record) =>
      _upsertDiscovery(record);

  /// Records the first sighting of an item definition. The recorder forms the
  /// `discoveryId` from the type and the content id; the explicit `type` /
  /// `contentId` / `instanceId` / `runId` fields stay authoritative and are
  /// never parsed back out of the id.
  void recordItemDiscovered({
    required String definitionId,
    String? instanceId,
    required String runId,
    required int runNumber,
    required DateTime timestamp,
    required DiscoverySnapshot snapshot,
  }) => recordDiscovery(
    AlmanacDiscoveryRecord(
      discoveryId: _discoveryId(AlmanacDiscoveryType.item, definitionId),
      type: AlmanacDiscoveryType.item,
      contentId: definitionId,
      instanceId: instanceId,
      runId: runId,
      runNumber: runNumber,
      timestamp: timestamp,
      snapshot: snapshot,
    ),
  );

  /// §6: a re-encounter of an already-discovered thing adds nothing — the first
  /// sighting is canonical and a later run is not a conflict. The recursive
  /// snapshot copy lives here rather than in [recordDiscovery] so that
  /// hydration gets it too (§5.1 item 1), mirroring where [_withDna] sits.
  void _upsertDiscovery(AlmanacDiscoveryRecord record) {
    final AlmanacDiscoveryRecord candidate = AlmanacDiscoveryRecord(
      discoveryId: record.discoveryId,
      type: record.type,
      contentId: record.contentId,
      instanceId: record.instanceId,
      runId: record.runId,
      runNumber: record.runNumber,
      timestamp: record.timestamp,
      snapshot: _copySnapshot(record.snapshot),
    );
    final bool stored = _appendUnique(
      _discoveries,
      candidate.discoveryId,
      candidate,
      label: 'AlmanacDiscoveryRecord(discoveryId=${candidate.discoveryId})',
      identityField: 'discoveryId',
    );
    if (stored) _linkDiscoveryToRun(candidate.runId, candidate.discoveryId);
  }

  /// Records a one-time meta achievement under `type.name` (plus `:contextId`
  /// when scoped). The `type` and `contextId` are stored as explicit fields;
  /// nothing ever parses the id back apart.
  void recordMilestone({
    required MilestoneType type,
    required String runId,
    required int runNumber,
    required DateTime timestamp,
    String? contextId,
  }) => _upsertMilestone(
    AlmanacMilestoneRecord(
      milestoneId: _milestoneId(type, contextId),
      type: type,
      runId: runId,
      runNumber: runNumber,
      timestamp: timestamp,
      contextId: contextId,
    ),
  );

  /// Mints whichever of the standard "first X" milestones this run qualifies
  /// for and that have not been earned yet. Each is idempotent by its own
  /// milestone id, so a later qualifying run leaves the established record
  /// untouched.
  void evaluateStandardMilestones({
    required String runId,
    required int runNumber,
    required RunOutcome outcome,
    required String lineageId,
    String? finalBuildId,
    required DateTime timestamp,
  }) {
    void mint(MilestoneType type, {String? contextId}) => recordMilestone(
      type: type,
      runId: runId,
      runNumber: runNumber,
      timestamp: timestamp,
      contextId: contextId,
    );

    final bool won = outcome == RunOutcome.won;
    // Evaluated in MilestoneType declaration order, so the seven standard
    // milestones appear in a stable order in `state.milestones`.
    mint(MilestoneType.firstRun);
    if (won) mint(MilestoneType.firstVictory);
    // §7.3: "first technique record ever." Defined on the technique ledger
    // itself, not on row emission (Fix 1 makes the two equivalent in a real
    // run, but this is the spec's stated definition).
    if (_techniques.isNotEmpty) mint(MilestoneType.firstTechniqueVariant);
    if (_inspirations.isNotEmpty) mint(MilestoneType.firstInspiredTechnique);
    if (_affixes.isNotEmpty) mint(MilestoneType.firstAffix);
    if (won) mint(MilestoneType.firstWinWithLineage, contextId: lineageId);
    if (won && finalBuildId != null) {
      mint(MilestoneType.firstSuccessfulBuild, contextId: finalBuildId);
    }
  }

  /// §6: the first qualifying occurrence is canonical; later ones are no-ops.
  void _upsertMilestone(AlmanacMilestoneRecord record) => _appendUnique(
    _milestones,
    record.milestoneId,
    record,
    label: 'AlmanacMilestoneRecord(milestoneId=${record.milestoneId})',
    identityField: 'milestoneId',
  );

  /// `type.name`, scoped with `:contextId` when the milestone is per-lineage or
  /// per-build. Formed here, never parsed back.
  String _milestoneId(MilestoneType type, String? contextId) =>
      contextId == null ? type.name : '${type.name}:$contextId';

  /// `type.name:contentId`. Formed here, never parsed back.
  String _discoveryId(AlmanacDiscoveryType type, String contentId) =>
      '${type.name}:$contentId';

  // ---------------------------------------------------------------------------
  // Shared helpers
  // ---------------------------------------------------------------------------

  /// Corrupt persisted input: the hydrated state held two records under one
  /// identity key. Byte-identical counts, because a well-formed `stateToJson`
  /// never emits a duplicate (§5.1 item 4). The one place that phrasing lives.
  Never _rejectHydrationDuplicate(
    String record,
    String field,
    Object? established,
  ) =>
      throw AlmanacIntegrityException(
        record: record,
        field: field,
        established: established,
        rejected: 'a second record under the same $field',
      );

  /// Store-if-absent for a write-once record: absent → store; a byte-identical
  /// resubmission → silent no-op live, corrupt input while hydrating; a
  /// different payload at the same key → refused, naming the first differing
  /// field. The one implementation behind `_addFight`, `_upsertBuild` and
  /// `_upsertInspiration` — and the reason hydration and the public `record…`
  /// methods cannot drift apart.
  void _putUnique<K, T extends Object>(
    Map<K, T> map,
    K key,
    T value, {
    required String label,
    required String identityField,
    required Map<String, dynamic> Function(T value) json,
  }) {
    final T? existing = map[key];
    if (existing == null) {
      map[key] = value;
      return;
    }
    if (existing == value) {
      if (_hydrating) {
        _rejectHydrationDuplicate(label, identityField, existing);
      }
      return;
    }
    throw AlmanacIntegrityException(
      record: label,
      field: _firstDifferingField(json(existing), json(value)),
      established: existing,
      rejected: value,
    );
  }

  /// Append-if-absent for a key whose repeats carry no contradiction — the
  /// observation ledgers (§6: "append only if that pair absent") plus
  /// discoveries and milestones, whose first write is canonical and whose later
  /// encounters add nothing. Returns whether [value] was stored. A repeat is a
  /// silent no-op live and corrupt input while hydrating.
  bool _appendUnique<K, T extends Object>(
    Map<K, T> map,
    K key,
    T value, {
    required String label,
    required String identityField,
  }) {
    final T? existing = map[key];
    if (existing != null) {
      if (_hydrating) {
        _rejectHydrationDuplicate(label, identityField, existing);
      }
      return false;
    }
    map[key] = value;
    return true;
  }

  /// Monotonic completion for a single field: an absent [incoming] leaves the
  /// established value alone, an unknown established value is filled, an equal
  /// value is a no-op, and a different value is refused.
  T? _fill<T>(String record, String field, T? established, T? incoming) {
    if (incoming == null) return established;
    if (established == null) return incoming;
    if (_valueEquals(established, incoming)) return established;
    throw AlmanacIntegrityException(
      record: record,
      field: field,
      established: established,
      rejected: incoming,
    );
  }

  /// The first JSON field on which two records of the same type differ, used to
  /// name the offending field on an [AlmanacIntegrityException]. Both maps come
  /// from `toJson`, so key order is the declared field order.
  String _firstDifferingField(
    Map<String, dynamic> established,
    Map<String, dynamic> rejected,
  ) {
    for (final String key in <String>{...established.keys, ...rejected.keys}) {
      if (!_valueEquals(established[key], rejected[key])) return key;
    }
    return 'record';
  }

  /// Structural equality over JSON-like values, so a rebuilt collection with
  /// equal contents is recognised as equal. Model value objects carry their own
  /// deep `==`.
  bool _valueEquals(Object? a, Object? b) {
    if (identical(a, b)) return true;
    if (a is List<Object?> && b is List<Object?>) {
      if (a.length != b.length) return false;
      for (int i = 0; i < a.length; i++) {
        if (!_valueEquals(a[i], b[i])) return false;
      }
      return true;
    }
    if (a is Map<Object?, Object?> && b is Map<Object?, Object?>) {
      if (a.length != b.length) return false;
      for (final Object? key in a.keys) {
        if (!b.containsKey(key) || !_valueEquals(a[key], b[key])) return false;
      }
      return true;
    }
    return a == b;
  }

  /// §7 ingress: [DiscoverySnapshot] freezes only the top level of its payload,
  /// so the recorder copies anything nested inside it before storing.
  DiscoverySnapshot _copySnapshot(DiscoverySnapshot snapshot) =>
      DiscoverySnapshot(
        label: snapshot.label,
        values: <String, Object?>{
          for (final MapEntry<String, Object?> entry in snapshot.values.entries)
            entry.key: _copyValue(entry.value),
        },
      );

  Object? _copyValue(Object? value) {
    if (value is List<Object?>) {
      return List<Object?>.unmodifiable([
        for (final Object? element in value) _copyValue(element),
      ]);
    }
    if (value is Map<Object?, Object?>) {
      return Map<String, Object?>.unmodifiable(<String, Object?>{
        for (final MapEntry<Object?, Object?> entry in value.entries)
          _jsonKey(entry.key): _copyValue(entry.value),
      });
    }
    return value;
  }

  /// [DiscoverySnapshot.values] is JSON-safe by contract, so every nested map
  /// key is a `String`. Says so out loud rather than surfacing a bare
  /// `TypeError` from a malformed payload.
  String _jsonKey(Object? key) {
    if (key is String) return key;
    throw ArgumentError.value(
      key,
      'key',
      'non-string key in DiscoverySnapshot.values',
    );
  }
}
