# SP4a — Client engine bump + consumable Almanac debt — brainstorm notes

**Date:** 2026-09-08
**Status:** brainstorm notes — full SP0a→SP3 audit complete. Promotion-ready
pending the two genuine open questions in §7.
**Repos:** `build_engine` (`Tome:RougelikeGame`, engine HEAD `1dc7e5d`) +
`Tome_client` (`/Users/m4maxpro/Projects/Tome_client`, Flutter; engine pin
`314f75a`, 2026-09-01)
**Parent:** `2026-09-02-tiered-component-effects-design.md` §1.2 (the SP0–SP4
decomposition)

---

## 1. Confirmed facts (verified against engine + client source, 2026-09-08)

### 1.1 The gap

- `Tome_client/pubspec.yaml` + `pubspec.lock` pin `build_engine` at
  `314f75af0485845b7e6aabf75f9ab750b2c8cc1e` (2026-09-01, "docs+test: relabel
  headless harness + lock the A1/A2/A4 boundary").
- Engine `main` HEAD is `1dc7e5d`. `git merge-base --is-ancestor 314f75a HEAD` →
  yes. `314f75a..HEAD` first-parent = **139 commits**, beginning exactly at
  `8a7f66c docs(specs): tiered component effects (SP1) + technique instancing
  (SP0a)`. The client sits on the last pre-SP commit.
- The range contains, in order: **SP0a** (technique instancing) → **SP0b**
  (technique inspiration/discovery) → **Almanac v1** (opt-in history) →
  **SP1 game-run migration** (`2026-09-04-sp1-techniquevariant-first-game-run`)
  → **SP1 tiered component effects** (`2026-09-05-tiered-component-effects-sp1`)
  → **SP2** (per-active auras) → **SP3** (per-fight consumables).
- The **audit A1/A2/A4 refactor is already on the client's side of the pin**
  (`314f75a`): `TechniqueEvolved` is already imported from
  `technique_plugin.dart` in `engine_session.dart`; `StyleCombatRules` /
  `BurstChainState` are already consumed in `combat_adapter.dart`;
  `ConsoleDecisionPolicy` is irrelevant (client uses no engine decision policy).
  So the bump does **not** re-introduce those migrations.

### 1.2 Client engine-boundary surface (what actually touches the engine)

`lib/core/engine/` — 11 adapter files. Verified consumers of changed surface:

| Client file | Engine surface it uses | Bump exposure |
|---|---|---|
| `engine_session.dart` | `PluginContext` construction; plugin `initialize` order (`CombatPlugin` → `MartialArtsPlugin` → `PhysiquePlugin` → `ItemPlugin` → `TechniquePlugin`); `TechniqueEvolved` subscription | **SP2**: Combat-first init already holds; verify no new mandatory plugin. **SP3**: `ConsumablePlugin` intentionally *not* registered. |
| `combat_adapter.dart` | `_ctx.tome.resolve(_me)` (**line 79**); `build.components` (**×2**); `const ItemActionInterpreter()` `.interpret(build:…)`; `AttackAction` / `SelfEffectAction` / `ApplyStatus`; `StyleCombatRules`; `techniqueDefinitionFromContent`; `WeaponStatTags` | **SP1 hard compile break** (see §4). |
| `item_adapter.dart` | `ItemInstance` / `ItemInstance.statBonuses` / `addItemStatBonuses`; `combineItems` / `canCombine`; `itemSubject`; `WeaponStatTags` | **SP1 semantic** (statBonuses now feeds `EffectProfile` supporting tier — field + writer survive; see §4). |
| `reward_adapter.dart` | `addItemStatBonuses` (**line 249**); `_applyTechniqueAffix` one-shot boons; `itemDefinition` / `techniqueDefinition`; `styleAlignedFamilies` | **SP1 semantic** (same as above); technique-affix one-shot path is the bug SP4b closes — **left as-is in SP4a**. |
| `technique_adapter.dart` | `techniqueDefinition`; `discoverTechnique` / `isTechniqueDiscovered` / `isTechniqueLearned` / `techniqueMasteryLevel` | **SP0a**: base-family accessors unchanged; no variant minting in SP4a. |
| `training_adapter.dart` | `resolveTechniqueEvolutionAfterTraining` (sig + `EvolutionResult{evolved, chosenCandidate.targetId}` **verified unchanged at HEAD**); `attemptToLearnTechnique`; `trainTechniqueMastery`; `TrainingSession` / `TrainingAttempt` / `trainingGain` (from `game.dart`) | **SP0a/SP0b**: evolution stays string-id + legacy `tome.replace`; `resolveTechniqueInspirationAfterTraining` **not called** (inert). |
| `tome_adapter.dart` | `tome.insert` / `.replace` / `.remove` / `.move` / `.inspect`; `addItemToTome`; `TomeDefinition.grid`; legacy null-instance technique refs | **SP0a**: `addTechniqueToTome` stays the documented legacy path; null `instanceEntityId` still resolves. No change needed. |
| `character_adapter.dart` | physique/lineage/tag setup | none identified. |

### 1.3 Facts that de-risk specific milestones

- **SP1 typed `RunTrainingTarget` (decision F) has zero client impact.** Grep:
  the client uses **none** of `RunDecisionPolicy`, `chooseTrainingTarget`,
  `DecisionLog`, `ReplayDecisionPolicy`, `RecordingDecisionPolicy`,
  `saveDecisionLog`/`loadDecisionLog`, `ConsoleDecisionPolicy`. The client runs
  training through its own UI + `TrainingAdapter`.
- **SP2's `BuildActionInterpreter.auraRules(...)` abstract addition does not
  break the client.** The client never implements/subclasses
  `BuildActionInterpreter` or `CompositeBuildActionInterpreter`, and constructs
  no interpreter list; it uses `const ItemActionInterpreter()` as a concrete
  instance and hand-builds its technique action pool. No test double implements
  the interface either.
- **`addItemStatBonuses` and `ItemInstance.statBonuses` both still exist at
  HEAD** (`lib/src/plugins/item/item_lifecycle.dart:44`,
  `item_instance.dart:35`). SP1 kept the field + writer as the *input* to the
  new `ItemEffectContributor` (supporting tier). Client writes and reads of
  `statBonuses` stay valid; only the internal delivery path (was `affix:*`
  `Modifier`, now `EffectProfile`) changed.
- **Almanac v1 is fully inert for the client.** The client calls no `runGame`,
  constructs no `AlmanacRecorder`, imports no `almanac.dart` / `almanac_file.dart`
  / `buildDna`. (The client's "Almanac" screen is an unrelated in-app codex UI.)
- **`resolveTechniqueEvolutionAfterTraining` is unchanged at HEAD** — verified
  in `lib/src/plugins/technique/technique_evolution.dart:50`. Same 4-arg
  signature, same `EvolutionResult`. The game-run migration minted variants in
  `TrainingStage`, **not** in this shared resolver.

## 2. Decisions taken (2026-09-08, via clarifying questions)

| # | Question | Answer |
|---|----------|--------|
| D1 | SP4 spans engine repo (loaded) + `Tome_client` (not loaded). How to proceed? | **Full SP4: spec here, then both.** |
| D2 | Client is 139 commits / (5 engine efforts) behind. Handle the bump vs. the surfacing? | **Split: SP4a = engine bump + engine-repo debt; SP4b = surfacing.** Each: own spec → plan → impl. |
| D3 | Bump strategy? | **Staged, one sub-project per step**, re-greening the client gate at each stop. |
| D4 | Client fixture drift when the bump shifts a seed's combat outcome / a golden? | **Update fixtures to observed values**, provided determinism *properties* (same seed + same submitted decisions → identical result) still hold. A property failure is a real bug — stop. |
| D5 | `AlmanacBuildRecord` shape for the consumable occupant kind (§6 old open question)? | **Slots-only + a `BuildDna` channel. No typed `ConsumablePlacementSnapshot` collection** — no concrete consumer needs one now (see §5.1). |

**SP4b (deferred, not this doc):** tiered reward affixes via `EffectContributor`;
`component_detail_sheet` grouping effects by tier; the client composition root
adopting `AuraBinder` + `ConsumableBinder` (Combat-first init order); a
`TomeClientAlmanacAdapter` with a `consumable` occupant kind.

## 3. SP4a scope

The client runs on `build_engine` HEAD with a green test gate and no behavioural
regression beyond deliberate seed-outcome drift; and `build_engine`'s own
Almanac replay-equivalence coverage stops filtering consumable placements out.

**No new client UX. No reward-model change. No binder adoption. No client Almanac
adapter.** If a bump stage cannot re-green without one of those, that is the
signal the SP4a/SP4b boundary needs revisiting — stop and surface it.

Lands in two parts, **Part A first** (self-contained; the engine surface Part B
bumps *to* is then final).

## 4. The one hard compile break (SP1), in full

`combat_adapter.dart` after the SP1 stage:

1. **`final build = _ctx.tome.resolve(_me);`** — `TomeService.resolve` is now
   `resolve(EntityId owner, {required List<BuildComponentRef> ownedRefs})` and
   returns **`ResolvedBuild`**, not `ActiveBuild`.
   - Minimal SP4a fix: `_ctx.tome.resolve(_me, ownedRefs: const [])`. The
     resolver unions every hung ref into `owned` by construction, so passing
     `[]` is safe; the `permanent` tier (owned-but-loose) simply contributes
     nothing — acceptable in SP4a (no loose-component combat concept, no
     tiered affixes yet). Leave a `// SP4b: derive real ownedRefs` marker.
     (Reference impl: `game_run.dart`'s `ownedComponentRefs(character, context)`.)
2. **`build.components`** (2 sites: the item loop, the technique loop) —
   `ResolvedBuild` exposes `owner` / `active` / `owned` / `asActiveBuild`, **no
   `.components`**. Fix: iterate `build.active` (identical membership to the old
   `ActiveBuild.components`).
3. **`_itemInterpreter.interpret(build: build, …)`** — signature is now
   `interpret({required ResolvedBuild build, …})`. Once `build` is the
   `ResolvedBuild` from (1), this call is correct as written.

**Semantic continuity to verify (not a compile break):** the item interpreter's
per-stat `Modifier` source string changed from `build:<itemId>:<actorValue>` /
`affix:*` to `effectprofile:item:<actorValue>:<stat>`. The client calls
`interpret` only for its side effect (register item stat modifiers on `_me`);
net damage math is unchanged. Confirm no client test asserts on the old source
name or calls `removeBySource('affix:…')`.

## 5. Part A — consumable occupant kind in the Almanac (`build_engine`, this repo)

Three deterministic, RNG-free, no-new-gameplay changes.

### 5.1 `AlmanacBuildRecord` shape — resolved (D5): slots-only + DNA channel

`HeadlessGameAlmanacBridge._buildSnapshot` already emits every Tome placement
into `TomeLayoutSnapshot.slots` as `TomeSlotSnapshot{slotId, occupantKind,
occupantRefId, instanceId}`. A consumable placement gets
`occupantKind: 'consumable'`, `occupantRefId: <contentId>`, `instanceId: null`
(a consumable has **no** per-copy instanced entity — charges are a per-fight
`ResourcePool` resource, not stored state, so there is nothing to snapshot
per copy).

**No typed `List<ConsumablePlacementSnapshot>` on `AlmanacBuildRecord`.**
Repository evidence: the only consumer of build-record placement structure is
`almanac_run_history_test.dart`'s `_occupants(b)` projection, which reads
`slots` + `occupantRefId`; and `buildDna`, which needs id strings only. A typed
collection would be dead surface until SP4b / a real client adapter defines a
concrete need. If SP4b surfaces one, add it then.

### 5.2 `buildDna()` gains a consumable channel
`lib/src/plugins/almanac/almanac_build_dna.dart`

- Current signature: `buildDna({lineageId, physiqueId, techniqueFamilies,
  itemIds, affixCategories, axisProfiles})` → tokens =
  `[LINEAGE, PHYSIQUE, …sortedUnique(techniqueFamilies), …sortedUnique(itemIds),
  …sortedUnique(affixCategories), …topAxis]`, FNV-1a-32 hashed.
- Add `required Iterable<String> consumableIds`, tokenised via
  `_sortedUniqueUpper` at a **fixed, documented position: after `itemIds`,
  before `affixCategories`.**
- Zero-consumable builds emit no token → every existing build's `signature` is
  **unchanged** (backward compatible; the reorder test in
  `d2c8950` still holds).
- `HeadlessGameAlmanacBridge._buildSnapshot` passes
  `consumableIds: [for (p in placements) if consumable → p.buildComponentRef.contentId]`.
- Core public-surface change → `CHANGELOG.md` under an SP4a heading.

### 5.3 `HeadlessGameAlmanacBridge._buildSnapshot`
`lib/src/plugins/game/almanac_bridge.dart`

- `occupantKind` ternary (currently `isTechnique ? 'technique' : isItem ? 'item'
  : 'empty'`) gains a `consumableReferenceType → 'consumable'` arm. Add the
  `consumable_plugin.dart` import (sibling-plugin import style already used).
- Feed `buildDna(… consumableIds: …)` as in §5.2.
- No new subscription, no new recorder call, no gameplay read.

### 5.4 `test/integration/almanac_run_history_test.dart`

- `_occupants(b)` currently excludes `occupantKind == 'consumable'` via the
  `s.occupantKind != 'empty'` filter that the `b0ee428` note flags. Change it to
  include `'consumable'`.
- Extend `_ForceItemReward` (or add a `_ForceConsumableReward`) so a run that
  places a consumable is exercised by the replay-equivalence projection, not
  only by `consumable_combat_stage_test.dart`'s full-`RunResult` equality.
- Delete the "SP4 debt" comment block added in `b0ee428`.

## 6. Stage-by-stage migration matrix (Part B — `Tome_client`)

Branch `sp4a-engine-bump` in `Tome_client`. **Five stages.** Each stage:
bump the `pubspec.yaml` git `ref` → `flutter pub get` → `flutter analyze` →
`flutter test` → fix breakage using that milestone's `CHANGELOG.md` section →
re-green → commit. Run `scripts/package_itch.sh` (web build) at least on the
final stage (it is in CI).

**Green-gate command:** `flutter pub get && flutter analyze && flutter test`
(client CI also runs `scripts/package_itch.sh`).

**Determinism-property check each stage:** re-run `combat_adapter_test.dart`,
`combat_mastery_test.dart`, `run_bloc_test.dart`, `training_adapter_test.dart`.
The property that must hold: *same `EngineSession(seed)` + same submitted
`TrainingAttempt`s / same combat inputs → identical outcome, run twice.* If a
specific seed's asserted hit/miss pattern or damage number changed **but the
property holds**, update the inline expectation to the observed value (D4). If
the property itself breaks (two identical runs diverge), **stop — real bug.**

---

### Stage 1 — SP0a: Technique instancing

- **Bump to:** `cb32b02` (last SP0a commit; `fix(technique): reject unmapped
  legacy evolved variants`). SP0b spec cites the SP0a merge as `96d6767`;
  `cb32b02` is a later same-milestone fix.
- **Public API added:** `TechniqueDescriptor` content type + `TechniqueAxes`;
  `TechniqueVariant` component (`owner`, `baseFamilyId`, `descriptorIds`,
  `axisProfile`, `styleId`); `TechniqueVariantResolver.resolve`;
  `composeAxisProfile`; `mintTechniqueVariant` / `hangTechniqueVariant` /
  `removeTechniqueVariant` / `ownedTechniqueVariants`;
  `trainTechniqueVariantMastery` / `techniqueVariantMasteryLevel`;
  `techniqueInstanceSubject(EntityId)`; `mintVariantForLegacyEvolvedId` +
  `LegacyTechniqueMigrationException`; events `TechniqueVariantMinted` /
  `TechniqueVariantRemoved`; optional `instanceId` on `TechniqueAddedToTome`.
- **Semantic migrations in the engine:** ownership authoritative on
  `TechniqueVariant.owner` (mirrors `ItemInstance.owner`); "hung" derived from
  Tome placement, never a stored list; every plugin-written technique
  `BuildComponentRef` now carries a non-null `instanceEntityId`
  (`hangTechniqueVariant`); `addTechniqueToTome` is the **documented legacy
  path**, still writes null, still resolves as the bare base; every base +
  evolved technique now gets a MASTERY rank axis at `TechniquePlugin.initialize`
  (was base-only; thresholds unchanged).
- **Client files likely affected:** none for compilation. `technique_adapter.dart`
  and `tome_adapter.dart` use only base-family accessors (`techniqueDefinition`,
  `discoverTechnique`, `isTechniqueLearned`, `techniqueMasteryLevel`) and the
  legacy `tome.insert` / `tome.replace` with a bare `BuildComponentRef`
  (null instance) — all still valid.
- **Expected compile failures:** none anticipated.
- **Expected behavioural changes:** none. The client mints no variants, so
  `instanceEntityId` stays null everywhere; the `ActionCompleted →
  recordTechniqueVariantUsage` path and every `TechniqueVariant*` subscription
  stay dormant (as in the engine's own pre-migration `game_run`).
- **Explicitly behaviourally inert:** all of SP0a — it is "data + lifecycle
  only", and the client exercises none of the new lifecycle.
- **Identity/ownership risk to audit:** confirm no client code assumes a
  technique Tome ref's `contentId` is unique per slot in a way that a future
  variant (same `baseFamilyId` contentId, different instance) would break —
  relevant only when SP4b adopts variants, but note it now. `training_adapter`'s
  `_slotOfTechnique` matches on `occupant?.contentId` — fine while ids are the
  evolved-string ids of the legacy path.
- **Fixture/golden implications:** none expected (behaviour unchanged).
- **`mintVariantForLegacyEvolvedId` risk:** **not triggered** — only code that
  explicitly calls that function hits `LegacyTechniqueMigrationException`; the
  client never does. The client's evolution path stays
  `resolveTechniqueEvolutionAfterTraining` → string id → `tome.replace`.

### Stage 2 — SP0b: Technique inspiration / discovery

- **Bump to:** `ff8c7db` (`fix(technique): SP0b whole-branch review fixes`).
- **Own stage (not folded into SP0a):** per D3 "one sub-project per step", and
  because SP0b adds a distinct public seam (`CombatAction.sourceRef`) and a
  distinct hook. Code evidence does not force a merge with SP0a.
- **Public API added:** `CombatAction.sourceRef: BuildComponentRef?` (optional,
  default null; matching optional ctor param on `AttackAction` /
  `SelfEffectAction`); `TechniqueUsageComponent` + `recordTechniqueVariantUsage`
  / `techniqueVariantUsage`; `TechniqueInspirationResolver.resolve` + `Inspirer`
  / `InspirationResult`; `resolveTechniqueInspirationAfterTraining`;
  `TechniqueVariantInspired` event; inspiration tuning constants +
  `techniqueFamilyTagPrefix` in `technique_vocabulary.dart`;
  `styleCentre(styleId, familyId)` on `martial_arts_plugin.dart`; SP0a's
  `_familyOf` / `_requireVariant` promoted to public `techniqueFamilyOf` /
  `requireTechniqueVariant` (visibility only).
- **Client files likely affected:** none for compilation. `AttackAction` /
  `SelfEffectAction` gain an *optional* named param — the client's positional +
  named constructions are unaffected. `training_adapter.dart` does **not** call
  `resolveTechniqueInspirationAfterTraining`.
- **Expected compile failures:** none.
- **Expected behavioural changes:** none. The inspiration hook is "wired but
  inert in the headless `game_run` harness" — and *doubly* inert in the client,
  which neither calls the hook nor owns any `TechniqueVariant` instance for it
  to draw from. No `context.rng` draw occurs.
- **Explicitly behaviourally inert:** all of SP0b for the client.
- **Fixture/golden implications:** none.
- **Client-impact note for SP4b:** when SP4b mints variants and calls the hook,
  `TechniqueVariantInspired` + a second `TechniqueVariantMinted` will fire per
  discovery; a client counting mints must expect inspired variants. Not in SP4a.

### Stage 3 — SP1: Tiered component effects (+ SP1 game-run migration + Almanac v1 interstitial)

- **Bump to:** `0663e8e` (`fix(effect-profile): address final whole-branch
  review findings` — last commit before the SP2 merge). This single bump
  crosses three engine efforts:
  1. **Almanac v1** (`c428bb8 … 2bf42a2`) — opt-in, default-off. `runGame`
     gains `almanac:` / `runId:` / `runNumber:` (all optional); new
     `almanac.dart` / `almanac_file.dart` barrels; `buildDna` / `BuildDna`.
     **Fully inert for the client** (§1.3). No stage of its own — nothing to
     migrate.
  2. **SP1 game-run migration** (`2026-09-04-…`; `51dcedd … 621fefa`) — migrates
     the engine's *own* `game_run` / `TrainingStage` to mint/hang/train/evolve
     `TechniqueVariant` instances and run inspiration at the real training
     boundary. Public-surface pieces: `TechniqueActionInterpreter` folds
     `axisProfile['power']` into `AttackAction.baseDamage` when
     `instanceEntityId` resolves a variant; `_legacyEvolvedDescriptors` maps all
     15 previously-unmapped evolved ids; typed `RunTrainingTarget` replaces the
     string `chooseTrainingTarget` across the engine's decision policies.
     **Client impact: none** — the power-fold only triggers for non-null
     `instanceEntityId` (client refs are null); `RunTrainingTarget` types are
     unused by the client (§1.3). This effort is the *reference blueprint* for
     SP4b's client composition migration, not SP4a work.
  3. **SP1 tiered component effects** (`2026-09-05-…`; `6322e59 … 0663e8e`) —
     the milestone that carries the client's **one hard compile break**.
- **Public API added:** `EffectTier` (fixed enum `permanent`/`active`/
  `supporting`); `EffectProfile` (+ `EffectProfile.of` / `.empty` / `tier` /
  `amount` / `merge`); `EffectContributor` (implement-the-interface, no
  registry); `EffectProfileResolver.resolve({owned, hung, usedThisCalculation,
  stat})`; `ResolvedBuild {owner, active, owned}` (+ `asActiveBuild`);
  `ItemEffectContributor` (`item_plugin.dart`); `BuildComponentRef` value
  equality (`operator==` / `hashCode` over `referenceType` / `contentId` /
  `instanceEntityId`).
- **Public API changed:** `TomeService.resolve` now
  `resolve(owner, {required List<BuildComponentRef> ownedRefs}) → ResolvedBuild`;
  `BuildActionInterpreter.interpret` takes `ResolvedBuild`;
  `TomeManager.placeItem` carries `instanceEntityId` into the placement;
  `ItemActionInterpreter` per-stat modifier source is now
  `effectprofile:item:<actorValue>:<stat>` (was `build:<itemId>:<actorValue>` /
  `affix:*`); `WeaponStatTags` relocated to `item_plugin.dart` (compat
  re-export from `build_interpretation.dart` retained — client's
  `show WeaponStatTags` import stays valid).
- **Semantic migration:** `ActiveBuild` → `ResolvedBuild { active, owned }`.
  `ItemInstance.statBonuses` and `TechniqueVariant.axisProfile['power']` now flow
  through `EffectProfile`, **not** `Modifier`s / direct arithmetic. The
  `affix:*` modifier source and the direct `axisProfile['power']` interpreter
  arithmetic are **both gone**. `ItemInstance.statBonuses` the field and
  `addItemStatBonuses` the writer **survive** as the supporting-tier input.
- **Client files affected & expected compile failures:** `combat_adapter.dart`
  — the three sites in §4 (`tome.resolve` needs `ownedRefs:`; `build.components`
  ×2 → `build.active`). This is the **only** stage with a compile failure.
- **Expected behavioural changes:** possible fixed-seed combat drift — two hung
  copies of one item now each contribute their scaled `attack` (the old
  `build:<itemId>` source collapsed duplicates); item modifier scoping is now
  per-actor. Net effect on the client's single-weapon builds is likely nil, but
  `combat_adapter_test.dart`'s "on this seed" expectations may move → update to
  observed (D4).
- **Explicitly behaviourally inert:** Almanac v1; the game-run variant
  migration (client stays on the legacy null-instance path).
- **Fixture/golden implications:** re-baseline any drifted inline seed
  expectations in `combat_adapter_test.dart` / `combat_mastery_test.dart` to
  observed values; `tome_visual_capture_test.dart` (structural capture, no PNG
  golden) should be unaffected — if it moves, inspect before re-baselining.
- **Semantic-continuity audit:** grep client tests for `affix:` /
  `removeBySource(` / `build:` modifier-source string assertions (none expected;
  confirm).

### Stage 4 — SP2: Per-active auras

- **Bump to:** `dc213d4` (merge `per-active-auras-sp2`).
- **Public API added:** `AuraScope {self, opponent}`; `AuraRule`;
  `AuraContributor` (via `ItemAuraContributor` / `TechniqueAuraContributor`
  wrappers holding a `ContentRegistry`); `SubjectIs` condition;
  `AuraBinder` / `AuraBinding` (`build_interpretation.dart`);
  `BuildActionInterpreter.auraRules({build, context})` (abstract; concrete on
  `ItemActionInterpreter` / `TechniqueActionInterpreter`;
  `CompositeBuildActionInterpreter` aggregates); `auras: [<ruleId>]` content
  field → `ItemDefinition.auraRuleIds` / `TechniqueDefinition.auraRuleIds`
  (`const []` when absent); `CombatPlugin.initialize` registers `TurnStarted` /
  `TurnEnded` / `ActionCompleted` content-rule triggers;
  `ContentRegistry.hasTrigger(String)`.
- **Interface-change check (`auraRules()`):** does **not** affect the client —
  it implements no `BuildActionInterpreter`, subclasses no interpreter, builds
  no interpreter list, and has no test double for the interface (§1.3). The
  concrete `const ItemActionInterpreter()` it uses simply gains a method it
  never calls.
- **Combat-first initialization requirement:** `engine_session.dart` already
  initializes `CombatPlugin` **before** `ItemPlugin` / `TechniquePlugin`, so
  the `hasTrigger`-gated aura-content load (which needs Combat's triggers
  registered first) is satisfied. **Verify this ordering is unchanged after the
  bump and add a comment locking it** (the CHANGELOG calls this "the constraint
  any future composition root must honour").
- **Client files likely affected:** none for compilation.
- **Expected compile failures:** none.
- **Expected behavioural changes:** none — SP2 is behaviourally inert without
  aura content hung, and the client hangs none (no `auras` keys reach its Tome;
  SP4b adds reward-rolled auras). The engine shipped `auras` keys on 7 content
  ids (`cloth_armor`, `training_staff`, `training_shoes`,
  `warlords_iron_sword`, `crushing_gauntlets`, `basic_guard`, `basic_slash`) —
  **the client does not bind auras** (`combat_adapter` builds its own action
  pool and never calls `AuraBinder`), so even a hung `basic_slash` contributes
  no aura in the client. Confirm the client's combat produces identical numbers
  pre/post bump for a build hanging one of those 7 ids.
- **Explicitly behaviourally inert:** all of SP2 for the client, pending SP4b.
- **Fixture/golden implications:** none expected; if a build with one of the 7
  ids drifts, that means an aura path leaked into the client — **stop and
  investigate** (it would mean the client is binding auras it shouldn't in
  SP4a).

### Stage 5 — SP3: Per-fight consumables

- **Bump to:** `1dc7e5d` (merge `Per-fight Consumables`) / engine HEAD.
- **Public API added:** `consumable_plugin.dart` barrel — `ConsumablePlugin`,
  `ConsumableDefinition`, `ConsumableTarget`, sealed `ConsumableEffectSpec`
  (`ConsumableHeal` / `ConsumableAttack` / `ConsumableGrantModifier` /
  `ConsumableRemoveAllStatuses`), `consumableDefinitionFromContent` /
  `consumableDefinition`, `consumableContentDefinitions`,
  `consumableReferenceType` (`'consumable'`), `consumableChargeResource`,
  `ConsumableIds`; `RemoveAllStatuses` `Effect` + `'removeAllStatuses'` content
  factory; `GrantModifier` `Effect` (CombatAction/PluginContext path only — no
  content factory, `RuleEngine`-dispatched it no-ops); `RuleContext.modifiers`
  (optional factory param, default fresh `ModifierCollection`);
  `PluginContext.ruleContextFor` supplies the real collection;
  `AttackAction` / `SelfEffectAction` optional `priority` ctor param (`num`,
  default 0); `ConsumableActionInterpreter`, `ConsumableBinder` /
  `ConsumableCharges` (`build_interpretation.dart`),
  `ConsumableAwareActionScorer` (`auto_combat_plugin.dart`).
- **Public API changed:** engine `game_run` reward pool +
  `RewardStage.resolveReward` + `TomeManager.placeConsumable` handle the third
  `referenceType`; engine `CombatStage.runFight` binds `ConsumableBinder.grant`
  + uses `ConsumableAwareActionScorer`. **These are engine-harness changes, not
  public-surface the client consumes.**
- **C1 fix (engine, for context):** `ConsumableActionInterpreter` attaches
  `conditions: [ResourceAbove('consumable:<id>', 0)]` to every consumable
  action, and `CombatStage.runFight` injects the fallback strike whenever the
  build has no *non-consumable* action — so a consumable-only Tome can't stall
  a fight. **The client has its own fallback-strike logic** in
  `combat_adapter._Resolver` (`if (!pool.any((t) => t.action is AttackAction))`)
  and its own action pool that never includes consumable actions — so C1 does
  not apply to the client's combat loop, but the parallel must be understood
  before SP4b wires consumables client-side.
- **Client files likely affected:** none for compilation. `ConsumablePlugin` is
  **not** registered in `engine_session.dart`; `AttackAction` /
  `SelfEffectAction` gain another *optional* param (unaffected);
  `RuleContext.modifiers` default keeps `RuleEngine._fire` behaviour identical.
- **Expected compile failures:** none.
- **Expected behavioural changes:** none — the client registers no
  `ConsumablePlugin`, places no consumables, and its combat pool has no
  consumable branch. Verify a full client run (create → train → fight → reward →
  repeat) is byte-identical for a fixed seed pre/post this stage.
- **Explicitly behaviourally inert:** all of SP3 for the client, pending SP4b.
- **Fixture/golden implications:** none expected.
- **Final-stage extra:** run `scripts/package_itch.sh`; confirm the web release
  build still succeeds (CI gate).

## 7. Determinism policy (explicit pass/fail)

1. **Expected seed-output drift** — a specific seed's asserted combat number /
   hit-miss pattern / mastery total changes because the new engine legitimately
   computes a value differently (SP1 duplicate-item summing, per-actor modifier
   scoping). **Action:** update the inline expectation to the observed value,
   note it in the stage commit.
2. **Unexpected nondeterminism** — running the *same* `EngineSession(seed)` with
   the *same* submitted `TrainingAttempt`s / combat inputs twice produces
   *different* results. **Action:** STOP. This is a real bug — do not update the
   fixture, do not weaken the assertion, diagnose it.
3. **Compile / API migration** — a signature or type change breaks the build.
   **Action:** apply the minimal mechanical fix per that milestone's CHANGELOG
   (§4 is the only one in this bump), no behaviour change intended.
4. **Actual gameplay regression** — a run *ends differently* in a way that is
   not a legitimate calculation change (wrong winner, crash, a plugin path
   firing that SP4a said is inert). **Action:** STOP, surface it; it likely
   means SP4b work leaked in or a real engine bug.

**Never weaken a determinism assertion to make the bump green.** Never delete a
"same seed twice → identical" test. If such a test can't pass, that is finding
(2) or (4), not a fixture update.

## 8. SP4a Part A / Part B boundary — frozen

### Part A (engine repo — `build_engine`)
- `BuildDna` gains `consumableIds` (fixed token position, §5.2).
- `HeadlessGameAlmanacBridge` emits `occupantKind: 'consumable'` + feeds the
  DNA channel (§5.3).
- `almanac_run_history_test.dart` replay-equivalence projection covers
  consumable placements; `b0ee428` debt comment removed (§5.4).
- **No** typed `ConsumablePlacementSnapshot` collection (D5, §5.1).
- `CHANGELOG.md` + `ARCHITECTURE.md` updated under an SP4a heading.

### Part B (client repo — `Tome_client`)
- Staged engine-pin bump only (5 stages, §6), plus the §4 compile fix and any
  D4 fixture re-baselines.
- **Explicitly NOT in SP4a:** tiered-affix rolling or UX; `component_detail_sheet`
  changes; `AuraBinder` adoption; `ConsumableBinder` adoption;
  `ConsumablePlugin` registration; consumable UI or reward-pool entries; any new
  reward model; `resolveTechniqueInspirationAfterTraining` wiring; minting /
  hanging `TechniqueVariant` instances; a `TomeClientAlmanacAdapter`; deriving
  real `ownedRefs` (a `const []` placeholder with a marker comment is the SP4a
  fix).
- If any stage cannot re-green without one of the above → stop, revisit the
  SP4a/SP4b line.

## 9. Remaining open questions (genuine — not answerable from the repo)

1. **One spec or two.** A single `2026-09-08-sp4a-engine-bump-design.md`
   covering Part A + Part B, **vs.** two specs (`…-sp4a-almanac-consumable-dna`
   in the engine repo, `…-sp4a-client-engine-bump` for the client) given they
   land in different repos with separate test gates and review cycles. Leaning
   two, cross-linked — Part A can land and be reviewed while Part B is still
   staging.
2. **Client branch integration.** Does `sp4a-engine-bump` in `Tome_client` land
   as one squashed PR after all five stages green, or five sequential PRs (one
   per stage) so each engine bump is independently revertable? Affects plan
   task granularity, not design.
3. **SP4b prerequisite ordering.** SP4b's client composition migration (mint /
   hang variants, adopt binders) will want the SP1 game-run migration
   (`2026-09-04`) as its blueprint. Confirm SP4b is scoped to *follow* SP4a
   fully (client on HEAD) rather than interleave — assumed yes, worth stating in
   the SP4a spec's "what comes next".

## 10. Audit summary

- **SP0a** — covered: full API list, ownership/hung-state semantics, legacy
  `addTechniqueToTome` path, `mintVariantForLegacyEvolvedId` non-trigger.
  Client impact: **compile-clean, behaviourally inert** (no variant minting).
- **SP0b** — covered as its **own stage**: `sourceRef` seam, usage tracking,
  inspiration resolver + hook, `styleCentre`, `TechniqueVariantInspired`.
  Client impact: **compile-clean, doubly inert** (hook not called, no variants).
- **SP1** — covered: `EffectTier` / `EffectProfile` / `EffectContributor` /
  `EffectProfileResolver` / `ResolvedBuild` / `BuildComponentRef` equality /
  `TomeService.resolve(ownedRefs:)` / `interpret(ResolvedBuild)` / `statBonuses`
  migration (field survives) / actor-scoped modifier source / `ActiveBuild →
  ResolvedBuild {active, owned}`. Plus the SP1 game-run migration and Almanac v1
  as inert interstitials in the same bump. Client impact: **one hard compile
  break** (`combat_adapter.dart`, §4), possible fixed-seed drift.
- **SP2** — covered: `AuraScope` / `AuraRule` / `AuraContributor` / `SubjectIs`
  / `AuraBinder` / `AuraBinding` / `auraRules()` interface addition / Combat
  trigger registration / `auras` content field / Combat-first init / per-fight
  bind-dispose. Client impact: **compile-clean, inert** (`auraRules()` doesn't
  touch the client; init order already correct — lock it with a comment).
- **SP3** — covered: `ConsumablePlugin` + `ConsumableDefinition` +
  `ConsumableEffectSpec` (4 variants) + `consumableReferenceType` +
  `consumableChargeResource` + `ConsumableActionInterpreter` + `ConsumableBinder`
  / `ConsumableCharges` + `ConsumableAwareActionScorer` + `RemoveAllStatuses` +
  `GrantModifier` + `RuleContext.modifiers` + `PluginContext.ruleContextFor` +
  `AttackAction`/`SelfEffectAction.priority` + reward/Tome support + per-fight
  reset + aggregate charges + unbounded max + strict parser + C1
  `ResourceAbove` guard + fallback strike. Client impact: **compile-clean,
  inert** (`ConsumablePlugin` unregistered; client has its own fallback strike).

**Self-audit checklist:** SP0a ✔ · SP0b ✔ (own stage) · SP1 ✔ · SP2 ✔ · SP3 ✔ ·
every public API migration named ✔ · every client compile-break seam named
(§4, one) ✔ · identity/ownership migration called out ✔ · `auraRules()`
interface change addressed ✔ · C1 consumable/fallback behaviour addressed ✔ ·
five bump stages ✔ · SP4a/SP4b boundary frozen (§8) ✔ · no engine code changed
✔ · no `Tome_client` work performed ✔.

## 11. Revised stage matrix (one-line form)

| # | Milestone | Bump ref | Client compile break | Client behaviour | Fixtures |
|---|-----------|----------|----------------------|------------------|----------|
| 1 | SP0a technique instancing | `cb32b02` | none | inert | none |
| 2 | SP0b inspiration/discovery | `ff8c7db` | none | inert (hook uncalled) | none |
| 3 | SP1 tiered effects (+ SP1 game-run + Almanac v1, both inert) | `0663e8e` | **`combat_adapter.dart` ×3 (§4)** | possible seed drift | re-baseline drifted inline seed expectations |
| 4 | SP2 per-active auras | `dc213d4` | none | inert (no aura bind) | none; drift ⇒ stop |
| 5 | SP3 per-fight consumables | `1dc7e5d` / HEAD | none | inert (plugin unregistered) | none; + web build |

## 12. Verdict

**READY FOR FORMAL SP4a DESIGN** — the SP0a→SP3 chain is fully audited against
engine + client source; the single client compile break is pinned to three
lines in `combat_adapter.dart`; every other milestone is compile-clean and
behaviourally inert for the client under SP4a's frozen scope. The three items in
§9 are process/packaging choices, not design gaps — resolve them when opening the
`-design.md` (or defer §9.2/§9.3 to the implementation plan).

## 13. Next step

Resolve §9.1 (one spec vs. two) → write the formal design doc(s) → spec
self-review → user review gate → `superpowers:writing-plans` (Part A tasks in
this repo; Part B tasks as the five staged bumps in `Tome_client`).
