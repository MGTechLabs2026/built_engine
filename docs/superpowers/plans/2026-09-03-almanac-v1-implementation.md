# Almanac v1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add Almanac v1 — a passive, persistent, cross-run player-history subsystem — as a composition-layer module that observes existing domain events and never drives gameplay.

**Architecture:** `Gameplay → composition adapter (HeadlessGameAlmanacBridge / out-of-repo TomeClientAlmanacAdapter) → AlmanacRecorder → AlmanacState → AlmanacRepository / AlmanacQueries`. The recorder takes only primitive/snapshot value objects; adapters build the snapshots from live state. The module imports Core only; the one `dart:io` file lives behind its own barrel so the public Almanac surface stays web-safe, mirroring the existing `lib/console_policy.dart` precedent.

**Tech Stack:** Plain Dart package (`sdk: ^3.7.0`), `package:test`, `dart:convert` for JSON. No new runtime dependencies. `analysis_options.yaml` enforces `strict-casts` / `strict-inference` / `strict-raw-types`.

**Spec:** `docs/superpowers/specs/2026-09-03-almanac-v1-design.md` (reviewed @ `536961e2abcf2b60e9323ea22004cb1e5429e2f8`). The plan argues from that spec; executors read both.

## Global Constraints

- **Core stays generic.** `lib/src/` outside `lib/src/plugins/` must not reference `almanac`. Almanac lives at `lib/src/plugins/almanac/` (a composition module like `build_interpretation/` and `game/`, **not** a `GamePlugin`).
- **Almanac imports Core only.** `package:build_engine/build_engine.dart` + `dart:convert`, and `dart:io` **only** in `almanac_file_repository.dart`. Never `technique_plugin.dart`, `item_plugin.dart`, `martial_arts_plugin.dart`, `combat_plugin.dart`, `physique_plugin.dart`, `build_interpretation.dart`, `game.dart`, or any `plugins/…` relative path.
- **`lib/almanac.dart` must not transitively require `dart:io`.** Web-safe surface = models + recorder + queries + repository interface + serialization. Only `JsonFileAlmanacRepository` (behind `lib/almanac_file.dart`) uses `dart:io`.
- **No Flutter / Flame / Devvit / database / backend / `dart:html` / `dart:ui`.**
- **All Almanac ids are opaque tokens.** Never `split` / `startsWith` / regex / prefix-parse an id to recover a relationship. Every relationship is a stored explicit field. Enforced by an architecture test.
- **Adapter ID formatting is not part of the Almanac API contract.** A composition adapter (the headless bridge, or an out-of-repo client adapter) MAY mint readable id strings — `<runId>:e<n>`, `<runId>:u<n>`, `<runId>:t<n>`, `<runId>:<phase>:<n>`. Downstream — every Almanac model, recorder, query, repository, serialization step — treats them as **opaque**: whole-string compare only, no structural inference. The bridge's specific format is an implementation detail; a client adapter may emit `action-8f3a91` and everything behaves identically. **Tests must assert relationships via explicit fields** (`fight.runId == expected`, `build.phase == expected`, `usage.runId == expected`), never via an id's textual prefix. (§11.2.1)
- **`runId` ≠ `runNumber` ≠ `seed`.** `runId`/`runNumber` are caller-supplied opaque values; `seed` is optional replay metadata that keys nothing; `runId = "run_<seed>"` is forbidden. The recorder never generates identity and never reads a repository.
- **Idempotency is identity-keyed.** Keys: run `runId`; fight `fightId` within `runs[runId].fights`; build snapshot `buildId`; technique history `instanceId`; technique-usage `(runId, usageEventId)`; inspiration `resultInstanceId`; discovery `discoveryId`; affix history `affixId`; affix observation `(affixId, affixEventId)`; training `(runId, trainingEventId)`; milestone `milestoneId`. Every key compared by whole-string equality.
- **Canonical history is identity-stable and monotonic.** Later observations may fill an `UNKNOWN` field, append a new ledger element, or advance `origin` `base`→`inspired`. A conflicting write-once value is retained and raises `AlmanacIntegrityException` — never a silent overwrite, never a merge/recovery system.
- **Deep immutability.** Every collection stored in a record is a copy that never aliases gameplay state; `AlmanacQueries` returns copies or `List.unmodifiable` / `Map.unmodifiable`. A valid later completion is not a mutation.
- **SP0b ancestry is stored verbatim** from `TechniqueVariantInspired` — no re-resolution, no re-query, no RNG.
- **`runGame` behaviour is byte-identical when `almanac == null`.** No `repo.load()` / `repo.save()` inside `runGame`. Existing golden/replay/determinism tests stay green.
- **Serialization: no second framework.** Module-local `toJson()` / `factory X.fromJson(Map<String, dynamic>)` over plain maps + `jsonEncode`/`jsonDecode`, matching `Container.toJson` (`lib/src/spatial/container.dart:188`) and `CombatantComponent.toJson`.
- **Do not weaken or delete any existing architecture test.**

---

## 1. Current codebase findings

Verified against the working tree at `536961e` (branch `almanac-v1`).

### 1.1 Package & tooling

- Plain Dart, `pubspec.yaml`: `name: build_engine`, `sdk: ^3.7.0`, `publish_to: none`, dev-deps `lints: ^5.0.0`, `test: ^1.25.0`. **No runtime dependencies** — do not add one.
- `analysis_options.yaml`: `package:lints/recommended.yaml` + `strict-casts` / `strict-inference` / `strict-raw-types`. Plan code must be strictly typed (no raw `List`/`Map`, no implicit `dynamic`).

### 1.2 Barrels & the `dart:io` precedent

- Core barrel `lib/build_engine.dart` — Core services only.
- Plugin barrels: `lib/technique_plugin.dart`, `lib/item_plugin.dart`, `lib/martial_arts_plugin.dart`, `lib/combat_plugin.dart`, `lib/physique_plugin.dart`, `lib/elemental_plugin.dart`, `lib/auto_combat_plugin.dart`.
- Composition barrels: `lib/game.dart` (headless harness), `lib/build_interpretation.dart`.
- **`lib/console_policy.dart`** — a dedicated barrel whose entire purpose is to keep the one `dart:io` file (`lib/src/plugins/game/console_decision_policy.dart`) **out** of `lib/game.dart`. Its doc comment: *"it is the only part of the engine that imports `dart:io`, and `game.dart` must stay usable from web targets."* **This is the exact pattern Almanac's file repository follows.**
- **No conditional exports** (`if (dart.library.io)`) anywhere in `lib/`. Use the dedicated-barrel pattern, not conditional exports.

### 1.3 Serialization conventions

- No engine-wide serialization framework. Module-local `Map<String, dynamic> toJson()` + `factory X.fromJson(Map<String, dynamic> json)`.
- Precedents: `Container.toJson` / `Container.fromJson` (`lib/src/spatial/container.dart:188`, `:214`), `CombatantComponent.toJson` / `.fromJson`, `CombatStateComponent`, `MartialLoadoutComponent`, `ContentRegistry.toJson` (`lib/src/content/content_registry.dart:163`).
- `dart:convert` (`jsonEncode`/`jsonDecode`) is pure and web-safe — fine for the platform-neutral surface.

### 1.4 Event bus

`lib/src/event/event_bus.dart` — `EventBus`:
- `EventSubscription subscribe<T>(void Function(T event) handler)` — dispatch by **exact runtime type**. Handler param must be explicitly typed or `T` passed explicitly.
- `EventSubscription subscribeDynamic(Type type, void Function(Object event) handler)`.
- `void publish<T>(T event)` — looks up `event.runtimeType`.
- `EventSubscription.cancel()` removes the handler.

### 1.5 Entity & id representation

`lib/src/entity/entity_id.dart` — `class EntityId { const EntityId(this.value); final int value; }` with value equality. **Almanac stringifies at the boundary: `entityId.value.toString()`.** Almanac models never import `EntityId`.

### 1.6 Tome representation

- `context.tome` is `TomeService` (`lib/src/tome/tome_service.dart`).
- `List<TomePlacement> inspect(EntityId owner)` → `TomePlacement { SlotId slot; BuildComponentRef buildComponentRef; ItemSize size; Rotation rotation }`.
- `SlotId { const SlotId(this.id); final String id; }`.
- `BuildComponentRef { String referenceType; String contentId; EntityId? instanceEntityId; }` (`lib/src/tome/build_component_ref.dart`). `referenceType` values: `techniqueReferenceType == 'technique'` (`lib/src/plugins/technique/technique_vocabulary.dart:104`), `itemReferenceType == 'item'` (`lib/src/plugins/item/item_vocabulary.dart:111`).
- The headless harness Tome is `TomeDefinition.namedSlots(id: 'run_tome', slotIds: slot_1..slot_999)` — a **named-slot** container, so `TomeLayoutSnapshot.width`/`height` are `null` for harness runs; `occupantKind` derives from `referenceType`.

### 1.7 TechniqueVariant / SP0a / SP0b

- `mintTechniqueVariant(owner, baseFamilyId, Set<String> descriptorIds, context, {String? styleId, Map<String,num> styleCentre})` publishes **`TechniqueVariantMinted(EntityId owner, EntityId instanceId, String baseFamilyId)`** (`lib/src/plugins/technique/technique_variant_lifecycle.dart:71`). Only `owner` + `instanceId` + `baseFamilyId` on the event.
- `TechniqueVariant` component (`lib/src/plugins/technique/technique_variant.dart`): `{ EntityId owner; String baseFamilyId; Set<String> descriptorIds; Map<String,num> axisProfile; String? styleId; }`. Read via `context.components.get<TechniqueVariant>(instanceId)` — the **bridge** does this (it has `context`); the recorder never does.
- Per-instance mastery: `MasteryDefinition(subject: techniqueInstanceSubject(instance), …)`. `context.mastery.levelOf(owner, techniqueInstanceSubject(instanceId)) → int`.
- **`TechniqueVariantInspired`** (`lib/src/plugins/technique/technique_events.dart`): `{ EntityId owner; EntityId instanceId; String familyId; Set<String> descriptorIds; List<EntityId> inspirerInstanceIds; }`. Published **once** from `lib/src/plugins/technique/technique_inspiration.dart:327`, and inspiration calls `mintTechniqueVariant` **first** (line 319) — so at runtime `Minted` precedes `Inspired` for the same `instanceId`. The recorder must still tolerate either order (spec §6).
- SP0b usage attribution already exists: `lib/src/plugins/game/combat_stage.dart:97-108` subscribes `ActionCompleted` and, when `e.action.sourceRef != null && ref.referenceType == techniqueReferenceType && ref.instanceEntityId != null`, calls `recordTechniqueVariantUsage(ref.instanceEntityId!, context)`. **The bridge reuses this exact predicate** to emit a `TechniqueUsageObservation`.
- `CombatAction.sourceRef → BuildComponentRef?` (`lib/src/plugins/combat/combat_action.dart:41`), set by `TechniqueActionInterpreter`, `null` for bare-handed fallback.

### 1.8 Run telemetry (`lib/src/plugins/game/run_events.dart`) — no engine run id

- `RunStarted { int seed; String characterName; }` — published at `game_run.dart:143`, **before** physique/style are chosen.
- `RunEnded { bool won; int encounterCount; }` — near `game_run.dart:249`.
- `CycleStarted { int cycleNumber; }`.
- `EncounterStarted { String name; String enemyId; }` / `EncounterResolved { String name; String enemyId; bool won; num playerHealthAfter; }` — **no index / no encounter id**.
- `RewardSelected { RewardKind chosen; }`.
- `TrainingStarted { String subject; }` / `TrainingResultRecorded { String subject; TrainingProfile profile; num gain; }` — published per session by `TrainingStage` (`training_stage.dart:83,110`).
- `TomeChanged { String stepName; List<BuildComponentRef> components; }` — every rebuild, `stepName == 'starting'` for the initial kit.
- `PhysiqueAssigned { EntityId character; String physiqueId; }` (`lib/src/plugins/physique/physique_events.dart`) — published by `initializePhysique`.
- **There is no style/tradition event.** `learnStyle` only grants tags. `game_run.dart` holds locals `physiqueId`, `traditionId`, `styleId` (~lines 164-170). `martialTraditionOf(styleId)` (`lib/src/plugins/martial_arts/martial_styles.dart`, barrel `martial_arts_plugin.dart`) → `'western'` / `'eastern'` / `null`.

### 1.9 `runGame` shape (`lib/src/plugins/game/game_run.dart`)

`RunResult runGame(int seed, {String characterName = 'Player', RunDecisionPolicy policy = const DefaultRunDecisionPolicy(), EventBus? eventBus})`. `events` bus created ~line 124; `RunStarted` at 143; plugins initialised; `character` created ~158; physique/style ~164-170; cycle loop; `RunEnded` ~249; returns `RunResult` (immutable, already carries `physiqueId` / `martialTradition` / `styleId` / `tomeHistory`). `runGame` never touches persistence today.

### 1.10 Architecture tests

`test/integration/architecture_dependency_test.dart` (a VM test — it may `import 'dart:io'`):
- `_assertNoSubstringInDirectory(String forbidden, String dir)` — recursive `.dart` scan.
- `_pluginBarrels` list + `_assertNoPluginImport(pluginDirName, barrel, dir)`.
- Group **"H: Core does not import either content plugin"** iterates every `lib/src` subdir except `plugins/` and asserts none references `plugins/` or any barrel in `_pluginBarrels`. **Adding `'almanac.dart'` + `'almanac_file.dart'` to `_pluginBarrels` auto-covers Core-purity for the new barrels.**
- Group **"audit A1 — the headless harness is top-of-graph"** asserts nothing under `lib/` except `plugins/game/` + `lib/game.dart` imports the harness.

No existing test forbids `dart:io` in `lib/build_engine.dart` / `lib/game.dart` — this plan **adds** that guard for the Almanac neutral surface.

---

## 2. Architecture boundary

```
Core  (lib/src/*, lib/build_engine.dart)
  │  provides: EventBus, EntityId, ContentRegistry, MasteryTracker, TomeService types
  ▼
Gameplay plugins  (technique, item, combat, martial_arts, physique, …)
  │  emit: TechniqueVariantMinted/Inspired, ActionCompleted, PhysiqueAssigned, SubjectDiscovered
  ▼
Composition layer
  ├─ lib/src/plugins/game/          headless harness + HeadlessGameAlmanacBridge   ← imports plugins AND almanac
  └─ <client repo>                  TomeClientAlmanacAdapter                        ← out of scope here
  ▼
Almanac  (lib/src/plugins/almanac/*)   ← imports Core only (+ dart:convert; dart:io only in almanac_file_repository.dart)
  models → serialization → repository interface → recorder → queries → build DNA
  ▼
Persistence / read models
  ├─ InMemoryAlmanacRepository   (neutral)
  └─ JsonFileAlmanacRepository   (dart:io, behind lib/almanac_file.dart)
```

Rules restated for enforcement (all become architecture-test assertions — see §13.1 + Phase 8):

| Rule | Mechanism |
|---|---|
| Almanac imports Core only | substring scan of `lib/src/plugins/almanac/**` for plugin barrels + `plugins/` |
| `lib/almanac.dart` neutral surface free of `dart:io` | scan every file `lib/almanac.dart` exports (and their `almanac/` imports) for `import 'dart:io'`; assert `lib/almanac.dart` does not export `almanac_file*` |
| Core does not import Almanac | `'almanac.dart'` + `'almanac_file.dart'` added to `_pluginBarrels`; existing group H covers it |
| Gameplay plugins do not import Almanac | new group: scan `lib/src/plugins/{technique,combat,martial_arts,item,physique,elemental,auto_combat}` for `almanac` |
| Recorder/queries RNG-free | scan for `RngService`, `context.rng`, `Random(`, `math.Random` |
| No id parsing | scan `almanac_recorder.dart` + `almanac_queries.dart` for `.split(`, `.startsWith(` |
| No UI/platform deps | scan `almanac/**` for `package:flutter/`, `dart:ui`, `dart:html`, `devvit`, `flame` |
| Bridge is the only dual-importer in-repo | it lives in `plugins/game/` (already top-of-graph); no new test needed beyond "nothing else imports `plugins/game/`" which audit A1 already enforces |

---

## 3. `dart:io` portability guardrail

**Decision: dedicated-barrel split (the `console_policy.dart` pattern), not conditional exports.**

### 3.1 File layout

| File | `dart:io`? | Exported by |
|---|---|---|
| `lib/src/plugins/almanac/almanac_models.dart` | no | `lib/almanac.dart` |
| `lib/src/plugins/almanac/almanac_serialization.dart` | no (`dart:convert` only) | `lib/almanac.dart` |
| `lib/src/plugins/almanac/almanac_repository.dart` | no (interface + `InMemoryAlmanacRepository`) | `lib/almanac.dart` |
| `lib/src/plugins/almanac/almanac_recorder.dart` | no | `lib/almanac.dart` |
| `lib/src/plugins/almanac/almanac_queries.dart` | no | `lib/almanac.dart` |
| `lib/src/plugins/almanac/almanac_build_dna.dart` | no | `lib/almanac.dart` |
| `lib/src/plugins/almanac/almanac_file_repository.dart` | **yes** (`dart:io` + `dart:convert`) | `lib/almanac_file.dart` **only** |
| `lib/almanac.dart` | no — must not `export` `almanac_file_repository.dart` | — |
| `lib/almanac_file.dart` | transitively yes | — |

`lib/almanac.dart` doc comment (verbatim intent, mirroring `console_policy.dart`):

```dart
/// The Almanac's platform-neutral public surface — persistent cross-run
/// player history. Safe to import from any Dart target, web included:
/// nothing here requires `dart:io`. The file-backed repository
/// (`JsonFileAlmanacRepository`) is deliberately kept in the separate
/// `package:build_engine/almanac_file.dart` barrel so this one stays
/// web-safe — the same split `console_policy.dart` uses for
/// `ConsoleDecisionPolicy`.
library;

export 'src/plugins/almanac/almanac_build_dna.dart';
export 'src/plugins/almanac/almanac_models.dart';
export 'src/plugins/almanac/almanac_queries.dart';
export 'src/plugins/almanac/almanac_recorder.dart';
export 'src/plugins/almanac/almanac_repository.dart';
export 'src/plugins/almanac/almanac_serialization.dart';
```

```dart
/// `JsonFileAlmanacRepository` — a `dart:io` file-backed `AlmanacRepository`.
/// Kept out of `package:build_engine/almanac.dart` on purpose: it is the
/// only Almanac file that imports `dart:io`, and the neutral barrel must
/// stay usable from web targets. Import this only from a file-capable
/// host (a CLI tool, a VM test, or a desktop client).
library;

export 'src/plugins/almanac/almanac_file_repository.dart';
```

### 3.2 Enforcement test (added in Phase 8)

`test/plugins/almanac/almanac_platform_neutral_test.dart`:

- Assert `lib/almanac.dart` source contains neither `almanac_file` nor `dart:io`.
- For every path `lib/almanac.dart` exports, and recursively every `import '…'` inside `lib/src/plugins/almanac/` reachable from those (excluding `almanac_file_repository.dart`), assert the file text contains no `import 'dart:io'`.
- Assert `lib/src/plugins/almanac/almanac_file_repository.dart` **is** the only file under `lib/src/plugins/almanac/` containing `import 'dart:io'`.

## 4. Domain model implementation — `almanac_models.dart`

One file. Every class: all fields `final`, `const` constructor where the fields allow, `Map<String, dynamic> toJson()`, `factory X.fromJson(Map<String, dynamic>)`. Collections copied in the constructor (`List.unmodifiable` / `Map.unmodifiable`) so a caller cannot mutate a stored record. `DateTime` ↔ ISO-8601 via `toIso8601String()` / `DateTime.parse`. All ids are `String`.

### 4.1 Enums

```dart
enum RunOutcome { won, lost, abandoned }
enum TechniqueOrigin { base, evolved, inspired }        // only base/inspired produced in v1
enum BuildPhase { initial, postReward, postTraining, finalBuild }
enum AlmanacDiscoveryType { technique, techniqueVariant, item, affix, lineage }
enum MilestoneType {
  firstRun, firstVictory, firstTechniqueVariant, firstInspiredTechnique,
  firstAffix, firstWinWithLineage, firstSuccessfulBuild,
}
```

Each serialized as `.name`; parsed with a shared `_enumByName<T>(List<T> values, Object? raw)` helper that throws on an unknown name.

### 4.2 Observation records (spec §5.6.1)

```dart
class TechniqueUsageObservation {
  const TechniqueUsageObservation({
    required this.usageEventId, required this.runId,
    required this.runNumber, required this.instanceId,
  });
  final String usageEventId;   // OPAQUE
  final String runId;          // explicit relation
  final int runNumber;
  final String instanceId;
  // toJson / fromJson
}

class AffixObservation {
  const AffixObservation({
    required this.affixEventId, required this.runId,
    required this.runNumber, this.lineageId,
  });
  final String affixEventId;   // OPAQUE
  final String runId;
  final int runNumber;
  final String? lineageId;
}

class TrainingObservation {
  const TrainingObservation({
    required this.trainingEventId, required this.runId, required this.runNumber,
  });
  final String trainingEventId; // OPAQUE
  final String runId;
  final int runNumber;
}
```

### 4.3 Snapshots

```dart
class TechniqueInstanceSnapshot {   // instanceId, baseFamilyId, styleId?, descriptorIds:List<String>,
                                    // axisProfile:Map<String,num>, origin:TechniqueOrigin, masteryAtSnapshot:int
}
class ItemInstanceSnapshot {        // definitionId, instanceId?, itemClass:int,
                                    // statBonuses:Map<String,num>, resolvedProperties:Map<String,num>
}
class AffixSnapshot {               // affixId, stat, value:num, category?
}
class TomeSlotSnapshot {            // slotId, occupantKind:('technique'|'item'|'empty'),
                                    // occupantRefId?, instanceId?
}
class TomeLayoutSnapshot {          // width:int?, height:int?, slots:List<TomeSlotSnapshot>
}
class BuildPerformanceSnapshot {    // fightsWon:int, fightsLost:int, enemiesDefeated:int, avgTurnsUsed:num?
}
class DiscoverySnapshot {           // label:String, values:Map<String,Object?>
}
class BuildDna {                    // tokens:List<String>, signature:String
}
```

### 4.4 Canonical records

```dart
class AlmanacFightRecord {
  // fightId (OPAQUE), runId, sequence:int, name, enemyId, won:bool,
  // playerHealthAfter:num, turnsUsed:int
}

class AlmanacRunRecord {
  // runId, runNumber:int, seed:int?, lineageId, physiqueId,
  // startedAt:DateTime, completedAt:DateTime?, outcome:RunOutcome,
  // fights:List<AlmanacFightRecord>, discoveryIds:List<String>,
  // trainingObservations:List<TrainingObservation>, finalBuildId:String?,
  // enemiesDefeated:int, techniquesUsed:int, trainingSessions:int   // last 3 = projections
}

class AlmanacBuildRecord {
  // buildId (OPAQUE), runId, phase:BuildPhase, sequence:int,
  // lineageId, physiqueId, techniques:List<TechniqueInstanceSnapshot>,
  // items:List<ItemInstanceSnapshot>, affixes:List<AffixSnapshot>,
  // tome:TomeLayoutSnapshot, performance:BuildPerformanceSnapshot?, dna:BuildDna
}

class AlmanacTechniqueRecord {
  // instanceId, baseFamilyId, styleId?, descriptorIds:List<String>,
  // axisProfile:Map<String,num>, discoveredRunId:String?, discoveredRunNumber:int?,
  // masteryAtDiscovery:int?, usageObservations:List<TechniqueUsageObservation>,
  // totalUsage:int, runsUsed:List<int>, origin:TechniqueOrigin     // totalUsage/runsUsed = projections
}

class TechniqueInspirationHistory {
  // resultInstanceId, runId, familyId,
  // descriptorIds:List<String>, inspirerInstanceIds:List<String>   // verbatim, order-preserving
}

class AlmanacAffixRecord {
  // affixId, discoveryObservations:List<AffixObservation>, usageObservations:List<AffixObservation>,
  // timesDiscovered:int, timesUsed:int, firstDiscoveredRunId:String?,
  // associatedLineageIds:List<String>, snapshot:AffixSnapshot        // counters/first/lineages = projections
}

class AlmanacDiscoveryRecord {
  // discoveryId (OPAQUE), type:AlmanacDiscoveryType, contentId, instanceId?,
  // runId, runNumber:int, timestamp:DateTime, snapshot:DiscoverySnapshot
}

class AlmanacMilestoneRecord {
  // milestoneId (OPAQUE), type:MilestoneType, runId, runNumber:int,
  // timestamp:DateTime, contextId:String?
}
```

### 4.5 Aggregate root

```dart
class AlmanacState {
  const AlmanacState({
    this.runs = const [], this.builds = const [], this.techniques = const [],
    this.inspirations = const [], this.affixes = const [],
    this.discoveries = const [], this.milestones = const [],
  });
  final List<AlmanacRunRecord> runs;
  final List<AlmanacBuildRecord> builds;
  final List<AlmanacTechniqueRecord> techniques;
  final List<TechniqueInspirationHistory> inspirations;
  final List<AlmanacAffixRecord> affixes;
  final List<AlmanacDiscoveryRecord> discoveries;
  final List<AlmanacMilestoneRecord> milestones;
}
```

**Key invariants:** every record round-trips through `toJson`/`fromJson` with structural equality; every collection field is unmodifiable after construction; no field is ever an `EntityId` / component / live handle.

**Tests required (Phase 1):** per-record round-trip; unknown-enum-name throws; passing a mutable list into a constructor then mutating the caller's copy leaves the record unchanged; `List.unmodifiable` on a returned collection throws on `.add`.

---

## 5. Recorder design — `almanac_recorder.dart`

```dart
class AlmanacIntegrityException implements Exception {
  AlmanacIntegrityException({
    required this.record, required this.field,
    required this.established, required this.rejected,
  });
  final String record;      // e.g. "AlmanacTechniqueRecord(instanceId=TV-1)"
  final String field;       // e.g. "descriptorIds"
  final Object? established;
  final Object? rejected;
  @override
  String toString() =>
      'Almanac integrity: $record.$field is already $established; '
      'refusing to overwrite with $rejected';
}

class AlmanacRecorder {
  /// Hydrates from an existing canonical state (§5.1). Rebuilds every
  /// identity index by REPLAYING `initial`'s records through the same
  /// invariant-preserving insert paths the public `record…` methods use —
  /// it does not retain any collection reference from `initial`. See §5.1.
  AlmanacRecorder([AlmanacState? initial]);   // defaults to AlmanacState.empty();
                                              // AlmanacState's ctor is non-const (§4 deep-immutability fix)

  AlmanacState get state;   // rebuilt from internal identity-indexed maps, lists in insertion order

  void beginRun({
    required String runId, required int runNumber, int? seed,
    required String lineageId, required String physiqueId, required DateTime startedAt,
  });

  void recordFight({
    required String runId, required String fightId, required int sequence,
    required String name, required String enemyId, required bool won,
    required num playerHealthAfter, required int turnsUsed,
  });

  void recordBuildSnapshot(AlmanacBuildRecord record);

  void recordTechniqueDiscovered({
    required String instanceId, required String baseFamilyId, String? styleId,
    required List<String> descriptorIds, required Map<String, num> axisProfile,
    required TechniqueOrigin origin, int? masteryAtDiscovery,
    required String runId, required int runNumber, required DateTime timestamp,
  });

  void recordTechniqueUsed(TechniqueUsageObservation observation);

  void recordTechniqueInspired({
    required String resultInstanceId, required String runId, required String familyId,
    required List<String> descriptorIds, required List<String> inspirerInstanceIds,
  });

  void recordItemDiscovered({
    required String definitionId, String? instanceId,
    required String runId, required int runNumber, required DateTime timestamp,
    required DiscoverySnapshot snapshot,
  });

  void recordAffixDiscovered({
    required String affixId, required AffixObservation observation,
    required AffixSnapshot snapshot, required DateTime timestamp,
  });
  void recordAffixUsed({required String affixId, required AffixObservation observation});

  void recordTrainingSession(TrainingObservation observation);

  void recordDiscovery(AlmanacDiscoveryRecord record);

  void recordMilestone({
    required MilestoneType type, required String runId, required int runNumber,
    required DateTime timestamp, String? contextId,
  });
  void evaluateStandardMilestones({
    required String runId, required int runNumber, required RunOutcome outcome,
    required String lineageId, String? finalBuildId, required DateTime timestamp,
  });

  void completeRun({
    required String runId, required DateTime completedAt,
    required RunOutcome outcome, String? finalBuildId,
  });
}
```

**Internal structure:**

```dart
// A structural composite key — NOT a concatenated string. Dart record types
// give value equality + hashCode for free; a `final class _BuildKey` with
// `==`/`hashCode` over the two fields is equivalent. Nothing ever parses it.
typedef _BuildKey = ({String runId, String buildId});

Map<String, _RunBuilder>                _runs;         // key: runId
Map<String, AlmanacTechniqueRecord>     _techniques;   // key: instanceId
Map<String, TechniqueInspirationHistory> _inspirations; // key: resultInstanceId
Map<String, AlmanacAffixRecord>         _affixes;      // key: affixId
Map<String, AlmanacDiscoveryRecord>     _discoveries;  // key: discoveryId
Map<String, AlmanacMilestoneRecord>     _milestones;   // key: milestoneId
Map<_BuildKey, AlmanacBuildRecord>      _builds;       // key: (runId, buildId) — structural
```

`_builds` is keyed by the **structural `(runId, buildId)` composite**, so a
lookup/upsert compares `runId == existing.runId && buildId == existing.buildId`
(via the value key's equality) and never concatenates or parses. Two runs that
happen to reuse the same `buildId` string are therefore distinct records.

Each map also records first-seen insertion order (a parallel `List` of keys, or
`LinkedHashMap`) so `state` materialises lists in the order records were first added.
`_RunBuilder` holds each run's `fights` keyed by `fightId` within that run
(i.e. structurally `(runId, fightId)`), its `trainingObservations` keyed by
`(runId, trainingEventId)`, and its `discoveryIds`.

### 5.1 Constructor hydration — `AlmanacRecorder([AlmanacState? initial])`

A first-class task (Phase 4.0), not an implicit detail. The constructor MUST:

1. **Rebuild indexes by replay, not by reference.** Iterate `initial.runs`, `initial.builds`, `initial.techniques`, `initial.inspirations`, `initial.affixes`, `initial.discoveries`, `initial.milestones` in list order and feed each record into the **same private insert path** the public `record…` methods use (`_upsertRun`, `_addFight`, `_upsertBuild`, `_upsertTechnique`, `_consumeUsageObservation`, `_upsertInspiration`, `_upsertAffix` + its observations, `_upsertDiscovery`, `_upsertMilestone`). Nested lists inside each record (fights, `usageObservations`, `discoveryObservations`, `usageObservations` (affix), `trainingObservations`, `descriptorIds`, `axisProfile`, snapshots) are **defensively copied** into the recorder's own representation exactly as an ingress from an adapter would be (§7). No `List`/`Map`/`Set` reference from `initial` is retained.
2. **Preserve insertion ordering.** The replay order is `initial`'s list order, so `recorder.state` reproduces the same ordering; observation ledgers keep their element order.
3. **Preserve identity & uniqueness invariants.** Because replay goes through the same insert paths, projections (`totalUsage`, `runsUsed`, affix counters, `firstDiscoveredRunId`, `associatedLineageIds`, per-run `enemiesDefeated` / `techniquesUsed` / `trainingSessions`) are **recomputed from the ledgers**, not trusted from `initial` — a persisted state whose projection disagrees with its ledger is normalised to the ledger-derived value (log-free; the ledger is canonical, §5, §6).
4. **Reject a corrupt input.** If `initial` contains **two records with the same identity key** — two `AlmanacRunRecord` with one `runId`; two `AlmanacBuildRecord` with the same structural **`(runId, buildId)`**; two `AlmanacTechniqueRecord` with one `instanceId`; two `TechniqueInspirationHistory` with one `resultInstanceId`; two `AlmanacAffixRecord` with one `affixId`; two `AlmanacDiscoveryRecord` with one `discoveryId`; two `AlmanacMilestoneRecord` with one `milestoneId`; or a ledger with two observations sharing its structural key (`(runId, fightId)`, `(runId, usageEventId)`, `(affixId, affixEventId)`, `(runId, trainingEventId)`) — the constructor throws `AlmanacIntegrityException`, for **conflicting** contents *and* for **byte-identical** duplicates, because a well-formed `AlmanacSerialization.stateToJson` never emits either (the one-record-per-identity invariant, spec §5.1). Fail-fast corrupt-input check, **not** a merge/recovery subsystem. All these comparisons are structural (field-by-field / value-key equality) — **no id is concatenated then parsed.**
5. **Future writes are invariant-preserving.** After hydration the recorder holds only its own copies; every subsequent `record…` call runs the same idempotency/monotonic/contradiction logic (§6) as on a fresh recorder.
6. **`recorder.state` stays deeply immutable** (§7) — hydration does not weaken egress copying.

**Tests required (Phase 4.0):**

- `load` a populated persisted state → `AlmanacRecorder(state)` → `recorder.state` **round-trips equal** to `state` (structural equality, same list order).
- hydrate → append new observations (a new run, a new usage observation on an existing technique) → resulting history is correct and projections match ledgers.
- hydrate, then **mutate the original `initial`'s collections** (add to `initial.runs`, mutate a nested `descriptorIds`) → `recorder.state` **unchanged**.
- mutate a collection returned by `recorder.state` → recorder internals **unchanged** (`.add` throws or is a no-copy).
- `initial` with a duplicated `runId` (identical contents) → `AlmanacIntegrityException`.
- `initial` with two `AlmanacBuildRecord`s sharing `(runId, buildId)` carrying **different** snapshots → `AlmanacIntegrityException`; sharing it with identical snapshots → also `AlmanacIntegrityException`.
- `initial` with two `AlmanacBuildRecord`s that share a `buildId` string but have **different `runId`** → **both retained** (distinct `_BuildKey`s).
- `initial` whose `AlmanacTechniqueRecord.totalUsage` disagrees with `usageObservations.length` → hydrated recorder reports the ledger-derived value.

**Milestone id derivation (never parsed back):** `milestoneId = contextId == null ? type.name : '${type.name}:$contextId'`. `evaluateStandardMilestones` also stores `type` + `contextId` as explicit fields; queries read those, never `split(':')`.

**Discovery id derivation:** the recorder forms `discoveryId` from `type` + `contentId` (or `instanceId` for `techniqueVariant`): `'${type.name}:$contentId'`. Explicit `type`/`contentId`/`instanceId`/`runId` fields on the record are authoritative.

**No RNG. No `dart:io`. No component access. No repository access.**

**Tests required (Phase 4):** every method's happy path; every idempotency key (deliver twice → one effect); `AlmanacIntegrityException` on each write-once conflict; monotonic `origin` (`base` then `inspired` → `inspired`; `inspired` then `base` → stays `inspired`); projections equal a fresh recompute from ledgers after an arbitrary event sequence.

---

## 6. Identity / idempotency design

**Key comparison rule.** A single-string key is compared by whole-string equality. A **pair / composite key** — written `(a, b)` below — is a structural value key: it compares `a == existing.a && b == existing.b` field-by-field (a Dart record `({a, b})` or a `_…Key` class with `==`/`hashCode`). **No key is ever formed by string concatenation, and no key string is ever parsed** (§11.2.1).

| Concern | Idempotency key | Explicit relational fields stored | Behaviour on repeat |
|---|---|---|---|
| Run | `runId` (string) | `runNumber`, `seed?` | `beginRun` twice → complete `UNKNOWN` fields only; conflict → `AlmanacIntegrityException` |
| Fight | `(runId, fightId)` — `fightId` unique within `runs[runId].fights` | `runId`, `sequence` | append only if absent; conflicting contents at same `(runId, fightId)` → exception |
| Build snapshot | **`_BuildKey(runId, buildId)`** — structural composite; `_builds: Map<_BuildKey, AlmanacBuildRecord>` | `runId`, `phase`, `sequence` | store if the `_BuildKey` is absent; a **byte-identical** payload at an existing `_BuildKey` → silent no-op; a **different** payload → `AlmanacIntegrityException` |
| Technique history | `instanceId` (string) | — | complete `UNKNOWN` fields; advance `origin` `base`→`inspired`; conflict → exception |
| Technique-usage observation | `(runId, usageEventId)` | `runId`, `runNumber`, `instanceId` | append only if that pair absent from `usageObservations` |
| Inspiration ancestry | `resultInstanceId` (string) | `runId` | store if absent; different payload for same key → exception |
| Discovery (first-seen) | `discoveryId` (string) | `type`, `contentId`, `runId`, `instanceId?` | first write canonical; later encounters add nothing |
| Affix history | `affixId` (string) | — | upsert |
| Affix observation | `(affixId, affixEventId)` | `affixId`, `runId`, `runNumber`, `lineageId?` | append only if that pair absent |
| Training observation | `(runId, trainingEventId)` | `runId`, `runNumber` | append only if that pair absent from `runs[runId].trainingObservations` |
| Milestone | `milestoneId` (string) | `type`, `contextId?` | first qualifying occurrence canonical; later qualifying events are no-ops |

**Uniqueness domain:** the recorder does **not** assume globally unique `buildId` / `fightId` / `usageEventId` / `affixEventId` / `trainingEventId`. The same opaque string under two `runId`s is two distinct records/observations, because every such key is the structural pair, not the bare string. All keys survive a `save`→`load` round-trip because the ledgers are serialized and the constructor rebuilds the composite indexes (§5.1).

**Spec alignment.** The design spec's authoritative identity table (spec §1.3) already lists the build-snapshot identity as `(runId, buildId)`; two shorthand mentions (spec §5.4, §7.2) said "`buildId`" alone — a genuine internal contradiction, now reconciled in the spec to `(runId, buildId)` to match §1.3. This plan implements the pair.

---

## 7. Snapshot / deep-immutability design

- **Ingress:** every recorder method that accepts a `List`/`Map` copies it (`List.of` / `Map.of`) before storing, recursively for nested collections. Snapshot value objects copy their own collection fields in their constructors (`this.descriptorIds = List.unmodifiable(descriptorIds)` etc.).
- **Storage:** the recorder never mutates a stored record; it replaces the map entry with a rebuilt instance when a field completes or a ledger grows.
- **Egress:** `AlmanacQueries` returns `List.unmodifiable` / `Map.unmodifiable` views or fresh copies; a query consumer cannot reach `AlmanacState`.
- **Adapters:** `HeadlessGameAlmanacBridge` builds every snapshot from `context` at observation time and passes only value objects — never a `ComponentStore` map, `TomePlacement` list, or `EntityId`.
- **Round-trip:** `decode(encode(state))` yields structurally-equal, independently-mutable-free collections.

**Tests required (Phase 1 + Phase 4):** mutate the caller's source list after `recordBuildSnapshot` → stored snapshot unchanged; mutate a `getBuild(...)` result list → `AlmanacState` unchanged; `encode`→`decode` then attempt `.add` on a nested list → throws.

---

## 8. Serialization & repository design

### 8.1 Dependency direction (no reverse edges)

```
almanac_models.dart          (pure value objects, each with toJson/fromJson)
        ▼
almanac_serialization.dart   (AlmanacState ↔ Map ↔ JSON string; schema version 1)
        ▼
almanac_repository.dart      (abstract AlmanacRepository + InMemoryAlmanacRepository)
        ▼
almanac_file_repository.dart (JsonFileAlmanacRepository → dart:io)   ← leaf, nothing imports it back
```

`almanac_serialization.dart` imports `almanac_models.dart` + `dart:convert`. `almanac_repository.dart` imports `almanac_models.dart` + `almanac_serialization.dart`. `almanac_file_repository.dart` imports all three + `dart:io`. Recorder and queries import `almanac_models.dart` only.

### 8.2 Public serialization API

```dart
class AlmanacSchemaVersionError implements Exception {
  AlmanacSchemaVersionError(this.found, this.expected);
  final Object? found;
  final int expected;
  @override
  String toString() =>
      'Almanac schema version $found is not supported (expected $expected)';
}

abstract final class AlmanacSerialization {
  static const int schemaVersion = 1;

  static Map<String, dynamic> stateToJson(AlmanacState state);   // adds 'almanacSchemaVersion': 1
  static AlmanacState stateFromJson(Map<String, dynamic> json);  // throws AlmanacSchemaVersionError if != 1
  static String encode(AlmanacState state);                       // jsonEncode(stateToJson(state))
  static AlmanacState decode(String text);                        // stateFromJson(jsonDecode(text) as Map<String, dynamic>)
}
```

### 8.3 Repository API

```dart
abstract interface class AlmanacRepository {
  AlmanacState load();
  void save(AlmanacState state);
}

class InMemoryAlmanacRepository implements AlmanacRepository {
  InMemoryAlmanacRepository([AlmanacState initial = const AlmanacState()]);
  // load() returns the held state; save() replaces it.
}
```

```dart
// almanac_file_repository.dart
class JsonFileAlmanacRepository implements AlmanacRepository {
  JsonFileAlmanacRepository(this._file);
  final File _file;

  @override
  AlmanacState load() => _file.existsSync()
      ? AlmanacSerialization.decode(_file.readAsStringSync())
      : const AlmanacState();

  @override
  void save(AlmanacState state) {
    // Serialize the COMPLETE state first — a serialization failure aborts
    // before any file is touched, so the on-disk Almanac is never partial.
    final payload = AlmanacSerialization.encode(state);
    _file.parent.createSync(recursive: true);
    // Atomic replace: write a sibling temp file, then rename over the
    // target. A crash leaves either the old complete file or the new
    // complete file — never a half-written one. No transactions, no DB.
    final tmp = File('${_file.path}.tmp');
    tmp.writeAsStringSync(payload, flush: true);
    tmp.renameSync(_file.path);
  }
}
```

Missing file → empty state. Malformed JSON → the `jsonDecode` / cast error propagates (fail loud). Schema mismatch → `AlmanacSchemaVersionError` (fail loud).

---

### 8.4 Behaviour summary

`almanacSchemaVersion = 1` written at the top of `stateToJson`. `stateFromJson` reads it first and throws `AlmanacSchemaVersionError(found, 1)` on mismatch — the migration seam. `encode`/`decode` are thin `jsonEncode`/`jsonDecode` wrappers. `InMemoryAlmanacRepository` is the neutral default; `JsonFileAlmanacRepository` (behind `lib/almanac_file.dart`) adds file IO.

### 8.5 Persistence atomicity contract

The repository boundary is deliberately **whole-state**, not incremental:

| Rule | Consequence for the implementer |
|---|---|
| `load()` returns a **complete** `AlmanacState` (or throws). | No caller ever sees a partial state. On a missing file, return `const AlmanacState()`. |
| `save(state)` takes a **complete** `AlmanacState` and writes a **complete** serialized snapshot. | There is **no** `saveRun(...)` / `appendFight(...)` / field-level persistence API. Do not add one. |
| `AlmanacRecorder` owns the whole canonical state in memory; `recorder.state` is always internally consistent (every projection matches its ledger — §5, §6). | The recorder never persists. A caller does `repo.save(recorder.state)` at whatever cadence it chooses (typically once, after `runGame` returns). |
| A failure during `save` must not leave a state that a later `load` would accept as valid-but-truncated. | `JsonFileAlmanacRepository.save` serializes fully first (a serialization error touches no file), then writes `<path>.tmp` and `renameSync`s it over `<path>` — a POSIX-atomic replace; best-effort on Windows. A crash between the two steps leaves the previous complete file intact. |
| No transactions, no database, no backend, no second persistence framework. | `dart:io` `File` + `rename` is the entire mechanism. `InMemoryAlmanacRepository` just holds the last `save`d reference. |

A custom (e.g. web-storage) `AlmanacRepository` in a client repo honours the same contract: `load` returns a whole state, `save` writes a whole state, partial writes are never surfaced as success.

**Tests required (Phase 2 + Phase 3):** `stateToJson`/`stateFromJson` round-trip on a fully-populated state (every record type, every ledger, `seed` present and absent); `encode`/`decode` round-trip; schema-version mismatch throws; `InMemory` save/load returns an equal state; `JsonFile` save/load via a `Directory.systemTemp.createTempSync` file; `JsonFile.load()` on a non-existent path returns `const AlmanacState()`; **after a successful `JsonFile.save`, no `<path>.tmp` remains**; **`JsonFile.save` of state B over an existing file holding state A, when serialization of B is forced to throw (inject via a state whose `toJson` throws in a test double), leaves the file still readable as state A**.

---

## 9. Query API — `almanac_queries.dart`

```dart
class AlmanacQueries {
  AlmanacQueries(this._state);
  final AlmanacState _state;

  List<AlmanacRunRecord> getRunHistory();                 // insertion order
  AlmanacRunRecord? getRun(String runId);
  List<AlmanacBuildRecord> getBuildHistory();
  AlmanacBuildRecord? getBuild(String runId, String buildId);   // matches b.runId == runId && b.buildId == buildId
  List<AlmanacBuildRecord> getBuildsForRun(String runId);       // b.runId == runId, in insertion order
  List<AlmanacRunRecord> getLineageHistory(String lineageId);   // runs with that lineageId
  AlmanacTechniqueRecord? getTechniqueHistory(String instanceId);
  List<TechniqueInspirationHistory> getTechniqueInspirations(String instanceId);
  AlmanacAffixRecord? getAffixHistory(String affixId);
  List<AlmanacDiscoveryRecord> getDiscoveries();
  List<AlmanacDiscoveryRecord> getRecentDiscoveries({int limit = 20});   // last N by insertion order
  List<AlmanacRunRecord> getRunsUsingTechnique(String instanceId);       // runs whose runId appears in the technique's usageObservations
  List<AlmanacBuildRecord> getBuildsUsingTechnique(String instanceId);   // builds whose techniques[] contains that instanceId
  List<AlmanacRunRecord> getRunsForLineage(String lineageId);
  List<AlmanacRunRecord> getRunsForPhysique(String physiqueId);

  LineageStatistics lineageStatistics(String lineageId);   // derived from records only
  List<MapEntry<String, int>> mostUsedTechniques({int limit = 10});   // (instanceId, totalUsage) desc, id asc tiebreak
  List<MapEntry<String, int>> mostUsedAffixes({int limit = 10});
  Map<AlmanacDiscoveryType, DiscoveryCompletion> discoveryCompletion({
    required Map<AlmanacDiscoveryType, Set<String>> known,
  });
}
```

`LineageStatistics` / `DiscoveryCompletion` are small `const` value objects. All list results are `List.unmodifiable`. Deterministic ordering: insertion order, or an explicit `(runNumber, id)` comparator where re-sorting. **No `.split` / `.startsWith` on any id.** `getRunsUsingTechnique` matches `observation.runId == run.runId`; `getBuild` matches `b.runId == runId && b.buildId == buildId` (both explicit fields — never a `buildId`-only lookup, never a parse).

**Tests required (Phase 5):** each getter on a hand-built state; `getBuild('run-A', 'build-1')` and `getBuild('run-B', 'build-1')` return the two *different* records when both exist (proves the composite match); `getRunsUsingTechnique` matches on the explicit `runId` field (proved by using an opaque `usageEventId` that does not textually contain the `runId`); determinism (same state → identical list order across two calls); `discoveryCompletion` fractions.

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

1. `tokens = [lineageId.toUpperCase(), physiqueId.toUpperCase(), ...sortedUnique(techniqueFamilies).map(upper), ...sortedUnique(itemIds).map(upper), ...sortedUnique(affixCategories).map(upper), ...topAxes]` where `topAxes` = axis names ordered by `(summedAbsValue desc, name asc)`, first 3, then re-sorted `name asc`, upper-cased.
2. `signature` = FNV-1a 32-bit hex of `tokens.join('|')` (pure integer arithmetic, no dependency).

`BuildDna` is a **derived projection**: `signature != buildId`, never a dedup key, recomputable from an `AlmanacBuildRecord`'s snapshot. Changing this algorithm reclassifies snapshots but invalidates no `buildId`.

**Tests required (Phase 6):** determinism (same inputs → same `signature`); input reordering → same `signature`; a changed input → different `signature`; `signature != buildId` for a sample build; FNV-1a matches a hand-computed value for a fixed token list.

---

## 11. Headless bridge — `lib/src/plugins/game/almanac_bridge.dart` + `runGame`

### 11.1 Bridge

```dart
// imports: package:build_engine/build_engine.dart,
//          package:build_engine/technique_plugin.dart,
//          package:build_engine/martial_arts_plugin.dart,
//          package:build_engine/almanac.dart,
//          sibling 'run_events.dart', and the physique event (via a plugin barrel).
class HeadlessGameAlmanacBridge {
  HeadlessGameAlmanacBridge(
    this._recorder, {
    required this.runId,     // caller-supplied opaque token — NEVER "run_$seed"
    required this.runNumber, // caller-supplied
    this.seed,               // metadata only, never keyed on
  });

  final AlmanacRecorder _recorder;
  final String runId;
  final int runNumber;
  final int? seed;

  // ---- run-local temporary context (legitimate for a composition adapter) ----
  int _encounterSeq = 0;        // per-run, incremented on EncounterStarted
  int _encounterTurns = 0;      // per-encounter, reset on EncounterStarted
  bool _encounterActive = false;// true between EncounterStarted and EncounterResolved
  final Map<BuildPhase, int> _buildSeq = {};   // per (run, phase)
  int _usageSeq = 0;            // per-run
  int _trainingSeq = 0;         // per-run
  String? _lineageId;           // from setRunProfile (no domain event carries it)
  String? _physiqueId;          // from setRunProfile / PhysiqueAssigned
  String? _finalBuildId;        // set when the RunEnded snapshot is taken
  bool _begun = false;
  bool _disposed = false;

  late final PluginContext _context;
  late final EntityId _character;
  final List<EventSubscription> _subs = <EventSubscription>[];

  /// Step 2 of §11.3. Binds the context the snapshot builders need and
  /// registers exactly one subscription per source event (§11.2). Every
  /// returned `EventSubscription` is stored in `_subs` and owned by THIS
  /// bridge instance. Idempotent: a second call is a no-op.
  void attach(EventBus events, PluginContext context, EntityId character) {
    if (_subs.isNotEmpty || _disposed) return;
    _context = context;
    _character = character;
    _subs.add(events.subscribe<PhysiqueAssigned>(_onPhysiqueAssigned));
    _subs.add(events.subscribe<TechniqueVariantMinted>(_onMinted));
    _subs.add(events.subscribe<TechniqueVariantInspired>(_onInspired));
    _subs.add(events.subscribe<SubjectDiscovered>(_onSubjectDiscovered));
    _subs.add(events.subscribe<ActionCompleted>(_onActionCompleted));
    _subs.add(events.subscribe<EncounterStarted>(_onEncounterStarted));
    _subs.add(events.subscribe<EncounterResolved>(_onEncounterResolved));
    _subs.add(events.subscribe<TrainingResultRecorded>(_onTrainingResult));
    _subs.add(events.subscribe<RunEnded>(_onRunEnded));
    // NOT observed for snapshots (§11.2, §11.2.1):
    //  * RunStarted   — pre-profile telemetry only (game_run.dart:143).
    //  * RewardSelected — a DECISION event published BEFORE resolveReward()
    //    mutates the Tome (reward_stage.dart) — too early for a snapshot;
    //    the reward's effect reaches history via SubjectDiscovered + the
    //    composition-driven postReward snapshot (§11.3 step 4a).
    //  * TomeChanged  — the `initial` snapshot is likewise composition-driven
    //    (§11.3 step 3a), removing a stepName-string dependency.
  }

  /// Step 3 of §11.3. Supplies the two facts no domain event carries. The
  /// first of the small set of explicit composition calls `runGame` makes
  /// into the bridge (see also `recordBuildPhase`, `detach`).
  void setRunProfile({required String lineageId, required String physiqueId}) {
    if (_disposed) return;
    _lineageId = lineageId;
    _physiqueId ??= physiqueId;
    _maybeBeginRun();
  }

  /// Steps 3a / 4a / 4b of §11.3 — a **state-boundary callback** the
  /// composition layer invokes AFTER a gameplay operation has fully
  /// applied its effects (`grantReward(...)` returned, `runTraining(...)`
  /// returned, starting kit placed). Only here does the bridge inspect
  /// live Tome/component state and build a snapshot. No-op before
  /// `beginRun` or after `detach`.
  void recordBuildPhase(BuildPhase phase) {
    if (!_begun || _disposed) return;
    _recorder.recordBuildSnapshot(
      _buildSnapshot(phase, sequence: _nextBuildSeq(phase)),
    );
  }

  void _onPhysiqueAssigned(PhysiqueAssigned e) {
    if (_disposed || e.character != _character) return;
    _physiqueId ??= e.physiqueId;
    _maybeBeginRun();
  }

  void _maybeBeginRun() {
    if (_begun || _disposed || _lineageId == null || _physiqueId == null) return;
    _begun = true;
    _recorder.beginRun(
      runId: runId, runNumber: runNumber, seed: seed,
      lineageId: _lineageId!, physiqueId: _physiqueId!, startedAt: DateTime.now(),
    );
  }

  void _onEncounterStarted(EncounterStarted e) {
    if (_disposed) return;
    _encounterActive = true;
    _encounterTurns = 0;
    _encounterSeq++;
  }

  void _onActionCompleted(ActionCompleted e) {
    if (_disposed) return;
    // (1) turnsUsed counts EVERY completed action while a fight is live —
    //     "actions executed, either side" (combat_stage.dart). Independent
    //     of whether the action came from a TechniqueVariant.
    if (_encounterActive) _encounterTurns++;
    // (2) INDEPENDENTLY, the exact combat_stage.dart:104-107 predicate:
    final ref = e.action.sourceRef;
    if (ref != null &&
        ref.referenceType == techniqueReferenceType &&
        ref.instanceEntityId != null) {
      _recorder.recordTechniqueUsed(TechniqueUsageObservation(
        usageEventId: '$runId:u${_usageSeq++}',
        runId: runId, runNumber: runNumber,
        instanceId: ref.instanceEntityId!.value.toString(),
      ));
    }
  }

  void _onEncounterResolved(EncounterResolved e) {
    if (_disposed) return;
    _recorder.recordFight(
      runId: runId,
      fightId: '$runId:e${_encounterSeq - 1}',
      sequence: _encounterSeq - 1,
      name: e.name, enemyId: e.enemyId, won: e.won,
      playerHealthAfter: e.playerHealthAfter,
      turnsUsed: _encounterTurns,
    );
    _encounterActive = false;
  }

  void _onTrainingResult(TrainingResultRecorded e) {
    if (_disposed) return;
    // Ledger only — NOT a snapshot boundary. TrainingResultRecorded is
    // published mid-runTraining, before mastery/learning/Tome/evolution
    // mutations, and the training branch then runs restoreHealth +
    // manageTome (training_stage.dart / game_run.dart:310-312). The
    // postTraining snapshot is taken by recordBuildPhase(postTraining)
    // AFTER that manageTome() call (game_run.dart:312).
    _recorder.recordTrainingSession(TrainingObservation(
      trainingEventId: '$runId:t${_trainingSeq++}',
      runId: runId, runNumber: runNumber,
    ));
  }

  // ... _onMinted / _onInspired / _onSubjectDiscovered / _onRunEnded per §11.2.
  // EVERY handler begins with `if (_disposed) return;`.

  /// Step 5 of §11.3. Cancels every subscription this bridge owns and marks
  /// the bridge dead. Safe to call more than once; a later EventBus publish
  /// reaches none of this bridge's handlers afterward.
  void detach() {
    if (_disposed) return;
    _disposed = true;
    for (final s in _subs) {
      s.cancel();   // EventSubscription.cancel() -> handlers.remove(wrapped); already idempotent
    }
    _subs.clear();
  }
}
```

Notes locked by the audit:

- Every subscription is created in `attach` and stored in `_subs`; the bridge is the sole owner. There is **no** module-level / static listener anywhere in `almanac_bridge.dart`.
- `EventBus.subscribe<T>` returns an `EventSubscription`; `cancel()` does `handlers.remove(wrapped)` (`lib/src/event/event_bus.dart:33`) — removing an absent handler is a harmless no-op, so `detach()` is idempotent without extra guards. The `_disposed` flag additionally makes every handler inert the instant `detach` runs, covering an in-flight `publish` iteration.
- `EventBus.publish` iterates `List.from(handlers)` (`event_bus.dart:52`), so a handler cancelling a subscription mid-dispatch is safe — but the bridge never does that; `detach` is only called from `runGame`.
- `attach` is idempotent (`_subs.isNotEmpty` guard) and refuses after `detach` (`_disposed` guard).

### 11.2 Bridge inputs — two categories

> **Almanac state snapshots are captured at composition operation-completion
> boundaries, not inferred from event publication timing.** An event tells the
> bridge *a decision was made* or *a fact occurred*; it does **not** prove the
> resulting gameplay state is already applied. `RewardSelected` fires *before*
> `resolveReward(...)` mutates the Tome (`reward_stage.dart`);
> `TrainingResultRecorded` fires *before* mastery / learning / Tome-swap /
> evolution / inspiration run (`training_stage.dart`). So the `postReward` /
> `postTraining` snapshots are taken from **explicit composition callbacks**
> after those operations return — never from the event.

#### (A) State-boundary inputs — the only points the bridge builds a snapshot

| Trigger | Where in `game_run.dart` | Bridge action |
|---|---|---|
| `bridge.recordBuildPhase(BuildPhase.initial)` | right after the starting-kit loop's first `manageTome()` (~L209) — kit is owned, discovered, placed | `recorder.recordBuildSnapshot(_buildSnapshot(initial, sequence: _nextBuildSeq(initial)))` → first (only) call yields `sequence 0` |
| `bridge.recordBuildPhase(BuildPhase.postReward)` | on the line **after each** `rewardStage.grantReward(...)` (3 sites, L321 / L328 / L335) — `grantReward` runs `resolveReward` to completion before returning, so the reward's Tome placement / `ownItem` / `context.resources.add` / slot unlock are all applied. This is a **per-reward** snapshot (each reward's immediate effect); a later cycle-end `manageTome()` (L338) rearrangement shows up in the next cycle's snapshots and in `finalBuild`. | `recorder.recordBuildSnapshot(_buildSnapshot(postReward, sequence: _nextBuildSeq(postReward)))` |
| `bridge.recordBuildPhase(BuildPhase.postTraining)` | on the line **after `manageTome()`** in the training branch (L312), i.e. **after** `trainingStage.runTraining(...)` (L310) **and** `restoreHealth(...)` (L311) **and** `manageTome()` (L312), immediately before `continue;` (L313) — so the snapshot reflects the *complete* training branch: mastery increase, item-usable placement, technique learning, `resolveTechniqueEvolutionAfterTraining`, `replaceWithEvolved`, `resolveTechniqueInspirationAfterTraining`, **and** the subsequent `manageTome()` pass (which can equip benched items / newly-usable items / known techniques, unequip, and spend upgrade points). | `recorder.recordBuildSnapshot(_buildSnapshot(postTraining, sequence: _nextBuildSeq(postTraining)))` |
| `RunEnded` (event — published *inside* `buildResult`, after the run is fully resolved) | `_onRunEnded` handler (**not** via `recordBuildPhase`, since it also does `completeRun` + milestones) | `s = _buildSnapshot(finalBuild, sequence: _nextBuildSeq(finalBuild))` (yields `0`); `_finalBuildId = s.buildId`; `recorder.recordBuildSnapshot(s)`; `recorder.completeRun(runId, completedAt: now, outcome: e.won ? won : lost, finalBuildId: _finalBuildId)`; `recorder.evaluateStandardMilestones(runId, runNumber, outcome, lineageId: _lineageId!, finalBuildId: _finalBuildId, timestamp: now)` |

`recordBuildPhase` (§11.1) is the smallest hook: a `void` composition callback, guarded `if (!_begun || _disposed) return;`, that inspects live state exactly once and hands the recorder an immutable `AlmanacBuildRecord`. `RunEnded` is genuinely a post-mutation boundary (the run is over when it publishes), so `finalBuild` stays on the event.

#### (B) Telemetry / observation inputs — never a snapshot boundary

Each row is one `_on…` method registered once in `attach`; every method first-lines `if (_disposed) return;`.

| Observed | Bridge action |
|---|---|
| `bridge.setRunProfile(lineageId, physiqueId)` (composition call, ~after `learnStyle` L170) | store `_lineageId`; `_physiqueId ??= physiqueId`; `_maybeBeginRun()` → `recorder.beginRun(...)` once physique **and** lineage are both known |
| `PhysiqueAssigned` for `_character` | `_physiqueId ??= e.physiqueId`; `_maybeBeginRun()` |
| `EncounterStarted` | `_encounterActive = true`; `_encounterTurns = 0`; `_encounterSeq++` (no recorder call) |
| `ActionCompleted` | **(1)** `if (_encounterActive) _encounterTurns++` — every completed action, either side, regardless of source. **(2)** *independently*, if `e.action.sourceRef?.referenceType == techniqueReferenceType && e.action.sourceRef?.instanceEntityId != null` (**the exact `combat_stage.dart:104-107` predicate**) → `recorder.recordTechniqueUsed(TechniqueUsageObservation(usageEventId: '$runId:u${_usageSeq++}', runId, runNumber, instanceId: ref.instanceEntityId!.value.toString()))`. The two are separate `if`s — a bare-handed / item / basic action still bumps `turnsUsed` and records no usage observation. |
| `EncounterResolved` | `recorder.recordFight(runId, fightId: '$runId:e${_encounterSeq - 1}', sequence: _encounterSeq - 1, name, enemyId, won, playerHealthAfter, turnsUsed: _encounterTurns)`; then `_encounterActive = false` |
| `TrainingResultRecorded` | **ledger only** — `recorder.recordTrainingSession(TrainingObservation(trainingEventId: '$runId:t${_trainingSeq++}', runId, runNumber))`. **No snapshot here** (the mutations that follow it inside `runTraining` are not yet applied). |
| `TechniqueVariantMinted` | `final v = _context.components.get<TechniqueVariant>(e.instanceId)!;` → `recorder.recordTechniqueDiscovered(instanceId: e.instanceId.value.toString(), baseFamilyId: e.baseFamilyId, styleId: v.styleId, descriptorIds: v.descriptorIds.toList(), axisProfile: Map.of(v.axisProfile), origin: TechniqueOrigin.base, masteryAtDiscovery: _masteryLevelOrNull(e.instanceId), runId, runNumber, timestamp: now)` |
| `TechniqueVariantInspired` | `recorder.recordTechniqueInspired(resultInstanceId: e.instanceId.value.toString(), runId, familyId: e.familyId, descriptorIds: e.descriptorIds.toList(), inspirerInstanceIds: [for (final i in e.inspirerInstanceIds) i.value.toString()])` |
| `SubjectDiscovered` where `techniqueSubjectId(e.subject) != null` | `recorder.recordDiscovery(AlmanacDiscoveryRecord(type: AlmanacDiscoveryType.technique, contentId: techniqueSubjectId(e.subject)!, runId, runNumber, timestamp: now, snapshot: const DiscoverySnapshot(label: 'technique', values: {})))` — `techniqueSubjectId` is the **Technique plugin's own** helper (the bridge imports that plugin); Almanac code never inspects the subject string |
| `SubjectDiscovered` where `itemSubjectId(e.subject) != null` | same, `type: AlmanacDiscoveryType.item`, via the **Item plugin's** helper |

**Not observed:** `RunStarted` (pre-profile), `RewardSelected` (pre-mutation decision — a future `AlmanacRewardRecord` could consume it, but v1 captures the reward's effect via `SubjectDiscovered` + the `postReward` snapshot), `TomeChanged` (the `initial` snapshot is a composition callback, dropping a `stepName`-string dependency).

`_nextBuildSeq(phase)` = `_buildSeq.update(phase, (n) => n + 1, ifAbsent: () => 0)` — returns the current value, then bumps it. So per run: `initial` → `sequence 0` (there is one), `postReward` → `0, 1, 2, …`, `postTraining` → `0, 1, 2, …`, `finalBuild` → `0` (taken once, on `RunEnded`).

`_buildId(BuildPhase phase, int sequence)` = `'$runId:${phase.name}:$sequence'`. This is the **bridge's** deterministic per-run scheme:

- **Uniqueness contract:** for a given run, the tuple `(runId, phase, sequence)` maps to **exactly one** `buildId` string, and the bridge only ever emits a given `(phase, sequence)` once per run (each `_nextBuildSeq(phase)` call yields a fresh integer; `finalBuild` is emitted once from the single `RunEnded` handler). So a well-behaved run produces one `AlmanacBuildRecord` per `buildId`.
- **Determinism:** replaying the same event stream through the bridge with the same `runId` produces the identical set of `buildId`s (§13.2 replay test).
- **Opacity downstream:** the recorder / queries / serialization treat `buildId` as an opaque whole string (§11.2.1). The record also carries `runId`, `phase`, `sequence` as explicit fields — those, never `buildId` parsing, are how any relationship is read.
- **Persistence identity:** the **structural composite `_BuildKey(runId, buildId)`** — the recorder's `_builds` map is `Map<_BuildKey, AlmanacBuildRecord>` (§5, §6). An upsert compares `runId == existing.runId && buildId == existing.buildId` (value-key equality); it refuses a **different** payload at an existing `_BuildKey` (`AlmanacIntegrityException`) and treats a **byte-identical** resubmission as a silent no-op. `runId` and `buildId` are never concatenated into one key string, and `buildId` is never parsed to recover `runId`. So `(run-A, build-1)` and `(run-B, build-1)` are two records.
- **`buildId` is not Build DNA identity.** `BuildDna.signature != buildId` (§10). DNA is a derived projection, never a key.
- The bridge's textual format is an **adapter implementation detail, not part of the Almanac API contract** — a production adapter may emit any opaque token (§11.2.1).

`_masteryLevelOrNull(instanceId)` = `context.mastery.levelOf(_character, techniqueInstanceSubject(instanceId))` if `techniqueInstanceSubject` is exported from `technique_plugin.dart` (watch-item, Pre-Implementation Blockers); otherwise `null` (spec-legal — the field stays `UNKNOWN`).

`_buildSnapshot(BuildPhase phase, {required int sequence})` builds one immutable `AlmanacBuildRecord` from `_context.tome.inspect(_character)` — `buildId: _buildId(phase, sequence)`, `runId: runId`, `phase: phase`, `sequence: sequence`, plus:
- `width`/`height` `null` (named-slot harness Tome).
- one `TomeSlotSnapshot` per placement: `slotId: p.slot.id`, `occupantKind: p.buildComponentRef.referenceType == techniqueReferenceType ? 'technique' : p.buildComponentRef.referenceType == itemReferenceType ? 'item' : 'empty'`, `occupantRefId: p.buildComponentRef.contentId`, `instanceId: p.buildComponentRef.instanceEntityId?.value.toString()`.
- `techniques`: for each technique placement with an `instanceEntityId`, a `TechniqueInstanceSnapshot` from the `TechniqueVariant` component + per-instance mastery level.
- `items`: for each item placement, an `ItemInstanceSnapshot` from `ItemInstance` (via `context.components`) — `resolvedProperties` copied from `statBonuses` at snapshot time.
- `affixes`: empty in v1 (finding §1: no affix identity).
- `dna`: `buildDna(lineageId: _lineageId!, physiqueId: _physiqueId!, techniqueFamilies: <baseFamilyIds>, itemIds: <definitionIds>, affixCategories: const [], axisProfiles: <from the technique snapshots>)`.

`_buildId` / `_nextBuildSeq` / `_buildSnapshot` are **instance methods** on `HeadlessGameAlmanacBridge`; `_buildSeq` resets with each bridge, so counters never leak between runs (§11.4).

### 11.2.1 Adapter-generated IDs are opaque downstream (implementation invariant)

The bridge builds `usageEventId` / `trainingEventId` / `fightId` / `buildId` by concatenating `runId` with a run-local counter (`'$runId:u$n'`, `'$runId:e$n'`, `'$runId:t$n'`, `_buildId(phase, n)`). This is **allowed** solely because the string is created and owned by the composition adapter and is never taken apart again.

**Allowed** (adapter, `almanac_bridge.dart`):

```dart
'$runId:e${_encounterSeq - 1}'            // mint an opaque token from runId + local seq
_buildId(BuildPhase.postReward, seq)      // -> '$runId:postReward:$seq', opaque thereafter
```

**Forbidden** (anywhere under `lib/src/plugins/almanac/`, and in tests):

```dart
buildId.split(':')                        // NO
usageEventId.startsWith(runId)            // NO
RegExp(r':e(\d+)$').firstMatch(fightId)   // NO
// reconstructing runId / phase / sequence from a composed id           NO
```

Enforcement:

- The architecture test (`almanac_architecture_test.dart`, Phase 8) already scans `almanac_recorder.dart` + `almanac_queries.dart` for `.split(` / `.startsWith(`; **extend that scan to every file under `lib/src/plugins/almanac/`** and to `RegExp(` used on an id-typed variable.
- **Test-authoring rule:** no test in `test/plugins/almanac/` or `test/integration/almanac_*` may `split` / `startsWith` / regex an Almanac id, or assert equality against a hand-built `'<runId>:…'` string as a *relationship* check. Relationships are asserted through explicit fields: `record.runId`, `record.phase`, `record.sequence`, `observation.runId`, `observation.instanceId`. Asserting a *full* id equals a full expected id (`fight.fightId == firstFight.fightId`) is fine — that is whole-string equality, not parsing.

### 11.3 Run lifecycle sequencing

The actual `game_run.dart` ordering is fixed and the plan does **not** move any of it:

```
create context → RunStarted → create character → initialize physique
  → choose tradition/style → learn style → Tome setup → gameplay → RunEnded
```

The bridge is a **composition adapter**: it may hold run-local temporary context (§11.1), but it never becomes gameplay authority — it makes no decision, mutates no gameplay state, and the recorder it feeds never touches `PluginContext`, the repository, or RNG. It attaches only *after the character exists* (handlers need it), and `RunStarted` is deliberately not the Almanac init event. The lifecycle, mapped onto the real call sites (no gameplay code is reordered for Almanac's benefit):

| # | `game_run.dart` point | Bridge step | Rationale |
|---|---|---|---|
| 0 | first statement of `runGame` body | **runtime guard**: `if (almanac != null && (runId == null || runNumber == null)) throw ArgumentError('runGame(almanac:) requires runId and runNumber');` — not `assert` (stripped in release). Inert when `almanac == null`. | Fail loud at the boundary; `runId!`/`runNumber!` safe afterward. |
| 1 | after `final events = eventBus ?? EventBus();` (~L124) | **construct** `HeadlessGameAlmanacBridge(almanac, runId: runId!, runNumber: runNumber!, seed: seed)` (guarded by `almanac != null`) | The caller has already supplied `runId` / `runNumber` / `seed`; the bridge holds them. No repository, no id generation. |
| 2 | after `context` is built (~L141), before `RunStarted` is published (L143) | `bridge.attach(events, context, character)` — **actually** attach after `character` is created (~L158), since a handler needs it. Attach registers one subscription per source event into `_subs`. | Subscriptions exist before the first observable domain event that matters. `RunStarted` (L143) is intentionally not observed (§11.1). |
| 3 | after `initializePhysique` (~L164) publishes `PhysiqueAssigned`, and after `learnStyle(character, styleId, context)` (~L170) | `bridge.setRunProfile(lineageId: martialTraditionOf(styleId) ?? styleId, physiqueId: physiqueId)` | **Physique** arrives via `PhysiqueAssigned` (`_onPhysiqueAssigned` already caught it) — `setRunProfile` re-passes it for safety. **Lineage/tradition/style** has *no domain event*; `runGame` holds `styleId` / `traditionId` as locals, so composition forwards it. Nothing is fabricated from an unrelated event. `_maybeBeginRun` fires `recorder.beginRun(...)` exactly once, when both facts are known. |
| 3a | after the starting-kit loop + its first `manageTome()` (~L209) | `bridge.recordBuildPhase(BuildPhase.initial)` | The kit is now owned / discovered / placed, so the snapshot is a true starting build. Composition callback, not an event — drops the `TomeChanged stepName=='starting'` dependency. |
| 4 | throughout the cycle loop | **event observation only** — `EncounterStarted`+`EncounterResolved`, `ActionCompleted`, `TrainingResultRecorded` (ledger only), `TechniqueVariantMinted`+`Inspired`, `SubjectDiscovered` (§11.2 B). A run already begun is enriched in place via monotonic completion (§6); a technique record created by `Minted` and completed by a later `Inspired` stays one record. **No snapshot is taken from any of these.** | The bridge never reorders or blocks gameplay; every handler is a pure translation to a recorder call. |
| 4a | on the line **after `manageTome()`** (L312) in the `choice == 'training'` branch — i.e. after `runTraining(...)` (L310), `restoreHealth(...)` (L311) **and** `manageTome()` (L312) — immediately before `continue;` (L313) | `bridge.recordBuildPhase(BuildPhase.postTraining)` | `runTraining` applies mastery / learning / evolution / inspiration; **then `manageTome()` can further mutate the Tome** (equip benched or newly-usable items, equip known techniques, unequip, spend upgrade points). `postTraining` is captured after the **complete training branch, including that management pass**, so it is the true post-training build the run presents. (§11.2 A) |
| 4b | on the line **after each** `rewardStage.grantReward(...)` returns (~L322 / ~L328 / ~L334) | `bridge.recordBuildPhase(BuildPhase.postReward)` | `grantReward` calls `resolveReward` internally, which has applied the reward (Tome placement, `ownItem`, `context.resources.add`, slot unlock) by the time it returns. `RewardSelected` fired earlier is a *decision*, not this boundary (§11.2 A). |
| 5 | inside `buildResult({required bool won})` (~L245), **immediately after** `events.publish(RunEnded(...))` | `bridge.detach()` | `EventBus.publish` is synchronous, so the bridge's `_onRunEnded` (final snapshot + `completeRun` + `evaluateStandardMilestones`) has already run when `publish` returns. `buildResult` is the **single funnel** for all four `runGame` return paths (three `return buildResult(won: false)` on fight loss + one `return buildResult(won: true)` at the cap), so one `detach()` call there covers every exit. |
| 6 | after `runGame` returns, in the **caller** | `repo.save(recorder.state)` | Whole-state persistence (§8.5). Never inside `runGame`. |

Explicit facts the plan commits to:

- **`RunStarted` is not assumed to carry complete run metadata.** It carries `seed` + `characterName` only, and is published before physique/style exist. The bridge ignores it.
- **Physique** comes from `PhysiqueAssigned` (`e.physiqueId`), filtered to `_character`.
- **Lineage / tradition / style** is *not* derivable from any event. It is supplied through the adapter's explicit composition API (`setRunProfile`), from values `runGame` already holds. It is never inferred from `PhysiqueAssigned`, tags, or any other event.
- **Any datum not available through an event is supplied through `setRunProfile`** (today: only `lineageId`). If a future need appears, extend `setRunProfile` — do not manufacture a gameplay event.
- **The recorder only ever receives completed primitive/snapshot observations.** The bridge does all `context` reads and builds every `TomeLayoutSnapshot` / `TechniqueInstanceSnapshot` / `ItemInstanceSnapshot` before calling the recorder.
- **Snapshots are captured at operation-completion boundaries, never at event-publication time.** `initial` / `postTraining` / `postReward` are `bridge.recordBuildPhase(...)` composition callbacks placed *after* the corresponding gameplay operation returns (steps 3a / 4a / 4b); `finalBuild` is the `RunEnded` handler (the run is fully resolved when it publishes). `RewardSelected` and `TrainingResultRecorded` are decision/telemetry — the bridge treats neither as proof the resulting build state is applied.
- **`recordBuildPhase` is the smallest hook.** It adds no new domain event; it is a narrowly-scoped `void` composition callback that the bridge alone acts on. `game_run.dart`'s reward/training order is unchanged — the callback is simply invoked on the line after the existing call returns.

`martialTraditionOf` is already importable — `game_run.dart` imports `package:build_engine/martial_arts_plugin.dart`.

### 11.4 Subscription lifecycle correctness

The bridge **owns every subscription it creates** and disposes them all when the run ends.

Guarantees (each becomes an acceptance criterion and a test, §13.1):

| Guarantee | How the plan achieves it |
|---|---|
| One observation per source event, per run | `attach` registers **exactly one** handler per event type into `_subs`; handlers are plain methods, not re-registered. |
| Two sequential runs never cross-observe | Each `runGame(almanac:)` call constructs a **fresh** `HeadlessGameAlmanacBridge` with its own `_subs`. Run A's bridge is `detach()`ed inside `buildResult` before `runGame` returns, so its handlers are removed from the `EventBus` before run B's bridge attaches (to a **new** `EventBus` anyway — `runGame` creates `events` per call unless the caller passes one). |
| No double recording from duplicate subscriptions | `attach` is guarded (`if (_subs.isNotEmpty || _disposed) return;`) so a mistaken second `attach` is a no-op. |
| No stale encounter/build/training state between runs | All run-local state (`_encounterSeq`, `_encounterTurns`, `_encounterActive`, `_buildSeq`, `_usageSeq`, `_trainingSeq`, `_lineageId`, `_physiqueId`, `_finalBuildId`, `_begun`) lives on the **instance**, discarded with it. There is no static/module state in `almanac_bridge.dart`. |
| No bridge subscription survives a completed run | `detach()` calls `s.cancel()` on every entry of `_subs` (→ `handlers.remove(wrapped)` in `EventBus`), sets `_disposed = true` (every handler early-returns thereafter), and clears `_subs`. |
| Disposal is safe and idempotent | `detach()` early-returns if `_disposed`; `EventSubscription.cancel()` on an already-removed handler is a harmless no-op (`event_bus.dart:33`). |
| Repeated attach/run/detach cycles stay correct | Each cycle is a new instance; nothing is reused. A test drives N cycles on one long-lived `EventBus` and asserts observation counts scale exactly ×N with no leakage. |

No global singleton listeners. No `EventBus` subclassing. The mechanism is exactly `EventBus.subscribe` / `EventSubscription.cancel` as they exist today.

### 11.5 `runGame` change (Phase 7)

`lib/src/plugins/game/game_run.dart` — new optional parameters, default off:

```dart
RunResult runGame(
  int seed, {
  String characterName = 'Player',
  RunDecisionPolicy policy = const DefaultRunDecisionPolicy(),
  EventBus? eventBus,
  AlmanacRecorder? almanac,   // NEW
  String? runId,              // NEW — required iff almanac != null
  int? runNumber,             // NEW — required iff almanac != null
});
```

**Runtime validation (not `assert`).** Dart assertions are stripped in
release/AOT, so the contract is enforced with an explicit throw. As the
very first statement of `runGame`'s body (before `Stopwatch`, before any
work), unconditionally:

```dart
if (almanac != null && (runId == null || runNumber == null)) {
  throw ArgumentError('runGame(almanac:) requires runId and runNumber');
}
```

- Runs only when `almanac != null` — `almanac == null` reaches the check, both sub-conditions short-circuit, nothing throws, behaviour is unchanged.
- After it, `runId!` / `runNumber!` are provably non-null.
- Introduces no repository access and no identity generation — it only rejects a missing caller-supplied value.
- `ArgumentError` matches the repo's existing input-rejection idiom (`tome_service.dart:45`, `item_combine.dart:94`, `progression_engine.dart:109`).

The **only** other `runGame` edits, every one `if (almanac != null)`-guarded and each a *single statement on the line after* an existing call (nothing in `game_run.dart` is reordered):

| Where | Edit |
|---|---|
| after `final events = eventBus ?? EventBus();` (~L124) | `_bridge = HeadlessGameAlmanacBridge(almanac, runId: runId!, runNumber: runNumber!, seed: seed);` (declare `HeadlessGameAlmanacBridge? _bridge;` at function top; `runId!`/`runNumber!` are safe — the runtime check above already ran) |
| after `final character = context.characters.create();` (~L158) | `_bridge!.attach(events, context, character);` |
| after `learnStyle(character, styleId, context);` (~L170) | `_bridge!.setRunProfile(lineageId: martialTraditionOf(styleId) ?? styleId, physiqueId: physiqueId);` |
| after the starting-kit loop's `manageTome();` (L211) | `_bridge?.recordBuildPhase(BuildPhase.initial);` |
| in the `choice == 'training'` branch, after `manageTome();` (L312) and **before `continue;`** (L313) — i.e. after `runTraining` + `restoreHealth` + `manageTome` | `_bridge?.recordBuildPhase(BuildPhase.postTraining);` |
| after **each** `rewardStage.grantReward('Cycle $cycleNumber Fight N', cycleIndex);` — 3 sites (L321 / L328 / L335) | `_bridge?.recordBuildPhase(BuildPhase.postReward);` |
| inside `RunResult buildResult({required bool won})`, on the line **after** `events.publish(RunEnded(won: won, encounterCount: combatStage.encounters.length));` | `_bridge?.detach();` |

That is one guard-throw + 8 guarded statements (construct, attach, setRunProfile, initial, postTraining, 3× postReward, detach), all inert when `almanac == null` (`_bridge` is `null` so the `_bridge?.` calls short-circuit and the `_bridge!` calls are inside `if (almanac != null)`). `buildResult` is the sole `RunResult` constructor site, so the single `detach()` there fires on every one of `runGame`'s four returns.

**When `almanac == null`:** the guard-throw's first sub-condition is false, `_bridge` stays `null`, and none of the edits do anything observable. `runGame` is byte-identical: no bridge, no subscriptions, no `RunEnded` observer beyond what already exists, no `context`/`rng`/`policy` interaction, no repository IO. Determinism, `DecisionLog` replay, and existing golden tests are untouched (§13.3).

### 11.6 Who supplies `runId` / `runNumber` (finding §1.9, spec §1.4)

The **headless caller** (a test, a CI balance job, a future harness driver). Pattern:

```dart
final repo = JsonFileAlmanacRepository(File('almanac.json'));   // or InMemory in tests
final recorder = AlmanacRecorder(repo.load());
final runNumber = recorder.state.runs.length + 1;               // caller's choice, outside runGame
final runId = 'run-${DateTime.now().microsecondsSinceEpoch}';   // opaque, unique per instance
final result = runGame(seed, policy: policy, almanac: recorder, runId: runId, runNumber: runNumber);
repo.save(recorder.state);
```

`runGame` never computes `runNumber` from repository history and never imports `AlmanacRepository`.

---

## 12. Production Tome-client adapter contract (out-of-repo)

`TomeClientAlmanacAdapter` lives in the client repository. This plan defines only the contract it must honour; **do not import or scaffold the client here.**

The client adapter MUST, using `package:build_engine/almanac.dart` only:

1. Allocate an opaque `runId` per run instance and a `runNumber` from its own history; call `recorder.beginRun(...)` once it knows lineage + physique.
2. For each resolved encounter, assign a per-run `sequence` and call `recorder.recordFight(runId, fightId: <opaque token it owns>, sequence, …)` — the recorder keys on the structural `(runId, fightId)` pair.
3. At each build milestone — **after** the operation that produces it has fully applied (post-reward: after the reward is granted *and* its Tome/inventory/resource effects are committed; post-training: after training's mastery/learning/Tome-swap/evolution/inspiration effects are committed) — assign a per-`(run, phase)` `sequence`, mint an **opaque `buildId` it owns** (any token — the recorder keys on the structural `(runId, buildId)` pair, never parses it), build an `AlmanacBuildRecord` with explicit `runId` / `buildId` / `phase` / `sequence` (snapshotting its own Tome model into `TomeLayoutSnapshot` — real `width`/`height` if its Tome is grid-shaped), and call `recorder.recordBuildSnapshot(...)`. **A "reward selected" / "training result" UI or domain event is a decision/telemetry signal, not this boundary** — the adapter snapshots at operation-completion, never at event-publication (mirrors §11.2 A / §11.3). Resubmitting the same `(runId, buildId)` with an identical snapshot is a safe no-op.
4. On first observation of a `TechniqueVariant` instance, call `recorder.recordTechniqueDiscovered(...)`; per performed technique action, call `recorder.recordTechniqueUsed(TechniqueUsageObservation(usageEventId: <its own stable action id, or a per-run sequence>, runId, runNumber, instanceId))`.
5. On its `TechniqueVariantInspired` equivalent, pass the payload verbatim to `recorder.recordTechniqueInspired(...)`.
6. Per completed training session, `recorder.recordTrainingSession(...)`.
7. On item discovery, `recorder.recordItemDiscovered(...)`. Affixes: only once the client has authoritative affix identity (see the deliberate-v1-limitation note in Global Constraints).
8. On run end, final build snapshot + `recorder.completeRun(...)` + `recorder.evaluateStandardMilestones(...)`.
9. Persist via its own `AlmanacRepository` implementation (may be `JsonFileAlmanacRepository` on desktop, or a custom web-storage implementation of the interface — the interface is web-safe).

The client adapter MUST NOT hand the recorder a live component, entity, event bus, or `PluginContext` — only value objects/snapshots. It MUST NOT parse any id string. Contract parity is proved in-repo by the synthetic adapter test (§13.2 / Phase 10); the client repo runs its own equivalent.

---

## 13. Tests

### 13.1 Unit — `test/plugins/almanac/`

| File | Proves |
|---|---|
| `almanac_models_test.dart` | per-record `toJson`/`fromJson` round-trip incl. all observation ledgers & `seed?`; unknown-enum-name throws; constructor copies collections (mutate source → record unchanged); returned collections are unmodifiable |
| `almanac_serialization_test.dart` | `stateToJson`/`stateFromJson` + `encode`/`decode` round-trip on a fully-populated state; `almanacSchemaVersion` written; mismatch → `AlmanacSchemaVersionError` |
| `almanac_repository_test.dart` | `InMemory` save/load returns an equal state; `JsonFile` save/load via temp file; `JsonFile.load()` on missing path → `const AlmanacState()`; `save` creates parent dir; **after a successful `save` no `<path>.tmp` remains** (atomicity, §8.5); **`save` of a state whose serialization throws, over a file holding state A, leaves the file still readable as A** (whole-state atomicity — use a test-double state or repo whose `encode` throws) |
| `almanac_platform_neutral_test.dart` | `lib/almanac.dart` + its transitive `almanac/` imports contain no `import 'dart:io'`; `almanac_file_repository.dart` is the sole `dart:io` file; `lib/almanac.dart` does not export `almanac_file*` |
| `almanac_recorder_test.dart` | begin/complete run; multiple runs separate; every method happy path; projections == fresh recompute after a random event sequence |
| `almanac_recorder_hydration_test.dart` | `AlmanacRecorder(state)` round-trips `.state` equal (same list order); hydrate then append new observations → correct, projections match ledgers; mutating `initial`'s collections post-construct → `.state` unchanged; mutating a `.state` collection → internals unchanged; duplicated `runId` (identical contents) → `AlmanacIntegrityException`; duplicated `buildId` (conflicting snapshot) → `AlmanacIntegrityException`; `initial` with `totalUsage` ≠ `usageObservations.length` → hydrated recorder reports the ledger-derived value (§5.1) |
| `almanac_build_identity_test.dart` | recorder keyed on the structural `_BuildKey(runId, buildId)` (`_builds: Map<_BuildKey, AlmanacBuildRecord>`), no concatenation, no parse. Cases: **`(run-A, build-1)` + `(run-B, build-1)` → 2 build records**; **`(run-A, build-1)` submitted twice with the identical snapshot → 1 record** (silent no-op); **`(run-A, build-1)` same id + conflicting payload → `AlmanacIntegrityException`**; distinct `(runId, phase, sequence)` from the bridge → distinct `_BuildKey`s → distinct records; two `finalBuild` submissions for one run → one canonical record. All relationship assertions via `build.runId` / `build.buildId` / `build.phase` / `build.sequence`, never a prefix parse; `getBuild('run-A','build-1')` ≠ `getBuild('run-B','build-1')` |
| `almanac_persist_query_determinism_test.dart` | build a populated `AlmanacState` → `AlmanacSerialization.encode` → `decode` → run every `AlmanacQueries` getter on both the original and the decoded state → **identical results and identical ordering**; structural round-trip equality of the whole state |
| `almanac_id_opacity_test.dart` | recorder + queries behave identically with structured ids (`run-1:u0`) and arbitrary opaque ids (`action-8f3a91`); a `usageEventId` that textually contains a *different* `runId` still binds to the explicit `runId` field |
| `almanac_run_identity_test.dart` | same `seed`, different `runId` → 2 `AlmanacRunRecord`s; ledgers disjoint even when the two runs reuse the *same* opaque `usageEventId` string; `seed` stored, keys nothing |
| `almanac_usage_uniqueness_domain_test.dart` | same opaque `usageEventId` under two `runId`s → 2 observations (`(runId, usageEventId)` key); no global-uniqueness assumption |
| `almanac_fight_identity_test.dart` | two `Bandit`/5-turn fights (seq 0,1) → 2 records; replay `EncounterResolved` → still 2; `enemiesDefeated` counts each win once |
| `almanac_bridge_turn_counting_test.dart` | fight = `EncounterStarted` → `ActionCompleted`(bare/basic, `sourceRef == null`) → `ActionCompleted`(technique, `sourceRef` identifies a `TechniqueVariant`) → `ActionCompleted`(bare/basic) → `EncounterResolved` ⇒ **`fight.turnsUsed == 3`** and **technique `usageObservations` for this run == 1**; an `ActionCompleted` published with **no active encounter** (before any `EncounterStarted`, or after `EncounterResolved`) does **not** change the next/previous fight's `turnsUsed`; a fresh `EncounterStarted` resets the counter to `0`; turn counting is a separate `if` from the technique predicate (an item/basic action still increments `turnsUsed`) |
| `almanac_snapshot_boundary_test.dart` | after `bridge.setRunProfile(...)` + a hand-fed `RewardSelected` (nothing else) → **no `postReward` build record exists**; then `bridge.recordBuildPhase(BuildPhase.postReward)` against a fake context whose `tome.inspect` now returns the reward's placement → the `postReward` snapshot's `TomeLayoutSnapshot` **contains that placement**. For training: a hand-fed `TrainingResultRecorded` alone → **no `postTraining` record**; then `recordBuildPhase(BuildPhase.postTraining)` against a fake context representing the state **after `runTraining` + `restoreHealth` + `manageTome()`** (e.g. `tome.inspect` shows a bench item that `manageTome` equipped, and/or the evolved `occupantRefId`) → the `postTraining` snapshot shows that **managed** Tome, not an intermediate one. `recordBuildPhase` before `beginRun` or after `detach` → no-op. |
| `almanac_build_snapshot_test.dart` | `postReward` seq 0 and 1 stay separate (assert via `build.sequence`); replay → no dup; `TomeLayoutSnapshot` preserves slot ids + instance ids; mutating a fake source list afterward leaves the stored snapshot unchanged |
| `almanac_technique_usage_test.dart` | two distinct `usageEventId`s, same run → `totalUsage` +2, `runsUsed` has run once; same `usageEventId` replayed → counts once; idempotency survives `save`→`load` between deliveries; `techniquesUsed for X` == count where `o.runId == X` |
| `almanac_monotonic_completion_test.dart` | `Minted`→`Inspired` **and** `Inspired`→`Minted` → one record, `origin: inspired`, ancestry present; lone `Inspired` leaves later fields `null` |
| `almanac_contradiction_test.dart` | second event with conflicting `descriptorIds` / `inspirerInstanceIds` / build-snapshot contents → `AlmanacIntegrityException`, established value retained |
| `almanac_inspiration_test.dart` | `TechniqueVariantInspired` payload verbatim + order-preserving; deliver twice → one `TechniqueInspirationHistory` + one technique record; no RNG, no Technique-state query |
| `almanac_cross_run_identity_test.dart` | same `baseFamilyId`, two runs, two instance ids → 2 `AlmanacTechniqueRecord`s |
| `almanac_immutability_test.dart` | mutate an adapter's source `List`/`Map` after a `record…` call → stored record unchanged; mutate a `List`/`Map` returned by `AlmanacQueries` → `AlmanacState` unchanged; a monotonic completion (`Minted` then `Inspired`) leaves the object previously returned by `getTechniqueHistory` unchanged (a new instance holds the completed field) |
| `almanac_affix_test.dart` | 3 `AffixObservation`s, distinct opaque `affixEventId`s, one `affixId` → 1 record, `timesDiscovered == 3`, `associatedLineageIds` unioned; repeat an `affixEventId` → unchanged |
| `almanac_milestone_identity_test.dart` | Runs 4,7,9 all win Western → one milestone (`type = firstWinWithLineage`, `contextId = western`) at Run 4; later runs don't mutate it; identity from explicit fields, not `milestoneId.split` |
| `almanac_lineage_test.dart` | `getRunsForLineage` / `lineageStatistics` correct and record-derived |
| `almanac_queries_test.dart` | every getter on a hand-built state; determinism (same state → identical order twice); `discoveryCompletion` fractions |
| `almanac_build_dna_test.dart` | deterministic; input reorder → same signature; input change → different; `signature != buildId`; FNV-1a matches a hand value |
| `almanac_bridge_lifecycle_test.dart` | drives a bare `EventBus` + a fake/minimal `PluginContext` + `character`. **(a)** one run: each source event published once → exactly one recorder observation; **(b)** two sequential attach→publish→`detach` cycles on the **same** `EventBus` with **fresh** bridges → no duplicated observations, no run-A event in run-B state; **(c)** after `detach()`, publishing every observed event type **and** calling `recordBuildPhase(...)` again → recorder state unchanged; **(d)** `detach()` called twice → no throw, state unchanged; **(e)** N attach/run/detach cycles → observation counts scale exactly ×N; **(f)** `attach` called twice on one bridge → still one subscription set; **(g)** counters (`_encounterSeq` / `_encounterActive` / `_buildSeq` etc.) never leak between instances; **(h)** `RewardSelected` / `TrainingResultRecorded` / `RunStarted` / `TomeChanged` are **not subscribed** (publishing them changes no build record) |
| `almanac_bridge_run_profile_test.dart` | `beginRun` is **not** emitted until both `PhysiqueAssigned` (or `setRunProfile` physique) **and** `setRunProfile` lineage are seen, in either order; `RunStarted` alone triggers nothing; lineage is never taken from `PhysiqueAssigned` |
| `almanac_architecture_test.dart` | §2 enforcement table + §3.2 assertions; **plus** every file under `lib/src/plugins/almanac/` contains no `.split(` / `.startsWith(` / `RegExp(` applied to an id (§11.2.1); `almanac_bridge.dart` contains no `static ` field of a subscription type and no module-level `EventSubscription` / `subscribe(` at library scope |
| `runGame_almanac_validation_test.dart` (in `test/plugins/game/`) | `runGame(seed, almanac: recorder, runId: null, runNumber: 1)` → **throws `ArgumentError`**; `runGame(seed, almanac: recorder, runId: 'opaque-run', runNumber: null)` → **throws `ArgumentError`**; `runGame(seed, almanac: null, runId: null, runNumber: null)` → existing behaviour, no throw, equal to `runGame(seed)` |

### 13.2 Integration — `test/integration/almanac_run_history_test.dart`

- 3 runs (own `runId` each, differing seeds/policies) → 3 distinct `AlmanacRunRecord`s; discoveries + final builds + lineage/physique captured.
- Same seed, two different `runId`s → two separate run records; fight/build/usage/training ledgers disjoint (matched on explicit `(runId, …)`).
- Same seed + same policy + same `runId` replayed through the bridge → equivalent `AlmanacState`.
- **Two full `runGame(almanac: recorder, …)` calls in one test, sharing one `AlmanacRecorder`, different `runId`s** → 2 `AlmanacRunRecord`s, no cross-run observations, each run's bridge subscriptions gone after its `runGame` returns (assert by publishing a stray `EncounterResolved` on the first run's `EventBus` after it returns and seeing no new fight).
- **Persist → re-hydrate → continue:** run 1 with `recorder1`; `repo.save(recorder1.state)`; `final recorder2 = AlmanacRecorder(repo.load());` run 2 with `recorder2` (new `runId`); `recorder2.state` holds **both** runs, run 1's history byte-identical to what run 1 produced, run 2 appended correctly.
- Whole-chronicle `encode`→`decode` round-trip via `JsonFileAlmanacRepository` (temp file); no `<path>.tmp` left behind; every `AlmanacQueries` getter returns identical ordered results before and after the round-trip (mirrors `almanac_persist_query_determinism_test.dart` at run scale).
- `almanac == null`: `runGame` result is byte-identical to a run without the parameter; assert `runGame` performs no repo IO (no `AlmanacRepository` / `JsonFileAlmanacRepository` referenced from `game_run.dart`) and no `HeadlessGameAlmanacBridge` is constructed; a determinism check (same seed+policy, `almanac == null`, twice → identical `RunResult`).
- **`postReward` snapshot reflects the applied reward.** Drive a `runGame(almanac:)` cycle whose reward is `RewardKind.itemOrTechnique` for an item that `isItemUsable` at grant time (so `resolveReward` calls `tomeManager.placeItem`). Assert the `postReward` `AlmanacBuildRecord` for that cycle (`phase == postReward`, matched by `runId` + `sequence`, not by parsing `buildId`) has a `TomeLayoutSnapshot` slot occupied by that item — i.e. the snapshot post-dates the reward mutation. Also assert a `RewardSelected` was published *before* that snapshot's timestamp/order (proves it isn't the trigger).
- **`postTraining` snapshot reflects the applied training *and* the subsequent `manageTome()` pass.** Drive a training cycle that makes an item usable / a technique known so it becomes eligible for `manageTome()` to equip. Assert the `postTraining` `AlmanacBuildRecord` for that cycle has the component **as `manageTome()` finally placed it** in its `TomeLayoutSnapshot` (slot occupied), not the intermediate post-`runTraining` state — i.e. the snapshot is taken *after* L312's `manageTome()`, not right after `runTraining` (L310). Also: `TrainingResultRecorded` was published before that snapshot; if the cycle evolves the technique, the snapshot shows the **evolved** `occupantRefId`; if `manageTome()` also spends banked upgrade points or unequips something, that is reflected too.
- **Full-run ordering by contents.** For a run with ≥1 reward cycle and ≥1 training cycle, assert per cycle: `initial` snapshot has only the starting kit; each `postReward` snapshot ⊇ the previous build + that cycle's reward; each `postTraining` snapshot ⊇ the training result; `finalBuild` == the last mutation state. Assertions compare **snapshot contents** (`TomeLayoutSnapshot` occupants, item classes), not merely record existence.

### 13.3 Golden / determinism protection

Before Phase 7, enumerate the existing tests that assert `runGame` output byte-for-byte or replay-stability (candidates: `test/plugins/game/*`, `test/game/*`, `test/integration/*` referencing `runGame` / `DecisionLog` / `RunResult`). Run the full suite green **before** and **after** the `runGame` change with no diff in those tests.

---

## 14. Documentation

- `ARCHITECTURE.md` — new `## Almanac — Persistent Player History` section: passive-observer/adapter model (`HeadlessGameAlmanacBridge` in-repo + out-of-repo `TomeClientAlmanacAdapter`); ids opaque, relationships explicit; `runId` ≠ `seed` ≠ `runNumber`, recorder never generates identity or reads a repo; canonical facts identity-stable & monotonic + `AlmanacIntegrityException`; observation ledgers + derived projections; deep value-aliasing immutability; `BuildDna` a projection not an identity; `dart:io` isolated behind `lib/almanac_file.dart` (web-safe neutral surface, `console_policy.dart` precedent); schema version 1; SP0b `TechniqueVariantInspired` relationship; ContentRegistry relationship; a `Save State ≠ Almanac History` subsection.
- `CHANGELOG.md` — under `## Unreleased`, `### Added — public API`: the two new barrels `package:build_engine/almanac.dart` (neutral) and `package:build_engine/almanac_file.dart` (`dart:io`), the model/recorder/queries/repository/serialization/build-DNA surface, and the opt-in `runGame(almanac:, runId:, runNumber:)` parameters (default-off, behaviour-preserving).

---

## 15. Commit sequence

Each task = one commit, builds & tests green standalone. `dart format .` + `dart analyze` clean at every commit.

### Phase 0 — repository verification (no code)

- [ ] **0.1** Re-run the §1 checks against `HEAD` of `almanac-v1`; confirm every API/signature/line-number in §1 still holds. Record any drift in this plan before proceeding. **Acceptance:** §1 matches the tree. **Risk:** the branch moved — if `game_run.dart` / `run_events.dart` / `technique_events.dart` changed, re-derive §11.2.
- [ ] **0.2** Enumerate the golden/determinism tests (§13.3) into a checklist file `docs/superpowers/plans/.almanac-golden-tests.md` (scratch). **Acceptance:** list exists; `dart test` is fully green now.

### Phase 1 — models (`almanac_models.dart`)

- [ ] **1.1** Create `lib/src/plugins/almanac/almanac_models.dart` with the enums + `_enumByName` helper. Test `almanac_models_test.dart`: unknown name throws; `.name` round-trips.
- [ ] **1.2** Add the three observation records + `toJson`/`fromJson`. Test: round-trip; `seed?`-style optionals.
- [ ] **1.3** Add the snapshots (`TechniqueInstanceSnapshot` … `BuildDna`). Test: round-trip; constructor copies collections (mutate source → unchanged); returned collection unmodifiable.
- [ ] **1.4** Add the canonical records + `AlmanacState`. Test: full round-trip of a populated `AlmanacState`.
- [ ] **1.5** `dart format` + `dart analyze` + `dart test test/plugins/almanac/almanac_models_test.dart`. Commit: `feat(almanac): domain model value objects + json`.

### Phase 2 — serialization (`almanac_serialization.dart`)

- [ ] **2.1** Write failing `almanac_serialization_test.dart`: `encode`→`decode` equality on a populated state; version written; mismatch throws.
- [ ] **2.2** Implement `AlmanacSchemaVersionError` + `AlmanacSerialization` (`stateToJson`/`stateFromJson`/`encode`/`decode`).
- [ ] **2.3** Tests green; `dart analyze` clean. Commit: `feat(almanac): schema-versioned serialization`.

### Phase 3 — repository (`almanac_repository.dart` + `almanac_file_repository.dart` + barrels)

- [ ] **3.1** `almanac_repository.dart`: `AlmanacRepository` interface (whole-state `load`/`save` only — §8.5) + `InMemoryAlmanacRepository`. Test `almanac_repository_test.dart`: in-memory save/load returns an equal state; no incremental/field-level API exists on the interface.
- [ ] **3.2** `almanac_file_repository.dart`: `JsonFileAlmanacRepository` (`dart:io`) — `save` = serialize-complete-first → write `<path>.tmp` → `renameSync` (§8.3, §8.5). Test: temp-file save/load; missing file → empty; `save` mkdirs; no `<path>.tmp` remains after success; a `save` whose serialization throws leaves the prior file intact and readable.
- [ ] **3.3** `lib/almanac.dart` (neutral barrel, §3.1) + `lib/almanac_file.dart` (`dart:io` barrel).
- [ ] **3.4** Extend `test/integration/architecture_dependency_test.dart`: add `'almanac.dart'` **and** `'almanac_file.dart'` to `_pluginBarrels`. Run full arch test — green.
- [ ] **3.5** `dart analyze` + `dart test`. Commit: `feat(almanac): repository abstraction + dart:io file repo behind own barrel`.

### Phase 4 — recorder (`almanac_recorder.dart`)

- [ ] **4.0 (recorder skeleton + constructor hydration)** — **File:** `lib/src/plugins/almanac/almanac_recorder.dart`. **Symbols:** the internal maps from §5 with their key types — `Map<String, _RunBuilder> _runs`, `Map<String, AlmanacTechniqueRecord> _techniques`, `Map<String, TechniqueInspirationHistory> _inspirations`, `Map<String, AlmanacAffixRecord> _affixes`, `Map<String, AlmanacDiscoveryRecord> _discoveries`, `Map<String, AlmanacMilestoneRecord> _milestones`, and **`typedef _BuildKey = ({String runId, String buildId});` with `Map<_BuildKey, AlmanacBuildRecord> _builds`** — each with a parallel insertion-order key list; private insert paths `_upsertRun` / `_addFight` / `_upsertBuild` / `_upsertTechnique` / `_consumeUsageObservation` / `_upsertInspiration` / `_upsertAffix` / `_upsertDiscovery` / `_upsertMilestone`; `AlmanacRecorder([AlmanacState? initial])` (defaults to `AlmanacState.empty()` — the model ctor is non-const); `AlmanacState get state`. **Rule:** the constructor replays `initial`'s seven record lists (in list order) through those private paths — copying every nested collection (§7), recomputing every projection from the ledgers, and throwing `AlmanacIntegrityException` on any duplicated identity key (identical *or* conflicting), builds compared by the structural `_BuildKey` (§5.1). No reference from `initial` is retained; `recorder.state` stays deeply immutable. **Tests** (`almanac_recorder_hydration_test.dart`): round-trip `state` → `AlmanacRecorder(state)` → `.state` equal (same order); hydrate then append → correct; mutate `initial` collections post-construct → `.state` unchanged; mutate a `.state` collection → internals unchanged; duplicated `runId` (identical) → `AlmanacIntegrityException`; two build records with the same `(runId, buildId)` (different snapshot) → `AlmanacIntegrityException`; two build records that share a `buildId` string but differ in `runId` → **both retained**; `totalUsage` ≠ `usageObservations.length` in `initial` → hydrated recorder reports the ledger value. **Acceptance:** §5.1 items 1-6 all demonstrably hold; `_builds` is `Map<_BuildKey, …>` in the source; `dart analyze` clean.
- [ ] **4.1** `AlmanacIntegrityException` + `AlmanacRecorder` skeleton (`beginRun`, `completeRun`, `state`) built on the Task-4.0 private paths. Test: begin→complete→one run record; `beginRun` twice → no dup; conflicting `beginRun` field → exception.
- [ ] **4.2** `recordFight` + `enemiesDefeated` projection. Test: two identical fights (seq 0,1) → 2; replay `fightId` → still 2; relationships asserted via `fight.runId` / `fight.sequence`, never by parsing `fightId` (§11.2.1).
- [ ] **4.3** `recordTechniqueDiscovered` / `recordTechniqueInspired` + monotonic `origin` + write-once completion + `AlmanacIntegrityException`. Test `almanac_monotonic_completion_test.dart` + `almanac_contradiction_test.dart` + `almanac_inspiration_test.dart`.
- [ ] **4.4** `recordTechniqueUsed` with `(runId, usageEventId)` key + `totalUsage`/`runsUsed` recompute. Test `almanac_technique_usage_test.dart` + `almanac_usage_uniqueness_domain_test.dart` + save/load-between-deliveries.
- [ ] **4.5** `recordAffixDiscovered` / `recordAffixUsed` + affix projections. Test `almanac_affix_test.dart`.
- [ ] **4.6** `recordTrainingSession` (`(runId, trainingEventId)` key) + `recordDiscovery` (+ append to `runs[runId].discoveryIds`) + `recordItemDiscovered`.
- [ ] **4.7** `recordBuildSnapshot` — **File:** `almanac_recorder.dart`. **Symbols:** the public `void recordBuildSnapshot(AlmanacBuildRecord record)` delegating to `_upsertBuild` (both `_BuildKey` and `Map<_BuildKey, AlmanacBuildRecord> _builds` were declared in Task 4.0). **Rule:** `_upsertBuild` computes `_BuildKey(runId: record.runId, buildId: record.buildId)`; if that key is absent → store (append its key to the insertion-order list); if present with a **byte-identical** `AlmanacBuildRecord` → silent no-op; if present with a **different** payload → `AlmanacIntegrityException(record: 'AlmanacBuildRecord(runId=${record.runId},buildId=${record.buildId})', field: '<first differing field>', established: <old>, rejected: <new>)`. Comparison is value-key equality — never `'$runId:$buildId'`, never `buildId.split`. Compute `record.dna` only if `record.dna.tokens` is empty (depends on Phase 6 — land 6 first or stub DNA and backfill). **Tests** (`almanac_build_identity_test.dart`): **`(run-A, build-1)` + `(run-B, build-1)` → 2 records**; **`(run-A, build-1)` twice, identical snapshot → 1 record**; **`(run-A, build-1)` + conflicting payload → `AlmanacIntegrityException`**; bridge-driven distinct `(runId, phase, sequence)` → distinct records; two `finalBuild` submissions for one run → 1 record; `getBuild('run-A','build-1')` and `getBuild('run-B','build-1')` return the two different records. **Acceptance:** `_builds` is `Map<_BuildKey, …>` in the source; no `buildId` concatenation/parse anywhere in `almanac/` or tests; all six cases green.
- [ ] **4.8** `recordMilestone` + `evaluateStandardMilestones` (explicit `type`+`contextId`). Test `almanac_milestone_identity_test.dart`.
- [ ] **4.9** `almanac_id_opacity_test.dart` + `almanac_run_identity_test.dart` + `almanac_cross_run_identity_test.dart`. Full `dart test test/plugins/almanac/`. Commit: `feat(almanac): identity-keyed monotonic recorder`.

### Phase 5 — queries (`almanac_queries.dart`)

- [ ] **5.1** Failing `almanac_queries_test.dart` for the required getters on a hand-built state.
- [ ] **5.2** Implement getters (insertion order, `List.unmodifiable`; `getRunsUsingTechnique` matches `observation.runId`; **`getBuild(String runId, String buildId)` matches `b.runId == runId && b.buildId == buildId`** — the composite, never a `buildId`-only scan; add `getBuildsForRun(String runId)`).
- [ ] **5.3** Aggregates: `lineageStatistics`, `mostUsedTechniques`, `mostUsedAffixes`, `discoveryCompletion` + `LineageStatistics`/`DiscoveryCompletion` value objects. Test `almanac_lineage_test.dart`.
- [ ] **5.4** Determinism test (same state → identical order twice). Commit: `feat(almanac): read-only query API`.

### Phase 6 — build DNA (`almanac_build_dna.dart`)

- [ ] **6.1** Failing `almanac_build_dna_test.dart`: determinism, reorder-invariance, change-sensitivity, `signature != buildId`, FNV-1a hand value.
- [ ] **6.2** Implement `buildDna` + FNV-1a. Green. Commit: `feat(almanac): deterministic build DNA signature`. *(Then backfill Task 4.7's DNA call.)*

### Phase 7 — headless bridge + `runGame`

- [ ] **7.1** Create `lib/src/plugins/game/almanac_bridge.dart` with `HeadlessGameAlmanacBridge` exactly per §11.1: constructor `(recorder, {runId, runNumber, seed})`; instance-only run-local fields (`_encounterSeq`, `_encounterTurns`, **`_encounterActive`**, `_buildSeq`, `_usageSeq`, `_trainingSeq`, `_lineageId`, `_physiqueId`, `_finalBuildId`, `_begun`, `_disposed`, `_subs`); `attach(EventBus, PluginContext, EntityId)` subscribing **only** `PhysiqueAssigned` / `TechniqueVariantMinted` / `TechniqueVariantInspired` / `SubjectDiscovered` / `ActionCompleted` / `EncounterStarted` / `EncounterResolved` / `TrainingResultRecorded` / `RunEnded` (guarded `if (_subs.isNotEmpty || _disposed) return;`) — **not** `RunStarted` / `RewardSelected` / `TomeChanged`; `setRunProfile({lineageId, physiqueId})`; **`recordBuildPhase(BuildPhase)` — the composition state-boundary callback (guard `if (!_begun || _disposed) return;`), the only place a snapshot is built for `initial` / `postReward` / `postTraining`**; `_maybeBeginRun`; `_nextBuildSeq`; **`_buildId(BuildPhase, int)` = `'$runId:${phase.name}:$sequence'`** (§11.2 uniqueness contract); `_masteryLevelOrNull`; `_buildSnapshot` (sets `buildId`/`runId`/`phase`/`sequence` explicit fields); `_onActionCompleted` with the **two independent `if`s** (turn count for every `ActionCompleted` while `_encounterActive`; technique-usage on the `combat_stage.dart:104-107` predicate); `_onEncounterStarted` sets `_encounterActive = true`, `_onEncounterResolved` sets it `false`; `_onTrainingResult` records the training **ledger only, no snapshot**; `detach()` (idempotent, sets `_disposed`, cancels every `_subs` entry, clears). **No `static` / library-scope subscription state; no id string is ever parsed (§11.2.1).** No `runGame` edit yet.
- [ ] **7.2** `almanac_bridge_lifecycle_test.dart` + `almanac_bridge_run_profile_test.dart` + `almanac_bridge_turn_counting_test.dart` + `almanac_snapshot_boundary_test.dart` (§13.1) — hand-driven `EventBus` + minimal/fake `PluginContext` + a `character` id. Prove: one-observation-per-event; two sequential fresh-bridge cycles on one bus → no duplication / no cross-run leak; post-`detach` publishes **and `recordBuildPhase`** are inert; double `detach` safe; N cycles scale ×N; `beginRun` deferred until physique+lineage both known in either order; **bare/technique/bare `ActionCompleted` sequence → `turnsUsed == 3`, usage observations == 1; `ActionCompleted` with no active encounter → no turn count; `EncounterStarted` resets to 0**; **`RewardSelected` / `TrainingResultRecorded` alone → no `postReward` / `postTraining` record; `recordBuildPhase(...)` after the mutating context → snapshot contains the change; `recordBuildPhase` before `beginRun` / after `detach` → no-op**.
- [ ] **7.3** Add `AlmanacRecorder? almanac`, `String? runId`, `int? runNumber` to `runGame`. **First** the runtime guard as the first body statement: `if (almanac != null && (runId == null || runNumber == null)) throw ArgumentError('runGame(almanac:) requires runId and runNumber');` — **not `assert`** (§11.5). **Then** apply the 8 guarded statements from §11.5's table, each a single line after an existing call, no reordering: construct `_bridge` after `events`; `_bridge!.attach(events, context, character)` after `character` (~L158); `_bridge!.setRunProfile(...)` after `learnStyle` (~L170); `_bridge?.recordBuildPhase(BuildPhase.initial)` after the starting-kit `manageTome()` (L211); `_bridge?.recordBuildPhase(BuildPhase.postTraining)` in the training branch after `manageTome()` (L312), before `continue;` (L313); `_bridge?.recordBuildPhase(BuildPhase.postReward)` after **each** `rewardStage.grantReward(...)` (L321 / L328 / L335); `_bridge?.detach()` in `buildResult` right after `events.publish(RunEnded(...))`.
- [ ] **7.4** `runGame_almanac_validation_test.dart` (§13.1) — `runId: null` → `ArgumentError`; `runNumber: null` → `ArgumentError`; `almanac: null` with both null → unchanged behaviour, equal to `runGame(seed)`. Then run the golden/determinism checklist from Task 0.2 — output **byte-identical** with `almanac == null` — and add a `runGame` determinism assertion (same seed+policy, no almanac, twice → equal `RunResult`).
- [ ] **7.5** `test/integration/almanac_run_history_test.dart` (§13.2), including the two-sequential-runs / stale-subscription, **persist → `AlmanacRecorder(repo.load())` → continue**, and the **`postReward` / `postTraining` snapshot-contents-prove-ordering** assertions. Commit: `feat(almanac): headless bridge + opt-in runGame wiring`.

### Phase 8 — architecture tests

- [ ] **8.1** `test/plugins/almanac/almanac_architecture_test.dart` — every assertion in §2 + §3.2.
- [ ] **8.2** `test/plugins/almanac/almanac_platform_neutral_test.dart` — §3.2.
- [ ] **8.3** New group in `architecture_dependency_test.dart`: gameplay-plugin dirs don't reference `almanac`. Full arch suite green. Commit: `test(almanac): architecture + platform-neutral guards`.

### Phase 9 — unit-test completeness pass

- [ ] **9.1** Fill any §13.1 file not yet created; ensure each spec-§13 case has a test. Commit: `test(almanac): complete unit coverage`.

### Phase 10 — integration hardening

- [ ] **10.1** Adapter-parity test `test/plugins/almanac/almanac_adapter_parity_test.dart` (§12 contract) — synthetic second adapter feeds the same recorder with (a) structured and (b) opaque ids; assert `AlmanacState` equality against the bridge's output for one scripted run. Commit: `test(almanac): adapter contract parity`.

### Phase 11 — documentation

- [ ] **11.1** `ARCHITECTURE.md` + `CHANGELOG.md` per §14. Commit: `docs(almanac): architecture + changelog`.

### Phase 12 — final validation

- [ ] **12.1** `dart format . && dart analyze && dart test` — all green. Manually confirm `Core purity / Dependency DAG / No circular plugin deps / No unmanaged RNG / No cross-plugin private imports` still PASS. Tick §16 acceptance checklist. Commit (if anything changed): `chore(almanac): final validation`.

---

## 16. Final acceptance checklist

- [ ] Almanac is a `lib/src/plugins/almanac/` composition module, not a `GamePlugin`.
- [ ] `lib/almanac.dart` imports resolve with **no** `dart:io`; architecture test proves it.
- [ ] `JsonFileAlmanacRepository` is the only `dart:io` file, behind `lib/almanac_file.dart`.
- [ ] Almanac imports Core only; no plugin/`game`/`build_interpretation` import; arch test proves it.
- [ ] No gameplay plugin imports `almanac`; arch test proves it.
- [ ] `runId` / `runNumber` supplied by the caller; `runGame` never generates identity, never reads a repo; `almanac == null` → byte-identical `runGame`.
- [ ] **`runGame` validates `runId`/`runNumber` at runtime with `throw ArgumentError` (not `assert`), only when `almanac != null`; works with assertions disabled.** (§11.5; `runGame_almanac_validation_test.dart`)
- [ ] `seed` stored as metadata only; `runId = "run_<seed>"` never used.
- [ ] **`AlmanacRecorder(initialState)` rebuilds indexes by replaying `initial` through the private insert paths, deep-copies every collection, recomputes projections from ledgers, and throws `AlmanacIntegrityException` on any duplicated identity key.** (§5.1; `almanac_recorder_hydration_test.dart`)
- [ ] **Adapter ID formatting is not part of the Almanac API contract:** the bridge composes readable ids from `runId` + a local counter; nothing under `lib/src/plugins/almanac/` (or any test) parses one; arch test scans the whole `almanac/` dir + tests for `.split`/`.startsWith`/`RegExp` on ids. (§11.2.1)
- [ ] Every id opaque; every relationship is an explicit field; tests assert relationships via `record.runId` / `.phase` / `.sequence`, never via textual prefix.
- [ ] `(runId, usageEventId)` / `(affixId, affixEventId)` / `(runId, trainingEventId)` keys; global id uniqueness not assumed.
- [ ] Canonical facts monotonic; conflicting write-once value → `AlmanacIntegrityException`; no silent overwrite/merge.
- [ ] `Minted`↔`Inspired` either order → one technique record, ancestry verbatim, `origin` `base`→`inspired` only.
- [ ] Snapshots deeply isolated; query results unmodifiable; source/result mutation can't alter `AlmanacState`; a valid later completion creates a new record instance, never mutates an exposed one.
- [ ] Fight identity is the structural `(runId, fightId)`; **build-snapshot identity is the structural `_BuildKey(runId, buildId)` — `_builds: Map<_BuildKey, AlmanacBuildRecord>`, compared field-by-field, never concatenated or parsed**. `(run-A, build-1)` + `(run-B, build-1)` → 2 records; `(run-A, build-1)` repeated identical → 1; `(run-A, build-1)` + conflicting payload → `AlmanacIntegrityException`; two `finalBuild` submissions → 1. (§5, §6, §11.2; `almanac_build_identity_test.dart`)
- [ ] Projections recomputable from ledgers; never updated without a ledger append.
- [ ] **Persist → re-hydrate → continue:** `AlmanacRecorder(repo.load())` then more runs → combined history correct, earlier runs unchanged; whole-state `encode`→`decode`→`AlmanacQueries` gives identical ordered results. (§13.2; `almanac_persist_query_determinism_test.dart`)
- [ ] **Run lifecycle** (§11.3): construct → attach (after `character`) → `setRunProfile` (lineage from composition, physique from `PhysiqueAssigned`) → `beginRun` once both known → observe → `RunEnded` finalize → `detach` in `buildResult` (single funnel for all 4 returns) → caller `repo.save`. `RunStarted` carries no metadata and is ignored.
- [ ] **Snapshot boundary timing** (§11.2 A, §11.3 3a/4a/4b): `initial` after the starting-kit `manageTome()` (L211); each `postReward` after its `grantReward(...)` (L321/328/335); `postTraining` after the **complete training branch** — `runTraining` **+ `restoreHealth` + `manageTome()`** (L312, before `continue;`), because `manageTome()` can itself equip/unequip/spend and change the build; `finalBuild` in the `RunEnded` handler. Never from `RewardSelected` / `TrainingResultRecorded`. Integration tests assert **snapshot contents** (applied reward's Tome placement; training's newly-eligible component after `manageTome()` equips it) prove the ordering, not mere record existence.
- [ ] **Fight turn counting** (§11.2 B): every `ActionCompleted` while `_encounterActive` increments `turnsUsed`, in a separate `if` from the technique-usage predicate (`combat_stage.dart:104-107`); bare/basic/item actions count toward `turnsUsed` with no usage observation; no active encounter → no count; `EncounterStarted` resets. Test: bare→technique→bare ⇒ `turnsUsed == 3`, usage == 1.
- [ ] **No new domain events** (§11.2, Blocker 5/6): `RewardSelected` / `TomeChanged` subscriptions dropped; `recordBuildPhase` is a narrow composition callback, not an event; `RewardApplied` / `TrainingApplied` are **not** added; `game_run.dart`'s event order is unchanged.
- [ ] **Subscription disposal** (§11.4): bridge owns every subscription; fresh bridge per `runGame`; `detach()` cancels all + `_disposed` guard; idempotent; no static listeners; two sequential runs never cross-observe; N attach/run/detach cycles scale ×N.
- [ ] **Repository atomicity** (§8.5): whole-state `load`/`save` only, no incremental API; `JsonFileAlmanacRepository.save` serializes fully then temp-file + `renameSync`; a failed `save` leaves the prior complete file; no transactions/DB.
- [ ] Affix model + queries + serialization present; **no** harness affix wiring (deliberate v1).
- [ ] `BuildDna` deterministic, order-normalized, RNG/ML-free, `signature != buildId`, recomputable.
- [ ] Serialization: schema version 1; missing file → empty; mismatch → `AlmanacSchemaVersionError`; round-trip stable.
- [ ] Query API pure, deterministic, no analytics engine.
- [ ] All new + existing architecture tests green; no existing test weakened.
- [ ] `ARCHITECTURE.md` + `CHANGELOG.md` updated, incl. `Save State ≠ Almanac History`.
- [ ] `dart format` / `dart analyze` / `dart test` green.

---

## Pre-Implementation Blockers

**None.** The plan is implementation-ready. The items below were raised and resolved during planning and are recorded here so an executor does not mistake them for open questions:

1. **Style / martial-tradition has no domain event.** `learnStyle` grants tags only; `game_run.dart` holds `styleId` / `traditionId` as locals. Consequence: the spec's *preferred* wiring (§11 option 1 — the caller builds the bridge, `runGame` never sees it) is **not viable**, because lineage is chosen inside `runGame` and no event carries it, so the bridge could never learn it. Resolution: adopt the spec's explicitly-**permitted** alternative (§11 option 2) — `runGame` takes `almanac` / `runId` / `runNumber` and constructs the bridge, and calls `bridge.setRunProfile(lineageId, physiqueId)` once (guarded by `almanac != null`) right after `learnStyle` (~`game_run.dart:170`), forwarding values it already holds. Still forbidden and still honoured: `runGame` never generates an id, never reads a repository, never computes `runNumber`. No new gameplay event is introduced (spec §16). `runGame` remains byte-identical when `almanac == null`.
2. **`RunStarted` fires before physique/style are chosen** (`game_run.dart:143`). Resolution: the bridge defers `beginRun` until `setRunProfile` supplies the profile; `_maybeBeginRun` is idempotent. `RunStarted` itself is a no-op for the bridge.

3. **`EncounterResolved` carries no `turnsUsed`, and turn counting must be independent of technique attribution.** Resolution: the bridge keeps `_encounterTurns` (`0` on `EncounterStarted`) and `_encounterActive` (`true` between `EncounterStarted`/`EncounterResolved`). `_onActionCompleted` runs **two separate `if`s**: `if (_encounterActive) _encounterTurns++` for *every* completed action either side (matching `combat_stage.dart`'s "actions executed, either side"); then, independently, `recordTechniqueUsed(...)` only when the action's `sourceRef` identifies a `TechniqueVariant` (the exact `combat_stage.dart:104-107` predicate). A bare/basic/item action still bumps `turnsUsed`. An `ActionCompleted` with no active encounter changes no fight. Not a gameplay change; no private `battle` id needed.
4. **Recorder build identity must be a structural composite, not a string.** Resolution: `_builds` is `Map<_BuildKey, AlmanacBuildRecord>` where `_BuildKey` is a value key `({String runId, String buildId})` (record type, or a `final class` with `==`/`hashCode`). Every build lookup/upsert compares `runId == existing.runId && buildId == existing.buildId`; nothing is concatenated into a key string and nothing is parsed back. Reflected identically in §5 internal structure, §5.1 hydration, §6 identity table, §11.2 `_upsertBuild`, §9 `getBuild(runId, buildId)`, Phases 4.0 / 4.7 / 5.2, and `almanac_build_identity_test.dart` — including the `(run-A, build-1)` + `(run-B, build-1)` → 2 records / `(run-A, build-1)` repeated → 1 / `(run-A, build-1)` + conflicting payload → `AlmanacIntegrityException` cases.
5. **`RewardSelected` is published *before* the reward is applied** (`reward_stage.dart`: `grantReward` publishes `RewardSelected`, then `resolveReward` mutates the Tome/inventory/resources). Resolution: the bridge does **not** subscribe to `RewardSelected`. The `postReward` snapshot is a `bridge.recordBuildPhase(BuildPhase.postReward)` composition callback on the line after **each** `rewardStage.grantReward(...)` returns (§11.3 step 4b) — the reward's Tome placement / `ownItem` / `context.resources.add` / slot unlock are all committed by then. The reward's effect also reaches history via `SubjectDiscovered`. No gameplay reordering; no new event.
6. **`TrainingResultRecorded` is published mid-`runTraining`, before mastery / item-usable placement / technique learning / `resolveTechniqueEvolutionAfterTraining` / `replaceWithEvolved` / `resolveTechniqueInspirationAfterTraining` — and the `game_run.dart` training branch continues with `restoreHealth(...)` then `manageTome()` after `runTraining` returns.** `manageTome()` is not bookkeeping: it can equip benched / newly-usable items, equip known techniques, unequip, and spend upgrade points, materially changing the Tome/build. Resolution: the bridge keeps observing `TrainingResultRecorded` **for the training ledger only** (`recordTrainingSession`); the `postTraining` snapshot is `bridge.recordBuildPhase(BuildPhase.postTraining)` on the line **after `manageTome()` (L312), before `continue;` (L313)** — i.e. after the *complete* training branch (`runTraining` + `restoreHealth` + `manageTome`), so it is the true post-training build the run presents. No gameplay reordering; no new event.

Watch-items (not blockers — verify in Phase 0 against the live branch):

- Per-instance mastery accessor `context.mastery.levelOf(owner, techniqueInstanceSubject(instanceId))` — confirm `techniqueInstanceSubject` is exported from `technique_plugin.dart` (used in `technique_variant_lifecycle.dart`); if not exported, `_masteryLevelOrNull` returns `null` and `masteryAtDiscovery` stays `UNKNOWN` (spec-legal).
- `SubjectDiscovered` subject-suffix helpers: confirm the Technique/Item plugins export `techniqueSubjectId` / `itemSubjectId` (or equivalent inverse of `techniqueSubject` / `itemSubject`). If neither exists, add the discovery-row wiring in a follow-up rather than parsing the subject string in Almanac code (§1.5). The bridge still records everything else.
- `ItemInstance` field names for `ItemInstanceSnapshot` (`definitionId`, `owner`, `itemClass`, `statBonuses`) — verified in `lib/src/plugins/item/item_instance.dart`; re-confirm in Phase 0.1.
- `PhysiqueAssigned` import path for the bridge — it lives in `lib/src/plugins/physique/physique_events.dart`; confirm it is re-exported from `package:build_engine/physique_plugin.dart` (add that export in a tiny separate commit if missing — a barrel-only change, not gameplay).

---

## Implementation Readiness Checklist

- [ ] **Architecture boundaries** — Almanac imports Core only; no gameplay plugin imports Almanac; `HeadlessGameAlmanacBridge` is the sole in-repo file importing both a gameplay plugin and Almanac; Core is unaware of Almanac; `TomeClientAlmanacAdapter` stays an external boundary. (§2, §12; arch tests §13.1 + Phase 8)
- [ ] **Web-safe barrel** — `lib/almanac.dart` transitively free of `dart:io`; `dart:io` only in `almanac_file_repository.dart` behind `lib/almanac_file.dart`; no conditional exports; no Flutter/Flame/Devvit/`dart:html`/`dart:ui`/DB/backend. (§3; `almanac_platform_neutral_test.dart`)
- [ ] **Opaque IDs** — no `split`/`startsWith`/regex/prefix parsing anywhere under `lib/src/plugins/almanac/` **or in any Almanac test**; adapter ID formatting (bridge composing `runId`+counter) is explicitly *not* an Almanac API contract; every relationship is an explicit stored field; arch test scans the whole `almanac/` dir. (Global Constraints, §6, §11.2.1; `almanac_id_opacity_test.dart`)
- [ ] **Build identity** — the recorder keys builds on the **structural composite `_BuildKey(runId, buildId)`** (`_builds: Map<_BuildKey, AlmanacBuildRecord>`), compared `runId == existing.runId && buildId == existing.buildId`, never concatenated, never parsed. `(run-A, build-1)` + `(run-B, build-1)` → 2 records; identical resubmission → no-op; conflicting payload → `AlmanacIntegrityException`; two `finalBuild` submissions → 1 record; `buildId` is opaque and is never Build DNA identity; the bridge maps `(runId, phase, sequence)` → exactly one `buildId` string it owns. Consistent in §5 internal structure, §5.1 hydration, §6 table, §11.2 `_upsertBuild`, §9 `getBuild(runId, buildId)`, and the tests. (§5, §5.1, §6, §9, §11.2; `almanac_build_identity_test.dart`)
- [ ] **Recorder hydration** — `AlmanacRecorder(initialState)` replays `initial` through the private insert paths, deep-copies every collection (no retained reference), recomputes projections from ledgers, throws `AlmanacIntegrityException` on any duplicated identity key (identical *or* conflicting); `recorder.state` stays deeply immutable; persist → `AlmanacRecorder(repo.load())` → continue works. (§5.1; `almanac_recorder_hydration_test.dart`)
- [ ] **Idempotency** — structural keys `(runId, usageEventId)`, `(affixId, affixEventId)`, `(runId, trainingEventId)`, plus `runId` / `fightId`-in-run / `buildId` / `instanceId` / `resultInstanceId` / `discoveryId` / `milestoneId`; no concatenated-string key whose parsing carries meaning; global uniqueness not assumed. (§6; `almanac_usage_uniqueness_domain_test.dart`)
- [ ] **Monotonic history** — `UNKNOWN → KNOWN → FINAL`, `base → inspired`; contradictory established value → `AlmanacIntegrityException`; no silent overwrite; no merge/recovery subsystem. (§5, §6; `almanac_monotonic_completion_test.dart`, `almanac_contradiction_test.dart`)
- [ ] **Deep immutability** — every stored `List`/`Set`/`Map` defensive-copied; query results `unmodifiable` / copies; a later completion yields a new value, never mutates a previously exposed record. (§7; `almanac_models_test.dart`, `almanac_immutability_test.dart`)
- [ ] **Serialization** — schema version 1; `stateFromJson` version-checks first (`AlmanacSchemaVersionError`); `encode`/`decode` round-trip stable incl. every ledger; missing file → `const AlmanacState()`. (§8; `almanac_serialization_test.dart`)
- [ ] **Run lifecycle** — explicit sequence construct → attach (after `character`) → `setRunProfile` → `beginRun` (physique from `PhysiqueAssigned`, lineage from composition, either order) → observe → `RunEnded` finalize → `detach` (single `buildResult` funnel) → caller `save`; `RunStarted` ignored; recorder never sees `PluginContext`/repo. (§11.3; `almanac_bridge_run_profile_test.dart`)
- [ ] **Snapshot boundary timing** — `initial` after the starting-kit `manageTome()` (L211); each `postReward` after its `grantReward(...)` (L321/328/335); **`postTraining` after the whole training branch — `runTraining` + `restoreHealth` + `manageTome()` (L312, before `continue;`)**, since `manageTome()` can equip benched/newly-usable items, equip known techniques, unequip, and spend upgrade points; `finalBuild` is the `RunEnded` handler. Never triggered by `RewardSelected` / `TrainingResultRecorded` (both fire before their mutations); `TrainingResultRecorded` feeds the training **ledger only**. Integration tests assert **snapshot contents**, including a training cycle where a newly-eligible item/technique is equipped by `manageTome()` and appears in the `postTraining` snapshot. (§11.2 A, §11.3 steps 3a/4a/4b; `almanac_snapshot_boundary_test.dart`, §13.2 reward/training/manageTome/full-run cases)
- [ ] **Fight turn counting** — `_encounterTurns++` runs for **every** `ActionCompleted` while `_encounterActive`, in a `separate if` from the technique-usage predicate; bare/basic/item actions count toward `turnsUsed` and record no usage observation. `ActionCompleted` with no active encounter changes no fight; `EncounterStarted` resets the counter. Test: bare→technique→bare ⇒ `turnsUsed == 3`, usage == 1. (§11.2 B; `almanac_bridge_turn_counting_test.dart`)
- [ ] **Subscription disposal** — bridge owns every `EventSubscription`; fresh bridge per `runGame`; `detach()` cancels all, sets `_disposed`, is idempotent; no static/module listeners; two sequential runs never cross-observe; repeated attach/run/detach scales exactly. (§11.4; `almanac_bridge_lifecycle_test.dart`)
- [ ] **Repository atomicity** — whole-state `load`/`save` only, no incremental API; `JsonFileAlmanacRepository.save` = serialize-complete → `<path>.tmp` → `renameSync`; failed `save` leaves the prior complete file; no transactions/DB. (§8.5; `almanac_repository_test.dart`)
- [ ] **SP0b ancestry** — `TechniqueVariantInspired` stored verbatim (`resultInstanceId`, `runId`, `familyId`, `descriptorIds`, `inspirerInstanceIds`), order preserved; never re-resolved, re-queried, or recomputed; no RNG in `almanac/`. (§6 of spec, §11.2; `almanac_inspiration_test.dart`)
- [ ] **Build DNA** — deterministic, order-normalized, RNG-free, ML-free, `signature != buildId`, recomputable from the snapshot, never a uniqueness key. (§10; `almanac_build_dna_test.dart`)
- [ ] **Headless adapter** — `_buildSnapshot` reads live Tome/component/mastery state in the bridge (via `recordBuildPhase` / `_onRunEnded`) and passes only completed value objects; snapshots are taken at operation-completion boundaries, never inferred from event timing; no manufactured gameplay events (`recordBuildPhase` is a narrow composition callback, not a new event); missing telemetry handled by bridge-local sequence/counter or `setRunProfile`. (§11.1–§11.3)
- [ ] **`runGame` opt-in behavior** — one runtime guard (`throw ArgumentError`, **not `assert`**, only when `almanac != null`) + 8 guarded statements (construct / attach / setRunProfile / `recordBuildPhase(initial)` / `recordBuildPhase(postTraining)` / 3× `recordBuildPhase(postReward)` / detach), each a single line after an existing call, **no gameplay reordering**; `almanac == null` ⇒ `_bridge` null, everything inert, byte-identical `RunResult`, determinism and `DecisionLog` replay unaffected. (§11.5; `runGame_almanac_validation_test.dart`, §13.2, §13.3)
- [ ] **Architecture tests** — new `almanac_architecture_test.dart` + `almanac_platform_neutral_test.dart` + extended `architecture_dependency_test.dart` (`_pluginBarrels` += `almanac.dart`, `almanac_file.dart`; gameplay-plugin dirs vs `almanac`); no existing architecture test weakened. (Phase 8)
- [ ] **Integration tests** — 3-run chronicle; same-seed-two-`runId` disjointness; two full `runGame(almanac:)` calls sharing one recorder with no cross-run leakage and no surviving subscriptions; whole-chronicle `JsonFile` round-trip with no `.tmp` residue. (§13.2)
- [ ] **Determinism / regression tests** — pre-Phase-7 golden list captured; `almanac == null` output byte-identical before/after; `runGame` determinism assertion (same seed+policy twice → equal `RunResult`); no Almanac-caused gameplay-state mutation. (§13.3, Phase 7.4)
