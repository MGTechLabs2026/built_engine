# Almanac v1 — Persistent Player History — design

**Date:** 2026-09-03
**Status:** draft — awaiting review
**Repo:** `build_engine` (`Tome:RougelikeGame`)
**Depends on:** SP0a (technique instancing), SP0b (technique inspiration — `TechniqueVariantInspired`)
**Touches:** `lib/src/plugins/game/game_run.dart` (one opt-in parameter, default off)

---

## 1. Why this exists

The engine can already *run* a game — a headless harness (`runGame`) drives
an endless survival loop, and a separate client owns the shipped run flow.
Neither keeps anything once a run ends. `RunResult` is a per-run snapshot
that the caller throws away.

The Almanac is the **chronicle of the player's martial journey across all
runs**. It answers questions the running game cannot:

> What happened in Run #24? What build did I use? Which techniques did I
> discover? Where did this TechniqueVariant come from — which previous
> techniques inspired it? Which affixes have I relied on? Which lineage do
> I play most? Which builds keep recurring? What have I discovered across
> my entire history?

It is **not** a gameplay system, progression authority, combat system,
reward system, or content database. It observes domain events and records
immutable history. It never drives gameplay.

### 1.1 The one hard rule

```
Gameplay → Domain Events → Almanac Recorder → Persistent History → Client Queries
```

The arrow only points right. The Almanac never modifies combat, training,
Tome, or RNG state; never decides rewards, lineage, or technique
evolution; never mints a `TechniqueVariant`; and is never a gameplay
dependency of any plugin.

### 1.2 Save State ≠ Almanac History

Save state is the *current mutable game state* — where the run is right
now, restorable. Almanac history is *what the player experienced* —
append-only, immutable, resilient to content rebalance. They are separate
concerns with separate serialization. A future content patch that changes
Iron Sword from `Attack +3` to `Attack +2` must not rewrite the Run #12
record that says `Attack +3`.

---

## 2. Scope

### 2.1 In scope

- New composition-layer module `lib/src/plugins/almanac/` (non-registrable,
  the `build_interpretation/` / `game/` pattern — sits on top of Core, not
  a `GamePlugin`).
- Immutable domain model: run / build / technique / inspiration / affix /
  discovery / milestone records, plus the snapshots they embed.
- `AlmanacRecorder` — a passive observer that folds primitive/snapshot
  inputs into an `AlmanacState` with idempotent upserts.
- `AlmanacRepository` (interface + in-memory + `dart:io` file-backed) and
  `AlmanacSerialization` (state ↔ Map ↔ JSON string, schema version 1).
- `AlmanacQueries` — read-only query API over an `AlmanacState`.
- `buildDna(...)` — a deterministic normalized build signature.
- `lib/src/plugins/game/almanac_bridge.dart` — the wiring that translates
  existing domain events into recorder calls, plus one opt-in
  `AlmanacRecorder?` parameter on `runGame` (default `null` ⇒ zero
  behaviour change).
- New architecture tests; extensions to
  `test/integration/architecture_dependency_test.dart`; `ARCHITECTURE.md`
  and `CHANGELOG.md` updates.

### 2.2 Out of scope (explicit — no scope creep)

Achievements, quests, meta-progression bonuses, unlock trees, player
leveling, cloud sync, a database backend, Devvit / itch.io integration,
Flutter / Flame UI, AI or ML build clustering, automatic human-readable
build naming, and any Magic / Alchemy / Cultivation almanac. SP0a / SP0b
technique mechanics are not redesigned.

### 2.3 Deliberate v1 limitations (honesty over completeness — spec §27)

| Area | Engine reality today | v1 decision |
|---|---|---|
| **Lineage identity** | No `LineageDefinition`. "Lineage" = MartialArts tradition (`western`/`eastern`) + style (`martial_styles.dart`). | Almanac stores `lineageId` as an **opaque string** supplied by the composition layer. It hardcodes no hierarchy and derives lineage aggregates from run records. |
| **Affix identity** | No `AffixDefinition`, no affix ids, no `AffixDiscovered` event. Affixes are `ItemInstance.statBonuses` (stat→value maps). | `AlmanacAffixRecord` + queries + serialization are **fully implemented and unit-tested**, but **no run wires affix recording** — `recordAffixDiscovered(...)` exists and is exercised only by tests. Wiring lands when the engine gains affix identity. |
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
  almanac_recorder.dart        observes → AlmanacState; idempotent upserts
  almanac_queries.dart         read-only query API
  almanac_build_dna.dart       deterministic build signature
lib/almanac.dart               public barrel
lib/src/plugins/game/almanac_bridge.dart   harness wiring (top-of-graph)
```

**Dependency direction:**

```
Core
  ↓
Gameplay Plugins (technique, item, combat, martial_arts, physique, …)
  ↓
Composition Layer (lib/src/plugins/game/  — incl. almanac_bridge.dart)
  ↓
Almanac (lib/src/plugins/almanac/)
```

- `almanac/` imports **Core only** (`package:build_engine/build_engine.dart`)
  plus `dart:convert` and, in `almanac_file_repository.dart` only,
  `dart:io`. It never imports `technique_plugin.dart`, `item_plugin.dart`,
  `martial_arts_plugin.dart`, `combat_plugin.dart`, `physique_plugin.dart`,
  `build_interpretation.dart`, or `game.dart`.
- `almanac_bridge.dart` (under `plugins/game/`, already top-of-graph) is the
  **only** file that imports both a gameplay plugin barrel and Almanac. It
  subscribes to existing events and calls the recorder with primitives.
- **All IDs in Almanac models are `String`.** The wiring stringifies
  `EntityId.value`. The persistent format never couples to `EntityId`'s
  representation, and cross-run instance ids stay stable opaque tokens.

This mirrors how `TechniqueVariantInspired` consumers are meant to work
(spec §16–17): the plugin emits the event; a composition layer routes it.

---

## 4. Domain model — `almanac_models.dart`

Every class: immutable, `const` constructor, module-local `toJson()` /
`fromJson(Map<String, dynamic>)` returning/taking plain maps (the
`Container.toJson` / `CombatantComponent.toJson` precedent — no
engine-wide serialization framework). `DateTime` ↔ ISO-8601 string.

### 4.1 Enums

| Enum | Values |
|---|---|
| `RunOutcome` | `won`, `lost`, `abandoned` |
| `TechniqueOrigin` | `base`, `evolved`, `inspired` (only `base`/`inspired` produced in v1) |
| `BuildPhase` | `initial`, `postReward`, `postTraining`, `finalBuild` |
| `AlmanacDiscoveryType` | `technique`, `techniqueVariant`, `item`, `affix`, `lineage` |
| `MilestoneType` | `firstRun`, `firstVictory`, `firstTechniqueVariant`, `firstInspiredTechnique`, `firstAffix`, `firstWinWithLineage`, `firstSuccessfulBuild` |

### 4.2 Snapshots (self-contained historical values — survive rebalance)

- `TechniqueInstanceSnapshot { String instanceId; String baseFamilyId;
  String? styleId; List<String> descriptorIds; Map<String, num> axisProfile;
  TechniqueOrigin origin; int masteryAtSnapshot }`
- `ItemInstanceSnapshot { String definitionId; String? instanceId;
  int itemClass; Map<String, num> statBonuses;
  Map<String, num> resolvedProperties }`
- `AffixSnapshot { String affixId; String stat; num value; String? category }`
- `TomeSlotSnapshot { String slotId; String occupantKind /* technique |
  item | empty */; String? occupantRefId; String? instanceId }`
- `TomeLayoutSnapshot { int? width; int? height;
  List<TomeSlotSnapshot> slots }` — `width`/`height` null ⇒ named-slot
  container. Preserves grid dimensions, slot arrangement, component
  identity, and technique instance identity (spec §7).
- `BuildPerformanceSnapshot { int fightsWon; int fightsLost;
  int enemiesDefeated; num? avgTurnsUsed }`
- `DiscoverySnapshot { String label; Map<String, Object?> values }`

### 4.3 Records

- `AlmanacFightRecord { String name; String enemyId; bool won;
  num playerHealthAfter; int turnsUsed }`
- `AlmanacRunRecord { String runId; int runNumber; String lineageId;
  String physiqueId; DateTime startedAt; DateTime? completedAt;
  RunOutcome outcome; List<AlmanacFightRecord> fights;
  List<String> discoveryIds; String? finalBuildId; int enemiesDefeated;
  int techniquesUsed; int trainingSessions }`
  — describes the run; never a replay save, never the mutable gameplay
  state.
- `AlmanacBuildRecord { String buildId; String runId; BuildPhase phase;
  String lineageId; String physiqueId;
  List<TechniqueInstanceSnapshot> techniques;
  List<ItemInstanceSnapshot> items; List<AffixSnapshot> affixes;
  TomeLayoutSnapshot tome; BuildPerformanceSnapshot? performance;
  BuildDna dna }`
- `AlmanacTechniqueRecord { String instanceId; String baseFamilyId;
  String? styleId; List<String> descriptorIds; Map<String, num> axisProfile;
  String? discoveredRunId; int? discoveredRunNumber; int masteryAtDiscovery;
  int totalUsage; List<int> runsUsed; TechniqueOrigin origin }`
  — keyed by `instanceId`; the base family never collapses distinct
  instances.
- `TechniqueInspirationHistory { String resultInstanceId; String runId;
  String familyId; List<String> descriptorIds;
  List<String> inspirerInstanceIds }`
  — exact attribution from `TechniqueVariantInspired`, stored verbatim.
- `AlmanacAffixRecord { String affixId; int timesDiscovered; int timesUsed;
  String? firstDiscoveredRunId; List<String> associatedLineageIds;
  AffixSnapshot snapshot }`
- `AlmanacDiscoveryRecord { String discoveryId; AlmanacDiscoveryType type;
  String contentId; String? instanceId; String runId; int runNumber;
  DateTime timestamp; DiscoverySnapshot snapshot }`
- `AlmanacMilestoneRecord { String milestoneId; MilestoneType type;
  String runId; int runNumber; DateTime timestamp; String? contextId }`
- `BuildDna { List<String> tokens; String signature }`

### 4.4 Aggregate root

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

  const AlmanacState({ /* all lists, default const [] */ });
  factory AlmanacState.empty() => const AlmanacState();
}
```

`inspirations` is a seventh list beyond the six in the task brief §19 —
justified: SP0b ancestry is called out as one of the most important
Almanac features (§9) and deserves a first-class collection with its own
query, rather than being buried inside a technique record.

Records are held in insertion order. There are no mutable counters at the
`AlmanacState` level — lineage/technique/affix aggregates are derived by
`AlmanacQueries` from the immutable records (task §12).

---

## 5. Recorder & idempotency — `almanac_recorder.dart`

`AlmanacRecorder(AlmanacState initial)` — a plain class. Internally holds a
working copy indexed by id (maps) for O(1) upsert; exposes
`AlmanacState get state` (rebuilt as ordered lists). **Never** references
`RngService`, `context.rng`, `Random`, the component store, the event bus,
or any gameplay mutation. Inputs are `String` / `num` / `bool` / `DateTime`
/ the snapshot classes only.

### 5.1 Methods

| Method | Effect |
|---|---|
| `beginRun({runId, runNumber, lineageId, physiqueId, startedAt})` | upsert an open `AlmanacRunRecord` (`outcome` provisional `abandoned`, `completedAt` null) |
| `recordFight(runId, AlmanacFightRecord)` | append to that run's `fights` (dedup by `(name, enemyId, turnsUsed)` within the run) |
| `recordBuildSnapshot(AlmanacBuildRecord)` | upsert by `buildId`; compute `dna` if the passed record's `dna.tokens` is empty |
| `recordTechniqueDiscovered({instanceId, baseFamilyId, styleId, descriptorIds, axisProfile, origin, masteryAtDiscovery, runId, runNumber})` | upsert `AlmanacTechniqueRecord` by `instanceId`; also emits a `techniqueVariant` discovery row |
| `recordTechniqueUsed({instanceId, runNumber})` | `totalUsage++`; add `runNumber` to `runsUsed` if absent |
| `recordTechniqueInspired({resultInstanceId, runId, familyId, descriptorIds, inspirerInstanceIds})` | upsert `TechniqueInspirationHistory` by `resultInstanceId` (verbatim, never recomputed); upsert the matching technique record's `origin` to `inspired` |
| `recordItemDiscovered({definitionId, instanceId, runId, runNumber, snapshot})` | emit an `item` discovery row (first occurrence immutable) |
| `recordItemUsed({definitionId, runNumber})` | (reserved; increments a usage counter on a future item record — v1 records the discovery row only) |
| `recordAffixDiscovered({affixId, runId, runNumber, lineageId, snapshot})` | upsert `AlmanacAffixRecord` by `affixId`: `timesDiscovered++`, set `firstDiscoveredRunId` once, union `lineageId` into `associatedLineageIds`; emit an `affix` discovery row |
| `recordAffixUsed({affixId, runNumber})` | `timesUsed++` on the affix record |
| `recordDiscovery(AlmanacDiscoveryRecord)` | generic upsert by `discoveryId` |
| `recordMilestone({type, runId, runNumber, timestamp, contextId})` | upsert by milestone key |
| `evaluateStandardMilestones({runId, runNumber, outcome, lineageId, finalBuildId, timestamp})` | derive and record the standard firsts (see §5.3) |
| `completeRun({runId, completedAt, outcome, finalBuildId, enemiesDefeated, techniquesUsed, trainingSessions})` | close the run record |

The typed `recordTechnique*/Item*/Affix*` methods internally build and pass
an `AlmanacDiscoveryRecord` to `recordDiscovery`, so discovery-row
idempotency has one implementation.

### 5.2 Idempotency keys

Re-processing the same domain event must never duplicate history (task
§22.4).

| Record | Stable key |
|---|---|
| run | `runId` |
| build | caller `buildId` (harness: `"$runId:${phase.name}"`, or `"$runId:${phase.name}:$cycle"` when a phase repeats per cycle) |
| technique | `instanceId` — `TechniqueVariantMinted` inserts `origin: base`; a later `TechniqueVariantInspired` for the same `instanceId` upserts `origin: inspired` in place (no new row) |
| inspiration | `resultInstanceId` (exactly one inspiration per minted instance) |
| discovery | `"${type.name}:$contentId"` — first occurrence is immutable; later encounters bump counters on the technique/item/affix record, never add a discovery row |
| affix | `affixId` |
| milestone | `type.name`, or `"${type.name}:$contextId"` for per-context firsts (`firstWinWithLineage:western`) |

`totalUsage` / `timesUsed` / `timesDiscovered` are **counts** — each call
increments; they are intentionally not idempotent. `runsUsed` /
`associatedLineageIds` are **sets** — additive but dedup'd.

### 5.3 Standard milestones (lightweight — task §15)

`evaluateStandardMilestones` records, at most once each:

- `firstRun` — state had zero runs before this one.
- `firstVictory` — `outcome == won` and no prior `won` run.
- `firstTechniqueVariant` — first technique record ever.
- `firstInspiredTechnique` — first technique record with `origin == inspired`.
- `firstAffix` — first affix record (v1: only reachable via tests).
- `firstWinWithLineage` (`contextId = lineageId`) — first `won` run for
  that lineage.
- `firstSuccessfulBuild` (`contextId = finalBuildId`) — first `won` run
  that has a non-empty final build.

No hundreds of achievements; a flat record is enough.

---

## 6. Repository & serialization

### 6.1 Repository

```dart
abstract interface class AlmanacRepository {
  AlmanacState load();
  void save(AlmanacState state);
}

class InMemoryAlmanacRepository implements AlmanacRepository {
  InMemoryAlmanacRepository([AlmanacState initial = const AlmanacState()]);
  // holds one AlmanacState; save replaces it, load returns it
}
```

`almanac_file_repository.dart` (isolated; `dart:io` + `dart:convert` — the
same `dart:io`-in-a-composition-module precedent as
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

### 6.2 Serialization — `almanac_serialization.dart`

- `Map<String, dynamic> stateToJson(AlmanacState)` — writes
  `{'almanacSchemaVersion': 1, 'runs': [...], 'builds': [...], ...}`.
- `AlmanacState stateFromJson(Map<String, dynamic>)` — throws
  `AlmanacSchemaVersionError` if `almanacSchemaVersion != 1` (the migration
  seam; future versions branch here).
- `String encode(AlmanacState)` / `AlmanacState decode(String)` —
  `jsonEncode` / `jsonDecode` wrappers.

Persisted values are only strings, nums, bools, lists, and maps. Never
serialized: closures, engine-service references, RNG state, component-store
internals, Flutter/UI objects, live entity references.

---

## 7. Query API — `almanac_queries.dart`

`AlmanacQueries(AlmanacState state)` — pure reads, deterministic order.
Records are returned in state-list insertion order; queries that re-sort
use an explicit `(runNumber, id)` comparator so results are stable
(task §22.10).

Required (task §20): `getRunHistory()` · `getRun(runId)` ·
`getBuildHistory()` · `getBuild(buildId)` · `getLineageHistory(lineageId)` ·
`getTechniqueHistory(instanceId)` · `getTechniqueInspirations(instanceId)` ·
`getAffixHistory(affixId)` · `getDiscoveries()` ·
`getRecentDiscoveries({int limit})` · `getRunsUsingTechnique(instanceId)` ·
`getBuildsUsingTechnique(instanceId)` · `getRunsForLineage(lineageId)` ·
`getRunsForPhysique(physiqueId)`.

Aggregates (kept small — no analytics engine): `lineageStatistics(lineageId)`
→ `{runs, wins, losses, techniquesDiscovered, itemsDiscovered,
affixesDiscovered, buildsUsed, physiquesUsed}` derived from records;
`mostUsedTechniques({int limit})`; `mostUsedAffixes({int limit})`;
`discoveryCompletion({Map<AlmanacDiscoveryType, Set<String>> known})` →
per-type `{discovered, total, fraction}`.

The client never mutates `AlmanacState` directly — it reads through
`AlmanacQueries` and writes only via events the recorder observes.

---

## 8. Build DNA — `almanac_build_dna.dart`

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
   ...sortedUnique(techniqueFamilies).map(upper),
   ...sortedUnique(itemIds).map(upper),
   ...sortedUnique(affixCategories).map(upper),
   ...topAxes ]`
   where `topAxes` = the axis names selected by ordering on
   `(summedAbsValue desc, name asc)` across `axisProfiles` and taking the
   first 3, then re-sorted by `name asc`, upper-cased. The `name asc`
   tie-break keeps selection deterministic when two axes share a summed
   magnitude.
2. `signature` = FNV-1a 32-bit hex of `tokens.join('|')`.

Stored on `AlmanacBuildRecord.dna`. No human-readable names in v1
(task §21) — a later UI may map a signature to `"Iron Mountain"`.

---

## 9. Harness wiring — `almanac_bridge.dart` + `runGame`

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

When `almanac == null`: no subscriptions, no snapshots, byte-identical to
today. Determinism and existing harness tests are unaffected because the
recorder can reach neither `rng` nor `policy`.

When non-null, `runGame` constructs
`_AlmanacBridge(almanac, runId: 'run_$seed', runNumber: <passed by caller>)`,
calls `.attach(events)` before the cycle loop, and `.finish(...)` on
`RunEnded`. `runNumber` is the caller's responsibility
(`repo.load().runs.length + 1`), passed in — `runGame` stays free of
persistence.

### 9.1 Event → recorder map (existing events only — no new events)

| Event (source) | Recorder call |
|---|---|
| run start (inside `runGame`) | `beginRun(lineageId: martialTraditionOf(styleId) ?? styleId, physiqueId: physiqueId, …)` |
| `TomeChanged` (harness) with `stepName == 'starting'` | `recordBuildSnapshot(phase: initial)` |
| `TechniqueVariantMinted` (technique plugin) | `recordTechniqueDiscovered(origin: base, …)` |
| `TechniqueVariantInspired` (technique plugin) | `recordTechniqueInspired(…)` — upserts `origin: inspired`, adds the ancestry row |
| `SubjectDiscovered` (Core) subject `technique:*` / `item:*` | `recordDiscovery(type: technique | item)` |
| technique-usage event (`ActionCompleted` / SP0b usage), when instance-backed | `recordTechniqueUsed` |
| `EncounterResolved` (harness) | `recordFight` |
| `RewardSelected` (harness) | `recordBuildSnapshot(phase: postReward)` |
| `TrainingResultRecorded` (harness) | `trainingSessions++`; `recordBuildSnapshot(phase: postTraining)` |
| `RunEnded` (harness) | final `recordBuildSnapshot(phase: finalBuild)` + DNA, `completeRun(...)`, `evaluateStandardMilestones(...)` |

An inspired variant emits `TechniqueVariantMinted` **then**
`TechniqueVariantInspired` (inspiration calls `mintTechniqueVariant`
internally). The `instanceId` key makes the pair converge on one technique
record with `origin: inspired` plus one ancestry row.

`TomeLayoutSnapshot` is built from `context.tome` and the
`List<BuildComponentRef>` the harness stages already hold.

Outcome mapping: harness `won: true` (survived to the safety cap) →
`RunOutcome.won`; `won: false` (died) → `RunOutcome.lost`; a run that never
reaches `RunEnded` stays `abandoned`.

After `runGame` returns, the caller persists: `repo.save(almanac.state)`.

---

## 10. Architecture tests & docs

### 10.1 New — `test/plugins/almanac/almanac_architecture_test.dart`

- Every `lib/src/plugins/almanac/*.dart` contains none of:
  `technique_plugin.dart`, `item_plugin.dart`, `martial_arts_plugin.dart`,
  `combat_plugin.dart`, `physique_plugin.dart`, `build_interpretation.dart`,
  `game.dart`, `plugins/` (relative escape).
- `almanac_recorder.dart` and `almanac_queries.dart` contain none of:
  `RngService`, `context.rng`, `Random(`, `math.Random`.
- No `lib/src/plugins/almanac/*.dart` contains `package:flutter/`,
  `dart:ui`, `devvit`, or `flame`.

### 10.2 Extend — `test/integration/architecture_dependency_test.dart` (add only)

- Add `'almanac.dart'` to `_pluginBarrels` so the enumerated "Core does not
  import any plugin barrel" group covers it automatically.
- New group "Almanac is a passive observer": each of
  `lib/src/plugins/{technique,combat,martial_arts,item,physique,elemental,auto_combat}`
  references neither `almanac.dart` nor `plugins/almanac/`.

No existing architecture assertion is weakened or removed.

### 10.3 Docs

- `ARCHITECTURE.md` — new "## Almanac — Persistent Player History" section:
  responsibility; event-driven recording; immutable history &
  rebalance-resilience; serialization boundary + schema version; query API;
  the `TechniqueVariantInspired` / SP0b relationship; the ContentRegistry
  relationship; why Almanac owns no gameplay state; a "Save State ≠ Almanac
  History" subsection.
- `CHANGELOG.md` — entry under a new dated heading.

---

## 11. Test plan

### 11.1 Unit — `test/plugins/almanac/`

| File | Proves |
|---|---|
| `almanac_models_test.dart` | immutability; per-record `toJson`/`fromJson` round-trips |
| `almanac_recorder_test.dart` | begin/complete run; multiple runs stay separate; two variant instances of one family stay distinct; base family never replaces an instance id; same event twice → no duplicate |
| `almanac_inspiration_test.dart` | synthetic `TechniqueVariantInspired` data → `inspirerInstanceIds` preserved exactly and in order; re-feed → no dup; ancestry never recomputed |
| `almanac_build_snapshot_test.dart` | Tome layout (dims + slots + instance ids) preserved; mutating a fake definition afterward leaves the stored snapshot unchanged |
| `almanac_affix_test.dart` | `recordAffixDiscovered` ×3 same affix → one record, `timesDiscovered == 3`, lineages unioned |
| `almanac_lineage_test.dart` | run records lineage; `getRunsForLineage` / `lineageStatistics` correct |
| `almanac_serialization_test.dart` | save→load equivalent for `InMemory` and `JsonFile` (temp file); schema-version mismatch throws |
| `almanac_queries_test.dart` | same state → identical, order-stable query results |
| `almanac_build_dna_test.dart` | same inputs → same signature; reordered inputs → same signature; changed inputs → different |
| `almanac_architecture_test.dart` | §10.1 |

### 11.2 Integration — `test/integration/almanac_run_history_test.dart`

- `runGame(seed, almanac: recorder)` for 3 different seeds/policies → 3
  distinct `AlmanacRunRecord`s; discoveries and final builds captured;
  lineage/physique preserved.
- Whole-chronicle serialization round-trips (`AlmanacSerialization` +
  `JsonFileAlmanacRepository`).
- `almanac == null` path: `RunResult` byte-identical to a run without the
  parameter.
- Same seed + same policy twice → equivalent `AlmanacState`.

### 11.3 Gate

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

## 12. Commit sequence

1. domain model + serialization + model tests
2. repository (in-memory + `dart:io` file) + serialization tests
3. recorder + idempotency + recorder / inspiration / affix tests
4. queries + build DNA + their tests
5. harness bridge + `runGame` opt-in parameter + integration tests
6. architecture tests + `ARCHITECTURE.md` + `CHANGELOG.md` + `lib/almanac.dart` barrel

Each commit builds and tests green on its own.

---

## 13. Acceptance criteria

- [ ] Almanac is a standalone composition-layer module; Core stays game-agnostic.
- [ ] No Combat → Almanac, Technique → Almanac, MartialArts → Almanac, or Training → Almanac dependency; no circular dependency.
- [ ] Run, build, and Tome snapshots persist; TechniqueVariant instances stay distinct; SP0b inspiration ancestry persists exactly as emitted.
- [ ] Item and affix history models + queries + serialization implemented (affix recording test-only in v1).
- [ ] Lineage, physique, and discovery history persist.
- [ ] Historical snapshots survive a later content rebalance.
- [ ] Records are idempotent under repeated event processing.
- [ ] Serialization round-trips; schema version 1 with a migration seam.
- [ ] Query API works and is deterministic.
- [ ] Build DNA is deterministic.
- [ ] `dart analyze` / `dart test` / all architecture tests pass.
- [ ] `ARCHITECTURE.md` and `CHANGELOG.md` updated, including "Save State ≠ Almanac History".
