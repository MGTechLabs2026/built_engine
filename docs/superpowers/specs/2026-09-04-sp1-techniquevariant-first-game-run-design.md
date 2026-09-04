# SP1 — Migrate the game run to TechniqueVariant-first gameplay

**Status:** design, pending review
**Date:** 2026-09-04
**Depends on:** `2026-09-02-technique-instancing-design.md` (SP0a), `2026-09-03-technique-inspiration-design.md` (SP0b)

---

## 1. Problem

`game_run` / `TrainingStage` still runs the legacy technique lifecycle as the
authoritative gameplay path:

```
legacy TechniqueDefinition id → attemptToLearnTechnique → addTechniqueToTome
(null instanceEntityId) → resolveTechniqueEvolutionAfterTraining → evolved
string id → tome.replace(contentId = evolvedId, null instance)
```

The SP0a/SP0b `TechniqueVariant` system is fully built and unit-tested but the
playable headless run never mints, hangs, trains, or uses a variant. The
`ActionCompleted → recordTechniqueVariantUsage` bridge in `CombatStage`
(`combat_stage.dart:97-110`) and every `TechniqueVariant*` subscription in
`HeadlessGameAlmanacBridge` are dormant because `instanceEntityId` is always
`null` in the run's Tome.

**Goal:** the headless run becomes the live demonstration of the new system —
acquire a variant, hang it by instance identity, execute it in combat through
`sourceRef`, accrue per-instance usage and mastery, evolve it into a variant
instance, inspire loose variants at the true post-training boundary, and let the
existing Almanac bridge observe the whole history — without weakening any
architecture test and with determinism understood and documented.

## 2. Audit — current authoritative call graph

| Concern | Current code | Behaviour |
|---|---|---|
| Training candidates | `TrainingStage.trainingCandidates` (`training_stage.dart:50`) | opaque `item:<id>` / `technique:<id>` strings; techniques come only from `rewardPoolTechniqueIds` = `{basic_punch, basic_slash, basic_guard}`, filtered to discovered-and-not-learned |
| Training target choice | `RunDecisionPolicy.chooseTrainingTarget(List<String>)` → recorded to `DecisionLog.trainingChoices: List<String>` → `ReplayDecisionPolicy` replays verbatim | string-typed; also round-tripped through `saveDecisionLog`/`loadDecisionLog` (console policy tests, `tool/play_interactive.dart`) |
| Learning | `attemptToLearnTechnique(base def, gain)` → `ProgressionEngine` on `techniqueKnowledgeSubject` | single `[10]` threshold; `learned` bool |
| Tome placement | `TomeManager.placeTechnique` → `addTechniqueToTome` (legacy path) | `BuildComponentRef(techniqueReferenceType, contentId=<baseId>, instanceEntityId=null)`; publishes `TechniqueAddedToTome` (no instance) |
| Evolution | inside `if (learning.learned)`: `resolveTechniqueEvolutionAfterTraining(base def, profile)` → `TomeManager.replaceWithEvolved(baseId, evolvedId)` → `tome.replace(contentId=<evolvedId>, null instance)` | Technique plugin owns the decision + the single `TechniqueEvolved` publish; only fires once per family because the family leaves the candidate list once learned |
| Inspiration | `resolveTechniqueInspirationAfterTraining(...)` **nested under `if (learning.learned)`** | inert — player owns zero `TechniqueVariant` instances, so `ownedTechniqueVariants` is empty and the resolver returns `InspirationResult.none` |
| Combat interpretation | `TechniqueActionInterpreter._actionFor` | reads `context.content.find(ref.contentId)`; `guard` tag → `SelfEffectAction`; else `properties['damage']` → `AttackAction(baseDamage: damage, sourceRef: ref)`. Ignores `instanceEntityId`. |
| Combat usage bridge | `CombatStage.runFight` `ActionCompleted` sub (`combat_stage.dart:104-108`) | already calls `recordTechniqueVariantUsage(ref.instanceEntityId!)` when `ref.referenceType == techniqueReferenceType && ref.instanceEntityId != null` — never true today |
| Almanac | `HeadlessGameAlmanacBridge.attach` subscribes `TechniqueVariantMinted`, `TechniqueVariantInspired`, instance-aware `ActionCompleted`, `SubjectDiscovered` (`_subjectLookup` already includes `TechniqueIds.bases` subjects) | ready; receives nothing |
| Manage Tome | `TomeManager.manageTome` equip/unequip loop | builds `equip:technique:<familyId>` from `knownTechniqueIds()` and `unequip:<slot>:<type>:<contentId>`; `applyUpgrade` `technique:` branch adds a stat modifier keyed by family tags |

### Evolution reachability & the descriptor map

`_legacyEvolvedDescriptors` (in `technique_variant_lifecycle.dart`) currently maps
20 evolved ids. **15 evolved ids in shipped content are unmapped**, including
`counter_punch`, `fast_guard`, `counter_guard` — all first-tier candidates of the
three reward-pool base families, i.e. reachable in a real run. Hitting an unmapped
evolved id throws `LegacyTechniqueMigrationException`. Full evolution graph
(`technique_content.dart`):

```
basic_punch → light_punch✓ heavy_punch✓ fast_punch✓ counter_punch✗
basic_slash → quick_slash✓ heavy_slash✓
basic_guard → fast_guard✗ counter_guard✗
(unmapped, deeper / other families) precise_jab, flashing_slash, cleaving_slash,
  rolling_guard, turning_guard, still_water_guard, focused_palm, pushing_palm,
  still_palm, finger_strike, snap_kick, crescent_kick
```

## 3. Resolved design decisions

| # | Decision | Choice |
|---|---|---|
| A | Evolved/derived variant combat damage | `TechniqueActionInterpreter`, when `ref.instanceEntityId` resolves a `TechniqueVariant`: `baseDamage = <base-family properties['damage']> + (axisProfile['power'] ?? 0)`, floored at `1`. Only `power` is read. Guard-family variants stay `SelfEffectAction` unchanged. |
| B | Variant trainability after learning | Owned variants (base, evolved, inspired) **stay trainable**. Each technique training session trains **per-instance** variant mastery via `trainTechniqueVariantMastery(instanceId, gain)` and runs inspiration. |
| C | Evolution re-fire guard | Evolution rolls for a family **only while that family's Tome occupant is still the base variant** (the descriptor-less, `styleId == null` instance). Once the occupant is an evolved/inspired variant, that family stops rolling evolution. Deeper evolution is not auto-driven in SP1; the descriptor map still covers those ids for save/legacy migration. |
| D | Inspiration boundary | The inspiration hook runs **once per training session, item sessions included**, at the end of `TrainingStage.runTraining`, after the target-specific branch — not nested under `if (learning.learned)`. `trainedFamilyId` = the technique target's family for a technique session; for an item session it is the family of the player's "top" owned variant (highest `(masteryLevel, usage, -instanceId.value)`); if the player owns no variants the hook is a no-op (`inspirers` empty → `InspirationResult.none`). |
| E | Descriptor map | **Complete all 15 missing evolved ids** in the canonical `_legacyEvolvedDescriptors` map. No mapping is duplicated anywhere else. |
| F | Training-target type | Replace the string `chooseTrainingTarget` interface with a typed `RunTrainingTarget` across `RunDecisionPolicy`, `DefaultRunDecisionPolicy`, `ConsoleDecisionPolicy`, `RecordingDecisionPolicy`, `ReplayDecisionPolicy`, `DecisionLog`, `saveDecisionLog`/`loadDecisionLog`, and every test policy. |
| G | Base-family vs variant progression (§9) | Variant training bumps **only** `techniqueInstanceSubject(instanceId)`. It never touches `techniqueSubject(familyId)` (base-family MASTERY) or `techniqueKnowledgeSubject(familyId)` (base-family LEARNING). Base-family LEARNING is moved only by `attemptToLearnTechnique` while the family is not yet learned. |

## 4. Authoritative representation after migration

* **Base-family knowledge** — unchanged. `isTechniqueLearned(owner, familyDef)` still
  answers "may this base family be acquired / has it been". Drives the *learning*
  training candidate only.
* **Concrete owned technique** — a `TechniqueVariant` entity: `owner`,
  `baseFamilyId`, `descriptorIds`, `axisProfile`, `styleId?`, plus per-instance
  mastery (`techniqueInstanceSubject`) and per-run usage (`TechniqueUsageComponent`).
* **Tome** — every technique placement is `hangTechniqueVariant(slot, instanceId)`:
  `BuildComponentRef(referenceType: techniqueReferenceType, contentId:
  variant.baseFamilyId, instanceEntityId: instanceId)`. The Tome never recovers an
  instance by parsing an id.
* **`RunResult.techniquesEvolved`** keeps storing the **legacy evolved string id**
  (`heavy_punch`, …) as historical/content identity. The owned/equipped object is
  the variant; its `contentId` in `finalBuild` is the base family. Tests that
  asserted the evolved string appears among `finalBuild` contentIds move to
  asserting it via the variant descriptors / the Almanac technique snapshot
  (see §8).

## 5. Component / file changes

### 5.1 Technique plugin (`lib/src/plugins/technique/`) — Core + siblings only

* `technique_variant_lifecycle.dart`
  * Extend `_legacyEvolvedDescriptors` with the 15 missing evolved ids (decision E),
    using only ids already in `technique_descriptor_content.dart` (axes are
    `power` / `speed` / `endurance` / `precision` — there is no `reaction`
    descriptor, so reaction-line forms map to the nearest thematic axis).
    **Proposed mapping (confirm in review):**

    | evolved id | descriptors | rationale |
    |---|---|---|
    | `counter_punch` | `{'focused'}` | reaction → timing/precision |
    | `precise_jab` | `{'bullseye'}` | precision line |
    | `flashing_slash` | `{'flash'}` | quick line |
    | `cleaving_slash` | `{'strong', 'iron'}` | heavy line (mirrors `hammer_blow`) |
    | `fast_guard` | `{'fast'}` | speed |
    | `counter_guard` | `{'focused'}` | reaction → timing/precision |
    | `rolling_guard` | `{'swift'}` | fast line |
    | `turning_guard` | `{'focused'}` | counter line |
    | `still_water_guard` | `{'mountain'}` | master control/endurance |
    | `focused_palm` | `{'focused'}` | precision |
    | `pushing_palm` | `{'wall'}` | control/endurance |
    | `still_palm` | `{'rooted'}` | control/endurance |
    | `finger_strike` | `{'focused'}` | precision |
    | `snap_kick` | `{'fast'}` | speed |
    | `crescent_kick` | `{'swift'}` | reaction line → speed |
  * No API changes. `mintVariantForLegacyEvolvedId`, `mintTechniqueVariant`,
    `hangTechniqueVariant`, `removeTechniqueVariant`, `ownedTechniqueVariants`
    are reused as-is.
* No new imports of `combat` / `martial_arts` / `game` / `almanac`.

### 5.2 Build interpretation (`lib/src/plugins/build_interpretation/technique_action_interpreter.dart`)

* `_actionFor` gains an optional `TechniqueVariant? variant` resolved from
  `ref.instanceEntityId` via `context.components.get<TechniqueVariant>`.
* Attack branch: `final base = technique.properties['damage']; final power =
  variant?.axisProfile['power'] ?? 0; final dmg = (base + power) < 1 ? 1 : base +
  power;` → `AttackAction(baseDamage: dmg, damageStat: _damageStatFor(technique),
  sourceRef: ref)`.
* Guard branch unchanged. Null-instance refs (legacy saves) behave exactly as
  today. This file already imports `technique_plugin` + `combat_plugin`; no new
  plugin dependency.

### 5.3 Composition layer (`lib/src/plugins/game/`)

**`run_decision_policy.dart`**
* New value type `RunTrainingTarget` (sealed): `RunTrainingTarget.item(String
  itemId)` and `RunTrainingTarget.technique(String familyId, {EntityId?
  variantInstanceId})`. `==`/`hashCode`, plus `encode()` / `RunTrainingTarget.decode(String)`:
  * `item:<itemId>`
  * `technique:<familyId>`
  * `technique:<familyId>#<instanceValue>` (variant instance present)
* `RunDecisionPolicy.chooseTrainingTarget(List<RunTrainingTarget> candidates)
  → RunTrainingTarget`.
* `DefaultRunDecisionPolicy` returns `candidates.first`.

**`decision_log.dart`**
* `DecisionLog.trainingChoices: List<RunTrainingTarget>`.
* `RecordingDecisionPolicy` / `ReplayDecisionPolicy` updated to the typed method.
* `saveDecisionLog` / `loadDecisionLog` encode/decode via
  `RunTrainingTarget.encode`/`.decode`. Cross-process replay of a log that
  references a variant instance id is best-effort — same-seed + same-decisions
  in-process replay is exact because entity allocation is deterministic from the
  seed and the action stream (this matches the existing documented "a DecisionLog
  is only guaranteed valid for the seed it was recorded against" contract).

**`console_decision_policy.dart`**
* `chooseTrainingTarget` prints `t.encode()` labels; returns the chosen
  `RunTrainingTarget`.

**`training_stage.dart`** — the core of the migration.
* `trainingCandidates(...)` returns `List<RunTrainingTarget>`:
  * items — unchanged rule (owned & not `isItemUsable`) → `RunTrainingTarget.item(id)`.
  * per family in `TechniqueIds.bases ∩ reachable` (the run's `rewardPoolTechniqueIds`
    plus any family the player owns a variant on):
    * if discovered & **not** learned → `RunTrainingTarget.technique(familyId)`
      (learning candidate, no instance).
    * for **each owned variant** on that family (from `ownedTechniqueVariants`
      filtered by `baseFamilyId`) whose per-instance mastery is below the top
      threshold → `RunTrainingTarget.technique(familyId, variantInstanceId: e)`.
* `runTraining(...)`:
  1. resolve `RunTrainingTarget` via `chooseTrainingTarget`.
  2. **item branch** — unchanged: `TrainingSession` on `itemSubject`, `mastery.increase`,
    `placeItem` on newly-usable. (No `attemptToLearnTechnique`, no evolution.)
  3. **technique branch**:
     * build the `TrainingSession` on `techniqueSubject(familyId)` exercise
       (`techniqueTrainingExerciseFor(familyDef, TimingExercise())`), submit the
       same `generateTrainingAttempts(rng)` attempts, `complete()`, compute `gain`,
       publish `TrainingResultRecorded`, append a `TrainingRecord`. (Attempt
       generation and profile maths are untouched → identical `rng` draw here.)
     * **if `variantInstanceId == null`** (learning candidate):
       `attemptToLearnTechnique(familyDef, gain)`. On first `learned == true`:
       * mint the base variant iff the player owns no descriptor-less base variant
         for this family:
         `final baseInstance = mintTechniqueVariant(character, familyId, const {},
         context);` (styleId `null`, no `styleCentre` → stays "basic", learning gate
         meaningful). Publishes `TechniqueVariantMinted`.
       * `tomeManager.placeTechniqueVariant(baseInstance, 'Training (technique
         learned)')` — `hangTechniqueVariant`, non-null instance, publishes
         `TechniqueAddedToTome(instanceId: …)`.
       * `techniquesLearned.add(familyId)`.
       * evolution (decision C): only if the family's Tome occupant is still the
         base variant → `resolveTechniqueEvolutionAfterTraining(familyDef,
         result.profile)`. On `evolved`:
         `final evolvedInstance = mintVariantForLegacyEvolvedId(character,
         chosen.targetId, context, styleId: styleId);`
         `tomeManager.replaceWithTechniqueVariant(slot, evolvedInstance, 'Training
         (evolved)');`
         `removeTechniqueVariant(baseInstance, context);` (frees per-instance
         mastery/usage/entity, publishes `TechniqueVariantRemoved`).
         `techniquesEvolved.add(chosen.targetId)`,
         `firstTechniqueEvolutionStep ??= cycleIndex`.
     * **if `variantInstanceId != null`** (variant-mastery candidate):
       `trainTechniqueVariantMastery(variantInstanceId, gain, context)` — decision
       G: per-instance only. Then evolution guard (decision C) — normally a no-op
       here because the occupant is already an evolved/inspired variant; kept for
       the case where the base variant is trained again before it evolved.
  4. **inspiration (decision D)** — after the branch, unconditionally once:
     * `familyId` = technique target's family, or (item target) the family of the
       player's top owned variant, or skip if none owned.
     * `resolveTechniqueInspirationAfterTraining(character, familyDef,
       styleCentre(styleId, familyId), context, styleId: styleId)`.
     * On a hit it mints an owned **loose** variant (not hung, not learned) and
       publishes `TechniqueVariantInspired`. `TrainingStage` records telemetry only;
       the next `manageTome()` may place it.

**`tome_manager.dart`**
* `placeTechniqueVariant(EntityId instanceId, String stepName)` — mirrors
  `placeItem`: `ref = BuildComponentRef(techniqueReferenceType, contentId:
  variant.baseFamilyId, instanceEntityId: instanceId)`, `chooseSlot`,
  `chooseReplace` on an occupied slot (on replace: `tome.remove` then
  `hangTechniqueVariant`), else `hangTechniqueVariant`, `snapshot`.
* `replaceWithTechniqueVariant(SlotId slot, EntityId instanceId, String stepName)`
  — `tome.remove(slot)` then `hangTechniqueVariant(slot, instanceId)`, `snapshot`.
  Replaces `replaceWithEvolved` (deleted — its only caller migrates).
* `placeTechnique(TechniqueDefinition, …)` and `addTechniqueToTome` are **kept**
  (not proven unused — `technique_end_to_end_test.dart`, tome fixtures) but
  `TrainingStage` / `manageTome` stop calling them.
* `manageTome` equip/unequip:
  * "benched technique" = `ownedTechniqueVariants(character)` minus instances
    already placed (`placement.buildComponentRef.instanceEntityId`).
  * candidate strings become `equip:techniqueVariant:<instanceValue>` and
    `unequip:<slotId>:technique:<baseFamilyId>`; equip resolves via
    `placeTechniqueVariant`. Item candidate strings unchanged.
  * `knownTechniqueIds()` (families with ≥1 owned variant) still feeds the
    `applyUpgrade` `technique:<familyId>` stat-bump path (family-level modifier —
    correct granularity, unchanged).

**`game_run.dart`**
* `knownTechniqueIds(character, context)` → `{ for (final e in
  ownedTechniqueVariants(character, context)) variant(e).baseFamilyId }` (families
  the player owns a variant on) instead of `isTechniqueLearned` over the reward
  roster. Used by `manageTome` and `RunStatus`.
* No other structural change; the four-collaborator wiring and the `rng`/`policy`
  call order outside the training branch are untouched.

### 5.4 Not touched

Combat rules, `CombatSystem`, `EvolutionResolver`, `TechniqueInspirationResolver`,
descriptor vocabulary, style tables, Almanac schema, Item plugin, client/UI, save
serialization format (beyond `DecisionLog.trainingChoices`'s element type),
Devvit/itch integration.

## 6. Event flow after migration (unchanged event contracts)

```
first learn      → TechniqueVariantMinted(base)         → bridge.recordTechniqueDiscovered(origin: base)
place            → TechniqueAddedToTome(instanceId)
combat           → ActionCompleted(sourceRef.instanceEntityId)
                   → CombatStage bridge: recordTechniqueVariantUsage(instanceId)
                   → Almanac bridge:     recordTechniqueUsed(instanceId)
evolve           → TechniqueVariantMinted(evolved) + TechniqueEvolved(fromId,toId) + TechniqueVariantRemoved(base)
inspire (hit)    → TechniqueVariantMinted(inspired) + TechniqueVariantInspired(inspirerInstanceIds)
                   → bridge.recordTechniqueInspired(ancestry)
remove           → TechniqueVariantRemoved
```

No new event types. `TechniqueEvolved` keeps its `{fromId, toId}` string contract
(both consumers — `telemetry_test`, the bridge's lineage — keep working); the
variant identity is carried by the `TechniqueVariantMinted` that immediately
precedes it.

## 7. Determinism / RNG / golden impact

The migration legitimately changes RNG consumption and run composition:

1. **Inspiration is now live.** `resolveTechniqueInspirationAfterTraining` draws
   from `context.rng` (a discovery roll, and on a hit a weighted descriptor draw)
   on **every** training session once the player owns ≥1 eligible variant. Before
   SP1 it returned before touching `rng`. → every seed's `rng` stream diverges
   from the training branch onward.
2. **Evolution timing.** Evolution still uses one `rng` draw when eligible, but the
   decision C guard ("only while occupant is the base variant") changes *whether*
   that draw happens on later sessions vs. today's "family already left the
   candidate list". Net: ≤ the number of evolution draws today for reward-pool
   families; deeper families are unaffected.
3. **Typed training target** does not itself consume `rng`, but the candidate
   *set* grows (owned variants below top mastery are now listed), so
   `DefaultRunDecisionPolicy`'s "first candidate" can select a different subject
   than the pre-SP1 string list → different training subject order → different
   `generateTrainingAttempts` consumption per cycle.

**Consequence:** any test asserting exact post-training `finalBuild` contentIds,
`techniquesEvolved` contents, encounter health numbers, or Almanac occupant sets
for a fixed seed will shift. This is expected and sanctioned by the SP1 brief §16
and §19. Handling:

* Determinism *property* is preserved and re-proven: same seed + same policy +
  same initial state → structurally equivalent `RunResult` and `AlmanacState`
  (two-call equality), and `ReplayDecisionPolicy(log)` reproduces the run.
* Each changed golden is updated deliberately with a one-line note in the test
  pointing at this section. No conditional/branchy test behaviour.
* `almanac == null` byte-identical-to-`runGame(seed)` guarantee
  (`run_game_almanac_validation_test`, `almanac_run_history_test` M2) is preserved
  — the Almanac path still adds no `rng`/state effects.

### Tests expected to need deliberate updates

| Test | Why | New assertion shape |
|---|---|---|
| `test/game/game_run_test.dart` "learns and evolves" (`:139`) | `finalBuild` contentId is now the base family, not the evolved string | assert the slot's `instanceEntityId` resolves a `TechniqueVariant` whose `descriptorIds` match the evolved mapping; `techniquesEvolved.last` still holds the legacy string |
| `test/game/game_run_test.dart` "auto-equip never evicts" (`:255`) | still valid — technique ref still has `referenceType == techniqueReferenceType` | unchanged, may need seed note |
| `test/integration/almanac_run_history_test.dart` "postTraining snapshot" (`:402`), evolved-in-finalBuild (`:450`) | `_occupants` reads `occupantRefId` = base family now | assert via `TechniqueInstanceSnapshot.descriptorIds` / `baseFamilyId` + `state.discoveries` for the variant |
| `test/game/telemetry_test.dart` (`:72-79`) | `TechniqueEvolved.toId` still a legacy string, still ∈ `techniquesEvolved` | unchanged; verify |
| `test/game/decision_log_replay_test.dart` | `DecisionLog.trainingChoices` type change; values still round-trip | update fixtures to `RunTrainingTarget`; replay equality still holds |
| `test/game/console_decision_policy_test.dart` (`:83`, `:175`) | typed `chooseTrainingTarget` + `save`/`load` round-trip | scripted input & expectations use `RunTrainingTarget.encode` forms |
| `test/game/multi_seed_diversity_test.dart`, `playtest_report_test.dart` | seed-composition shift | re-baseline any exact counts; keep structural assertions |
| `test/integration/training_pipeline_integration_test.dart` (`:75`) | uses `subject: 'technique:basic_punch'` directly against `TrainingSession` — not `runGame` | unaffected |

## 8. New tests (per SP1 §18)

All under `test/plugins/game/`, `test/plugins/technique/`, `test/integration/`.
None mock the technique lifecycle.

1. **Acquisition** — first `learned` base family → exactly one owned
   descriptor-less base `TechniqueVariant`; learning it again mints no duplicate.
2. **Tome identity** — after placement, the slot's `BuildComponentRef` has
   `referenceType == techniqueReferenceType`, `contentId == familyId`,
   `instanceEntityId == baseInstance`.
3. **Combat identity (real pipeline)** — drive `CombatStage.runFight` (or `runGame`)
   with two owned variants A and B placed; a completed action sourced from A
   increments `techniqueVariantUsage(A)` and leaves `techniqueVariantUsage(B)`
   unchanged. Not a bare helper call.
4. **Damage folding** — a variant with `axisProfile['power'] = n` produces an
   `AttackAction.baseDamage == familyDamage + n` (and `≥ 1` when `n` is very
   negative); guard-family variant still yields `SelfEffectAction`.
5. **Evolution** — learn a base family, force evolution, assert: old Tome occupant
   replaced by the evolved variant instance, base variant entity removed, evolved
   variant carries the mapped descriptors, `techniquesEvolved` has the legacy id.
6. **Evolution re-fire guard (C)** — once the occupant is the evolved variant, a
   further training session on that family runs no evolution `rng` draw / mints no
   further evolved variant.
7. **Inspiration once per session** — with eligible variants owned, a training
   session (technique target) → exactly one inspiration resolution → ≤ 1 variant
   minted → `TechniqueVariantInspired` emitted at most once.
8. **Inspiration timing** — a training session that is **not** first-time base
   learning (variant-mastery target, or item target) still runs exactly one
   inspiration resolution.
9. **Newborn protection** — a just-inspired variant has mastery 0 / usage 0 and
   cannot itself be an inspirer in the same or next session.
10. **Cross-pollination** — own high-mastery/high-usage `basic_punch` variants,
    train `basic_kick`; any inspired variant has `baseFamilyId == 'basic_kick'`.
11. **Legacy migration completeness** — `mintVariantForLegacyEvolvedId` succeeds
    for every id in `TechniqueIds` that is an evolved (non-base) content id and is
    in `_legacyEvolvedDescriptors`; a synthetic evolved id absent from the map
    throws `LegacyTechniqueMigrationException`. (Guards §18 "every mapped … must
    migrate; every unmapped … must fail loudly".)
12. **Usage per-run lifetime** — a fresh `PluginContext` starts every variant at
    usage 0; within one run A and B increment independently; `TechniqueUsageComponent`
    is never persisted by `runGame`.
13. **Owned variant removal** — `removeTechniqueVariant` drops the Tome placement,
    clears per-instance mastery + usage, destroys the entity, emits
    `TechniqueVariantRemoved`; no game-layer duplicate cleanup.
14. **Determinism** — same seed + `NeverReplacePolicy` twice → structurally equal
    `RunResult` and `AlmanacState` projections; `ReplayDecisionPolicy` reproduces.
15. **End-to-end Almanac** (`test/integration/`) —
    `runGame(seed, almanac: recorder, runId, runNumber)` with a train-heavy policy
    → `AlmanacRecorder` state contains: ≥1 technique-variant discovery
    (`recordTechniqueDiscovered`), ≥1 variant usage observation with a real
    `instanceId`, and — for a seed where inspiration fires — an inspiration
    ancestry record with non-empty `inspirerInstanceIds`. Asserted through
    `AlmanacQueries`, no lifecycle mocking.
16. **Architecture guard** — `architecture_dependency_test` unchanged and green;
    add nothing that weakens it. (Technique dir still imports no
    combat/martial_arts/item/almanac; the damage-folding change is in
    `build_interpretation`, already a sanctioned dual-importer.)

## 9. Rollout / sequencing (for the implementation plan)

1. Complete `_legacyEvolvedDescriptors` (E) + test 11 — isolated, no run wiring.
2. `TechniqueActionInterpreter` damage folding (A) + tests 4 — isolated.
3. `RunTrainingTarget` type + `DecisionLog`/policy/console/save-load plumbing (F) +
   update `decision_log_replay` / `console_decision_policy` tests. Run stays on the
   legacy technique branch, just typed — no behaviour change yet, goldens hold.
4. `TomeManager.placeTechniqueVariant` / `replaceWithTechniqueVariant` + tests 2, 13.
5. `TrainingStage` migration: base-variant mint on learn, variant Tome placement,
   evolution → `mintVariantForLegacyEvolvedId`, inspiration moved to session
   boundary (B, C, D, G) + tests 1, 5, 6, 7, 8, 9, 10.
6. `manageTome` loose-variant equip/unequip + `knownTechniqueIds` rewrite.
7. Combat usage + Almanac end-to-end (tests 3, 12, 15) — mostly verifying dormant
   wiring now fires.
8. Re-baseline the deliberate goldens (§7 table) with in-test notes.
9. `dart analyze`; `dart test`; architecture/dependency tests explicitly.

## 10. Completion criteria

The SP1 brief §20 checklist, plus: `_legacyEvolvedDescriptors` total over shipped
evolved content; `TechniqueActionInterpreter` power-folding covered; typed
`RunTrainingTarget` end-to-end incl. save/load round-trip; every deliberately
changed golden carries a one-line pointer to §7.
