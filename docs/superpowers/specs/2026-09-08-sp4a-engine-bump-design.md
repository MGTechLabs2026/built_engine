# SP4a (engine) — Consumable Almanac DNA + the client-bump contract register

**Date:** 2026-09-08
**Status:** design — pending user review
**Repo:** `build_engine` (`Tome:RougelikeGame`), HEAD `1dc7e5d`
**Parent:** `2026-09-02-tiered-component-effects-design.md` §1.2 (SP0–SP4 decomposition)
**Brainstorm notes:** `2026-09-08-sp4a-engine-bump-notes.md` (full SP0a→SP3 audit; read for the evidence behind §5's register)
**Sibling spec:** `Tome_client:…-sp4a-client-bump-design.md` — the five staged dependency bumps; it cites §5 of this doc as the frozen contract per stage.

---

## 1. Why this exists

Parent-decomposition **SP4** ("`Tome_client` surfacing") was found un-buildable
as scoped: the client's `build_engine` pin (`314f75a`, 2026-09-01) is 139 commits
and five engine efforts behind HEAD (SP0a → SP0b → Almanac v1 → SP1 game-run →
SP1 tiered-effects → SP2 → SP3). SP4 is therefore split (notes §2, D2):

- **SP4a** — drag the client onto engine HEAD (no new UX), and close the one
  piece of *engine-repo* debt the SP-series left tagged "SP4".
- **SP4b** — the actual surfacing (tiered reward affixes, tier-grouped detail
  sheet, `AuraBinder`/`ConsumableBinder` adoption, a client Almanac adapter).
  Starts only after SP4a is fully merged and green (notes §2, D8).

**This spec covers the engine-repo half of SP4a.** It has two jobs:

1. **Part A** — teach the in-engine Almanac an SP3-consumable occupant kind, so
   `build_engine`'s own replay-equivalence coverage stops silently dropping
   consumable placements (debt recorded in `b0ee428`,
   `test/integration/almanac_run_history_test.dart`).
2. **The contract register (§5)** — freeze, per bump stage, the exact engine
   public surface the client migration consumes. The client spec must not
   assume any engine API not listed here as merged and verified.

There is **no engine code change for the bump stages themselves** — SP0a…SP3 are
already merged. Part A is the only new engine work.

## 2. Scope

### 2.1 In scope (Part A)

- `buildDna(...)` gains a `consumableIds` channel (`almanac_build_dna.dart`).
- `HeadlessGameAlmanacBridge._buildSnapshot` classifies a `consumable` Tome
  placement as `occupantKind: 'consumable'` and feeds the DNA channel
  (`almanac_bridge.dart`).
- `test/integration/almanac_run_history_test.dart` — split the occupant
  projection so the replay-equivalence check sees consumable placements while
  the discovery/monotonicity assertions keep their "discoverable kit" meaning;
  remove the `b0ee428` debt comment.
- `CHANGELOG.md` + `ARCHITECTURE.md` — the `buildDna` surface change and the
  Almanac "consumable occupant kind" note.

### 2.2 Out of scope

- A typed `ConsumablePlacementSnapshot` collection on `AlmanacBuildRecord`
  (notes D5 — no consumer needs one; SP4b adds it if a real client adapter
  does).
- Any `AlmanacRecorder` / query / serialization-schema change. Consumable
  placements ride in the existing `TomeLayoutSnapshot.slots` list and the
  existing `BuildDna.tokens` list; `AlmanacSerialization` schema v1 is
  unchanged (a new token in an existing `List<String>`, a new `String` value in
  an existing field).
- Any gameplay read of the Almanac, any new event, any RNG.
- Anything in `Tome_client`. That is the sibling spec.
- Retiring the client's legacy technique path, tiered affixes, binder adoption
  — SP4b.

## 3. Contract fit (`claude.md`)

| Rule | Compliance |
|------|-----------|
| Core provides verbs; plugins provide nouns. | `buildDna` already tokenises `itemIds` / `techniqueFamilies` / `affixCategories` — opaque id strings, no interpretation. `consumableIds` is the same: a sorted-unique upper-cased string projection. The bridge (`lib/src/plugins/game/`) is the *composition root*, already the one sanctioned in-repo file that imports gameplay plugins next to the Almanac. |
| No god classes / no new base class. | No new type. One parameter on a pure function; one ternary arm + one list-comprehension in an existing method. |
| No speculative abstraction. | The concrete consumer is `almanac_run_history_test.dart`'s replay-equivalence projection, today. Rejecting the typed-collection option (D5) is this rule applied. |
| Determinism; RNG only via `RngService`. | `buildDna` is explicitly RNG-free (`almanac_build_dna.dart` docstring). The bridge snapshot is a pure read of live Tome state. No new randomness. |
| Data flows one way: gameplay → recorder → state → client queries. | Unchanged. Part A only widens what the *observer* records; nothing reads it back. |

## 4. Part A design

### 4.1 The latent bug being fixed

`HeadlessGameAlmanacBridge._buildSnapshot` (`almanac_bridge.dart`) builds each
`TomeSlotSnapshot` with:

```dart
occupantKind: isTechnique ? 'technique' : isItem ? 'item' : 'empty',
occupantRefId: ref.contentId,   // always the real content id
```

A **consumable** placement (`ref.referenceType == consumableReferenceType`) is
neither technique nor item, so it is emitted as `occupantKind: 'empty'` **with a
non-null `occupantRefId`** — an internally inconsistent record. The SP3 reward
pool is a single flat list and `RewardKind.itemOrTechnique` draws consumables
too (`reward_stage.dart:68`, `run_content.dart`), so these inconsistent slots
occur in real headless runs (see the seed-3 note at
`almanac_run_history_test.dart:453`).

### 4.2 `buildDna()` — new `consumableIds` channel

`lib/src/plugins/almanac/almanac_build_dna.dart`

```dart
BuildDna buildDna({
  required String lineageId,
  required String physiqueId,
  required Iterable<String> techniqueFamilies,
  required Iterable<String> itemIds,
  required Iterable<String> consumableIds,   // NEW — required
  required Iterable<String> affixCategories,
  required Iterable<Map<String, num>> axisProfiles,
}) {
  final tokens = <String>[
    lineageId.toUpperCase(),
    physiqueId.toUpperCase(),
    ..._sortedUniqueUpper(techniqueFamilies),
    ..._sortedUniqueUpper(itemIds),
    ..._sortedUniqueUpper(consumableIds),   // NEW — fixed position
    ..._sortedUniqueUpper(affixCategories),
    ..._topAxisTokens(axisProfiles),
  ];
  return BuildDna(tokens: tokens, signature: _fnv1a32Hex(tokens.join('|')));
}
```

- **Fixed token position: after `itemIds`, before `affixCategories`.** Documented
  in the docstring alongside the existing ordering note.
- **Backward-compatible signature.** `_sortedUniqueUpper(const [])` contributes
  nothing, so every build with zero consumables hashes to the **same
  `signature`** as before. The reorder-invariance guard (`d2c8950`,
  `d2c8950 fix(almanac): JS-safe FNV-1a multiply; strengthen build-DNA reorder
  test`) still holds; add one case: a build with consumables hashes stably
  regardless of consumable placement order, and differently from the same build
  without them.
- **`required`, not optional-with-default.** `buildDna` has one in-repo caller
  (`almanac_bridge.dart:413`) and one recorder-internal caller
  (`almanac_recorder.dart:591`). A required parameter forces both to be updated
  deliberately (the recorder caller passes `const []` — it composes DNA from
  already-projected record fields that carry no consumable channel yet; that is
  correct and is noted at the call site). Mirrors how `techniqueFamilies` /
  `itemIds` are already required.

### 4.3 `HeadlessGameAlmanacBridge._buildSnapshot`

`lib/src/plugins/game/almanac_bridge.dart`

1. Add `import 'package:build_engine/consumable_plugin.dart';` (sibling-plugin
   import style; the file already imports `item_plugin.dart` /
   `technique_plugin.dart` / `combat_plugin.dart` / `physique_plugin.dart`).
2. In the placement loop, add the classification:
   ```dart
   final bool isConsumable = ref.referenceType == consumableReferenceType;
   ...
   occupantKind: isTechnique ? 'technique'
              : isItem       ? 'item'
              : isConsumable  ? 'consumable'
              : 'empty',
   ```
   `occupantRefId` stays `ref.contentId`; `instanceId` stays
   `ref.instanceEntityId?.value.toString()` — **null for a consumable** (no
   per-copy instanced entity: charges are a per-fight `ResourcePool` resource,
   not stored state — SP3 spec §5.1). No `techniques` / `items` snapshot list
   entry is added for a consumable; there is no per-copy state to record.
3. Feed the DNA channel:
   ```dart
   dna: buildDna(
     ...
     consumableIds: <String>[
       for (final TomePlacement p in placements)
         if (p.buildComponentRef.referenceType == consumableReferenceType)
           p.buildComponentRef.contentId,
     ],
     ...
   ),
   ```
   Collected straight from `placements` in the same loop pass (or a small
   second comprehension, matching the existing `techniques` / `items` style).

No new subscription, no recorder call, no gameplay read. `AlmanacBuildRecord`,
`TomeSlotSnapshot`, `TomeLayoutSnapshot`, `AlmanacSerialization` are all
untouched (the `TomeSlotSnapshot` docstring's "`'technique'`, `'item'`, or
`'empty'`" line gains "`'consumable'`").

### 4.4 `test/integration/almanac_run_history_test.dart`

The helper `_occupants(b)` (`{for s in b.tome.slots if occupantRefId != null &&
occupantKind != 'empty'}`) is used at five sites. Once the bridge emits
`'consumable'`, `!= 'empty'` stops filtering consumables — desired at one site,
wrong at the others:

| Line | Use | Wants consumables? |
|------|-----|---------------------|
| ~190 | replay-equivalence `project()` — `build\|…\|${_occupants(b)…}` | **yes** — this is the coverage the `b0ee428` note demands |
| ~411 | `newlyPlaced` → feeds a *discovery* assertion (`state.discoveries`) | **no** — consumables have no discovery subject (`_subjectLookup` is item/technique only); their ids would have no matching `disc\|` row |
| ~502, ~563 | monotonic-superset (`finalBuild ⊇ initial`, `chain[i] ⊇ chain[i-1]`) | harmless to include (fixtures only grow the kit) but not required |

**Change:** split the helper.

```dart
/// Item + technique occupants — the discoverable kit. Consumables are
/// deliberately excluded: they are real Tome occupants but carry no
/// discovery subject, so a discovery-delta assertion must not see them.
Set<String?> _discoverableOccupants(AlmanacBuildRecord b) => {
  for (final s in b.tome.slots)
    if (s.occupantRefId != null &&
        (s.occupantKind == 'item' || s.occupantKind == 'technique'))
      s.occupantRefId,
};

/// Every non-empty placement, consumables included — the full placed set
/// the replay-equivalence projection must reproduce.
Set<String?> _placedOccupants(AlmanacBuildRecord b) => {
  for (final s in b.tome.slots)
    if (s.occupantRefId != null && s.occupantKind != 'empty') s.occupantRefId,
};
```

- Line ~190 (replay `project()`): use `_placedOccupants`.
- Lines ~411, ~502, ~563: use `_discoverableOccupants` (preserves today's
  asserted behaviour exactly).
- Delete the "SP4 debt" doc-comment block; replace the surviving helper
  docstring per the above.
- **Add positive coverage:** assert that at least one of the replay run's build
  records carries an `occupantKind == 'consumable'` slot, and that the two
  `project()` passes still compare equal with consumables now inside the
  `build|` row and the `dna.signature`. (The `_ForceItemReward` policy on a seed
  whose reward pool yields a consumable already produces this — pick/confirm the
  seed, mirroring the existing `seed 3` note.)

### 4.5 Docs

- `CHANGELOG.md` — new **"Changed — SP4a (Almanac consumable DNA)"** entry:
  `buildDna` gains a required `consumableIds` channel (fixed token position;
  zero-consumable signatures unchanged); `HeadlessGameAlmanacBridge` now emits
  `occupantKind: 'consumable'` (was an inconsistent `'empty'` + non-null refId).
- `ARCHITECTURE.md` — the Almanac section's occupant-kind list gains
  `consumable`; one line that a consumable placement has no per-copy snapshot
  (no instanced entity).

## 5. Consumed-contract register (authoritative for the client spec)

Per bump stage: the exact engine ref to pin, and the public surface the client
migration is permitted to rely on. Everything here is **merged on `main` and
verified against source** (notes §1, §6). The client spec cites this table; if
the client needs an API not listed, that is a scope error — stop.

### Stage 1 — SP0a (technique instancing) · pin `cb32b02`

- **Relied on:** unchanged base-family accessors — `techniqueDefinition`,
  `discoverTechnique`, `isTechniqueDiscovered`, `isTechniqueLearned`,
  `techniqueMasteryLevel`, `trainTechniqueMastery`, `attemptToLearnTechnique`.
  `addTechniqueToTome` / `TomeService.insert` / `.replace` with a bare
  `BuildComponentRef` (null `instanceEntityId`) — **documented legacy path**,
  still resolves as the bare base.
- **Present but NOT relied on in SP4a:** `TechniqueVariant`,
  `mintTechniqueVariant`, `hangTechniqueVariant`, `removeTechniqueVariant`,
  `ownedTechniqueVariants`, `TechniqueVariantResolver`, `composeAxisProfile`,
  `techniqueInstanceSubject`, `trainTechniqueVariantMastery`,
  `techniqueVariantMasteryLevel`, `mintVariantForLegacyEvolvedId`,
  `LegacyTechniqueMigrationException`, `TechniqueDescriptor`, `TechniqueAxes`,
  events `TechniqueVariantMinted` / `TechniqueVariantRemoved`, optional
  `instanceId` on `TechniqueAddedToTome`. (SP4b consumes these.)
- **Client compatibility work:** none expected (compile-clean, inert).
- **Migration hazard:** `mintVariantForLegacyEvolvedId` is the only path that
  throws `LegacyTechniqueMigrationException`; the client must not call it. Its
  evolution stays `resolveTechniqueEvolutionAfterTraining` → string id →
  `tome.replace` (null instance).

### Stage 2 — SP0b (technique inspiration/discovery) · pin `ff8c7db`

- **Relied on:** `resolveTechniqueEvolutionAfterTraining(owner, technique,
  profile, context) → EvolutionResult { evolved, chosenCandidate.targetId,
  eligibleCandidates }` — **signature + shape verified unchanged at HEAD**
  (`technique_evolution.dart:50`).
- **Present but NOT relied on:** `CombatAction.sourceRef` (+ matching optional
  ctor param on `AttackAction` / `SelfEffectAction`), `TechniqueUsageComponent`,
  `recordTechniqueVariantUsage`, `techniqueVariantUsage`,
  `TechniqueInspirationResolver`, `Inspirer` / `InspirationResult`,
  `resolveTechniqueInspirationAfterTraining`, `TechniqueVariantInspired`,
  `styleCentre`, `techniqueFamilyOf`, `requireTechniqueVariant`, the
  `kInspiration*` constants.
- **Client compatibility work:** none. The inspiration hook is not called; the
  client owns no `TechniqueVariant` for it to draw from; no `context.rng` draw
  occurs.
- **Optional-param note:** `AttackAction` / `SelfEffectAction` gained an optional
  named `sourceRef`. The client's existing constructions are unaffected.

### Stage 3 — SP1 (tiered component effects) · pin `0663e8e`

This pin also crosses **Almanac v1** (`runGame(almanac:, runId:, runNumber:)`,
`almanac.dart` / `almanac_file.dart` barrels, `buildDna` / `BuildDna`) and the
**SP1 game-run migration** (`2026-09-04-…`). Both are **inert for the client**:
it calls no `runGame`, constructs no `AlmanacRecorder`, imports no `almanac*`
barrel; and it stays on the legacy null-instance technique path so the
game-run's variant-first `TrainingStage` rewrite and typed `RunTrainingTarget`
policies never touch it (the client uses no engine decision policy).

- **Relied on (changed surface):**
  - `TomeService.resolve(EntityId owner, {required List<BuildComponentRef>
    ownedRefs}) → ResolvedBuild`. `ResolvedBuild` exposes `owner` / `active` /
    `owned` / `asActiveBuild` — **no `.components`**.
  - `BuildActionInterpreter.interpret({required ResolvedBuild build, …})`
    (`ItemActionInterpreter` included).
  - `ItemInstance.statBonuses` (field) and `addItemStatBonuses` (writer) —
    **retained**; now feed `ItemEffectContributor`'s `supporting` tier instead
    of an `affix:*` `Modifier`. Client reads/writes stay valid.
  - `WeaponStatTags` — relocated to `item_plugin.dart`; compat re-export from
    `build_interpretation.dart` retained, so `show WeaponStatTags` imports keep
    working.
- **Present but NOT relied on:** `EffectTier`, `EffectProfile`,
  `EffectContributor`, `EffectProfileResolver`, `ItemEffectContributor`
  (directly), `BuildComponentRef` value equality (as a client concern), the
  `active`/`permanent` tiers. (SP4b consumes `EffectContributor` for tiered
  affixes.)
- **Client compatibility work — the one hard compile break:**
  `combat_adapter.dart`:
  1. `_ctx.tome.resolve(_me)` → `_ctx.tome.resolve(_me, ownedRefs: const [])`
     (`// SP4b: derive real ownedRefs` — reference: `game_run.dart`
     `ownedComponentRefs(character, context)`).
  2. `build.components` (×2) → `build.active`.
  3. `_itemInterpreter.interpret(build: build, …)` — correct once `build` is the
     `ResolvedBuild` from (1).
- **Behavioural drift to expect:** two hung copies of one item now each
  contribute scaled `attack` (old `build:<itemId>` source collapsed
  duplicates); item modifier source is per-actor. Re-baseline any drifted
  `combat_adapter_test.dart` / `combat_mastery_test.dart` inline seed
  expectations to observed values (notes §7 case 1). Grep client tests for
  `affix:` / `build:` / `removeBySource(` modifier-source assertions
  (none expected).

### Stage 4 — SP2 (per-active auras) · pin `dc213d4`

- **Relied on:** nothing new. `const ItemActionInterpreter()` still constructs
  and still `interpret`s.
- **Present but NOT relied on:** `AuraScope`, `AuraRule`, `AuraContributor`,
  `ItemAuraContributor` / `TechniqueAuraContributor`, `SubjectIs`, `AuraBinder`
  / `AuraBinding`, `BuildActionInterpreter.auraRules({build, context})`,
  `ItemDefinition.auraRuleIds` / `TechniqueDefinition.auraRuleIds`, the `auras`
  content field, `ContentRegistry.hasTrigger`,
  `CombatPlugin.initialize`'s `TurnStarted` / `TurnEnded` / `ActionCompleted`
  trigger registration. (SP4b consumes `AuraBinder`.)
- **`auraRules()` interface addition — non-breaking for the client:** it
  implements/subclasses no `BuildActionInterpreter` or
  `CompositeBuildActionInterpreter`, has no interface test double, builds no
  interpreter list. The concrete `ItemActionInterpreter` gains a method the
  client never calls.
- **Client compatibility work:** none — but **lock the init order.**
  `engine_session.dart` already initialises `CombatPlugin` **before**
  `ItemPlugin` / `TechniquePlugin`; the `hasTrigger`-gated aura-content load
  requires Combat-first, permanently, for that `PluginContext`. Add a comment at
  the `CombatPlugin()..initialize(context)` line stating this is load-bearing
  (CHANGELOG: "the constraint any future composition root must honour").
- **Inert-content check:** the engine added `auras` keys to 7 content ids
  (`cloth_armor`, `training_staff`, `training_shoes`, `warlords_iron_sword`,
  `crushing_gauntlets`, `basic_guard`, `basic_slash`). The client never calls
  `AuraBinder`, so a hung one of these contributes **no aura** in the client.
  Verify a client build hanging one produces identical combat numbers pre/post
  bump — a drift there means an aura path leaked in; **stop**.

### Stage 5 — SP3 (per-fight consumables) · pin `1dc7e5d` (engine HEAD)

- **Relied on:** nothing new. `RuleContext.modifiers` default keeps
  `RuleEngine._fire` identical; `AttackAction` / `SelfEffectAction` gain an
  optional `priority` param (client constructions unaffected).
- **Present but NOT relied on:** the entire `consumable_plugin.dart` barrel
  (`ConsumablePlugin`, `ConsumableDefinition`, `ConsumableTarget`,
  `ConsumableEffectSpec` + 4 variants, `consumableReferenceType`,
  `consumableChargeResource`, `consumableDefinition*`, `ConsumableIds`),
  `RemoveAllStatuses`, `GrantModifier`, `ConsumableActionInterpreter`,
  `ConsumableBinder` / `ConsumableCharges`, `ConsumableAwareActionScorer`, the
  engine `RewardStage` / `TomeManager.placeConsumable` reward-pool wiring, the
  C1 `ResourceAbove` guard + fallback-strike injection. (SP4b consumes
  `ConsumableBinder`; the C1 pattern is SP4b's reference for a client consumable
  loop.)
- **Client compatibility work:** none. `ConsumablePlugin` is **not** registered
  in `engine_session.dart` and must not be in SP4a. The client's combat pool has
  no consumable branch; it has its own fallback strike
  (`combat_adapter._Resolver`), so C1 does not apply to it.
- **Final-stage gate:** run `scripts/package_itch.sh` (web release build) — it
  is in client CI.

### After Stage 5

Client is on engine HEAD, gate green. Part A (this repo) is merged. **Only then**
does SP4b begin, targeting engine HEAD + the fully migrated client (notes D8).

## 6. Testing (Part A)

Engine repo, `dart test` / `dart analyze`.

- **`test/plugins/almanac/almanac_build_dna_test.dart`** (or the existing DNA
  test file):
  - zero-consumable `buildDna(...)` signature byte-identical to the pre-change
    fixture (backward-compat).
  - consumable order-invariance: `consumableIds: ['a','b']` and `['b','a']` →
    same `signature`; and `!=` the same build with `consumableIds: const []`.
  - `consumableIds` token lands between the last `itemIds` token and the first
    `affixCategories` token.
- **`test/plugins/almanac/almanac_build_snapshot_test.dart`**: a Tome with a
  consumable placement produces a slot with `occupantKind == 'consumable'`,
  `occupantRefId == <id>`, `instanceId == null`; no extra `items` / `techniques`
  entry; `dna` reflects the consumable.
- **`test/plugins/almanac/almanac_adapter_parity_test.dart`**: the synthetic
  adapter parity fixture gains a `consumable` slot so the recorder contract
  parity still holds byte-for-byte with the new kind present.
- **`test/integration/almanac_run_history_test.dart`** (§4.4): helper split;
  replay-equivalence uses `_placedOccupants`; discovery-delta / monotonic use
  `_discoverableOccupants`; a positive assertion that a `'consumable'` slot
  exists in the replay run and both `project()` passes still compare equal;
  debt comment removed.
- **Determinism:** the existing `test/game/` seed-stable + replay assertions
  must pass unchanged — Part A adds no gameplay and no RNG. A failure there is a
  real bug, stop.
- **Dependency guard:** the Almanac→plugin architecture guard
  (`6cee5f9`) still passes — the bridge already imports plugins; no new
  Almanac-module→plugin edge is added.

## 7. Files (Part A)

**Changed — engine:**
- `lib/src/plugins/almanac/almanac_build_dna.dart` — `consumableIds` param +
  token + docstring.
- `lib/src/plugins/almanac/almanac_recorder.dart` — the internal `buildDna(...)`
  call (`:591`) passes `consumableIds: const []` with a why-comment.
- `lib/src/plugins/game/almanac_bridge.dart` — import; `occupantKind` arm;
  `consumableIds:` feed.
- `lib/src/plugins/almanac/almanac_models.dart` — `TomeSlotSnapshot` docstring
  line only (`'consumable'` added to the enumerated kinds).
- `CHANGELOG.md`, `ARCHITECTURE.md`.

**Changed — tests:** the four files in §6.

**New:** none.

## 8. Determinism & no-gameplay guarantees

- `buildDna` stays pure and RNG-free; the new channel is a sorted-unique string
  projection.
- The bridge change is a pure read of live Tome placements already being
  iterated; it adds no subscription, no recorder method, no branch that runs
  gameplay.
- Zero-consumable builds are byte-identical (same `signature`, same slot set) —
  no existing Almanac fixture outside the four test files in §6 needs
  regenerating.
- `output/` artifacts: unaffected (no run behaviour change).

## 9. Spec self-review

- **Placeholders:** none. Every "~line NNN" is an as-of-`1dc7e5d` locator, not a
  TODO.
- **Internal consistency:** §4.2 required-param choice is consistent with §7's
  two-call-site edit; §4.4's helper split is consistent with §5 Stage 3's
  "consumables have no discovery subject".
- **Scope:** Part A is one pure-function param + one ternary arm + one test
  refactor + docs — single-plan sized. The contract register is reference
  material, not work.
- **Ambiguity:** "fixed token position" is pinned to *after `itemIds`, before
  `affixCategories`*. "No per-copy snapshot for a consumable" is explicit
  (`instanceId: null`, no `items`/`techniques` entry).

## 10. Next step

User review of this spec + the sibling client spec → `superpowers:writing-plans`
for the Part A implementation plan (this repo). The client spec drives its own
five-PR plan in `Tome_client`.
