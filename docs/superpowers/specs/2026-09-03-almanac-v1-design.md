# Almanac v1 — Persistent Player History — design

**Date:** 2026-09-03
**Status:** draft — awaiting review (revised)
**Repo:** `build_engine` (`Tome:RougelikeGame`)
**Depends on:** SP0a (technique instancing), SP0b (technique inspiration — `TechniqueVariantInspired`)
**Touches:** `lib/src/plugins/game/game_run.dart` (one opt-in parameter, default off)

> **Revision note (2026-09-03):** resolves identity/idempotency and client-integration
> issues raised in review. Fight, build-snapshot, and technique-usage identity are now
> composition-assigned stable ids (the engine emits none). A dedicated **Production
> Integration Boundary** section defines the two adapters. Canonical history vs. derived
> projections is made explicit. No scope growth.

---

## 1. Why this exists

The engine can already *run* a game — a headless harness (`runGame`) drives an endless
survival loop, and a separate, out-of-repo client owns the shipped run flow. Neither
keeps anything once a run ends. `RunResult` is a per-run snapshot the caller throws away.

The Almanac is the **chronicle of the player's martial journey across all runs**. It
answers questions the running game cannot:

> What happened in Run #24? What build did I use? Which techniques did I discover? Where
> did this TechniqueVariant come from — which previous techniques inspired it? Which
> affixes have I relied on? Which lineage do I play most? Which builds keep recurring?
> What have I discovered across my entire history?

It is **not** a gameplay system, progression authority, combat system, reward system, or
content database. It observes events and records immutable history. It never drives
gameplay.

### 1.1 The one hard rule

```
Gameplay → Domain / Composition Events → Almanac Adapter → AlmanacRecorder
        → Persistent AlmanacState → AlmanacQueries
```

The arrow only points right. The Almanac never modifies combat, training, Tome, or RNG
state; never decides rewards, lineage, or technique evolution; never mints a
`TechniqueVariant`; never calls RNG; and is never a gameplay dependency of any plugin.

### 1.2 Save State ≠ Almanac History

Save state is the *current mutable game state* — where the run is right now, restorable.
Almanac history is *what the player experienced* — append-only, immutable, resilient to
content rebalance. Separate concerns, separate serialization. A future content patch that
changes Iron Sword from `Attack +3` to `Attack +2` must not rewrite the Run #12 record
that says `Attack +3`.

### 1.3 Identity, not values (the global idempotency rule)

> **Almanac idempotency is based on stable event identity or stable domain-instance
> identity — never on mutable gameplay values.**

Two fights against a `Bandit` that both last `5` turns are two distinct historical
events. Nothing may collapse them. Every record therefore carries an identity that is
either a persistent domain identity or a deterministic composition-assigned id — and
re-processing the same observation, including after a save/load cycle, is always a no-op.

| Record | Identity | Identity source |
|---|---|---|
| Run | `runId` | domain — adapter-supplied stable run id |
| Fight | `fightId` = `"<runId>:e<sequence>"` | **composition** — the engine emits no encounter id |
| Build snapshot | `buildId` = `"<runId>:<phase>:<sequence>"` | **composition** — one `(run, phase)` may recur |
| Technique history | `instanceId` (`TechniqueVariant` entity id) | domain — instance identity |
| Technique-usage observation | `usageEventId` (adapter per-run monotonic) | **composition** — `ActionCompleted` carries none |
| Inspiration ancestry | `resultInstanceId` | domain — instance identity |
| Discovery (first-seen) | `"<type>:<contentId>"` | domain — content identity |
| Affix history | `affixId` | domain — content identity (test-only wiring in v1) |
| Affix discovery/usage observation | `affixEventId` (adapter-assigned) | **composition** |
| Milestone | `type`, or `"<type>:<contextId>"` | domain — fact identity |

Composition-assigned sequences are deterministic given a fixed event stream: the adapter
increments a counter per relevant event in observation order, so the same run replayed
through the same adapter yields byte-identical ids.

---

## 2. Scope

### 2.1 In scope

- New composition-layer module `lib/src/plugins/almanac/` (non-registrable — the
  `build_interpretation/` / `game/` pattern; sits on top of Core, not a `GamePlugin`).
- Immutable domain model: run / build / technique / inspiration / affix / discovery /
  milestone records, plus the snapshots they embed, each with a stable identity (§1.3).
- `AlmanacRecorder` — a passive observer that folds primitive/snapshot inputs into an
  `AlmanacState` with strictly identity-keyed idempotent upserts.
- `AlmanacRepository` (interface + in-memory + `dart:io` file-backed) and
  `AlmanacSerialization` (state ↔ Map ↔ JSON string, schema version 1).
- `AlmanacQueries` — read-only query API over an `AlmanacState`.
- `buildDna(...)` — a deterministic normalized build signature.
- **Two composition adapters** (§4): `HeadlessGameAlmanacBridge` (in this repo, under
  `lib/src/plugins/game/`) and `TomeClientAlmanacAdapter` (contract only — the
  implementation lives in the client repo).
- One opt-in `AlmanacRecorder?` parameter on `runGame` (default `null` ⇒ zero behaviour
  change).
- New architecture tests; additive extensions to
  `test/integration/architecture_dependency_test.dart`; `ARCHITECTURE.md` and
  `CHANGELOG.md` updates.

### 2.2 Out of scope (explicit — no scope creep)

Achievements, quests, meta-progression bonuses, unlock trees, player leveling, cloud
sync, a database backend, Devvit / itch.io integration, Flutter / Flame UI, AI or ML
build clustering, automatic human-readable build naming, any Magic / Alchemy /
Cultivation almanac. SP0a / SP0b technique mechanics are not redesigned. `runGame`'s loop,
the Tome client, and any gameplay code are not modified beyond the single opt-in
parameter.

### 2.3 Deliberate v1 limitations (honesty over completeness — task §7 / §27)

| Area | Engine reality today | v1 decision |
|---|---|---|
| **Tome client** | Not in this repo — only `lib/src/tome` (the generic container service). | `TomeClientAlmanacAdapter` is a **contract**, not code here. This spec defines the recorder API and snapshot value objects it must call; the client repo implements the adapter against them. |
| **Lineage identity** | No `LineageDefinition`. "Lineage" = MartialArts tradition (`western`/`eastern`) + style (`martial_styles.dart`). | Almanac stores `lineageId` as an **opaque string** supplied by the adapter. It hardcodes no hierarchy; lineage aggregates are query-derived from run records. |
| **Affix identity** | No `AffixDefinition`, no affix ids, no `AffixDiscovered` event. Affixes are `ItemInstance.statBonuses` (stat→value maps). | `AlmanacAffixRecord` + queries + serialization are **fully implemented and unit-tested**, but **no run wires affix recording** — `recordAffixDiscovered(...)` exists and is exercised only by tests. Wiring lands when the engine gains affix identity. No fabricated live event. |
| **`TechniqueOrigin.evolved`** | Harness technique evolution is definition-level (`TechniqueEvolved { fromId, toId }`), not instance-backed. | The enum value exists; only `base` and `inspired` are produced in v1. No fabricated evolved-instance history. |
| **Physique as discovery** | Physique is assigned per run (random), not discovered. | Not a discovery type. Preserved as a run/build field only. |

---

## 3. Module shape & dependency policy

```
lib/src/plugins/almanac/
  almanac_models.dart          immutable records + snapshots + enums + AlmanacState
  almanac_serialization.dart   state ↔ Map ↔ JSON string; almanacSchemaVersion = 1
  almanac_repository.dart      AlmanacRepository interface + InMemoryAlmanacRepository
  almanac_file_repository.dart JsonFileAlmanacRepository (dart:io) — isolated
  almanac_recorder.dart        observes → AlmanacState; identity-keyed idempotent upserts
  almanac_queries.dart         read-only query API
  almanac_build_dna.dart       deterministic build signature
lib/almanac.dart               public barrel
lib/src/plugins/game/almanac_bridge.dart   HeadlessGameAlmanacBridge (top-of-graph)
```

**Dependency direction:**

```
Core
  ↓
Gameplay Plugins (technique, item, combat, martial_arts, physique, …)
  ↓
Composition Layer
  ├── lib/src/plugins/game/  (headless harness + HeadlessGameAlmanacBridge)
  └── <client repo>          (TomeClientAlmanacAdapter)
  ↓
Almanac (lib/src/plugins/almanac/)
```

- `almanac/` imports **Core only** (`package:build_engine/build_engine.dart`) plus
  `dart:convert` and, in `almanac_file_repository.dart` only, `dart:io`. It never imports
  `technique_plugin.dart`, `item_plugin.dart`, `martial_arts_plugin.dart`,
  `combat_plugin.dart`, `physique_plugin.dart`, `build_interpretation.dart`, or
  `game.dart`.
- `almanac_bridge.dart` (under `plugins/game/`, already top-of-graph) is the **only**
  file in this repo that imports both a gameplay plugin barrel and Almanac. It subscribes
  to existing events and calls the recorder with primitives.
- **All IDs in Almanac models are `String`.** Adapters stringify `EntityId.value`. The
  persistent format never couples to `EntityId`'s representation, and cross-run instance
  ids stay stable opaque tokens.
- `almanac/` contains no `package:flutter/`, `dart:ui`, `devvit`, or `flame`.

---

## 4. Production integration boundary

The Almanac is engine-side and UI-independent. It is fed by **adapters** in the
composition layer, never by gameplay code reaching into it. Both adapters translate their
own event vocabulary into the same primitive/snapshot recorder inputs.

```
build_engine
    ├── AlmanacRecorder          ← the shared contract
    ├── AlmanacRepository
    ├── AlmanacQueries
    ├── Almanac domain models + snapshots
    └── lib/src/plugins/game/almanac_bridge.dart  →  HeadlessGameAlmanacBridge

<client repo>
    └── production Almanac adapter  →  TomeClientAlmanacAdapter
```

> **The headless harness adapter proves the Almanac contract against the reference
> simulation, while the Tome client adapter is the production integration boundary for
> the shipped game.**

### 4.1 Two adapters, one recorder

| | `HeadlessGameAlmanacBridge` | `TomeClientAlmanacAdapter` |
|---|---|---|
| Lives in | `lib/src/plugins/game/almanac_bridge.dart` (this repo) | the client repo (out of scope here) |
| Observes | the harness `EventBus` (`run_events.dart` + Core/Combat/Technique events) | the client's own orchestration events |
| Purpose | CI/reference proof that the contract records a full chronicle deterministically | the real persistent history of shipped play |
| Feeds | `AlmanacRecorder` | the **same** `AlmanacRecorder` API |

Neither adapter is in Core. Neither adapter forces its orchestration into the engine.
`build_engine` does not depend on the client; the client depends on `build_engine`'s
Almanac public surface (`lib/almanac.dart`).

### 4.2 Adapter responsibilities (identical contract for both)

Each adapter must supply, as immutable value/snapshot objects (never live gameplay
handles):

- **run begin / end** — `runId`, `runNumber`, `lineageId`, `physiqueId`, timestamps,
  final `RunOutcome`.
- **fight completion** — one call per resolved encounter, carrying an adapter-assigned
  `sequence` (0,1,2,… per run) so `fightId` is stable (§1.3, §5.3).
- **build snapshots** — at meaningful milestones, each with `phase` **and** an
  adapter-assigned per-`(run,phase)` `sequence` (§5.4).
- **technique discovery** — on first observation of a `TechniqueVariant` instance.
- **technique usage** — one call per performed technique action, carrying an
  adapter-assigned `usageEventId` (§5.5).
- **training** — one call per completed training session.
- **item discovery** — on first observation of an item.
- **affix discovery** — *when affix identity exists* (v1: test-only).
- **lineage / physique** — as opaque strings on the run record (and echoed on build
  snapshots).
- **SP0b inspiration** — the `TechniqueVariantInspired` payload, verbatim (§6).

The adapter converts gameplay state into snapshots at the moment of observation. It never
hands the recorder a mutable component, entity, `PluginContext`, or event bus.

---

## 5. Domain model — `almanac_models.dart`

Every class: immutable, `const` constructor, module-local `toJson()` /
`fromJson(Map<String, dynamic>)` returning/taking plain maps (the `Container.toJson` /
`CombatantComponent.toJson` precedent — no engine-wide serialization framework).
`DateTime` ↔ ISO-8601 string.

### 5.1 Canonical history vs. derived projections

The Almanac is **not** a full event store (task §6 — "avoid a huge event-sourcing
system"). Instead:

- **Canonical records** are immutable once written and keyed by a stable identity
  (§1.3). Writing the same identity again is a no-op. These are the source of truth:
  `AlmanacRunRecord`, `AlmanacFightRecord`, `AlmanacBuildRecord`,
  `AlmanacDiscoveryRecord`, `TechniqueInspirationHistory`, `AlmanacMilestoneRecord`, and
  the **consumed-observation ledgers** `AlmanacTechniqueRecord.usageEventIds`,
  `AlmanacAffixRecord.discoveryEventIds`, `AlmanacAffixRecord.usageEventIds`.
- **Derived projections** are recorder-maintained fields kept for query convenience and
  fully recomputable from canonical data. They are never independent history:

  | Projection | Recomputable from |
  |---|---|
  | `AlmanacTechniqueRecord.totalUsage` | `usageEventIds.length` |
  | `AlmanacTechniqueRecord.runsUsed` | the run numbers of the consumed usage observations |
  | `AlmanacAffixRecord.timesDiscovered` | `discoveryEventIds.length` |
  | `AlmanacAffixRecord.timesUsed` | `usageEventIds.length` |
  | `AlmanacAffixRecord.associatedLineageIds` | union of `lineageId` over consumed discovery observations |
  | `AlmanacRunRecord.enemiesDefeated` / `techniquesUsed` / `trainingSessions` | the run's fights / consumed usage observations / training observations |

  Every projection mutation is gated by an idempotent identity check: the recorder
  applies the increment/union **only** when the driving `usageEventId` /
  `affixEventId` / `fightId` was not already consumed. Replayed observations — including
  across a save/load boundary, because the ledgers are persisted — change nothing.

Fields set once at first observation (`discoveredRunId`, `discoveredRunNumber`,
`masteryAtDiscovery`, `descriptorIds`, `axisProfile`, `styleId`) are canonical-at-first-write;
`origin` is the sole exception — `base` at `TechniqueVariantMinted`, upgraded to
`inspired` in place when the matching `TechniqueVariantInspired` arrives (§6).

### 5.2 Enums

| Enum | Values |
|---|---|
| `RunOutcome` | `won`, `lost`, `abandoned` |
| `TechniqueOrigin` | `base`, `evolved`, `inspired` (only `base`/`inspired` produced in v1) |
| `BuildPhase` | `initial`, `postReward`, `postTraining`, `finalBuild` |
| `AlmanacDiscoveryType` | `technique`, `techniqueVariant`, `item`, `affix`, `lineage` |
| `MilestoneType` | `firstRun`, `firstVictory`, `firstTechniqueVariant`, `firstInspiredTechnique`, `firstAffix`, `firstWinWithLineage`, `firstSuccessfulBuild` |

### 5.3 `AlmanacFightRecord` — stable fight identity

```dart
class AlmanacFightRecord {
  final String fightId;          // "<runId>:e<sequence>" — the identity
  final String runId;
  final int sequence;            // adapter-assigned, per run, 0-based, observation order
  final String name;
  final String enemyId;
  final bool won;
  final num playerHealthAfter;
  final int turnsUsed;
}
```

No gameplay property participates in identity. Two fights with identical `name`,
`enemyId`, and `turnsUsed` are two records because their `sequence` (hence `fightId`)
differ. Idempotency: the recorder appends a fight to its run only if `fightId` is not
already present in that run's `fights`.

The engine emits no encounter id (`EncounterStarted`/`EncounterResolved` in
`run_events.dart` carry `name` + `enemyId` only, no index). The adapter assigns
`sequence` by counting `EncounterStarted` (or the client's equivalent) per run.

### 5.4 `AlmanacBuildRecord` — stable snapshot identity

```dart
class AlmanacBuildRecord {
  final String buildId;         // "<runId>:<phase>:<sequence>" — the identity
  final String runId;
  final BuildPhase phase;
  final int sequence;           // adapter-assigned, per (run, phase), 0-based
  final String lineageId;
  final String physiqueId;
  final List<TechniqueInstanceSnapshot> techniques;
  final List<ItemInstanceSnapshot> items;
  final List<AffixSnapshot> affixes;
  final TomeLayoutSnapshot tome;
  final BuildPerformanceSnapshot? performance;
  final BuildDna dna;
}
```

A build snapshot is an **immutable historical observation of a build at a specific
milestone**, not live Tome state. One run may legitimately produce `initial`,
`postReward#0`, `postReward#1`, `postTraining#0`, `postTraining#1`, `finalBuild` — the
`sequence` keeps `postReward#0` and `postReward#1` as distinct records. A second snapshot
never overwrites an earlier one that shares a `BuildPhase`. Idempotency: dedup on
`buildId`.

### 5.5 Snapshots (self-contained historical values — survive rebalance)

- `TechniqueInstanceSnapshot { String instanceId; String baseFamilyId; String? styleId;
  List<String> descriptorIds; Map<String, num> axisProfile; TechniqueOrigin origin;
  int masteryAtSnapshot }`
- `ItemInstanceSnapshot { String definitionId; String? instanceId; int itemClass;
  Map<String, num> statBonuses; Map<String, num> resolvedProperties }`
- `AffixSnapshot { String affixId; String stat; num value; String? category }`
- `TomeSlotSnapshot { String slotId; String occupantKind /* technique | item | empty */;
  String? occupantRefId; String? instanceId }`
- `TomeLayoutSnapshot { int? width; int? height; List<TomeSlotSnapshot> slots }` —
  `width`/`height` null ⇒ named-slot container. Preserves grid dimensions, slot
  arrangement, component identity, and technique **instance** identity (task §7).
- `BuildPerformanceSnapshot { int fightsWon; int fightsLost; int enemiesDefeated;
  num? avgTurnsUsed }`
- `DiscoverySnapshot { String label; Map<String, Object?> values }`

**Rebalance safety.** Every historical record embeds a *resolved snapshot* captured at
observation time. `definitionId` is stored only as a reference for grouping and linking
(`getBuildsUsingTechnique`, lineage aggregates) — it is **never** the source of a
displayed historical value. Reconstructing Run #12 never resolves the current
`ContentRegistry`. If Iron Sword is later re-tuned to `Attack +2`, the Run #12
`ItemInstanceSnapshot.resolvedProperties` still reads `+3`.

### 5.6 Records

- `AlmanacRunRecord { String runId; int runNumber; String lineageId; String physiqueId;
  DateTime startedAt; DateTime? completedAt; RunOutcome outcome;
  List<AlmanacFightRecord> fights; List<String> discoveryIds; String? finalBuildId;
  int enemiesDefeated; int techniquesUsed; int trainingSessions }`
  — the last three are projections (§5.1). Describes the run; never a replay save, never
  the mutable gameplay state.
- `AlmanacTechniqueRecord { String instanceId; String baseFamilyId; String? styleId;
  List<String> descriptorIds; Map<String, num> axisProfile; String? discoveredRunId;
  int? discoveredRunNumber; int masteryAtDiscovery; List<String> usageEventIds;
  int totalUsage; List<int> runsUsed; TechniqueOrigin origin }`
  — keyed by `instanceId`; `usageEventIds` is the canonical ledger, `totalUsage` /
  `runsUsed` are its projections. The base family never collapses distinct instances.
- `TechniqueInspirationHistory { String resultInstanceId; String runId; String familyId;
  List<String> descriptorIds; List<String> inspirerInstanceIds }`
  — stored exactly as emitted by `TechniqueVariantInspired` (§6). Never recomputed.
- `AlmanacAffixRecord { String affixId; List<String> discoveryEventIds;
  List<String> usageEventIds; int timesDiscovered; int timesUsed;
  String? firstDiscoveredRunId; List<String> associatedLineageIds; AffixSnapshot snapshot }`
  — `discoveryEventIds` / `usageEventIds` canonical; the counters and `associatedLineageIds`
  are projections.
- `AlmanacDiscoveryRecord { String discoveryId; AlmanacDiscoveryType type;
  String contentId; String? instanceId; String runId; int runNumber; DateTime timestamp;
  DiscoverySnapshot snapshot }`
  — `discoveryId = "<type>:<contentId>"`; first occurrence is immutable, later encounters
  never add a row (they feed the technique/item/affix projections instead).
- `AlmanacMilestoneRecord { String milestoneId; MilestoneType type; String runId;
  int runNumber; DateTime timestamp; String? contextId }`
  — `milestoneId = type.name`, or `"<type>:<contextId>"` for per-context firsts
  (`firstWinWithLineage:western`, `firstSuccessfulBuild:<finalBuildId>`). First occurrence
  canonical; duplicate delivery ignored.
- `AlmanacFightRecord` — §5.3. `AlmanacBuildRecord` — §5.4.
- `BuildDna { List<String> tokens; String signature }` — §9.

### 5.7 Aggregate root

```dart
class AlmanacState {
  final List<AlmanacRunRecord> runs;
  final List<AlmanacBuildRecord> builds;
  final List<AlmanacTechniqueRecord> techniques;
  final List<TechniqueInspirationHistory> inspirations;
  final List<AlmanacAffixRecord> affixes;
  final List<AlmanacDiscoveryRecord> discoveries;
  final List<AlmanacMilestoneRecord> milestones;

  static const int almanacSchemaVersion = 1;

  const AlmanacState({ /* all lists default const [] */ });
  factory AlmanacState.empty() => const AlmanacState();
}
```

`inspirations` is a seventh list beyond the six in task §19 — justified: SP0b ancestry is
called out as one of the most important Almanac features (task §9) and deserves a
first-class collection with its own query rather than being buried inside a technique
record. Records are held in insertion order. No mutable counters live at the
`AlmanacState` level.

---

## 6. SP0b inspiration ancestry — preserved exactly

When `TechniqueVariantInspired` is observed, the adapter passes its payload verbatim and
the recorder stores:

```
resultInstanceId   → TechniqueInspirationHistory.resultInstanceId  (the identity)
familyId           → .familyId
descriptorIds      → .descriptorIds        (order preserved)
inspirerInstanceIds→ .inspirerInstanceIds  (order preserved, exactly as emitted)
runId              → .runId
```

The recorder **never** re-runs inspiration resolution, recalculates attribution,
re-queries current inspirers, or calls RNG. Historical ancestry is authoritative from the
event.

**Event ordering.** An inspired variant emits `TechniqueVariantMinted` **then**
`TechniqueVariantInspired` (inspiration calls `mintTechniqueVariant` internally —
confirmed in `technique_inspiration.dart`). Both are observed. They **converge on one
`AlmanacTechniqueRecord` keyed by `instanceId`**: `Minted` inserts it with
`origin: base`; `Inspired` upserts `origin: inspired` in place (no second row) and adds
exactly one `TechniqueInspirationHistory` keyed by `resultInstanceId`. Re-delivery of
either event changes nothing.

---

## 7. Recorder & idempotency — `almanac_recorder.dart`

`AlmanacRecorder(AlmanacState initial)` — a plain class. Internally holds a working copy
indexed by identity for O(1) upsert; exposes `AlmanacState get state` (rebuilt as ordered
lists). **Never** references `RngService`, `context.rng`, `Random`, `math.Random`, the
component store, the event bus, or any gameplay mutation. Inputs are `String` / `num` /
`bool` / `DateTime` / the snapshot classes only.

### 7.1 Methods

| Method | Effect (all identity-gated) |
|---|---|
| `beginRun({runId, runNumber, lineageId, physiqueId, startedAt})` | upsert an open `AlmanacRunRecord` by `runId` (`outcome` provisional `abandoned`, `completedAt` null) |
| `recordFight({runId, sequence, name, enemyId, won, playerHealthAfter, turnsUsed})` | build `fightId = "<runId>:e<sequence>"`; append to that run's `fights` **iff** `fightId` absent; bump `enemiesDefeated` projection iff newly appended and `won` |
| `recordBuildSnapshot(AlmanacBuildRecord)` | `buildId` already `"<runId>:<phase>:<sequence>"`; upsert by `buildId`; compute `dna` if `dna.tokens` empty |
| `recordTechniqueDiscovered({instanceId, baseFamilyId, styleId, descriptorIds, axisProfile, origin, masteryAtDiscovery, runId, runNumber})` | upsert `AlmanacTechniqueRecord` by `instanceId` (first write sets the discovery fields); emit a `techniqueVariant` discovery row keyed `"techniqueVariant:<instanceId>"` |
| `recordTechniqueUsed({instanceId, runId, runNumber, usageEventId})` | **iff** `usageEventId` not in that record's `usageEventIds`: add it, `totalUsage++`, add `runNumber` to `runsUsed` if absent, bump the run's `techniquesUsed` projection |
| `recordTechniqueInspired({resultInstanceId, runId, familyId, descriptorIds, inspirerInstanceIds})` | upsert `TechniqueInspirationHistory` by `resultInstanceId` (verbatim); upsert the matching technique record's `origin → inspired` |
| `recordItemDiscovered({definitionId, instanceId, runId, runNumber, snapshot})` | emit an `item` discovery row keyed `"item:<definitionId>"` (first occurrence immutable) |
| `recordAffixDiscovered({affixId, affixEventId, runId, runNumber, lineageId, snapshot})` | upsert `AlmanacAffixRecord` by `affixId`; **iff** `affixEventId` not in `discoveryEventIds`: add it, `timesDiscovered++`, set `firstDiscoveredRunId` once, union `lineageId`; emit an `affix` discovery row |
| `recordAffixUsed({affixId, affixEventId, runNumber})` | **iff** `affixEventId` not in `usageEventIds`: add it, `timesUsed++` |
| `recordTrainingSession({runId, runNumber, sessionEventId})` | **iff** `sessionEventId` unseen for that run: bump `trainingSessions` projection |
| `recordDiscovery(AlmanacDiscoveryRecord)` | generic upsert by `discoveryId` (the typed methods delegate here); on first write also append `discoveryId` to `runs[runId].discoveryIds` if absent |
| `recordMilestone({type, runId, runNumber, timestamp, contextId})` | upsert by `milestoneId` (`type.name` or `"<type>:<contextId>"`); first write canonical |
| `evaluateStandardMilestones({runId, runNumber, outcome, lineageId, finalBuildId, timestamp})` | derive and record the standard firsts (§7.3) |
| `completeRun({runId, completedAt, outcome, finalBuildId})` | close the run record by `runId`; projections already maintained incrementally |

### 7.2 Identity keys (the full set)

| Record / projection input | Key |
|---|---|
| run | `runId` |
| fight | `fightId = "<runId>:e<sequence>"` |
| build snapshot | `buildId = "<runId>:<phase>:<sequence>"` |
| technique history | `instanceId` |
| technique-usage projection | `usageEventId` (stored in `AlmanacTechniqueRecord.usageEventIds`) |
| inspiration | `resultInstanceId` |
| discovery row | `"<type>:<contentId>"` (variant rows: `"techniqueVariant:<instanceId>"`) |
| affix history | `affixId` |
| affix discovery/usage projection | `affixEventId` (stored in the affix record's ledgers) |
| training projection | `sessionEventId` (per run) |
| milestone | `type.name` or `"<type>:<contextId>"` |

Counts (`totalUsage`, `timesUsed`, `timesDiscovered`, `enemiesDefeated`, `techniquesUsed`,
`trainingSessions`) and sets (`runsUsed`, `associatedLineageIds`) are **projections** —
mutated once per newly-consumed identity, never on replay. Because the consumed-identity
ledgers are part of `AlmanacState` and are serialized, idempotency holds across
save/load.

### 7.3 Standard milestones (lightweight — task §15)

`evaluateStandardMilestones` records, at most once each (dedup on `milestoneId`):

- `firstRun` — state had zero runs before this one.
- `firstVictory` — `outcome == won` and no prior `won` run.
- `firstTechniqueVariant` — first technique record ever.
- `firstInspiredTechnique` — first technique record with `origin == inspired`.
- `firstAffix` — first affix record (v1: only reachable via tests).
- `firstWinWithLineage` (`contextId = lineageId`) — first `won` run for that lineage.
- `firstSuccessfulBuild` (`contextId = finalBuildId`) — first `won` run with a non-empty
  final build.

No hundreds of achievements; a flat record is enough.

---

## 8. Repository & serialization — `almanac_repository.dart` / `almanac_serialization.dart`

### 8.1 Repository

```dart
abstract interface class AlmanacRepository {
  AlmanacState load();
  void save(AlmanacState state);
}

class InMemoryAlmanacRepository implements AlmanacRepository {
  InMemoryAlmanacRepository([AlmanacState initial = const AlmanacState()]);
}
```

`almanac_file_repository.dart` (isolated; `dart:io` + `dart:convert` — the same
`dart:io`-in-a-composition-module precedent as
`plugins/game/console_decision_policy.dart`):

```dart
class JsonFileAlmanacRepository implements AlmanacRepository {
  JsonFileAlmanacRepository(this._file);
  final File _file;
  AlmanacState load() => _file.existsSync()
      ? AlmanacSerialization.decode(_file.readAsStringSync())
      : AlmanacState.empty();
  void save(AlmanacState state) =>
      _file.writeAsStringSync(AlmanacSerialization.encode(state));
}
```

No database dependency. No Flutter / Flame / Devvit / backend.

### 8.2 Serialization

- `Map<String, dynamic> stateToJson(AlmanacState)` — writes
  `{'almanacSchemaVersion': 1, 'runs': [...], 'builds': [...], ...}` including every
  consumed-identity ledger.
- `AlmanacState stateFromJson(Map<String, dynamic>)` — throws
  `AlmanacSchemaVersionError` if `almanacSchemaVersion != 1` (the migration seam).
- `String encode(AlmanacState)` / `AlmanacState decode(String)` — `jsonEncode` /
  `jsonDecode` wrappers.

Persisted values are only strings, nums, bools, lists, maps. Never serialized: closures,
engine-service references, RNG state, component-store internals, Flutter/UI objects, live
entity references.

---

## 9. Query API — `almanac_queries.dart`

`AlmanacQueries(AlmanacState state)` — pure reads, deterministic order. Records are
returned in state-list insertion order; queries that re-sort use an explicit
`(runNumber, id)` comparator so results are stable (task §22.10).

Required (task §20): `getRunHistory()` · `getRun(runId)` · `getBuildHistory()` ·
`getBuild(buildId)` · `getLineageHistory(lineageId)` · `getTechniqueHistory(instanceId)` ·
`getTechniqueInspirations(instanceId)` · `getAffixHistory(affixId)` · `getDiscoveries()` ·
`getRecentDiscoveries({int limit})` · `getRunsUsingTechnique(instanceId)` ·
`getBuildsUsingTechnique(instanceId)` · `getRunsForLineage(lineageId)` ·
`getRunsForPhysique(physiqueId)`.

Aggregates (small — no analytics engine): `lineageStatistics(lineageId)` →
`{runs, wins, losses, techniquesDiscovered, itemsDiscovered, affixesDiscovered,
buildsUsed, physiquesUsed}` derived from records; `mostUsedTechniques({int limit})`;
`mostUsedAffixes({int limit})`; `discoveryCompletion({Map<AlmanacDiscoveryType,
Set<String>> known})` → per-type `{discovered, total, fraction}`.

The client never mutates `AlmanacState` directly — it reads through `AlmanacQueries` and
writes only through its adapter.

---

## 10. Build DNA — `almanac_build_dna.dart`

```dart
BuildDna buildDna({
  required String lineageId,
  required String physiqueId,
  required Iterable<String> techniqueFamilies,
  required Iterable<String> itemIds,
  required Iterable<String> affixCategories,
  required Iterable<Map<String, num>> axisProfiles,
});
```

Fully deterministic — no RNG, no clustering, no ML:

1. `tokens = [ lineageId.toUpperCase(), physiqueId.toUpperCase(),
   ...sortedUnique(techniqueFamilies).map(upper), ...sortedUnique(itemIds).map(upper),
   ...sortedUnique(affixCategories).map(upper), ...topAxes ]`
   where `topAxes` = the axis names selected by ordering on
   `(summedAbsValue desc, name asc)` across `axisProfiles`, taking the first 3, then
   re-sorted by `name asc`, upper-cased. The `name asc` tie-break keeps selection
   deterministic when two axes share a summed magnitude.
2. `signature` = FNV-1a 32-bit hex of `tokens.join('|')`.

Stored on `AlmanacBuildRecord.dna`. No human-readable names in v1 (task §21).

---

## 11. Headless harness bridge — `almanac_bridge.dart` + `runGame`

`runGame` gains one optional parameter:

```dart
RunResult runGame(
  int seed, {
  String characterName = 'Player',
  RunDecisionPolicy policy = const DefaultRunDecisionPolicy(),
  EventBus? eventBus,
  AlmanacRecorder? almanac,   // NEW — null ⇒ zero behaviour change
});
```

`almanac == null`: no subscriptions, no snapshots, byte-identical to today. Determinism
and existing harness tests are unaffected because the recorder can reach neither `rng`
nor `policy`.

Non-null: `runGame` constructs `HeadlessGameAlmanacBridge(almanac, runId: 'run_$seed',
runNumber: <caller-supplied>)`, calls `.attach(events)` before the cycle loop, and
`.finish(...)` on `RunEnded`. `runNumber` = `repo.load().runs.length + 1` is the caller's
responsibility, passed in — `runGame` stays free of persistence. After `runGame` returns
the caller persists: `repo.save(almanac.state)`.

### 11.1 Bridge-assigned identities

The bridge owns three per-run counters, all incremented in observation order:

| Counter | Incremented on | Feeds |
|---|---|---|
| `encounterSeq` | each `EncounterStarted` | `recordFight(sequence: …)` on the matching `EncounterResolved` |
| `buildSeq[phase]` | each build snapshot it takes for `phase` | `AlmanacBuildRecord.sequence` |
| `usageSeq` | each `ActionCompleted` it attributes to a technique instance | `usageEventId = "run_$seed:u<usageSeq>"` |
| `trainingSeq` | each `TrainingResultRecorded` | `sessionEventId = "run_$seed:t<trainingSeq>"` |

These are deterministic for a fixed seed + policy, so a replayed run produces an
identical `AlmanacState`.

### 11.2 Event → recorder map (existing events only — no new events)

| Event (source) | Recorder call |
|---|---|
| run start (inside `runGame`) | `beginRun(lineageId: martialTraditionOf(styleId) ?? styleId, physiqueId: physiqueId, …)` |
| `TomeChanged` (harness) `stepName == 'starting'` | `recordBuildSnapshot(phase: initial, sequence: 0)` |
| `TechniqueVariantMinted` (technique) | `recordTechniqueDiscovered(origin: base, …)` |
| `TechniqueVariantInspired` (technique) | `recordTechniqueInspired(…)` — upserts `origin: inspired`, adds ancestry |
| `SubjectDiscovered` (Core) subj `technique:*` / `item:*` | `recordDiscovery(type: technique | item)` |
| `ActionCompleted` (combat) with `action.sourceRef.instanceEntityId != null` and `referenceType == techniqueReferenceType` | `recordTechniqueUsed(usageEventId: "run_$seed:u<usageSeq++>")` — the same attribution `combat_stage.dart` already does for SP0b |
| `EncounterStarted` (harness) | `encounterSeq++` (no recorder call) |
| `EncounterResolved` (harness) | `recordFight(sequence: encounterSeq-1, …)` |
| `RewardSelected` (harness) | `recordBuildSnapshot(phase: postReward, sequence: buildSeq['postReward']++)` |
| `TrainingResultRecorded` (harness) | `recordTrainingSession(sessionEventId: …)`; `recordBuildSnapshot(phase: postTraining, sequence: buildSeq['postTraining']++)` |
| `RunEnded` (harness) | final `recordBuildSnapshot(phase: finalBuild, sequence: 0)` + DNA; `completeRun(outcome: won ? RunOutcome.won : RunOutcome.lost, …)`; `evaluateStandardMilestones(…)` |

`TomeLayoutSnapshot` is built from `context.tome` and the `List<BuildComponentRef>` the
harness stages already hold. Outcome mapping: harness `won: true` (survived to the
safety cap) → `RunOutcome.won`; `won: false` (died) → `RunOutcome.lost`; a run that never
reaches `RunEnded` stays `abandoned`.

---

## 12. Architecture tests & docs

### 12.1 New — `test/plugins/almanac/almanac_architecture_test.dart`

- Every `lib/src/plugins/almanac/*.dart` contains none of: `technique_plugin.dart`,
  `item_plugin.dart`, `martial_arts_plugin.dart`, `combat_plugin.dart`,
  `physique_plugin.dart`, `build_interpretation.dart`, `game.dart`, `plugins/` (relative
  escape).
- `almanac_recorder.dart` and `almanac_queries.dart` contain none of: `RngService`,
  `context.rng`, `Random(`, `math.Random`.
- No `lib/src/plugins/almanac/*.dart` contains `package:flutter/`, `dart:ui`, `devvit`,
  or `flame`.

### 12.2 Extend — `test/integration/architecture_dependency_test.dart` (add only)

- Add `'almanac.dart'` to `_pluginBarrels` so the enumerated "Core does not import any
  plugin barrel" group covers it automatically.
- New group "Almanac is a passive observer": each of
  `lib/src/plugins/{technique,combat,martial_arts,item,physique,elemental,auto_combat}`
  references neither `almanac.dart` nor `plugins/almanac/`.

No existing architecture assertion is weakened or removed.

### 12.3 Docs

- `ARCHITECTURE.md` — new "## Almanac — Persistent Player History" section: responsibility;
  the passive-observer / adapter model with both `HeadlessGameAlmanacBridge` and the
  out-of-repo `TomeClientAlmanacAdapter`; identity-not-values idempotency; canonical
  history vs. derived projections; immutable-history & rebalance-resilience;
  serialization boundary + schema version; query API; the `TechniqueVariantInspired` /
  SP0b relationship; the ContentRegistry relationship; why Almanac owns no gameplay
  state; a "Save State ≠ Almanac History" subsection.
- `CHANGELOG.md` — entry under a new dated heading.

---

## 13. Test plan

### 13.1 Unit — `test/plugins/almanac/`

| File | Proves |
|---|---|
| `almanac_models_test.dart` | immutability; per-record `toJson`/`fromJson` round-trips including ledgers |
| `almanac_recorder_test.dart` | begin/complete run; multiple runs stay separate; same event twice → no duplicate; projections match their ledgers |
| `almanac_fight_identity_test.dart` | two `Bandit` / `5`-turn fights in one run → **2** `AlmanacFightRecord`s (distinct `fightId`); replaying either `EncounterResolved` observation → still **2**; `enemiesDefeated` projection counts each win once |
| `almanac_build_snapshot_test.dart` | `postReward` sequence `0` and `1` remain separate records; replaying either → no duplicate; Tome layout (dims + slots + instance ids) preserved; mutating a fake definition afterward leaves the stored snapshot unchanged (rebalance) |
| `almanac_technique_usage_test.dart` | same `usageEventId` delivered twice → `totalUsage` +1, `runsUsed` unchanged; two distinct `usageEventId`s → `totalUsage` +2; idempotency survives a save/load between the two deliveries |
| `almanac_inspiration_test.dart` | synthetic `TechniqueVariantInspired` → `inspirerInstanceIds` preserved exactly and in order; deliver it twice → **one** `TechniqueInspirationHistory` and **one** `AlmanacTechniqueRecord`; `Minted`→`Inspired` ordering converges on `origin: inspired`; ancestry never recomputed / no RNG |
| `almanac_cross_run_identity_test.dart` | same `baseFamilyId` in two runs with two different `TechniqueVariant` instance ids → **two** `AlmanacTechniqueRecord`s |
| `almanac_affix_test.dart` | `recordAffixDiscovered` with 3 distinct `affixEventId`s for one `affixId` → one record, `timesDiscovered == 3`, lineages unioned; repeat an `affixEventId` → unchanged |
| `almanac_lineage_test.dart` | run records lineage; `getRunsForLineage` / `lineageStatistics` correct and derived-only |
| `almanac_serialization_test.dart` | save→load equivalent for `InMemory` and `JsonFile` (temp file); ledgers survive; schema-version mismatch throws |
| `almanac_queries_test.dart` | same state → identical, order-stable query results |
| `almanac_build_dna_test.dart` | same inputs → same signature; reordered inputs → same signature; changed inputs → different |
| `almanac_architecture_test.dart` | §12.1 |

### 13.2 Production integration boundary — `test/plugins/almanac/almanac_adapter_parity_test.dart`

A synthetic second adapter (standing in for `TomeClientAlmanacAdapter`) feeds the **same**
`AlmanacRecorder` an observation sequence equivalent to a harness run — same `runId`,
same fight sequences, same `usageEventId`s, same `TechniqueVariantInspired` payload. The
resulting `AlmanacState` is equal to the one produced by `HeadlessGameAlmanacBridge` for
that run. Proves the recorder contract is adapter-agnostic and the client is a drop-in
producer of the same primitives.

### 13.3 Integration — `test/integration/almanac_run_history_test.dart`

- `runGame(seed, almanac: recorder)` for 3 different seeds/policies → 3 distinct
  `AlmanacRunRecord`s; discoveries and final builds captured; lineage/physique preserved.
- Whole-chronicle serialization round-trips (`AlmanacSerialization` +
  `JsonFileAlmanacRepository`).
- `almanac == null` path: `RunResult` byte-identical to a run without the parameter.
- Same seed + same policy twice → equivalent `AlmanacState` (bridge-assigned ids are
  deterministic).

### 13.4 Gate

`dart format .`, `dart analyze`, `dart test` all green; every pre-existing
architecture/dependency test still passes:

```
Core purity: PASS
Dependency DAG: PASS
No circular plugin dependencies: PASS
No unmanaged RNG: PASS
No cross-plugin private implementation imports: PASS
```

---

## 14. Commit sequence

1. domain model (with identity fields + ledgers) + serialization + model tests
2. repository (in-memory + `dart:io` file) + serialization tests
3. recorder + identity-keyed idempotency + recorder / fight-identity / usage / inspiration / affix / cross-run tests
4. queries + build DNA + their tests
5. `HeadlessGameAlmanacBridge` + `runGame` opt-in parameter + adapter-parity + integration tests
6. architecture tests + `ARCHITECTURE.md` + `CHANGELOG.md` + `lib/almanac.dart` barrel

Each commit builds and tests green on its own.

---

## 15. Design questions answered

| # | Question | Answer |
|---|---|---|
| 1 | How does the actual Tome client feed Almanac? | Through `TomeClientAlmanacAdapter` in the **client repo**, calling the same `AlmanacRecorder` public API (`lib/almanac.dart`) with primitive/snapshot value objects. No Almanac code moves into the client; the client never exposes mutable gameplay internals to the recorder. §4. |
| 2 | How does the headless harness feed Almanac? | Through `HeadlessGameAlmanacBridge` (`lib/src/plugins/game/almanac_bridge.dart`), subscribed to the harness `EventBus`, wired by an opt-in `AlmanacRecorder?` param on `runGame`. §11. |
| 3 | What is the stable identity of a fight? | `fightId = "<runId>:e<sequence>"`, where `sequence` is a composition-assigned per-run counter over `EncounterStarted` — never `(name, enemyId, turnsUsed)`. §1.3, §5.3. |
| 4 | What is the stable identity of a build snapshot? | `buildId = "<runId>:<phase>:<sequence>"`, `sequence` a per-`(run, phase)` counter, so repeated `postReward`/`postTraining` states never overwrite. §1.3, §5.4. |
| 5 | How is usage-event idempotency guaranteed? | Each `recordTechniqueUsed` call carries an adapter-assigned `usageEventId`, stored in `AlmanacTechniqueRecord.usageEventIds` (canonical, serialized). The `totalUsage` / `runsUsed` projections mutate only when the id is newly consumed — replay, including across save/load, is a no-op. §5.1, §7.1–§7.2. |
| 6 | Which data is canonical history? | Identity-keyed immutable records (run, fight, build, discovery, inspiration, milestone) plus the consumed-observation ledgers (`usageEventIds`, affix `discoveryEventIds` / `usageEventIds`). §5.1. |
| 7 | Which values are derived projections? | `totalUsage`, `runsUsed`, affix `timesDiscovered` / `timesUsed` / `associatedLineageIds`, run `enemiesDefeated` / `techniquesUsed` / `trainingSessions` — all recomputable from canonical data, all identity-gated. §5.1. |
| 8 | How is SP0b inspiration ancestry preserved? | `TechniqueVariantInspired` payload stored verbatim in `TechniqueInspirationHistory` keyed by `resultInstanceId`; no re-resolution, no re-query, no RNG; `Minted`→`Inspired` converge by `instanceId`. §6. |
| 9 | How does historical data survive content rebalance? | Every record embeds a resolved snapshot captured at observation time; `definitionId` is a reference for linking only, never the source of a displayed value; reconstruction never resolves the current `ContentRegistry`. §5.5. |
| 10 | How are architecture boundaries enforced? | `almanac/` imports Core only; one bridge file is the sole dual-importer in-repo; new + extended substring-scan architecture tests assert no plugin imports `almanac.dart` / `plugins/almanac/` and Core imports no `almanac.dart`. §3, §12. |

---

## 16. Acceptance criteria

- [ ] Almanac is a standalone composition-layer module; Core stays game-agnostic.
- [ ] Both `HeadlessGameAlmanacBridge` (in-repo) and the `TomeClientAlmanacAdapter` contract feed one shared `AlmanacRecorder`; the client adapter implementation stays out of `build_engine`.
- [ ] No Combat → Almanac, Technique → Almanac, MartialArts → Almanac, or Training → Almanac dependency; no circular dependency; `build_engine` does not depend on the client.
- [ ] Fight identity is `runId`+sequence, never gameplay values; two identical-looking fights stay two records; replay adds none.
- [ ] Build-snapshot identity is `runId`+phase+sequence; repeated `postReward`/`postTraining` snapshots stay distinct; replay adds none.
- [ ] Technique-usage, affix-discovery/usage, and training projections are driven by explicit event ids and are idempotent across save/load.
- [ ] Canonical history and derived projections are explicitly separated in the model and docs.
- [ ] TechniqueVariant instances stay distinct across runs; SP0b inspiration ancestry persists exactly as emitted; `Minted`/`Inspired` converge by `instanceId`.
- [ ] Item and affix history models + queries + serialization implemented (affix recording test-only in v1).
- [ ] Lineage, physique, and discovery history persist.
- [ ] Historical snapshots survive a later content rebalance.
- [ ] Milestone identity is `type` (+ context); duplicates are ignored.
- [ ] Serialization round-trips (records + ledgers); schema version 1 with a migration seam.
- [ ] Query API works and is deterministic.
- [ ] Build DNA is deterministic.
- [ ] `dart analyze` / `dart test` / all architecture tests pass.
- [ ] `ARCHITECTURE.md` and `CHANGELOG.md` updated, including "Save State ≠ Almanac History".
