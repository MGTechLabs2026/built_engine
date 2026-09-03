# Almanac v1 — Persistent Player History — design

**Date:** 2026-09-03
**Status:** draft — awaiting review (revised)
**Repo:** `build_engine` (`Tome:RougelikeGame`)
**Depends on:** SP0a (technique instancing), SP0b (technique inspiration — `TechniqueVariantInspired`)
**Touches:** `lib/src/plugins/game/game_run.dart` (one opt-in parameter, default off)

> **Revision note (2026-09-03, rev 2):** rev 1 resolved client integration and made
> fight / build-snapshot / technique-usage identity composition-assigned (the engine
> emits none), added the **Production Integration Boundary** section, and separated
> canonical history from derived projections. Rev 2 finalizes: `runId` ≠ `seed` ≠
> `runNumber` (§1.4) with the recorder never generating identity or reading the
> repository; deep immutability — copy-in / unmodifiable-out (§5.8); the adapter
> event-identity contract (§4.3); event-order-independent inspiration merge by
> `instanceId` (§6); `BuildDna` explicitly a derived projection, not an identity (§10).
> No scope growth.

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
| Run | `runId` | **composition** — opaque per-run-instance id, never the seed (§1.4) |
| Fight | `fightId` = `"<runId>:e<sequence>"` | **composition** — the engine emits no encounter id |
| Build snapshot | `buildId` = `"<runId>:<phase>:<sequence>"` | **composition** — one `(run, phase)` may recur |
| Technique history | `instanceId` (`TechniqueVariant` entity id) | domain — instance identity |
| Technique-usage observation | `usageEventId` (adapter stable/monotonic — §4.3) | **composition** — `ActionCompleted` carries none |
| Inspiration ancestry | `resultInstanceId` | domain — instance identity |
| Discovery (first-seen) | `"<type>:<contentId>"` | domain — content identity |
| Affix history | `affixId` | domain — content identity (test-only wiring in v1) |
| Affix discovery/usage observation | `affixEventId` (adapter-assigned) | **composition** |
| Milestone | `type`, or `"<type>:<contextId>"` | domain — fact identity |

Composition-assigned sequences are deterministic given a fixed event stream: the adapter
increments a counter per relevant event in observation order, so the same run replayed
through the same adapter yields byte-identical ids.

### 1.4 Run identity — `runId` ≠ `seed` ≠ `runNumber`

These are three different concepts and must never be conflated:

| Field | Meaning | Assigned by | Canonical identity? |
|---|---|---|---|
| `runId` | Opaque unique id for **one run instance** (e.g. `run-000001`, `run-000002`, …). | The caller / player-session composition layer (the headless harness's *caller*, or the production client). | **Yes** — the run's canonical identity and the root of every derived id. |
| `runNumber` | The chronological, player-facing "Run #N". | Same composition layer (it may consult repository history — but see below). | No — display ordering only; two histories could disagree, `runId` cannot. |
| `seed` | The gameplay RNG seed, kept only as optional replay/debug metadata. | Gameplay. | **No.** The same seed is legitimately reused across many runs. |

**Rules:**

- `seed` is **never** a run identity. `runId = "run_<seed>"` is forbidden.
- `runId` is a stable unique token per run instance. This spec mandates no textual
  format (the repo has none today); `run-000001`-style is illustrative.
- The `AlmanacRecorder` **only accepts** a supplied `runId` / `runNumber`; it never
  generates or infers them, and it never reads the repository.
- Every composition-generated id derived from a run uses `runId`, never `seed`:
  `fightId = "<runId>:e<n>"`, `buildId = "<runId>:<phase>:<n>"`,
  `usageEventId = "<runId>:u<n>"`, `trainingEventId = "<runId>:t<n>"`.

**Cross-run example — same seed, two runs, fully separate history:**

```
Run #24                         Run #25
  runId      = run-000024         runId      = run-000025
  runNumber  = 24                 runNumber  = 25
  seed       = 12345              seed       = 12345   ← identical, irrelevant
  fight      run-000024:e0        fight      run-000025:e0
  build      run-000024:postReward:0   build run-000025:postReward:0
  usage      run-000024:u17       usage      run-000025:u4
  variant    instanceId entity-901
```

`run-000024` and `run-000025` are distinct `AlmanacRunRecord`s with disjoint derived
ids despite the shared seed. A `TechniqueVariant` minted in Run #24 keeps its own
`instanceId`; a same-family variant in Run #25 has a different `instanceId` and a
separate `AlmanacTechniqueRecord`.

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

- **run begin / end** — the caller-assigned `runId` (opaque, per-run-instance, never the
  seed) and `runNumber`, optional `seed` metadata, `lineageId`, `physiqueId`, timestamps,
  final `RunOutcome` (§1.4).
- **fight completion** — one call per resolved encounter, carrying an adapter-assigned
  `sequence` (0,1,2,… per run) so `fightId` is stable (§1.3, §5.3).
- **build snapshots** — at meaningful milestones, each with `phase` **and** an
  adapter-assigned per-`(run,phase)` `sequence` (§5.4).
- **technique discovery** — on first observation of a `TechniqueVariant` instance.
- **technique usage** — one call per performed technique action, carrying an
  `usageEventId` that satisfies the event-identity contract (§4.3).
- **training** — one call per completed training session.
- **item discovery** — on first observation of an item.
- **affix discovery** — *when affix identity exists* (v1: test-only).
- **lineage / physique** — as opaque strings on the run record (and echoed on build
  snapshots).
- **SP0b inspiration** — the `TechniqueVariantInspired` payload, verbatim (§6).

The adapter converts gameplay state into snapshots at the moment of observation. It never
hands the recorder a mutable component, entity, `PluginContext`, or event bus.

### 4.3 Event-identity contract for adapters

Every observation that feeds a **projection** (technique usage, affix discovery/usage,
training sessions) must carry an id that satisfies, in priority order:

1. **Prefer an existing stable source identity.** If the source system already exposes a
   durable id for the action/event (a persisted action id, a command id, …), the adapter
   uses it directly.
2. **Otherwise, a deterministic composition-assigned sequence.** The adapter maintains a
   monotonic per-run counter over the relevant event, in observation order.
3. **Replay-stable.** The *same* source event replayed through the *same* adapter must
   yield the *same* id (`ActionCompleted #17 → run-024:u17`, always).
4. **Distinctness.** A genuinely separate action must yield a different id
   (`ActionCompleted #18 → run-024:u18`).
5. **Never value-derived.** The id must not be `techniqueId + runNumber + result` or any
   other combination of mutable gameplay values.

This is *observation-order identity*, explicitly weaker than a *stable source-event
identity* — acceptable because it is deterministic for a fixed event stream and the
`AlmanacRecorder` only needs "is this the same observation I already consumed?". The
production `TomeClientAlmanacAdapter` is free to use its own mechanism (option 1 or 2);
it is **not** required to copy `HeadlessGameAlmanacBridge`'s counter implementation. The
recorder is agnostic to how the id was formed.

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
  | `AlmanacRunRecord.enemiesDefeated` | won `fights` in the run |
  | `AlmanacRunRecord.techniquesUsed` | `usageEventIds` across all technique records that carry this run's `runId` prefix |
  | `AlmanacRunRecord.trainingSessions` | `AlmanacRunRecord.trainingEventIds.length` |

  Every projection mutation is gated by an idempotent identity check: the recorder
  applies the increment/union **only** when the driving `usageEventId` / `affixEventId` /
  `trainingEventId` / `fightId` was not already consumed. Replayed observations —
  including across a save/load boundary, because the ledgers are persisted — change
  nothing.

Fields set at first observation (`discoveredRunId`, `discoveredRunNumber`,
`masteryAtDiscovery`, `descriptorIds`, `axisProfile`, `styleId`) are write-once: a later
event for the same `instanceId` **fills** still-unset fields but never overwrites a set
one. `origin` moves in one direction only — `base` → `inspired` — and never back,
whichever of `TechniqueVariantMinted` / `TechniqueVariantInspired` arrives first (§6).

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

- `AlmanacRunRecord { String runId; int runNumber; int? seed; String lineageId;
  String physiqueId; DateTime startedAt; DateTime? completedAt; RunOutcome outcome;
  List<AlmanacFightRecord> fights; List<String> discoveryIds;
  List<String> trainingEventIds; String? finalBuildId;
  int enemiesDefeated; int techniquesUsed; int trainingSessions }`
  — `runId` is the canonical per-run-instance identity; `runNumber` is display ordering;
  `seed` is optional replay/debug metadata and is **never** an identity (§1.4).
  `trainingEventIds` is the canonical per-run training ledger; the three trailing ints
  are projections (§5.1). Describes the run; never a replay save, never the mutable
  gameplay state.
- `AlmanacTechniqueRecord { String instanceId; String baseFamilyId; String? styleId;
  List<String> descriptorIds; Map<String, num> axisProfile; String? discoveredRunId;
  int? discoveredRunNumber; int? masteryAtDiscovery; List<String> usageEventIds;
  int totalUsage; List<int> runsUsed; TechniqueOrigin origin }`
  — keyed by `instanceId`; `usageEventIds` is the canonical ledger, `totalUsage` /
  `runsUsed` are its projections. Nullable discovery fields tolerate an `Inspired`-first
  provisional record later completed by `Minted` (§6). The base family never collapses
  distinct instances.
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
  **Discovery history and observation projections are separate axes:** encountering Iron
  Sword again adds no first-discovery row, yet its separate observation ids may still
  advance usage/discovery counters on the item/affix record. TechniqueVariant rows key on
  `"techniqueVariant:<instanceId>"` — a personalized variant is a distinct historical
  discovery and is **never** collapsed onto its base family.
- `AlmanacMilestoneRecord { String milestoneId; MilestoneType type; String runId;
  int runNumber; DateTime timestamp; String? contextId }`
  — `milestoneId` is a stable **fact** identity, not an event identity: `type.name`, or
  `"<type>:<contextId>"` for per-context firsts (`firstWinWithLineage:western`,
  `firstSuccessfulBuild:<finalBuildId>`). The first qualifying occurrence is canonical;
  every later qualifying event is ignored and never mutates the record — Run #4, #7, #9
  all winning Western still yield only `firstWinWithLineage:western → Run #4`. Milestone
  identity is never inferred from a mutable `buildId` **except** where the milestone
  definition explicitly intends a build-specific context (`firstSuccessfulBuild`, whose
  `contextId` is the run's `finalBuildId`).
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

### 5.8 Deep immutability

"Immutable record" here means **deeply immutable historical data**, not merely a class
with `final` fields. A `final List`/`Map` field can still alias a mutable gameplay
collection — that is forbidden.

```
Live gameplay state  ──copy at the observation boundary──▶  immutable Almanac value
```

**Invariant:**

> Once an Almanac record is accepted, later mutation of the adapter's source objects or
> of gameplay state cannot alter the historical record; and a caller mutating a value
> returned by `AlmanacQueries` cannot alter `AlmanacState`.

**Implementation expectation** (using the repo's existing conventions — no new
immutable-collections dependency; the package has none today):

- **Ingress:** the `AlmanacRecorder` defensively copies every incoming collection
  (`List<String>`, `List<T>`, `Map<String, num>`, `Map<String, Object?>`) before storing
  it, recursively for nested collections. Snapshot value objects (`TomeLayoutSnapshot`,
  `TechniqueInstanceSnapshot`, …) copy their own collection fields in their constructors.
- **Storage:** stored collections are treated as read-only; the recorder rebuilds rather
  than mutates when a projection changes.
- **Egress:** `AlmanacQueries` returns either deep copies or `List.unmodifiable` /
  `Map.unmodifiable` views, so query consumers cannot reach back into `AlmanacState`.
- **Adapters:** never hand the recorder a live component/entity collection — always a
  snapshot/copy taken at the moment of observation (§4.2).
- **Serialization round-trip** produces structurally-equal, still-isolated collections.

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

**Event ordering.** In the current engine an inspired variant emits
`TechniqueVariantMinted` **then** `TechniqueVariantInspired` (inspiration calls
`mintTechniqueVariant` internally — confirmed in `technique_inspiration.dart`). The
recorder is nonetheless order-independent — instance identity is authoritative, not
arrival order:

| Arrival | Recorder behaviour |
|---|---|
| `Minted` then `Inspired` (today's order) | `Minted` inserts `AlmanacTechniqueRecord(instanceId, origin: base, …)`; `Inspired` upserts `origin: inspired` in place and adds one `TechniqueInspirationHistory` keyed by `resultInstanceId`. |
| `Inspired` first | Create/complete a **provisional** `AlmanacTechniqueRecord` keyed by `instanceId` with `origin: inspired`, `baseFamilyId = familyId`, `descriptorIds` from the event; store the exact `TechniqueInspirationHistory` immediately. A later `Minted` **merges** into the same `instanceId` record, filling only still-unknown fields (e.g. `styleId`, `masteryAtDiscovery`, `discoveredRunNumber`); it never downgrades `origin` back to `base` and never overwrites the ancestry. |
| Only one of the two ever arrives | The record persists with whatever historical payload was received. Missing fields stay absent (`null` / empty) — the recorder never fabricates defaults, never re-runs inspiration, never calls RNG, never queries the Technique plugin. |

> **Invariant:** event ordering may vary; the `TechniqueVariant` `instanceId` remains the
> authoritative key, and the `TechniqueVariantInspired` payload is authoritative for
> ancestry regardless of when it arrives. Re-delivery of either event changes nothing.

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
| `beginRun({runId, runNumber, seed?, lineageId, physiqueId, startedAt})` | upsert an open `AlmanacRunRecord` by the **caller-supplied** `runId` (`outcome` provisional `abandoned`, `completedAt` null). The recorder never generates `runId`/`runNumber` and never reads the repository. |
| `recordFight({runId, sequence, name, enemyId, won, playerHealthAfter, turnsUsed})` | build `fightId = "<runId>:e<sequence>"`; append to that run's `fights` **iff** `fightId` absent; bump `enemiesDefeated` projection iff newly appended and `won` |
| `recordBuildSnapshot(AlmanacBuildRecord)` | `buildId` already `"<runId>:<phase>:<sequence>"`; upsert by `buildId`; compute `dna` if `dna.tokens` empty |
| `recordTechniqueDiscovered({instanceId, baseFamilyId, styleId, descriptorIds, axisProfile, origin, masteryAtDiscovery, runId, runNumber})` | create-or-merge `AlmanacTechniqueRecord` by `instanceId`: fill only still-unset fields, never downgrade `origin` from `inspired` to `base` (§6); emit a `techniqueVariant` discovery row keyed `"techniqueVariant:<instanceId>"` |
| `recordTechniqueUsed({instanceId, runId, runNumber, usageEventId})` | **iff** `usageEventId` not in that record's `usageEventIds`: add it, `totalUsage++`, add `runNumber` to `runsUsed` if absent, bump the run's `techniquesUsed` projection |
| `recordTechniqueInspired({resultInstanceId, runId, familyId, descriptorIds, inspirerInstanceIds})` | upsert `TechniqueInspirationHistory` by `resultInstanceId` (verbatim, never overwritten); create-or-merge the `instanceId` technique record (provisional if no `Minted` yet — `baseFamilyId = familyId`, `descriptorIds` from the event), set `origin → inspired` (§6) |
| `recordItemDiscovered({definitionId, instanceId, runId, runNumber, snapshot})` | emit an `item` discovery row keyed `"item:<definitionId>"` (first occurrence immutable) |
| `recordAffixDiscovered({affixId, affixEventId, runId, runNumber, lineageId, snapshot})` | upsert `AlmanacAffixRecord` by `affixId`; **iff** `affixEventId` not in `discoveryEventIds`: add it, `timesDiscovered++`, set `firstDiscoveredRunId` once, union `lineageId`; emit an `affix` discovery row |
| `recordAffixUsed({affixId, affixEventId, runNumber})` | **iff** `affixEventId` not in `usageEventIds`: add it, `timesUsed++` |
| `recordTrainingSession({runId, runNumber, trainingEventId})` | **iff** `trainingEventId` not in `runs[runId].trainingEventIds`: add it, bump `trainingSessions` projection |
| `recordDiscovery(AlmanacDiscoveryRecord)` | generic upsert by `discoveryId` (the typed methods delegate here); on first write also append `discoveryId` to `runs[runId].discoveryIds` if absent |
| `recordMilestone({type, runId, runNumber, timestamp, contextId})` | upsert by `milestoneId` (`type.name` or `"<type>:<contextId>"`); first write canonical |
| `evaluateStandardMilestones({runId, runNumber, outcome, lineageId, finalBuildId, timestamp})` | derive and record the standard firsts (§7.3) |
| `completeRun({runId, completedAt, outcome, finalBuildId})` | close the run record by `runId`; projections already maintained incrementally |

### 7.2 Identity keys (the full set)

| Record / projection input | Key |
|---|---|
| run | `runId` (caller-supplied, opaque, per-run-instance — never `seed`; §1.4) |
| fight | `fightId = "<runId>:e<sequence>"` |
| build snapshot | `buildId = "<runId>:<phase>:<sequence>"` |
| technique history | `instanceId` |
| technique-usage projection | `usageEventId` (stored in `AlmanacTechniqueRecord.usageEventIds`) |
| inspiration | `resultInstanceId` |
| discovery row | `"<type>:<contentId>"` (variant rows: `"techniqueVariant:<instanceId>"`) |
| affix history | `affixId` |
| affix discovery/usage projection | `affixEventId` (stored in the affix record's ledgers) |
| training projection | `trainingEventId` (stored in `AlmanacRunRecord.trainingEventIds`) |
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
  consumed-identity ledger (`AlmanacTechniqueRecord.usageEventIds`,
  `AlmanacAffixRecord.discoveryEventIds` / `usageEventIds`,
  `AlmanacRunRecord.trainingEventIds` / `discoveryIds`) and every identity field (`seed`,
  `sequence`, `fightId`, `buildId`).
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

**BuildDna is a derived projection, not an identity.**

| Concept | Role |
|---|---|
| `AlmanacBuildRecord` | the canonical historical build snapshot |
| `buildId` (`"<runId>:<phase>:<sequence>"`) | the snapshot's **canonical identity** |
| `BuildDna` | a deterministic classification *describing* the snapshot |

Therefore:

- `BuildDna.signature != buildId`. DNA is never a uniqueness key and never dedups a
  snapshot.
- `BuildDna` is fully recomputable from the stored snapshot at any time.
- Changing the DNA algorithm in a future schema version reclassifies snapshots but does
  **not** invalidate any `buildId` or alter any snapshot's canonical fields.
- The recorder computes `dna` once at ingest for query convenience; it is stored, not
  authoritative.

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

`almanac == null` (and no `runId`/`runNumber`): no subscriptions, no snapshots,
byte-identical to today. Determinism and existing harness tests are unaffected because
the recorder can reach neither `rng` nor `policy`.

**`runGame` never owns persistent identity and never touches the repository.** The
caller / player-session composition layer assigns identity and constructs the bridge:

```dart
// composition layer (a test, a CI balance job, or a future harness driver) —
// NOT inside runGame:
final events = EventBus();
final runId = allocateRunId();          // opaque, unique per run instance (§1.4)
final runNumber = playerSession.nextRunNumber();  // may consult repo history HERE
final bridge = HeadlessGameAlmanacBridge(
  recorder,
  runId: runId,
  runNumber: runNumber,
  seed: seed,               // replay/debug metadata only
)..attach(events);          // subscribes to the same bus runGame will publish on
final result = runGame(seed, policy: policy, almanac: recorder, eventBus: events);
repo.save(recorder.state);
```

Two coherent wirings are permitted; this spec adopts the first:

1. **Preferred (adopted):** `runGame` stays gameplay-only. It takes `AlmanacRecorder?
   almanac` and an `EventBus`; the composition layer builds `HeadlessGameAlmanacBridge`
   with `runId` / `runNumber` / `seed` and attaches it to that bus. `runGame` never sees
   `runId`.
2. **Alternative:** `runGame` additionally accepts explicit `String? runId` / `int?
   runNumber` and forwards them to an internally-constructed bridge. Still forbidden:
   `runGame` deriving `runNumber` from `repo.load().runs.length + 1` or otherwise reading
   the repository.

Either way: `runNumber` is caller-assigned; `runId` is unique per run instance; `seed`
is optional metadata; `runGame` never derives identity from repository history.

### 11.1 Bridge-assigned identities

The bridge owns three per-run counters, all incremented in observation order:

| Counter | Incremented on | Feeds |
|---|---|---|
| `encounterSeq` | each `EncounterStarted` | `recordFight(sequence: …)` on the matching `EncounterResolved` |
| `buildSeq[phase]` | each build snapshot it takes for `phase` | `AlmanacBuildRecord.sequence` |
| `usageSeq` | each `ActionCompleted` it attributes to a technique instance | `usageEventId = "<runId>:u<usageSeq>"` |
| `trainingSeq` | each `TrainingResultRecorded` | `trainingEventId = "<runId>:t<trainingSeq>"` |

All derived ids are rooted at the injected **`runId`**, never `seed` (§1.4). They are
deterministic for a fixed event stream, so the same run replayed through the bridge with
the same `runId` produces an identical `AlmanacState`. Per §4.3 this is observation-order
identity: the headless `ActionCompleted` carries no durable id of its own, so the bridge
supplies one; a production adapter may instead use a stable source id.

### 11.2 Event → recorder map (existing events only — no new events)

| Event (source) | Recorder call |
|---|---|
| run start — the bridge, once it has observed the run's style + physique (early, from the harness's existing `PhysiqueAssigned` / style signals), using its injected identity | `beginRun(runId: <injected>, runNumber: <injected>, seed: <injected>, lineageId: martialTraditionOf(styleId) ?? styleId, physiqueId: physiqueId, startedAt: …)` |
| `TomeChanged` (harness) `stepName == 'starting'` | `recordBuildSnapshot(phase: initial, sequence: 0)` |
| `TechniqueVariantMinted` (technique) | `recordTechniqueDiscovered(origin: base, …)` |
| `TechniqueVariantInspired` (technique) | `recordTechniqueInspired(…)` — upserts `origin: inspired`, adds ancestry |
| `SubjectDiscovered` (Core) subj `technique:*` / `item:*` | `recordDiscovery(type: technique | item)` |
| `ActionCompleted` (combat) with `action.sourceRef.instanceEntityId != null` and `referenceType == techniqueReferenceType` | `recordTechniqueUsed(usageEventId: "<runId>:u<usageSeq++>")` — the same attribution `combat_stage.dart` already does for SP0b |
| `EncounterStarted` (harness) | `encounterSeq++` (no recorder call) |
| `EncounterResolved` (harness) | `recordFight(sequence: encounterSeq-1, …)` |
| `RewardSelected` (harness) | `recordBuildSnapshot(phase: postReward, sequence: buildSeq['postReward']++)` |
| `TrainingResultRecorded` (harness) | `recordTrainingSession(trainingEventId: "<runId>:t<trainingSeq++>")`; `recordBuildSnapshot(phase: postTraining, sequence: buildSeq['postTraining']++)` |
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
  out-of-repo `TomeClientAlmanacAdapter`; identity-not-values idempotency; `runId` ≠
  `seed` ≠ `runNumber` (§1.4) and that the recorder never generates identity or reads the
  repository; canonical history vs. derived projections; deep immutability (§5.8) —
  copy-in / unmodifiable-out; `BuildDna` as a derived projection, not an identity;
  event-order-independent inspiration merge by `instanceId`; immutable-history &
  rebalance-resilience; serialization boundary + schema version; query API; the
  `TechniqueVariantInspired` / SP0b relationship; the ContentRegistry relationship; why
  Almanac owns no gameplay state; a "Save State ≠ Almanac History" subsection.
- `CHANGELOG.md` — entry under a new dated heading.

---

## 13. Test plan

### 13.1 Unit — `test/plugins/almanac/`

| File | Proves |
|---|---|
| `almanac_models_test.dart` | immutability; per-record `toJson`/`fromJson` round-trips including `seed`, `sequence`, `fightId`/`buildId`, and every ledger (`usageEventIds`, affix `discoveryEventIds`/`usageEventIds`, `trainingEventIds`, `discoveryIds`) |
| `almanac_recorder_test.dart` | begin/complete run; multiple runs stay separate; same event twice → no duplicate; projections match their ledgers |
| `almanac_run_identity_test.dart` | `beginRun` twice with the **same `seed`** but different `runId` → **2** distinct `AlmanacRunRecord`s; their derived ids (`<runId>:e0`, `<runId>:postReward:0`, `<runId>:u0`, `<runId>:t0`) are disjoint across the two runs; `seed` is stored but never keys anything; `run-000024` vs `run-000025` from §1.4 |
| `almanac_fight_identity_test.dart` | two `Bandit` / `5`-turn fights in one run → **2** `AlmanacFightRecord`s (distinct `fightId` via `sequence`); replaying either `EncounterResolved` observation → still **2**; `enemiesDefeated` projection counts each win once |
| `almanac_build_snapshot_test.dart` | `postReward` sequence `0` and `1` remain separate records; replaying either → no duplicate; Tome layout (dims + slots + instance ids) preserved; mutating a fake definition afterward leaves the stored snapshot unchanged (rebalance) |
| `almanac_technique_usage_test.dart` | same `usageEventId` delivered twice → `totalUsage` +1, `runsUsed` unchanged; two distinct `usageEventId`s → `totalUsage` +2; idempotency survives a `save`→`load` performed **between** the two deliveries |
| `almanac_inspiration_test.dart` | synthetic `TechniqueVariantInspired` → `inspirerInstanceIds` preserved exactly and in order; deliver it twice → **one** `TechniqueInspirationHistory` and **one** `AlmanacTechniqueRecord`; **both orderings** — `Minted`→`Inspired` **and** `Inspired`→`Minted` — yield one technique history with `origin: inspired` and correct ancestry; a lone `Inspired` (no `Minted`) still stores full ancestry with no fabricated fields; ancestry never recomputed / no RNG |
| `almanac_cross_run_identity_test.dart` | same `baseFamilyId` in two runs with two different `TechniqueVariant` instance ids → **two** `AlmanacTechniqueRecord`s |
| `almanac_immutability_test.dart` | after a record is accepted, mutating the source `List`/`Map` the adapter passed → record unchanged; mutating a `List`/`Map` returned by `AlmanacQueries` → `AlmanacState` unchanged; a serialization round-trip yields structurally-equal but still-isolated collections |
| `almanac_affix_test.dart` | `recordAffixDiscovered` with 3 distinct `affixEventId`s for one `affixId` → one record, `timesDiscovered == 3`, lineages unioned; repeat an `affixEventId` → unchanged |
| `almanac_lineage_test.dart` | run records lineage; `getRunsForLineage` / `lineageStatistics` correct and derived-only |
| `almanac_serialization_test.dart` | save→load equivalent for `InMemory` and `JsonFile` (temp file); **every identity/ledger field from this revision** (`seed`, `sequence`, `fightId`, `buildId`, `usageEventIds`, affix ledgers, `trainingEventIds`, `discoveryIds`) survives; schema-version mismatch throws |
| `almanac_queries_test.dart` | same state → identical, order-stable query results |
| `almanac_build_dna_test.dart` | same snapshot → same `signature`; reordered inputs → same `signature`; changed inputs → different `signature`; `signature != buildId`; changing the DNA inputs/algorithm does **not** change any `buildId` |
| `almanac_milestone_identity_test.dart` | Run #4, #7, #9 all win Western → exactly one `firstWinWithLineage:western` pointing at Run #4; the later runs never mutate it; replay of a qualifying event adds nothing |
| `almanac_architecture_test.dart` | §12.1 |

### 13.2 Production integration boundary — `test/plugins/almanac/almanac_adapter_parity_test.dart`

A synthetic second adapter (standing in for `TomeClientAlmanacAdapter`) feeds the **same**
`AlmanacRecorder` an observation sequence equivalent to a harness run — same `runId`,
same fight sequences, same `usageEventId`s, same `TechniqueVariantInspired` payload. The
resulting `AlmanacState` is equal to the one produced by `HeadlessGameAlmanacBridge` for
that run. Proves the recorder contract is adapter-agnostic and the client is a drop-in
producer of the same primitives.

### 13.3 Integration — `test/integration/almanac_run_history_test.dart`

- 3 runs (each with its own composition-assigned `runId`, differing seeds/policies) →
  3 distinct `AlmanacRunRecord`s; discoveries and final builds captured; lineage/physique
  preserved.
- **Same seed, two different `runId`s** → two fully separate run records whose derived
  `fightId` / `buildId` / `usageEventId` / `trainingEventId` sets are disjoint; neither
  run's history leaks into the other.
- Same seed + same policy + **same `runId`** replayed through the bridge → equivalent
  `AlmanacState` (bridge counters are deterministic for a fixed event stream).
- Whole-chronicle serialization round-trips (`AlmanacSerialization` +
  `JsonFileAlmanacRepository`).
- `almanac == null` path: `RunResult` byte-identical to a run without the parameter;
  `runGame` performs no `repo.load()` / `repo.save()` of its own.

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
3. recorder + identity-keyed idempotency + recorder / run-identity / fight-identity / build-snapshot / usage / inspiration (both orderings) / affix / cross-run / milestone-identity / deep-immutability tests
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
| 8 | How is SP0b inspiration ancestry preserved? | `TechniqueVariantInspired` payload stored verbatim in `TechniqueInspirationHistory` keyed by `resultInstanceId`; no re-resolution, no re-query, no RNG. **Either** `Minted`→`Inspired` **or** `Inspired`→`Minted` merges onto one `AlmanacTechniqueRecord` by `instanceId`, `origin: inspired`, ancestry authoritative regardless of arrival order; missing fields stay absent, never fabricated. §6. |
| 9 | How does historical data survive content rebalance? | Every record embeds a resolved snapshot captured at observation time; `definitionId` is a reference for linking only, never the source of a displayed value; reconstruction never resolves the current `ContentRegistry`. §5.5. |
| 10 | How are architecture boundaries enforced? | `almanac/` imports Core only; one bridge file is the sole dual-importer in-repo; new + extended substring-scan architecture tests assert no plugin imports `almanac.dart` / `plugins/almanac/` and Core imports no `almanac.dart`. §3, §12. |
| 11 | How is run identity kept independent of the seed? | `runId` is an opaque per-run-instance token assigned by the caller / player-session composition; `seed` is optional replay metadata that never keys anything (`runId = "run_<seed>"` is forbidden); `runNumber` is caller-assigned display ordering. The recorder accepts all three, generates none, and never reads the repository; `runGame` never derives identity from repository history. Every derived id roots at `runId`. §1.4, §11. |
| 12 | Is `BuildDna` an identity? | No. `buildId` is the snapshot's canonical identity; `BuildDna` is a deterministic classification *of* the snapshot, recomputable from it, and `signature != buildId`. Changing the DNA algorithm never invalidates a `buildId`. §10. |
| 13 | What guarantees deep immutability? | Copy-in at the recorder / snapshot-constructor boundary; unmodifiable-or-copied out of `AlmanacQueries`; adapters pass only snapshots, never live collections. Mutating a source or a query result cannot alter `AlmanacState`. §5.8. |

---

## 16. Acceptance criteria

- [ ] Almanac is a standalone composition-layer module; Core stays game-agnostic.
- [ ] Both `HeadlessGameAlmanacBridge` (in-repo) and the `TomeClientAlmanacAdapter` contract feed one shared `AlmanacRecorder`; the client adapter implementation stays out of `build_engine`.
- [ ] No Combat → Almanac, Technique → Almanac, MartialArts → Almanac, or Training → Almanac dependency; no circular dependency; `build_engine` does not depend on the client.
- [ ] `runId` ≠ `seed` ≠ `runNumber`: `runId` is a caller-assigned opaque per-run-instance token, `seed` is optional metadata that keys nothing, `runNumber` is caller-assigned ordering. The recorder generates no identity and never reads the repository; `runGame` never queries `repo`. Same seed + two `runId`s → two disjoint histories.
- [ ] Every composition-derived id (`fightId`, `buildId`, `usageEventId`, `trainingEventId`) roots at `runId`, never `seed`.
- [ ] Deep immutability: mutating an adapter's source `List`/`Map` after recording, or a `List`/`Map` returned by `AlmanacQueries`, cannot alter `AlmanacState`; round-trip collections stay isolated.
- [ ] `BuildDna` is a derived projection, not an identity; `signature != buildId`; a DNA-algorithm change invalidates no `buildId`.
- [ ] Inspiration recording is event-order-independent — `Minted`→`Inspired` and `Inspired`→`Minted` both merge onto one `instanceId` record with authoritative ancestry and no fabricated fields.
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
