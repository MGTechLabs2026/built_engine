import 'package:build_engine/almanac.dart';
import 'package:build_engine/build_engine.dart';
import 'package:build_engine/combat_plugin.dart';
import 'package:build_engine/item_plugin.dart';
import 'package:build_engine/physique_plugin.dart';
import 'package:build_engine/technique_plugin.dart';

import 'run_content.dart';
import 'run_events.dart';

/// The **only** in-repo file that imports both a gameplay plugin and the
/// Almanac — by design, and architecturally sanctioned: it lives in the
/// game composition root, alongside `runGame`, not in the Almanac module.
///
/// A passive composition adapter. It subscribes to composition / domain
/// events on the run's own [EventBus], translates each into a completed
/// value observation, and hands it to an [AlmanacRecorder]. It never
/// mutates gameplay state, never calls RNG, never touches a repository —
/// the caller owns `repo.save(recorder.state)` after `runGame` returns.
///
/// Everything it holds is **run-local instance state**: a fresh bridge is
/// built per `runGame` call and [detach]ed before that call returns, so
/// no observation from one run can leak into another. There is no
/// `static` / library-scope mutable state anywhere in this file, and no
/// adapter-minted id string (`'$runId:e$n'`, `_buildId(...)`, …) is ever
/// parsed back apart — downstream every id is an opaque whole-string token
/// and every relationship is a stored explicit field.
class HeadlessGameAlmanacBridge {
  HeadlessGameAlmanacBridge(
    this._recorder, {
    required this.runId,
    required this.runNumber,
    this.seed,
  });

  final AlmanacRecorder _recorder;

  /// Caller-supplied opaque token — never `'run_$seed'`.
  final String runId;

  /// Caller-supplied.
  final int runNumber;

  /// Replay metadata only; keys nothing.
  final int? seed;

  // ---- run-local temporary context (legitimate for a composition adapter) --
  int _encounterSeq = 0;
  int _encounterTurns = 0;
  bool _encounterActive = false;
  final Map<BuildPhase, int> _buildSeq = <BuildPhase, int>{};
  int _usageSeq = 0;
  int _trainingSeq = 0;
  String? _lineageId;
  String? _physiqueId;
  String? _finalBuildId;
  bool _begun = false;
  bool _disposed = false;

  late final PluginContext _context;
  late final EntityId _character;
  final List<EventSubscription> _subs = <EventSubscription>[];

  /// Closed subject → (discovery type, content id) roster, built once in
  /// [attach] from the harness's own content ids (`run_content.dart`) via
  /// the Item / Technique plugins' **forward** subject helpers. A
  /// `SubjectDiscovered` whose subject is absent from this map is ignored
  /// (outside the harness roster). No subject string is ever parsed.
  late final Map<String, ({AlmanacDiscoveryType type, String contentId})>
  _subjectLookup;

  /// Binds the context the snapshot builders need and registers exactly
  /// one subscription per source event. Every [EventSubscription] is
  /// stored in `_subs` and owned by THIS bridge instance. Idempotent: a
  /// second call, or a call after [detach], is a no-op.
  void attach(EventBus events, PluginContext context, EntityId character) {
    if (_subs.isNotEmpty || _disposed) return;
    _context = context;
    _character = character;
    _subjectLookup = <String, ({AlmanacDiscoveryType type, String contentId})>{
      for (final id in <String>[
        ...RunStartingKit.itemIds,
        ...rewardPoolItemIds,
      ])
        itemSubject(id): (type: AlmanacDiscoveryType.item, contentId: id),
      for (final id in <String>[
        ...rewardPoolTechniqueIds,
        ...TechniqueIds.bases,
      ])
        techniqueSubject(id): (
          type: AlmanacDiscoveryType.technique,
          contentId: id,
        ),
    };
    _subs.add(events.subscribe<PhysiqueAssigned>(_onPhysiqueAssigned));
    _subs.add(events.subscribe<TechniqueVariantMinted>(_onMinted));
    _subs.add(events.subscribe<TechniqueVariantInspired>(_onInspired));
    _subs.add(events.subscribe<SubjectDiscovered>(_onSubjectDiscovered));
    _subs.add(events.subscribe<ActionCompleted>(_onActionCompleted));
    _subs.add(events.subscribe<EncounterStarted>(_onEncounterStarted));
    _subs.add(events.subscribe<EncounterResolved>(_onEncounterResolved));
    _subs.add(events.subscribe<TrainingResultRecorded>(_onTrainingResult));
    _subs.add(events.subscribe<RunEnded>(_onRunEnded));
    // NOT observed: RunStarted (pre-profile telemetry), RewardSelected
    // (a decision published before the Tome mutation), TomeChanged (the
    // `initial` snapshot is a composition callback, not an event).
  }

  /// Supplies the two facts no domain event carries. Physique also
  /// arrives via `PhysiqueAssigned`; it is re-passed here for safety.
  /// Lineage / tradition / style has no domain event — `runGame` holds it
  /// as a local and forwards it. `beginRun` fires once both are known.
  void setRunProfile({required String lineageId, required String physiqueId}) {
    if (_disposed) return;
    _lineageId = lineageId;
    _physiqueId ??= physiqueId;
    _maybeBeginRun();
  }

  /// A state-boundary callback the composition layer invokes AFTER a
  /// gameplay operation has fully applied its effects (`grantReward(...)`
  /// returned, the whole training branch returned, the starting kit was
  /// placed). Only here does the bridge inspect live Tome / component
  /// state and build a snapshot. No-op before `beginRun` or after
  /// [detach].
  void recordBuildPhase(BuildPhase phase) {
    if (!_begun || _disposed) return;
    _recorder.recordBuildSnapshot(
      _buildSnapshot(phase, sequence: _nextBuildSeq(phase)),
    );
  }

  /// Cancels every subscription this bridge owns and marks it dead. Safe
  /// to call more than once; a later `EventBus` publish reaches none of
  /// this bridge's handlers afterward.
  void detach() {
    if (_disposed) return;
    _disposed = true;
    for (final EventSubscription s in _subs) {
      s.cancel();
    }
    _subs.clear();
  }

  // ---------------------------------------------------------------------------
  // Handlers — every one first-lines `if (_disposed) return;`.
  // ---------------------------------------------------------------------------

  void _onPhysiqueAssigned(PhysiqueAssigned e) {
    if (_disposed || e.character != _character) return;
    _physiqueId ??= e.physiqueId;
    _maybeBeginRun();
  }

  void _onMinted(TechniqueVariantMinted e) {
    if (_disposed) return;
    final TechniqueVariant v =
        _context.components.get<TechniqueVariant>(e.instanceId)!;
    _recorder.recordTechniqueDiscovered(
      instanceId: e.instanceId.value.toString(),
      baseFamilyId: e.baseFamilyId,
      styleId: v.styleId,
      descriptorIds: v.descriptorIds.toList(),
      axisProfile: Map<String, num>.of(v.axisProfile),
      origin: TechniqueOrigin.base,
      masteryAtDiscovery: _masteryLevelOf(e.instanceId),
      runId: runId,
      runNumber: runNumber,
      timestamp: DateTime.now(),
    );
  }

  void _onInspired(TechniqueVariantInspired e) {
    if (_disposed) return;
    _recorder.recordTechniqueInspired(
      resultInstanceId: e.instanceId.value.toString(),
      runId: runId,
      familyId: e.familyId,
      descriptorIds: e.descriptorIds.toList(),
      inspirerInstanceIds: <String>[
        for (final EntityId i in e.inspirerInstanceIds) i.value.toString(),
      ],
    );
  }

  void _onSubjectDiscovered(SubjectDiscovered e) {
    if (_disposed) return;
    final ({AlmanacDiscoveryType type, String contentId})? hit =
        _subjectLookup[e.subject];
    if (hit == null) return;
    _recorder.recordDiscovery(
      AlmanacDiscoveryRecord(
        discoveryId: _discoveryId(hit.type, hit.contentId),
        type: hit.type,
        contentId: hit.contentId,
        runId: runId,
        runNumber: runNumber,
        timestamp: DateTime.now(),
        snapshot: DiscoverySnapshot(
          label: hit.type.name,
          values: const <String, Object?>{},
        ),
      ),
    );
  }

  void _onActionCompleted(ActionCompleted e) {
    if (_disposed) return;
    // (1) turnsUsed counts EVERY completed action while a fight is live,
    //     either side, regardless of source.
    if (_encounterActive) _encounterTurns++;
    // (2) INDEPENDENTLY, the exact combat_stage.dart:104-107 predicate.
    final BuildComponentRef? ref = e.action.sourceRef;
    if (ref != null &&
        ref.referenceType == techniqueReferenceType &&
        ref.instanceEntityId != null) {
      _recorder.recordTechniqueUsed(
        TechniqueUsageObservation(
          usageEventId: '$runId:u${_usageSeq++}',
          runId: runId,
          runNumber: runNumber,
          instanceId: ref.instanceEntityId!.value.toString(),
        ),
      );
    }
  }

  void _onEncounterStarted(EncounterStarted e) {
    if (_disposed) return;
    _encounterActive = true;
    _encounterTurns = 0;
    _encounterSeq++;
  }

  void _onEncounterResolved(EncounterResolved e) {
    if (_disposed) return;
    _recorder.recordFight(
      runId: runId,
      fightId: '$runId:e${_encounterSeq - 1}',
      sequence: _encounterSeq - 1,
      name: e.name,
      enemyId: e.enemyId,
      won: e.won,
      playerHealthAfter: e.playerHealthAfter,
      turnsUsed: _encounterTurns,
    );
    _encounterActive = false;
  }

  void _onTrainingResult(TrainingResultRecorded e) {
    if (_disposed) return;
    // Ledger only — NOT a snapshot boundary. The mutations that follow
    // this event inside `runTraining`, plus the training branch's own
    // `restoreHealth` + `manageTome()`, are not applied yet; the
    // `postTraining` snapshot is taken by
    // `recordBuildPhase(BuildPhase.postTraining)` after that `manageTome()`.
    _recorder.recordTrainingSession(
      TrainingObservation(
        trainingEventId: '$runId:t${_trainingSeq++}',
        runId: runId,
        runNumber: runNumber,
      ),
    );
  }

  void _onRunEnded(RunEnded e) {
    if (_disposed) return;
    // A driver that publishes `RunEnded` without ever supplying a run profile
    // (no `setRunProfile` / `PhysiqueAssigned`) never began a run — clean
    // no-op rather than a null-check throw on `_lineageId!`.
    if (!_begun) return;
    final DateTime now = DateTime.now();
    final RunOutcome outcome = e.won ? RunOutcome.won : RunOutcome.lost;
    final AlmanacBuildRecord s = _buildSnapshot(
      BuildPhase.finalBuild,
      sequence: _nextBuildSeq(BuildPhase.finalBuild),
    );
    _finalBuildId = s.buildId;
    _recorder.recordBuildSnapshot(s);
    _recorder.completeRun(
      runId: runId,
      completedAt: now,
      outcome: outcome,
      finalBuildId: _finalBuildId,
    );
    _recorder.evaluateStandardMilestones(
      runId: runId,
      runNumber: runNumber,
      outcome: outcome,
      lineageId: _lineageId!,
      finalBuildId: _finalBuildId,
      timestamp: now,
    );
  }

  // ---------------------------------------------------------------------------
  // Internals
  // ---------------------------------------------------------------------------

  void _maybeBeginRun() {
    if (_begun || _disposed || _lineageId == null || _physiqueId == null) {
      return;
    }
    _begun = true;
    _recorder.beginRun(
      runId: runId,
      runNumber: runNumber,
      seed: seed,
      lineageId: _lineageId!,
      physiqueId: _physiqueId!,
      startedAt: DateTime.now(),
    );
  }

  /// Current per-phase counter, then bump it: the first snapshot of each
  /// phase in a run is `sequence 0`.
  int _nextBuildSeq(BuildPhase phase) =>
      _buildSeq.update(phase, (int n) => n + 1, ifAbsent: () => 0);

  /// The bridge's deterministic per-run scheme. An opaque token
  /// downstream: the record also carries `runId` / `phase` / `sequence`
  /// as explicit fields, and those — never this string — are how a
  /// relationship is read.
  String _buildId(BuildPhase phase, int sequence) =>
      '$runId:${phase.name}:$sequence';

  /// Stable dedup token for a discovery of [contentId]. Minted here from
  /// the type name and the content id; never parsed back apart.
  String _discoveryId(AlmanacDiscoveryType type, String contentId) =>
      '${type.name}:$contentId';

  int? _masteryLevelOf(EntityId instanceId) => _context.mastery.levelOf(
    _character,
    techniqueInstanceSubject(instanceId),
  );

  AlmanacBuildRecord _buildSnapshot(BuildPhase phase, {required int sequence}) {
    final List<TomePlacement> placements = _context.tome.inspect(_character);
    final List<TomeSlotSnapshot> slots = <TomeSlotSnapshot>[];
    final List<TechniqueInstanceSnapshot> techniques =
        <TechniqueInstanceSnapshot>[];
    final List<ItemInstanceSnapshot> items = <ItemInstanceSnapshot>[];

    for (final TomePlacement p in placements) {
      final BuildComponentRef ref = p.buildComponentRef;
      final bool isTechnique = ref.referenceType == techniqueReferenceType;
      final bool isItem = ref.referenceType == itemReferenceType;
      slots.add(
        TomeSlotSnapshot(
          slotId: p.slot.id,
          occupantKind:
              isTechnique
                  ? 'technique'
                  : isItem
                  ? 'item'
                  : 'empty',
          occupantRefId: ref.contentId,
          instanceId: ref.instanceEntityId?.value.toString(),
        ),
      );

      if (isTechnique && ref.instanceEntityId != null) {
        final EntityId inst = ref.instanceEntityId!;
        final TechniqueVariant? v = _context.components.get<TechniqueVariant>(
          inst,
        );
        if (v != null) {
          techniques.add(
            TechniqueInstanceSnapshot(
              instanceId: inst.value.toString(),
              baseFamilyId: v.baseFamilyId,
              styleId: v.styleId,
              descriptorIds: v.descriptorIds.toList(),
              axisProfile: Map<String, num>.of(v.axisProfile),
              origin: TechniqueOrigin.base,
              masteryAtSnapshot: _context.mastery.levelOf(
                _character,
                techniqueInstanceSubject(inst),
              ),
            ),
          );
        }
      } else if (isItem) {
        final ItemInstance? inst =
            ref.instanceEntityId != null
                ? _context.components.get<ItemInstance>(ref.instanceEntityId!)
                : _findItemInstance(ref.contentId);
        if (inst != null) {
          items.add(
            ItemInstanceSnapshot(
              definitionId: inst.definitionId,
              instanceId: ref.instanceEntityId?.value.toString(),
              itemClass: inst.itemClass,
              statBonuses: Map<String, num>.of(inst.statBonuses),
              resolvedProperties: Map<String, num>.of(inst.statBonuses),
            ),
          );
        }
      }
    }

    return AlmanacBuildRecord(
      buildId: _buildId(phase, sequence),
      runId: runId,
      phase: phase,
      sequence: sequence,
      lineageId: _lineageId!,
      physiqueId: _physiqueId!,
      techniques: techniques,
      items: items,
      affixes: const <AffixSnapshot>[],
      tome: TomeLayoutSnapshot(width: null, height: null, slots: slots),
      dna: buildDna(
        lineageId: _lineageId!,
        physiqueId: _physiqueId!,
        techniqueFamilies: <String>[
          for (final TechniqueInstanceSnapshot t in techniques) t.baseFamilyId,
        ],
        itemIds: <String>[
          for (final ItemInstanceSnapshot i in items) i.definitionId,
        ],
        affixCategories: const <String>[],
        axisProfiles: <Map<String, num>>[
          for (final TechniqueInstanceSnapshot t in techniques) t.axisProfile,
        ],
      ),
    );
  }

  /// The [ItemInstance] `_character` owns for [definitionId], or `null`.
  /// The harness places items without an `instanceEntityId` on the Tome
  /// ref, so the snapshot resolves the copy from live ECS state.
  ItemInstance? _findItemInstance(String definitionId) {
    for (final EntityId entity
        in _context.components.entitiesWith<ItemInstance>()) {
      final ItemInstance? inst = _context.components.get<ItemInstance>(entity);
      if (inst != null &&
          inst.owner == _character &&
          inst.definitionId == definitionId) {
        return inst;
      }
    }
    return null;
  }
}
