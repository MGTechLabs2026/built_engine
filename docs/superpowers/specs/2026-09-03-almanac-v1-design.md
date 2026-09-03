# Almanac v1 — Persistent Player History — design

**Date:** 2026-09-03
**Status:** draft — implementation-ready pending review (rev 3)
**Repo:** `build_engine` (`Tome:RougelikeGame`)
**Depends on:** SP0a (technique instancing), SP0b (technique inspiration — `TechniqueVariantInspired`)
**Touches:** `lib/src/plugins/game/game_run.dart` (one opt-in parameter, default off)

> **Revision note (2026-09-03, rev 3):** rev 1 resolved client integration and made
> fight / build-snapshot / technique-usage identity composition-assigned (the engine
> emits none) and separated canonical history from derived projections. Rev 2 finalized
> `runId` ≠ `seed` ≠ `runNumber` (§1.4), deep immutability (§5.8), the adapter
> event-identity contract (§4.3), order-independent inspiration merge (§6), and `BuildDna`
> as a projection not an identity (§10). **Rev 3** (this revision):
>
> - makes **all ids explicitly opaque** — never parsed (`split`/`startsWith`/prefix/
>   regex) to recover a relationship (§1.5), with an architecture-test guard (§12.1);
> - **removes relational dependence on id parsing** — every relationship is an explicit
>   stored field (§1.3 table, §7.2);
> - makes **usage / affix / training observations explicitly carry run identity** as
>   relational records `TechniqueUsageObservation` / `AffixObservation` /
>   `TrainingObservation` (§5.6.1); `techniquesUsed for X = count where o.runId == X`;
> - defines **canonical history as identity-stable and monotonic** — completion vs.
>   overwrite, the UNKNOWN→KNOWN→FINAL model, and `AlmanacIntegrityException` on a
>   contradiction (§5.1, §5.1.1);
> - **classifies every field** write-once / monotonic / append-only / derived projection
>   (§5.1);
> - sets the **idempotency uniqueness domain** — `(runId, usageEventId)` etc., global id
>   uniqueness not assumed (§7.2);
> - adds tests for all of the above (§13.1).
>
> No scope growth; SP0b ancestry semantics unchanged (§6); client/harness boundary
> unchanged (§4).

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

| Record | Identity key | Explicit relational fields (authoritative) | Identity source |
|---|---|---|---|
| Run | `runId` | `runNumber`, `seed?` | **composition** — opaque per-run-instance id, never the seed (§1.4) |
| Fight | `(runId, fightId)` | `runId`, `sequence` | **composition** — the engine emits no encounter id |
| Build snapshot | `(runId, buildId)` | `runId`, `phase`, `sequence` | **composition** — one `(run, phase)` may recur |
| Technique history | `instanceId` (`TechniqueVariant` entity id) | — | domain — instance identity |
| Technique-usage observation | `(runId, usageEventId)` (§7.2) | `runId`, `runNumber`, `instanceId` | **composition** — `ActionCompleted` carries none (§4.3) |
| Inspiration ancestry | `resultInstanceId` | `runId` | domain — instance identity |
| Discovery (first-seen) | `discoveryId` | `type`, `contentId`, `runId`, `runNumber`, `instanceId?` | domain — content identity |
| Affix history | `affixId` | — | domain — content identity (test-only wiring in v1) |
| Affix discovery/usage observation | `(affixId, affixEventId)` | `affixId`, `runId`, `runNumber`, `lineageId?` | **composition** |
| Milestone | `milestoneId` | `type`, `contextId?` | domain — fact identity |

Every "identity key" cell is an **opaque token** compared only for whole-string equality
(§1.5). Where a key is written as a pair — `(runId, usageEventId)` — both members are
stored as their own fields and both are matched; the recorder never parses one out of the
other. `HeadlessGameAlmanacBridge`'s readable id formats (`"<runId>:e<n>"`, …) are a
convenience of that one adapter, not a contract: they are deterministic for a fixed event
stream so a replayed run yields byte-identical state, but a production adapter may emit
wholly unrelated tokens and the recorder behaves identically.

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
- A composition layer *may* format a derived id from `runId` for its own readability —
  `HeadlessGameAlmanacBridge` uses `"<runId>:e<n>"`, `"<runId>:<phase>:<n>"`,
  `"<runId>:u<n>"`, `"<runId>:t<n>"` — but per §1.5 the recorder never relies on that
  shape. A production adapter is free to emit unrelated tokens (`action-8f3a91`).

### 1.5 IDs are opaque tokens

> **Every Almanac id is an opaque identifier. Its textual format carries no semantic
> meaning and is never parsed — by split, prefix/`startsWith`, regex, or any other
> means — to recover a relationship.**

Applies to `runId`, `fightId`, `buildId`, `usageEventId`, `trainingEventId`,
`affixEventId`, `discoveryId`, `milestoneId`, `instanceId`, and `resultInstanceId`.

Consequences:

- Structured, human-readable id formats (`"run-000024:postReward:1"`) are allowed for
  composition-side convenience. Their components are **not** semantically recoverable
  from the string.
- Every relationship an id might appear to encode is instead carried as an **explicit
  field** that is authoritative: a build snapshot stores `buildId` **and** `runId` +
  `phase` + `sequence` as separate data; a usage observation stores `usageEventId`
  **and** `runId` + `runNumber` + `instanceId` (§5.6.1); a milestone stores
  `milestoneId` **and** `type` + `contextId`.
- The recorder compares whole id strings for equality only. It never does
  `buildId.split(':')`, `usageEventId.startsWith(runId)`, or `discoveryId` component
  extraction.

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

Every class is a value object — all fields `final`, no setters, `const` constructor where
possible, module-local `toJson()` / `fromJson(Map<String, dynamic>)` over plain maps (the
`Container.toJson` / `CombatantComponent.toJson` precedent — no engine-wide serialization
framework). `DateTime` ↔ ISO-8601 string. A record is never mutated in place; the
recorder produces a **new** instance when it completes a field or appends to a ledger
(§5.1), and that instance's collections are copies that never alias gameplay state
(§5.8).

### 5.1 Canonical history vs. derived projections

The Almanac is **not** a full event store (task §6 — "avoid a huge event-sourcing
system"). It has three layers:

**1. Canonical facts — identity-stable and monotonic.**

> A canonical Almanac fact has a stable identity (§1.3, §1.5) and evolves only
> monotonically. A record may be *completed* by later observations when information
> arrives out of order, but an established value is never replaced by a conflicting one,
> nothing is ever deleted, and no value is ever recomputed from current content.

The canonical records are `AlmanacRunRecord`, `AlmanacFightRecord`, `AlmanacBuildRecord`,
`AlmanacDiscoveryRecord`, `TechniqueInspirationHistory`, `AlmanacMilestoneRecord`, and
the **observation ledgers** — lists of small relational records, not bare id strings:

| Ledger | Element |
|---|---|
| `AlmanacTechniqueRecord.usageObservations` | `TechniqueUsageObservation { usageEventId, runId, runNumber, instanceId }` (§5.6.1) |
| `AlmanacAffixRecord.discoveryObservations` | `AffixObservation { affixEventId, runId, runNumber, lineageId? }` |
| `AlmanacAffixRecord.usageObservations` | `AffixObservation { affixEventId, runId, runNumber, lineageId? }` |
| `AlmanacRunRecord.trainingObservations` | `TrainingObservation { trainingEventId, runId, runNumber }` |
| `AlmanacRunRecord.discoveryIds` | `discoveryId` strings (the run→discovery link; each `AlmanacDiscoveryRecord` also stores its own `runId`) |

Each observation **carries its own `runId`** so every relationship is an explicit field,
never recovered by parsing the id (§1.5).

**2. Monotonic update model.** Every field is one of:

```
UNKNOWN ──fill──▶ KNOWN ──(monotonic upgrade only)──▶ FINAL
```

| Class | Fields | An observation may | An observation may **not** |
|---|---|---|---|
| **Write-once** | `discoveredRunId`, `discoveredRunNumber`, `masteryAtDiscovery`, `descriptorIds`, `axisProfile`, `styleId`, `TechniqueInspirationHistory` payload, every embedded snapshot, run `lineageId` / `physiqueId` / `seed` / `startedAt`, `completedAt` / `outcome` (set at `completeRun`) | set it while `UNKNOWN` | overwrite it once `KNOWN`; a conflicting later value is an **integrity failure** (§5.1.1), not a silent replace |
| **Monotonic** | `origin` (`base` → `inspired` only) | advance it along the allowed direction | move it backward |
| **Append-only ledger** | `usageObservations` (technique), `discoveryObservations` / `usageObservations` (affix), `trainingObservations`, `discoveryIds`, `fights` | add a previously-unseen element (keyed as below) | remove or mutate an existing element |
| **Derived projection** | see layer 3 | be recomputed | be an independent source of truth |

An out-of-order completion is a *fill*, not a *replace*: e.g. `Inspired` before `Minted`
sets `origin: inspired` and the ancestry; the later `Minted` fills `styleId` /
`masteryAtDiscovery` / `discoveredRunNumber` while they are still `UNKNOWN` and leaves
`origin` alone (§6).

**3. Derived projections** — recorder-maintained for query convenience, fully
recomputable from layer 1, never independent history:

| Projection | Recomputed as |
|---|---|
| `AlmanacTechniqueRecord.totalUsage` | `usageObservations.length` |
| `AlmanacTechniqueRecord.runsUsed` | distinct `o.runNumber` over `usageObservations` |
| `AlmanacAffixRecord.timesDiscovered` | `discoveryObservations.length` |
| `AlmanacAffixRecord.timesUsed` | `usageObservations.length` |
| `AlmanacAffixRecord.associatedLineageIds` | union of `o.lineageId` over `discoveryObservations` |
| `AlmanacAffixRecord.firstDiscoveredRunId` | `o.runId` of the `discoveryObservations` element with the smallest `runNumber` |
| `AlmanacRunRecord.enemiesDefeated` | count of won `fights` |
| `AlmanacRunRecord.techniquesUsed` | count of `TechniqueUsageObservation`s across all technique records where `o.runId == this.runId` |
| `AlmanacRunRecord.trainingSessions` | `trainingObservations.length` |

Every ledger append and projection bump is gated by an **idempotency key**: an
observation is consumed only if that key is not already present. Keys:
`(runId, usageEventId)` for technique usage, `(affixId, affixEventId)` for affix
observations, `(runId, trainingEventId)` for training, `fightId` within a run for fights,
`discoveryId` for first-seen discoveries. Because the ledgers are part of `AlmanacState`
and are serialized, replay — including across a save/load boundary — changes nothing.

#### 5.1.1 Contradiction handling

If an observation would overwrite an established **write-once** value with a different
one (`descriptorIds` was `[A, B]`, a later event for the same `instanceId` carries
`[A, C]`), the recorder:

- keeps the first established value;
- does **not** apply the conflicting value;
- raises a deterministic `AlmanacIntegrityException` (or records an integrity-failure
  marker where the caller has opted to collect rather than throw) identifying the record,
  field, established value, and rejected value.

This is a fail-fast integrity check, not a recovery or merge system. In normal operation
(consistent adapter, monotonic completion) it never fires.

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
  final String fightId;          // OPAQUE token (bridge: "<runId>:e<sequence>")
  final String runId;            // explicit, authoritative
  final int sequence;            // adapter-assigned, per run, 0-based, observation order
  final String name;
  final String enemyId;
  final bool won;
  final num playerHealthAfter;
  final int turnsUsed;
}
```

No gameplay property participates in identity. Two fights with identical `name`,
`enemyId`, and `turnsUsed` are two records because their `sequence` (and the adapter's
`fightId`) differ. Idempotency: the recorder appends a fight to `runs[runId].fights` only
if no element there already has this `fightId` — `fightId` compared as a whole string,
`runId` taken from the explicit field, never parsed out of `fightId` (§1.5).

The engine emits no encounter id (`EncounterStarted`/`EncounterResolved` in
`run_events.dart` carry `name` + `enemyId` only, no index). The adapter assigns
`sequence` by counting `EncounterStarted` (or the client's equivalent) per run.

### 5.4 `AlmanacBuildRecord` — stable snapshot identity

```dart
class AlmanacBuildRecord {
  final String buildId;         // OPAQUE token (bridge: "<runId>:<phase>:<sequence>")
  final String runId;           // explicit, authoritative
  final BuildPhase phase;       // explicit, authoritative
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

A build snapshot is a historical observation of a build at a specific milestone, not live
Tome state (§5.8 — its collections never alias gameplay state). One run may legitimately
produce `initial`, `postReward#0`, `postReward#1`, `postTraining#0`, `postTraining#1`,
`finalBuild` — the `sequence` keeps `postReward#0` and `postReward#1` as distinct
records. A second snapshot never overwrites an earlier one that shares a `BuildPhase`.
Idempotency: dedup on the **`(runId, buildId)` pair** — both stored as explicit fields
and compared structurally (a value key), never concatenated into one string and never
parsed apart (§1.3, §1.5). So the same `buildId` string under two different `runId`s is
two records. A repeat `(runId, buildId)` carrying **different** contents is a
contradiction → `AlmanacIntegrityException` (§5.1.1); a byte-identical repeat is a
silent no-op.

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
  List<TrainingObservation> trainingObservations; String? finalBuildId;
  int enemiesDefeated; int techniquesUsed; int trainingSessions }`
  — `runId` is the canonical per-run-instance identity; `runNumber` is display ordering;
  `seed` is optional replay/debug metadata and is **never** an identity (§1.4).
  `trainingObservations` is the canonical per-run training ledger; the three trailing
  ints are projections (§5.1). Describes the run; never a replay save, never the mutable
  gameplay state.
- `AlmanacTechniqueRecord { String instanceId; String baseFamilyId; String? styleId;
  List<String> descriptorIds; Map<String, num> axisProfile; String? discoveredRunId;
  int? discoveredRunNumber; int? masteryAtDiscovery;
  List<TechniqueUsageObservation> usageObservations;
  int totalUsage; List<int> runsUsed; TechniqueOrigin origin }`
  — keyed by `instanceId`; `usageObservations` is the canonical ledger (each element
  carries its own `runId` / `runNumber`, §5.6.1), `totalUsage` / `runsUsed` are its
  projections. Nullable discovery fields tolerate an `Inspired`-first provisional record
  later completed by `Minted` (§6). The base family never collapses distinct instances.
- `TechniqueInspirationHistory { String resultInstanceId; String runId; String familyId;
  List<String> descriptorIds; List<String> inspirerInstanceIds }`
  — stored exactly as emitted by `TechniqueVariantInspired` (§6). Never recomputed.
- `AlmanacAffixRecord { String affixId; List<AffixObservation> discoveryObservations;
  List<AffixObservation> usageObservations; int timesDiscovered; int timesUsed;
  String? firstDiscoveredRunId; List<String> associatedLineageIds; AffixSnapshot snapshot }`
  — `discoveryObservations` / `usageObservations` are canonical (each carries its own
  `runId` / `runNumber` / `lineageId?`, §5.6.1); `timesDiscovered`, `timesUsed`,
  `firstDiscoveredRunId`, and `associatedLineageIds` are **derived projections** (§5.1)
  recomputed from those ledgers, never independently authored. `snapshot` is a write-once
  historical snapshot.
- `AlmanacDiscoveryRecord { String discoveryId; AlmanacDiscoveryType type;
  String contentId; String? instanceId; String runId; int runNumber; DateTime timestamp;
  DiscoverySnapshot snapshot }`
  — the recorder forms `discoveryId` for its own dedup (the bridge uses
  `"<type>:<contentId>"`, or `"techniqueVariant:<instanceId>"`), but `type`, `contentId`,
  `runId`, and `instanceId` are all **explicit fields** — never parsed back out of
  `discoveryId` (§1.5). The record is write-once (§5.1); a later encounter of the same
  content adds no row (it feeds the technique/item/affix ledgers instead).
  **Discovery history and observation projections are separate axes:** encountering Iron
  Sword again adds no first-discovery row, yet its separate observation ids may still
  advance usage/discovery counters on the item/affix record. TechniqueVariant rows key on
  `"techniqueVariant:<instanceId>"` — a personalized variant is a distinct historical
  discovery and is **never** collapsed onto its base family.
- `AlmanacMilestoneRecord { String milestoneId; MilestoneType type; String runId;
  int runNumber; DateTime timestamp; String? contextId }`
  — `milestoneId` is a stable **fact** identity, not an event identity. The recorder
  forms it from `type` and (where the milestone is per-context) `contextId` — both kept
  as **explicit fields**, never parsed back out of `milestoneId` (§1.5). The first
  qualifying occurrence is canonical (write-once, §5.1); every later qualifying event is
  ignored and never mutates the record — Run #4, #7, #9 all winning Western still yield
  only one `firstWinWithLineage` / `contextId = western` → Run #4. `contextId` is a
  `buildId` only for `firstSuccessfulBuild`, where a build-specific context is the
  milestone's intent.
- `AlmanacFightRecord` — §5.3. `AlmanacBuildRecord` — §5.4.
- `BuildDna { List<String> tokens; String signature }` — §10.

#### 5.6.1 Observation records

Each is an immutable value object carrying its identity **and** its relational fields, so
the recorder never parses one from the other (§1.5):

- `TechniqueUsageObservation { String usageEventId; String runId; int runNumber;
  String instanceId }` — one performed technique action. Idempotency key
  `(runId, usageEventId)` (§7.2). `techniquesUsed for run X = count where o.runId == X`.
- `AffixObservation { String affixEventId; String runId; int runNumber;
  String? lineageId }` — one affix discovery *or* one affix use (the two ledgers are
  separate). Idempotency key `(affixId, affixEventId)`.
- `TrainingObservation { String trainingEventId; String runId; int runNumber }` — one
  completed training session. Idempotency key `(runId, trainingEventId)`; the containing
  `AlmanacRunRecord` also fixes the run.

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

This is the **value-aliasing** guarantee, orthogonal to the monotonic-completion rule of
§5.1: a record may still be *completed* (unset → set) or have a ledger *appended* by a
later observation, but no already-stored value — scalar or collection element — is ever
mutated in place, and no stored collection ever aliases mutable gameplay state. A
`final List`/`Map` field that aliases a live gameplay collection is forbidden.

```
Live gameplay state  ──copy at the observation boundary──▶  isolated Almanac value
```

**Invariant:**

> Once a value is stored in an Almanac record, later mutation of the adapter's source
> objects or of gameplay state cannot alter it; a caller mutating a value returned by
> `AlmanacQueries` cannot alter `AlmanacState`. (Later *observations* may still fill an
> unset field or append a new ledger element per §5.1 — that is completion, not
> mutation.)

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

This is monotonic completion (§5.1), not overwrite. If a second `Minted` / `Inspired`
for the same `instanceId` carries a **conflicting** write-once value — a different
`descriptorIds`, `axisProfile`, `styleId`, or a different `inspirerInstanceIds` /
`descriptorIds` on the ancestry — the recorder keeps the first established value and
raises `AlmanacIntegrityException` (§5.1.1). It never silently replaces stored ancestry
or stored discovery fields.

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
| `recordFight({runId, fightId, sequence, name, enemyId, won, playerHealthAfter, turnsUsed})` | append `AlmanacFightRecord` to `runs[runId].fights` **iff** no element there already has this `fightId`; bump `enemiesDefeated` projection iff newly appended and `won`. `fightId` is the adapter's opaque token; `runId` + `sequence` are the authoritative relational fields. |
| `recordBuildSnapshot(AlmanacBuildRecord)` | upsert by `buildId` (whole-string match); the record's own `runId` / `phase` / `sequence` are authoritative; compute `dna` if `dna.tokens` empty |
| `recordTechniqueDiscovered({instanceId, baseFamilyId, styleId, descriptorIds, axisProfile, origin, masteryAtDiscovery, runId, runNumber})` | create-or-**complete** `AlmanacTechniqueRecord` by `instanceId`: fill only `UNKNOWN` fields, advance `origin` `base`→`inspired` only, raise `AlmanacIntegrityException` on a conflicting write-once value (§5.1.1); emit a `techniqueVariant` discovery row |
| `recordTechniqueUsed(TechniqueUsageObservation o)` | **iff** no element of that record's `usageObservations` has key `(o.runId, o.usageEventId)`: append `o`; recompute `totalUsage` / `runsUsed`; bump `runs[o.runId].techniquesUsed` |
| `recordTechniqueInspired({resultInstanceId, runId, familyId, descriptorIds, inspirerInstanceIds})` | upsert `TechniqueInspirationHistory` by `resultInstanceId`; if it already exists with a **different** payload → `AlmanacIntegrityException` (never overwrite); create-or-complete the `instanceId` technique record (provisional if no `Minted` yet), advance `origin → inspired` (§6) |
| `recordItemDiscovered({definitionId, instanceId, runId, runNumber, snapshot})` | emit an `item` discovery row keyed on the recorder-formed `discoveryId` (write-once) |
| `recordAffixDiscovered(AffixObservation o, {affixId, snapshot})` | upsert `AlmanacAffixRecord` by `affixId`; **iff** no element of `discoveryObservations` has key `(affixId, o.affixEventId)`: append `o`; recompute `timesDiscovered`, `firstDiscoveredRunId` (first by `runNumber`), `associatedLineageIds`; emit an `affix` discovery row |
| `recordAffixUsed(AffixObservation o, {affixId})` | **iff** no element of `usageObservations` has key `(affixId, o.affixEventId)`: append `o`; recompute `timesUsed` |
| `recordTrainingSession(TrainingObservation o)` | **iff** no element of `runs[o.runId].trainingObservations` has key `(o.runId, o.trainingEventId)`: append `o`; recompute `trainingSessions` |
| `recordDiscovery(AlmanacDiscoveryRecord)` | generic upsert by `discoveryId` (the typed methods delegate here); on first write also append `discoveryId` to `runs[record.runId].discoveryIds` if absent |
| `recordMilestone({type, runId, runNumber, timestamp, contextId})` | recorder forms `milestoneId` from `type` + `contextId`; first write canonical; a later qualifying event is a no-op |
| `evaluateStandardMilestones({runId, runNumber, outcome, lineageId, finalBuildId, timestamp})` | derive and record the standard firsts (§7.3) |
| `completeRun({runId, completedAt, outcome, finalBuildId})` | complete the run record by `runId` (`completedAt` / `outcome` were `UNKNOWN`); projections already maintained incrementally |

### 7.2 Identity keys (the full set — every key an opaque token, §1.5)

| Record / projection input | Idempotency key | Authoritative relational fields |
|---|---|---|
| run | `runId` | `runNumber`, `seed?` |
| fight | `(runId, fightId)` — `fightId` scoped within `runs[runId].fights` | `runId`, `sequence` |
| build snapshot | `(runId, buildId)` | `runId`, `phase`, `sequence` |
| technique history | `instanceId` | — |
| technique-usage observation | `(runId, usageEventId)` | `runId`, `runNumber`, `instanceId` |
| inspiration | `resultInstanceId` | `runId` |
| discovery row | `discoveryId` | `type`, `contentId`, `runId`, `instanceId?` |
| affix history | `affixId` | — |
| affix discovery/usage observation | `(affixId, affixEventId)` | `affixId`, `runId`, `runNumber`, `lineageId?` |
| training observation | `(runId, trainingEventId)` | `runId`, `runNumber` |
| milestone | `milestoneId` | `type`, `contextId?` |

Keys are matched by **whole-string equality only**; a pair key means both members are
stored as fields and both are compared — the recorder never parses one from the other.
Counts (`totalUsage`, `timesUsed`, `timesDiscovered`, `enemiesDefeated`,
`techniquesUsed`, `trainingSessions`) and sets (`runsUsed`, `associatedLineageIds`,
`firstDiscoveredRunId`) are **projections** — recomputed from the observation ledgers,
never an independent source of truth. Because the ledgers are part of `AlmanacState` and
are serialized, replay across a save/load boundary changes nothing.

**Uniqueness domain.** An adapter-provided event id must be unique *within the
domain the recorder consumes it in*. The recorder therefore keys technique usage on
`(runId, usageEventId)`, affix observations on `(affixId, affixEventId)`, and training on
`(runId, trainingEventId)` — it does **not** assume globally unique event ids. If a
production source guarantees global uniqueness, the pair key is simply stricter than
needed and still correct.

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
  observation ledger with its per-element relational fields
  (`AlmanacTechniqueRecord.usageObservations`,
  `AlmanacAffixRecord.discoveryObservations` / `usageObservations`,
  `AlmanacRunRecord.trainingObservations` / `discoveryIds`) and every identity field
  (`seed`, `sequence`, `fightId`, `buildId`, each observation's `runId` / `runNumber`).
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
| `buildId` (opaque; bridge formats it as `"<runId>:<phase>:<sequence>"`) | the snapshot's **canonical identity**, with `runId` / `phase` / `sequence` also stored as explicit fields (§1.5) |
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

The bridge owns four per-run counters, all incremented in observation order, and stamps
each observation with the injected `runId` / `runNumber` as **explicit fields** (not by
embedding them in the id — §1.5):

| Counter | Incremented on | Feeds | Id string the bridge forms (opaque to the recorder) |
|---|---|---|---|
| `encounterSeq` | each `EncounterStarted` | `AlmanacFightRecord.sequence` + `fightId` | `"<runId>:e<encounterSeq>"` |
| `buildSeq[phase]` | each build snapshot it takes for `phase` | `AlmanacBuildRecord.sequence` + `buildId` | `"<runId>:<phase>:<buildSeq>"` |
| `usageSeq` | each attributed `ActionCompleted` | `TechniqueUsageObservation.usageEventId` | `"<runId>:u<usageSeq>"` |
| `trainingSeq` | each `TrainingResultRecorded` | `TrainingObservation.trainingEventId` | `"<runId>:t<trainingSeq>"` |

The id strings are a readability convenience of *this* adapter; the recorder treats them
as opaque and relies on the explicit `runId` / `sequence` / `instanceId` fields alongside
them (§1.5, §4.3). They are deterministic for a fixed event stream, so the same run
replayed through the bridge with the same `runId` produces an identical `AlmanacState`. A
production adapter may emit unrelated tokens (`action-8f3a91`) and the recorder behaves
identically because it keys usage on `(runId, usageEventId)`, not on the string's shape.

### 11.2 Event → recorder map (existing events only — no new events)

| Event (source) | Recorder call |
|---|---|
| run start — the bridge, once it has observed the run's style + physique (early, from the harness's existing `PhysiqueAssigned` / style signals), using its injected identity | `beginRun(runId: <injected>, runNumber: <injected>, seed: <injected>, lineageId: martialTraditionOf(styleId) ?? styleId, physiqueId: physiqueId, startedAt: …)` |
| `TomeChanged` (harness) `stepName == 'starting'` | `recordBuildSnapshot(phase: initial, sequence: 0)` |
| `TechniqueVariantMinted` (technique) | `recordTechniqueDiscovered(origin: base, …)` |
| `TechniqueVariantInspired` (technique) | `recordTechniqueInspired(…)` — upserts `origin: inspired`, adds ancestry |
| `SubjectDiscovered` (Core) subj `technique:*` / `item:*` | `recordDiscovery(type: technique | item)` |
| `ActionCompleted` (combat) with `action.sourceRef.instanceEntityId != null` and `referenceType == techniqueReferenceType` | `recordTechniqueUsed(TechniqueUsageObservation(usageEventId: "<runId>:u<usageSeq++>", runId, runNumber, instanceId))` — the same attribution `combat_stage.dart` already does for SP0b |
| `EncounterStarted` (harness) | `encounterSeq++` (no recorder call) |
| `EncounterResolved` (harness) | `recordFight(fightId: "<runId>:e<encounterSeq-1>", runId, sequence: encounterSeq-1, …)` |
| `RewardSelected` (harness) | `recordBuildSnapshot(AlmanacBuildRecord(buildId: …, runId, phase: postReward, sequence: buildSeq['postReward']++, …))` |
| `TrainingResultRecorded` (harness) | `recordTrainingSession(TrainingObservation(trainingEventId: "<runId>:t<trainingSeq++>", runId, runNumber))`; `recordBuildSnapshot(… phase: postTraining, sequence: buildSeq['postTraining']++ …)` |
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
- `almanac_recorder.dart` and `almanac_queries.dart` contain no `.split(` and no
  `.startsWith(` — a lightweight guard that no id string is parsed to recover a
  relationship (§1.5); relational data is always read from an explicit field.
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
  out-of-repo `TomeClientAlmanacAdapter`; identity-not-values idempotency; **all ids are
  opaque tokens — never parsed; relational data is always an explicit field** (§1.5);
  `runId` ≠ `seed` ≠ `runNumber` (§1.4) and that the recorder never generates identity or
  reads the repository; **canonical facts are identity-stable and monotonic** — completion
  vs. overwrite, the write-once / monotonic / append-only / projection field classes, and
  `AlmanacIntegrityException` on a contradiction (§5.1); observation ledgers of
  relational records (`TechniqueUsageObservation`, `AffixObservation`,
  `TrainingObservation`); derived projections recomputable from those ledgers; deep
  value-aliasing immutability (§5.8); `BuildDna` as a derived projection, not an identity;
  event-order-independent inspiration merge by `instanceId`; rebalance-resilience;
  serialization boundary + schema version; query API; the `TechniqueVariantInspired` /
  SP0b relationship; the ContentRegistry relationship; why Almanac owns no gameplay
  state; a "Save State ≠ Almanac History" subsection.
- `CHANGELOG.md` — entry under a new dated heading.

---

## 13. Test plan

### 13.1 Unit — `test/plugins/almanac/`

| File | Proves |
|---|---|
| `almanac_models_test.dart` | immutability; per-record `toJson`/`fromJson` round-trips including `seed`, `sequence`, `fightId`/`buildId`, and every observation ledger with its per-element `runId`/`runNumber`/`lineageId?` (`usageObservations`, affix `discoveryObservations`/`usageObservations`, `trainingObservations`, `discoveryIds`) |
| `almanac_recorder_test.dart` | begin/complete run; multiple runs stay separate; same event twice → no duplicate; every projection equals a fresh recompute from its ledger |
| `almanac_id_opacity_test.dart` | recorder behaves identically whether ids are structured (`"run-000024:u17"`) or arbitrary opaque tokens (`"action-8f3a91"`): usage still associates to the correct run **via the observation's explicit `runId`**, never by string inspection; a fabricated `usageEventId` that *textually* contains a different `runId` is still bound to the `runId` field passed with it |
| `almanac_run_identity_test.dart` | `beginRun` twice with the **same `seed`** but different `runId` → **2** distinct `AlmanacRunRecord`s; each run's observation ledgers stay disjoint (matched on `(runId, eventId)`), even if the two runs reuse the *same* opaque `usageEventId` string; `seed` is stored but never keys anything; `run-000024` vs `run-000025` from §1.4 |
| `almanac_fight_identity_test.dart` | two `Bandit` / `5`-turn fights in one run (adapter `sequence` 0 and 1) → **2** `AlmanacFightRecord`s; replaying either `EncounterResolved` observation → still **2**; `enemiesDefeated` projection counts each win once |
| `almanac_build_snapshot_test.dart` | `postReward` sequence `0` and `1` remain separate records; replaying either → no duplicate; Tome layout (dims + slots + instance ids) preserved; mutating a fake definition afterward leaves the stored snapshot unchanged (rebalance) |
| `almanac_technique_usage_test.dart` | two `TechniqueUsageObservation`s with **different opaque `usageEventId`s, same `runId`** → `totalUsage` +2, `runsUsed` has that run once; **same opaque `usageEventId` replayed** → counts once; a `save`→`load` performed **between** the two deliveries does not change the outcome; `techniquesUsed for run X` = count of observations with `o.runId == X` (no string parsing) |
| `almanac_usage_uniqueness_domain_test.dart` | the **same opaque `usageEventId` string** delivered under **two different `runId`s** → **two** distinct usage observations (key is `(runId, usageEventId)`); global uniqueness is never assumed |
| `almanac_monotonic_completion_test.dart` | `Minted`→`Inspired` **and** `Inspired`→`Minted` both yield **one** coherent `AlmanacTechniqueRecord` (`origin: inspired`, ancestry present, discovery fields filled once available); a lone `Inspired` leaves later-arriving fields `UNKNOWN`, never fabricated |
| `almanac_contradiction_test.dart` | a second event for the same `instanceId` with a **conflicting** write-once value (`descriptorIds` `[A,B]` then `[A,C]`; or a different `inspirerInstanceIds`) → established value retained, **`AlmanacIntegrityException` raised**, no silent overwrite; a second build snapshot for an existing `buildId` with different contents → same |
| `almanac_inspiration_test.dart` | synthetic `TechniqueVariantInspired` → `inspirerInstanceIds` preserved exactly and in order; deliver it twice → **one** `TechniqueInspirationHistory` and **one** `AlmanacTechniqueRecord`; ancestry never recomputed / no RNG / no Technique-state query |
| `almanac_cross_run_identity_test.dart` | same `baseFamilyId` in two runs with two different `TechniqueVariant` instance ids → **two** `AlmanacTechniqueRecord`s |
| `almanac_immutability_test.dart` | after a value is stored, mutating the source `List`/`Map` the adapter passed → record unchanged; mutating a `List`/`Map` returned by `AlmanacQueries` → `AlmanacState` unchanged; a serialization round-trip yields structurally-equal but still-isolated collections; a valid later *completion* (unset→set, ledger append) is allowed and is not a mutation |
| `almanac_affix_test.dart` | 3 `AffixObservation`s with distinct opaque `affixEventId`s for one `affixId` → one record, `timesDiscovered == 3`, `associatedLineageIds` unioned from each observation's `lineageId`; repeat an `affixEventId` → unchanged |
| `almanac_lineage_test.dart` | run records lineage; `getRunsForLineage` / `lineageStatistics` correct and derived-only |
| `almanac_serialization_test.dart` | save→load equivalent for `InMemory` and `JsonFile` (temp file); **every field from this revision** (`seed`, `sequence`, `fightId`, `buildId`, all observation ledgers with their `runId`/`runNumber`/`lineageId?` elements, `discoveryIds`) survives; schema-version mismatch throws |
| `almanac_queries_test.dart` | same state → identical, order-stable query results |
| `almanac_build_dna_test.dart` | same snapshot → same `signature`; reordered inputs → same `signature`; changed inputs → different `signature`; `signature != buildId`; changing the DNA inputs/algorithm does **not** change any `buildId` |
| `almanac_milestone_identity_test.dart` | Run #4, #7, #9 all win Western → exactly one milestone (`type = firstWinWithLineage`, `contextId = western`) pointing at Run #4; later runs never mutate it; replay of a qualifying event adds nothing; identity built from explicit `type` + `contextId`, not parsed from `milestoneId` |
| `almanac_architecture_test.dart` | §12.1 |

### 13.2 Production integration boundary — `test/plugins/almanac/almanac_adapter_parity_test.dart`

A synthetic second adapter (standing in for `TomeClientAlmanacAdapter`) feeds the **same**
`AlmanacRecorder` an observation sequence equivalent to a harness run — same `runId`,
same fight/build `sequence`s, same `(runId, usageEventId)` keys, same
`TechniqueVariantInspired` payload — but is also run once with **arbitrary opaque** event
ids (`"action-…"`) carrying the same explicit `runId`/`runNumber` fields. Both feeds
produce an `AlmanacState` equal to the one `HeadlessGameAlmanacBridge` produces for that
run. Proves the recorder contract is adapter-agnostic and independent of id string shape.

### 13.3 Integration — `test/integration/almanac_run_history_test.dart`

- 3 runs (each with its own composition-assigned `runId`, differing seeds/policies) →
  3 distinct `AlmanacRunRecord`s; discoveries and final builds captured; lineage/physique
  preserved.
- **Same seed, two different `runId`s** → two fully separate run records; their fight,
  build, usage, and training observation ledgers stay disjoint because every element is
  matched on its explicit `(runId, …)` key, not on the id string.
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

1. domain model — records, snapshots, observation records (`TechniqueUsageObservation` /
   `AffixObservation` / `TrainingObservation`), enums, `AlmanacState` — + serialization
   + model tests
2. repository (in-memory + `dart:io` file) + serialization tests
3. recorder + monotonic-completion / `(runId, eventId)` idempotency / `AlmanacIntegrityException`
   + recorder / run-identity / id-opacity / usage-uniqueness-domain / fight-identity /
   build-snapshot / monotonic-completion / contradiction / inspiration / affix / cross-run /
   milestone-identity / deep-immutability tests
4. queries + build DNA + their tests
5. `HeadlessGameAlmanacBridge` + `runGame` opt-in parameter + adapter-parity + integration tests
6. architecture tests (incl. no-`.split`/`.startsWith` guard) + `ARCHITECTURE.md` +
   `CHANGELOG.md` + `lib/almanac.dart` barrel

Each commit builds and tests green on its own.

---

## 15. Design questions answered

| # | Question | Answer |
|---|---|---|
| 1 | How does the actual Tome client feed Almanac? | Through `TomeClientAlmanacAdapter` in the **client repo**, calling the same `AlmanacRecorder` public API (`lib/almanac.dart`) with primitive/snapshot value objects. No Almanac code moves into the client; the client never exposes mutable gameplay internals to the recorder. §4. |
| 2 | How does the headless harness feed Almanac? | Through `HeadlessGameAlmanacBridge` (`lib/src/plugins/game/almanac_bridge.dart`), subscribed to the harness `EventBus`, wired by an opt-in `AlmanacRecorder?` param on `runGame`. §11. |
| 3 | What is the stable identity of a fight? | The pair `(runId, fightId)` — both stored as explicit fields, plus `sequence`. `fightId` is an **opaque** token the adapter forms (`HeadlessGameAlmanacBridge` uses `"<runId>:e<sequence>"`); the recorder never parses it. Never `(name, enemyId, turnsUsed)`. §1.3, §1.5, §5.3. |
| 4 | What is the stable identity of a build snapshot? | The opaque `buildId`, with `runId` / `phase` / `sequence` also stored as explicit fields; repeated `postReward`/`postTraining` states get distinct `sequence`s and never overwrite. §1.3, §1.5, §5.4. |
| 5 | How is usage-event idempotency guaranteed? | Each usage is a `TechniqueUsageObservation { usageEventId, runId, runNumber, instanceId }` appended to `AlmanacTechniqueRecord.usageObservations` only if no element already has key **`(runId, usageEventId)`** (global uniqueness is not assumed). `totalUsage` / `runsUsed` are recomputed from that ledger. Serialized, so replay across save/load is a no-op. §5.1, §5.6.1, §7.1–§7.2. |
| 6 | Which data is canonical history? | The identity-stable, monotonic records (run, fight, build, discovery, inspiration, milestone) **plus** the observation ledgers of relational records (`usageObservations`, affix `discoveryObservations` / `usageObservations`, `trainingObservations`). §5.1. |
| 7 | Which values are derived projections? | `totalUsage`, `runsUsed`, affix `timesDiscovered` / `timesUsed` / `associatedLineageIds` / `firstDiscoveredRunId`, run `enemiesDefeated` / `techniquesUsed` / `trainingSessions` — each recomputed from an observation ledger (e.g. `techniquesUsed for X = count of usage observations with `o.runId == X`), never parsed from an id, never an independent source of truth. §5.1. |
| 8 | How is SP0b inspiration ancestry preserved? | `TechniqueVariantInspired` payload stored verbatim in `TechniqueInspirationHistory` keyed by `resultInstanceId`; no re-resolution, no re-query, no RNG. **Either** `Minted`→`Inspired` **or** `Inspired`→`Minted` completes one `AlmanacTechniqueRecord` by `instanceId` (`origin` monotonically `base`→`inspired`); ancestry authoritative regardless of arrival order; unset fields stay `UNKNOWN`, never fabricated; a conflicting later payload raises `AlmanacIntegrityException`. §5.1.1, §6. |
| 9 | How does historical data survive content rebalance? | Every record embeds a resolved snapshot captured at observation time; `definitionId` is a reference for linking only, never the source of a displayed value; reconstruction never resolves the current `ContentRegistry`. §5.5. |
| 10 | How are architecture boundaries enforced? | `almanac/` imports Core only; one bridge file is the sole dual-importer in-repo; new + extended substring-scan architecture tests assert no plugin imports `almanac.dart` / `plugins/almanac/` and Core imports no `almanac.dart`. §3, §12. |
| 11 | How is run identity kept independent of the seed? | `runId` is an opaque per-run-instance token assigned by the caller / player-session composition; `seed` is optional replay metadata that never keys anything (`runId = "run_<seed>"` is forbidden); `runNumber` is caller-assigned display ordering. The recorder accepts all three, generates none, and never reads the repository; `runGame` never derives identity from repository history. Every derived id roots at `runId`. §1.4, §11. |
| 12 | Is `BuildDna` an identity? | No. `buildId` is the snapshot's canonical identity; `BuildDna` is a deterministic classification *of* the snapshot, recomputable from it, and `signature != buildId`. Changing the DNA algorithm never invalidates a `buildId`. §10. |
| 13 | What guarantees deep immutability? | Copy-in at the recorder / snapshot-constructor boundary; unmodifiable-or-copied out of `AlmanacQueries`; adapters pass only snapshots, never live collections. Mutating a source or a query result cannot alter `AlmanacState`. A valid later completion (unset→set, ledger append) is not a mutation. §5.8. |
| 14 | Are Almanac ids ever parsed? | No. Every id (`runId`, `fightId`, `buildId`, `usageEventId`, `trainingEventId`, `affixEventId`, `discoveryId`, `milestoneId`, `instanceId`) is opaque and compared only for whole-string equality. Every relationship is an explicit field stored alongside the id; the recorder does no `split` / `startsWith` / prefix / regex extraction, and an architecture test guards it. §1.5, §7.2, §12.1. |
| 15 | What happens on a contradictory observation? | Established write-once values are retained, the conflicting value is rejected, and `AlmanacIntegrityException` is raised (or an integrity-failure marker collected). No merge, no recovery system, no silent overwrite. In consistent operation it never fires. §5.1.1. |
| 16 | Must adapter event ids be globally unique? | No. They must be unique only within the domain the recorder keys them in: `(runId, usageEventId)`, `(affixId, affixEventId)`, `(runId, trainingEventId)`. The same opaque string under two `runId`s is two observations. §7.2. |

---

## 16. Acceptance criteria

- [ ] Almanac is a standalone composition-layer module; Core stays game-agnostic.
- [ ] Both `HeadlessGameAlmanacBridge` (in-repo) and the `TomeClientAlmanacAdapter` contract feed one shared `AlmanacRecorder`; the client adapter implementation stays out of `build_engine`.
- [ ] No Combat → Almanac, Technique → Almanac, MartialArts → Almanac, or Training → Almanac dependency; no circular dependency; `build_engine` does not depend on the client.
- [ ] `runId` ≠ `seed` ≠ `runNumber`: `runId` is a caller-assigned opaque per-run-instance token, `seed` is optional metadata that keys nothing, `runNumber` is caller-assigned ordering. The recorder generates no identity and never reads the repository; `runGame` never queries `repo`. Same seed + two `runId`s → two disjoint histories.
- [ ] **All ids are opaque tokens** — never parsed (`split` / `startsWith` / prefix / regex); every relationship is an explicit field, guarded by an architecture test.
- [ ] Usage / affix / training observations are relational records (`{eventId, runId, runNumber, …}`); idempotency keys are `(runId, usageEventId)` / `(affixId, affixEventId)` / `(runId, trainingEventId)` — global id uniqueness is not assumed.
- [ ] `techniquesUsed` (and every other projection) is recomputed from an observation ledger by comparing explicit fields, never by parsing an id string.
- [ ] **Canonical facts are identity-stable and monotonic**: later observations may fill an `UNKNOWN` field, append a new ledger element, or advance `origin` `base`→`inspired`; a conflicting write-once value is retained and raises `AlmanacIntegrityException` (no silent overwrite, no recovery system).
- [ ] Write-once / monotonic / append-only / derived-projection field classes are explicit in the model and docs.
- [ ] Deep immutability: mutating an adapter's source `List`/`Map` after recording, or a `List`/`Map` returned by `AlmanacQueries`, cannot alter `AlmanacState`; a valid later completion is not a mutation; round-trip collections stay isolated.
- [ ] `BuildDna` is a derived projection, not an identity; `signature != buildId`; a DNA-algorithm change invalidates no `buildId`.
- [ ] Inspiration recording is event-order-independent — `Minted`→`Inspired` and `Inspired`→`Minted` both complete one `instanceId` record with authoritative ancestry and no fabricated fields.
- [ ] Fight identity is `(runId, fightId)` + `sequence`, never gameplay values; two identical-looking fights stay two records; replay adds none.
- [ ] Build-snapshot identity is `buildId` with explicit `runId`/`phase`/`sequence`; repeated `postReward`/`postTraining` snapshots stay distinct; replay adds none.
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
