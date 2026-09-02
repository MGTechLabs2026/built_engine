# Technique Inspiration / Discovery Path — SP0b design

**Date:** 2026-09-03
**Status:** draft — awaiting review
**Repo:** `build_engine` (`Tome:RougelikeGame`)
**Depends on:** SP0a (technique instancing — merged to `main` @ `96d6767`)
**Shares a seam with:** SP1 (tiered component effects — `CombatAction.sourceRef`)

---

## 1. Why this exists

### 1.1 The chain

SP0a made every technique a player holds an instanced entity
(`TechniqueVariant`) with a descriptor-driven `axisProfile` and
per-instance mastery. It deliberately shipped **data + lifecycle only**:
`mintTechniqueVariant` takes the `descriptorIds` and `styleCentre` from a
caller and never decides them. SP0b is that caller for the case that
makes a build personal — **new variants generated from how you actually
fight.**

The player's loop, in their words: *lean on heavy jabs and fast jabs, and
that inspires a heavy-fast jab.* The style sets the centre; the
high-mastery variants you actually use are the seed.

### 1.2 Where SP0b sits

| SP | Scope | Depends on |
|----|-------|------------|
| SP0a | Technique instances, descriptor→axis model, per-instance mastery. **Merged.** | — |
| **SP0b** (this doc) | Per-variant combat-usage tracking; a post-training discovery roll; a pure weighted-blend resolver that mints a new derived variant on the trained family. `CombatAction.sourceRef` seam. | SP0a |
| SP1 | Tiered `EffectProfile` resolution. Reads `CombatAction.sourceRef` for its `active` tier. | SP0a |
| SP2 / SP3 / SP4 | Hooks/auras, potions, `Tome_client` surfacing (closes the original reward-affix bug). | SP1 |

### 1.3 The mechanic, decided

| Question | Answer |
|---|---|
| **Trigger** | After a training session — a parallel hook to today's `resolveTechniqueEvolutionAfterTraining`. Exactly one discovery roll per call; **at most one** new variant per training session. |
| **Usage signal** | A variant instance *performed a combat action* (hung **and** it struck / guarded in a resolved fight), counted from `ActionCompleted`. |
| **Inspirers** | `0` eligible → no discovery. `1` eligible → **focused** inspiration (a single well-practiced technique alone can inspire). `2+` → **blended**. |
| **Weighting** | `w = masteryLevel × √usage` — mastery is the linear proficiency signal, usage the recent-behaviour signal with **diminishing returns**; `usage 0` contributes nothing. |
| **Seed blend** | Weighted draw over the descriptors **compatible** with the trained family; each candidate's weight tracks how much its *positive* axes overlap the axes your inspirers emphasize. RNG via `RngService`. |
| **Family** | Always the **trained** technique's family (train a kick → a kick variant, seeded by your heavy/fast Punch usage — cross-pollination preserved). |
| **Descriptor count** | Behaviour-driven: single source → 1, multiple distinct → 2, a strong multi-source blend → 3. Hard cap 3. |
| **Discovery odds** | `p = base + gain · concentration`, where `concentration = max inspirer weight / total inspirer weight` — deterministic, monotonic, bounded `[0, 1]`. |
| **Result placement** | Minted **owned but loose**; the player hangs it. Never a replacement, never a Tome eviction; the inspirers are never mutated. |

---

## 2. Scope

### 2.1 In scope

- `CombatAction.sourceRef: BuildComponentRef?` (optional), set by
  `TechniqueActionInterpreter`. The SP1 active-tier seam, brought forward.
- `TechniqueUsageComponent` — per-variant combat-action counts, on the
  fighter entity; a Core-only `recordTechniqueVariantUsage` reducer plus a
  `techniqueVariantUsage` accessor in `technique/`; the `ActionCompleted`
  → usage bridge added to the composition layer's existing subscription
  (§5.2), never inside `technique/`.
- `TechniqueInspirationResolver` — a pure function: inspirers + descriptor
  pool + rng → `InspirationResult`.
- `resolveTechniqueInspirationAfterTraining` — the one authoritative
  post-training hook. Gathers inspirers, calls the resolver, mints on a
  hit, publishes `TechniqueVariantInspired`.
- `TechniqueVariantInspired` event.
- Tuning constants in `technique_vocabulary.dart`.
- `removeTechniqueVariant` also drops the removed instance's usage entry.
- `martial_arts`: a `styleCentre(styleId, familyId)` lookup over a
  per-style, per-base-family axis-nudge table.
- Tests. `CHANGELOG.md` + `ARCHITECTURE.md`.

### 2.2 Out of scope

- Retiring `EvolutionResolver` / `resolveTechniqueEvolutionAfterTraining`
  / `TechniqueEvolved` — SP0b runs **alongside** the existing evolution
  path (see §7). A later, separate pass retires it.
- `ItemActionInterpreter` setting `sourceRef` — SP0b has no item-usage
  need; SP1 does that when it needs the item active tier.
- Turning `axisProfile` into combat numbers — SP1.
- Any `Tome_client` change beyond the one-line call into
  `resolveTechniqueInspirationAfterTraining` from `TrainingAdapter` (its
  code isn't in this repo; the spec only defines the engine surface it
  calls).
- Persisting `TechniqueUsageComponent` — usage is per-run, discarded with
  the run's `PluginContext`, exactly like SP0a's per-instance
  `MasteryDefinition`s.
- A player-facing "accept / reject the discovery" step — the variant is
  minted and offered on the roster; the client decides presentation.

---

## 3. Contract fit (`claude.md`)

| Rule | Compliance |
|------|-----------|
| *Core provides verbs; plugins provide nouns.* | Nothing enters core. `sourceRef` is an optional field on the existing `CombatAction` value type (Combat plugin). Everything else is in `technique/` or `martial_arts/`. "jab", "heavy", "inspiration" never reach core. |
| *No giant classes.* | `TechniqueUsageComponent` = one `Map<EntityId,int>`. `Inspirer` / `InspirationResult` are small immutable value types. `TechniqueInspirationResolver` is a `const` class with one pure method (mirrors `EvolutionResolver` / `RewardResolver`). |
| *No speculative abstraction.* | `sourceRef` has two concrete consumers (SP0b usage, SP1 active tier). The resolver has one caller. Constants are the four the mechanic needs. |
| *Data-driven where practical; RNG through `RngService`.* | The style-centre table is content in `martial_arts`. Every draw is `context.rng`; a seed reproduces the run. |
| *Dependencies point downward.* | `technique/` still names neither `combat` nor `martial_arts` — `architecture_dependency_test` enforces both. The `ActionCompleted` → usage bridge lives in the composition layer (§5.2), which already subscribes to that event; it calls the Core-only `recordTechniqueVariantUsage`. `styleCentre` is *passed into* `resolveTechniqueInspirationAfterTraining` by a caller that has it — the technique plugin never looks it up. |
| *One authoritative publisher per domain event.* | `TechniqueVariantInspired` is published only by `resolveTechniqueInspirationAfterTraining`, mirroring `TechniqueEvolved`. |

**Engine footprint:** one optional field on `CombatAction` + the
interpreter setting it. Everything else is plugin-level.

---

## 4. The `sourceRef` seam

### 4.1 `CombatAction`

```dart
// lib/src/plugins/combat/combat_action.dart
abstract class CombatAction {
  /// The build component this action was interpreted from, if any — set
  /// by the build-interpretation layer (SP0b: TechniqueActionInterpreter).
  /// Carries `referenceType` + `contentId` + `instanceEntityId`. Null for
  /// an action with no build origin (a bare-handed fallback strike, a
  /// rule-spawned action). Consumers: SP0b per-variant usage, SP1 active
  /// tier.
  BuildComponentRef? get sourceRef;
  // ... existing members unchanged
}
```

`AttackAction` and `SelfEffectAction` gain a `BuildComponentRef? sourceRef`
constructor parameter (optional named, default `null`) and expose it.
Every existing construction site keeps compiling.

### 4.2 `TechniqueActionInterpreter`

`interpret` already loops `for (final ref in build.components)` and builds
one action per technique ref. Each built `AttackAction` / `SelfEffectAction`
is constructed with `sourceRef: ref`. The bare-handed fallback (when the
build produced no attack) is constructed with `sourceRef: null`.

Nothing else in `build_interpretation` changes. `ItemActionInterpreter`
is untouched (SP1's job).

### 4.3 Determinism

`sourceRef` is set-once at interpretation, read-only after. It does not
enter damage math, modifier resolution, or action ordering. Combat
outcomes are byte-identical with and without the field populated —
asserted by a test.

---

## 5. Usage lifecycle (`technique/technique_usage.dart`)

### 5.1 Component

```dart
/// Per-run tally of how many combat actions each of an owner's technique
/// variant instances has performed. Pure state. Attached to the fighter
/// entity. Not persisted — a run's fresh PluginContext starts it empty,
/// the same lifetime bound SP0a's per-instance MasteryDefinitions have.
class TechniqueUsageComponent {
  const TechniqueUsageComponent(this.byInstance);
  final Map<EntityId, int> byInstance;
}
```

### 5.2 The `ActionCompleted` → usage bridge

`test/integration/architecture_dependency_test.dart` forbids **any** file
under `lib/src/plugins/technique/` from naming Combat (`'Technique does
not reference Combat'`), so the subscription **cannot** live in
`TechniquePlugin` — it would have to name the `ActionCompleted` type. The
split mirrors the precedent `TechniqueActionInterpreter`'s own docstring
states: *the bridging code that needs both Combat and Technique lives
outside `technique/`; the Technique plugin stays Combat-free.*

- **`technique/technique_usage.dart` (Core-only)** owns the state and a
  pure reducer:

  ```dart
  /// Records one performed combat action for variant [instanceId] on its
  /// owner's TechniqueUsageComponent. Pure ECS state mutation, no Combat
  /// types. Owner read from TechniqueVariant.owner (rule 5). Throws
  /// TechniqueVariantNotFoundException for an unknown instance id.
  void recordTechniqueVariantUsage(EntityId instanceId, PluginContext context);
  ```

- **The composition layer's existing combat-event subscription** does the
  `sourceRef` unwrap and calls it. In the headless harness that is
  `CombatStage.runFight`, which **already** holds an
  `events.subscribe<ActionCompleted>` (it counts `turnsUsed`); SP0b adds
  three lines to that same handler:

  ```dart
  final ref = e.action.sourceRef;
  if (ref != null &&
      ref.referenceType == techniqueReferenceType &&
      ref.instanceEntityId != null) {
    recordTechniqueVariantUsage(ref.instanceEntityId!, context);
  }
  ```

  The client's combat loop adds the equivalent call at its own
  `ActionCompleted` site (out of this repo; §2.2).

`ActionCompleted` is chosen over `ActionStarted` so a condition-failed
action (evaluated but not performed) does not count — `CombatSystem`
publishes `ActionCompleted` only after the effects apply. The harness
subscription is already battle-scoped and cancelled at fight end, so
re-entry cannot double-count.

### 5.3 Accessor + cleanup

```dart
int techniqueVariantUsage(EntityId instanceId, PluginContext context);
```

Owner derived from the instance's `TechniqueVariant.owner` (rule 5); `0`
if no `TechniqueUsageComponent` or no entry. Throws
`TechniqueVariantNotFoundException` for an unknown instance id (via
`_requireVariant`, promoted to a public `requireTechniqueVariant` in
`technique_variant_lifecycle.dart` and reused here — visibility only,
behaviour unchanged).

`removeTechniqueVariant` (SP0a file) gains one step between its
mastery-trim and component-removal: if the owner's
`TechniqueUsageComponent` has an entry for `instanceId`, rebuild it
without that key — the same rebuild pattern it already uses for
`MasteryComponent`.

---

## 6. The inspiration resolver (`technique/technique_inspiration.dart`)

### 6.1 Types

```dart
class Inspirer {
  const Inspirer({
    required this.instanceId,    // the variant entity — reported back in the event
    required this.axisProfile,   // the variant's stored TechniqueVariant.axisProfile
    required this.masteryLevel,  // per-instance mastery level, 0..3
    required this.usage,         // combat actions performed this run, >= 0
  });
  final EntityId instanceId;
  final Map<String, num> axisProfile;
  final int masteryLevel;
  final int usage;
}

class InspirationResult {
  const InspirationResult({
    required this.discovered,
    required this.familyId,             // == trainedFamilyId; '' when !discovered
    required this.descriptorIds,        // 1..3 ids when discovered, empty otherwise
    required this.inspirerInstanceIds,  // the eligible inspirers the resolver used; [] when !discovered
  });
  final bool discovered;
  final String familyId;
  final Set<String> descriptorIds;
  final List<EntityId> inspirerInstanceIds;

  static const none = InspirationResult(
    discovered: false, familyId: '', descriptorIds: {}, inspirerInstanceIds: [],
  );
}

class TechniqueInspirationResolver {
  const TechniqueInspirationResolver();

  InspirationResult resolve({
    required String trainedFamilyId,
    required Iterable<Inspirer> inspirers,       // caller has NOT pre-filtered
    required Iterable<TechniqueDescriptor> descriptorPool,
    required RngService rng,
    Set<Set<String>> exclude = const {},         // descriptor sets not to produce
  });
}
```

`styleCentre` is **not** a resolver input — it informs nothing in the
draw. The caller passes it straight to `mintTechniqueVariant` (SP0a
rule 3: style composition stays out of the resolver, and here also out of
the roll).

`exclude` is the set of descriptor sets the caller already has for the
trained family (the exact-duplicate guard, §7 / §16). The resolver's draw
retries past an excluded outcome a bounded number of times, then gives up
(`InspirationResult.none`).

### 6.2 Algorithm

**Step 0 — eligibility filter.** `eligible = inspirers where masteryLevel
>= kMinMasteryToInspire && usage >= kMinUsageToInspire`.

- `eligible.length == 0` → `InspirationResult.none`.
- `eligible.length == 1` → **focused inspiration** (a single highly
  practiced, heavily used technique alone can inspire a new variant).
- `eligible.length >= 2` → **blended inspiration**.

There is no lower bound of 2.

**Step 1 — damped inspirer weights.** For each eligible inspirer,
`w_i = masteryLevel_i * sqrt(usage_i)`. Rationale: mastery is the stronger
proficiency signal (linear); usage is the recent-behaviour signal but
with **diminishing returns** (`sqrt`), so a long-lived high-usage variant
cannot run away with every future discovery. `usage_i == 0` → `w_i == 0`.
If `Σ w_i == 0` → `InspirationResult.none`.

**Step 2 — emphasis profile `E`.** For each axis,
`E[axis] = Σ_i w_i * max(0, axisProfile_i[axis])`. Only **positive** axis
contributions feed emphasis — a descriptor's negative trade-off is not
"what the player emphasizes". This is a *selection* signal only; the
minted variant's `axisProfile` (built by `TechniqueVariantResolver` over
the drawn descriptors, SP0a) keeps every axis, negatives included — SP0b
never strips them (§3). If `Σ E == 0` (every eligible inspirer is
all-neutral / all-negative) → `InspirationResult.none`. Otherwise
normalize: `E[axis] /= Σ E`.

**Step 3 — concentration `c`.**
`c = max_i(w_i) / Σ_i(w_i)`. A single dominant inspirer → `c` near 1; an
even spread → `c` near `1 / eligible.length`. Deterministic, monotonic
with focus, bounded to `(0, 1]`. Worked examples (using raw weights for
illustration): `{100}` → 1.0; `{60, 30, 10}` → 0.60;
`{34, 33, 33}` → ≈ 0.34.

**Step 4 — discovery roll.**
`p = clamp(kInspirationBaseChance + kInspirationConcentrationGain * c,
0, 1)` — monotonic in `c`, bounded `[0, 1]`. Draw `rng.nextDouble()`; if
`>= p` → `InspirationResult.none`. (This is the single roll that gives
§8's one-discovery-per-training guarantee.)

**Step 5 — compatible descriptor pool.**
`compatible = descriptorPool where compatibleWith(d, trainedFamilyId)`:

- If `d.tags` contains **no** tag of the form `family:<base>` → compatible
  (unrestricted content stays open-ended).
- If `d.tags` contains one or more `family:<base>` tags → compatible
  **iff** one of them is `family:<trainedFamilyId>` (e.g.
  `family:basic_kick`).

A descriptor explicitly restricted away from the trained family is never
selected. No launch descriptor carries a `family:` tag today, so every
current descriptor is universal; this is forward-looking content vocab,
not a launch-content change. If `compatible` is empty →
`InspirationResult.none`.

**Step 6 — descriptor count `k`.**
`k = min(eligible.length, 2)`  (1 source → 1, 2+ sources → 2).
`strong = mean(eligible.masteryLevel) >= kInspirationStrongMasteryBar &&
Σ w_i >= kInspirationStrongWeightBar`.
`if (eligible.length >= 2 && strong) k = 3`.
`k = clamp(k, 1, 3)`, then `k = min(k, compatible.length)`.

So: single ordinary source → 1; single strong source → 1; multiple
distinct sources → 2; a strong multi-source blend → 3. Cap 3 always.

**Step 7 — weighted draw, `k` times, without replacement, over
`compatible`.** For each remaining candidate `d`,
`weight(d) = Σ_axis E[axis] * max(0, d.axes[axis])`. A `d` with no
positive overlap has weight 0. Pick: `total = Σ weight(remaining)`;
`t = rng.nextDouble() * total`; walk the remaining candidates in a stable
order accumulating `weight`, take the first whose running sum `> t` — the
normalized-cumulative pick `RewardResolver` already uses. Remove the
picked `d` and repeat. If every remaining candidate has weight 0, stop
early — a result with ≥ 1 descriptor still stands; 0 descriptors →
`InspirationResult.none`.

**Step 8 — exclusion retry.** If the drawn set is set-equal to any entry
in `exclude`, discard it and redo steps 6–7 with the *already-advanced*
`rng`. Repeat at most `kInspirationExcludeRetries` (3) times; if still
excluded or empty, `InspirationResult.none`.

**Result:** `InspirationResult(discovered: true, familyId:
trainedFamilyId, descriptorIds: {the drawn ids}, inspirerInstanceIds:
[eligible instance ids])`.

Every step is pure arithmetic over `num` plus `rng`. Same `rng` state +
same inputs → identical result — a two-runs-equal test locks it.

### 6.3 Tuning constants (`technique_vocabulary.dart`)

```dart
const kInspirationBaseChance = 0.05;         // p at zero concentration
const kInspirationConcentrationGain = 0.55;  // p rises toward ~0.60 at c == 1
const kMinMasteryToInspire = 1;              // an inspirer is at least level 1
const kMinUsageToInspire = 3;               // ...and has acted 3+ times this run
const kInspirationExcludeRetries = 3;       // draw re-rolls past a duplicate blend
const kInspirationStrongMasteryBar = 2;     // mean eligible mastery for a "strong" blend
const kInspirationStrongWeightBar = 6.0;    // total damped weight for a "strong" blend
```

Placeholder values — tuned against `game_run` balance sweeps; each is a
named constant, never inline in the resolver.

---

## 7. Trigger wiring (`technique/technique_inspiration.dart`)

```dart
/// The one authoritative "did training just inspire a new variant?" step.
/// Call once after a training session, parallel to
/// `resolveTechniqueEvolutionAfterTraining`. [styleCentre] is the trained
/// family's centre for the character's style — the caller supplies it
/// (the technique plugin does not import `martial_arts`).
///
/// Gathers the owner's variant instances as [Inspirer]s (mastery + usage
/// read from the plugin's own trackers), runs
/// [TechniqueInspirationResolver] once, and on a hit:
///   - `mintTechniqueVariant(owner, familyId, descriptorIds, context,
///      styleId: <char style>, styleCentre: styleCentre)`,
///   - publishes [TechniqueVariantInspired] exactly once, built from the
///     result's `inspirerInstanceIds` + `descriptorIds`.
/// Exactly one call → one resolver roll → **at most one** minted variant
/// and **at most one** event. No cooldown, no mutable state; the single
/// roll is the cap (§8). Returns the [InspirationResult] snapshot; the
/// caller owns telemetry / UI.
InspirationResult resolveTechniqueInspirationAfterTraining(
  EntityId owner,
  TechniqueDefinition trainedTechnique,
  Map<String, num> styleCentre,
  PluginContext context, {
  String? styleId,
});
```

- **Trained family:** SP0a's `_familyOf(trainedTechnique.id, context)`,
  promoted from private to a reusable `techniqueFamilyOf` (behaviour
  unchanged — just visibility).
- **Inspirers:** `for (final e in ownedTechniqueVariants(owner, context))`
  build `Inspirer(instanceId: e, axisProfile: v.axisProfile, masteryLevel:
  techniqueVariantMasteryLevel(e, context), usage: techniqueVariantUsage(e,
  context))`. Pass the whole set; the resolver filters (§6.2 step 0). A
  **newly minted** variant has `masteryLevel == 0` and `usage == 0`, so it
  fails the eligibility filter and **cannot inspire** until it
  independently crosses the thresholds — no `canInspire` flag, the
  behaviour falls out of the numbers (§7 of the improvement brief).
- **Descriptor pool:** `context.content.allOfType('technique_descriptor')`
  parsed via `techniqueDescriptorFromContent`. The resolver applies the
  compatibility filter (§6.2 step 5) and then the axis weighting.
- **Exact-duplicate guard:** build `exclude` = `{ v.descriptorIds : v in
  owned variants where v.baseFamilyId == trainedFamilyId }` and pass it to
  `resolve`. The resolver's step 8 handles the bounded retry / give-up.
  SP0b guards only **exact** descriptor-set duplicates; near-duplicates
  (`{strong, swift}` vs `{strong, fast}`) may coexist — semantic
  similarity is a future content concern (§16 of the improvement brief).
- **Cross-pollination is preserved:** `familyId` is always the *trained*
  family; the inspirers are not required to share it. Training a Kick with
  high-mastery Heavy/Swift Punches inspires a **Kick** variant carrying
  power/speed descriptors.
- **Mint:** the discovered variant gets `styleId` set, so
  `hangTechniqueVariant` treats it as **derived** (no learning gate). It
  is minted **owned but loose** — no Tome placement, no eviction; the
  client hangs it later. The inspirers are never touched: no descriptor
  edit, no mastery reset, no replacement.
- **Callers:** the engine's reference training flow
  (`game_run` / `training_stage`) and, in the client, `TrainingAdapter`,
  each add one call immediately after their existing
  `resolveTechniqueEvolutionAfterTraining` call. Inspiration is **never**
  attached to an individual exercise or to Combat.

---

## 8. `TechniqueVariantInspired` (`technique/technique_events.dart`)

```dart
/// One training session inspired a new derived variant. Published exactly
/// once per discovery, from exactly one place —
/// `resolveTechniqueInspirationAfterTraining` — mirroring `TechniqueEvolved`'s
/// single-publisher discipline. Lineage / telemetry / UI consumers
/// subscribe from `package:build_engine/technique_plugin.dart`.
class TechniqueVariantInspired {
  const TechniqueVariantInspired({
    required this.owner,
    required this.instanceId,           // the freshly minted variant
    required this.familyId,             // its base family (== the trained family)
    required this.descriptorIds,        // the drawn descriptors — lets a client name it
    required this.inspirerInstanceIds,  // the eligible variants that influenced it
  });
  final EntityId owner;
  final EntityId instanceId;
  final String familyId;
  final Set<String> descriptorIds;
  final List<EntityId> inspirerInstanceIds;
}
```

Enough for a client to render *"Your Heavy Jab and Swift Jab inspired a
new Heavy-Fast Jab"* — `inspirerInstanceIds` names the real influencing
variants, `descriptorIds` + `familyId` name the result. RNG internals and
intermediate scores are **not** exposed.

---

## 9. `martial_arts` — style-centre table

```dart
/// The per-style, per-base-family axis nudge applied to a minted variant.
/// Content-shaped (a const table today; a ContentRegistry batch later if
/// it grows). `{}` for an unknown style/family pair.
Map<String, num> styleCentre(String styleId, String familyId);
```

Backing data: one small table over the six shipped `MartialStyles`
(`polearming` / `wrestling` / `fencing` / `shaolin` / `taiChi` /
`kunlun`) × the six base families, e.g.

| style | family | centre |
|---|---|---|
| `wrestling` | `basic_punch` | `{power: 3}` |
| `kunlun` | `basic_kick` | `{speed: 2, precision: 1}` |
| `taiChi` | `basic_guard` | `{endurance: 3}` |
| … | … | … |

Every `(style) × (base family)` pair gets an entry (possibly `{}`). The
caller of `resolveTechniqueInspirationAfterTraining` (the composition
layer / client — which knows the character's style) reads it and passes
the result in. SP0a's starting-variant seeding may use the same function.

This lives in `martial_arts` (which owns styles); the technique plugin
never sees it.

---

## 10. Coexistence with the evolution path

Untouched: `EvolutionResolver`, `resolveTechniqueEvolutionAfterTraining`,
`evolveTechnique`, `TechniqueEvolved`, `TechniqueDefinition.evolutionCandidates`,
the hand-authored evolved ids, and SP0a's `mintVariantForLegacyEvolvedId`.

SP0b's `resolveTechniqueInspirationAfterTraining` is a **sibling**. A
post-training flow calls both: evolution may replace a hung technique in
its slot; inspiration may add a new loose variant to the roster. They
never interact. Retiring the evolution path is a later pass — the
parallel structure makes it a near-mechanical delete once nothing calls
the evolution function.

---

## 11. Data flow

```
                combat
  ActionCompleted(actor, action)                    training session ends
        │                                                   │
   action.sourceRef is a technique instance?          resolveTechniqueEvolutionAfterTraining(...)   (unchanged)
        │ yes                                               │
   TechniqueUsageComponent[actor].byInstance[inst]++        resolveTechniqueInspirationAfterTraining(owner, trained, styleCentre, ctx)
        │                                                   │
        └──────────────► per-variant usage ◄───────────┐    ├─ inspirers = ownedTechniqueVariants
                                                        │    │     × (per-instance mastery, per-instance usage)
   per-instance mastery (SP0a) ─────────────────────────┘    ├─ TechniqueInspirationResolver.resolve(..., rng, exclude) → InspirationResult
                                                             │        eligible: 0 → none | 1 → focused | 2+ → blended
                                                             │        w_i = mastery × √usage  → emphasis E (positive axes only)
                                                             │        c = max(w_i) / Σ(w_i)   → p = base + gain·c → roll
                                                             │        compatibility filter → k (source count + blend strength, 1..3)
                                                             │        weighted draw → exact-duplicate exclusion (bounded retry)
                                                             ├─ mintTechniqueVariant(owner, familyId, descriptorIds,
                                                             │     styleId, styleCentre)          ← SP0a  (owned, loose; inspirers untouched)
                                                             └─ publish TechniqueVariantInspired(owner, instanceId, familyId,
                                                                   descriptorIds, inspirerInstanceIds)
```

---

## 12. Edge cases

| Case | Behaviour |
|------|-----------|
| Zero eligible inspirers | `InspirationResult.none`, no event, no mint. |
| Exactly one eligible inspirer | Focused inspiration — discovery is possible; concentration `c == 1.0`. |
| Newly minted variant (`mastery 0`, `usage 0`) as a candidate inspirer | Fails the eligibility filter; cannot inspire until it independently reaches `kMinMasteryToInspire` / `kMinUsageToInspire`. |
| Every eligible inspirer all-neutral / all-negative (`Σ E == 0`) | `InspirationResult.none`. |
| `Σ w_i == 0` (every eligible inspirer has `usage == 0`) | `InspirationResult.none`. |
| Compatible descriptor pool empty (all pooled descriptors restricted away from the trained family) | `InspirationResult.none`. |
| Weighted draw runs out of positive-weight candidates before `k` | Stop early; a result with ≥ 1 descriptor still `discovered: true`; 0 → `InspirationResult.none`. |
| Drawn set set-equal to an `exclude` entry | Re-roll steps 6–7, at most `kInspirationExcludeRetries` times; still excluded/empty → `InspirationResult.none`. Near-duplicates are allowed. |
| Trained technique is a base family, not an evolved id | `techniqueFamilyOf` returns it unchanged; the inspired variant is of that family. |
| Cross-pollination: inspirers of a different family than the trained one | Allowed and preserved — `familyId` is always the trained family; inspirer families only shape the axis emphasis. |
| A technique action with `sourceRef.instanceEntityId == null` (pre-SP0a placement) | Usage handler ignores it — no tally, no crash. |
| Bare-handed fallback strike (`sourceRef == null`) or an item-origin action | Ignored by the usage handler (only `referenceType == techniqueReferenceType` with a non-null instance counts). |
| `removeTechniqueVariant` on an instance with a usage entry | The entry is dropped alongside the mastery-progress trim. |
| Same seed, same owner state, same trained technique | Identical `InspirationResult` — no wall-clock, no hidden state, one `RngService`. |
| Combat outcome with `sourceRef` populated vs not | Identical — `sourceRef` never enters damage / modifier / ordering / RNG. |
| Two `resolveTechniqueInspirationAfterTraining` calls in one training session | Not the plugin's concern — each call is one roll / ≤ one mint. Callers make exactly one call per session. |

---

## 13. Files

**New**

- `lib/src/plugins/technique/technique_usage.dart` — `TechniqueUsageComponent`,
  `recordTechniqueVariantUsage` (pure, Core-only), `techniqueVariantUsage`.
- `lib/src/plugins/technique/technique_inspiration.dart` — `Inspirer`,
  `InspirationResult`, `TechniqueInspirationResolver`,
  `descriptorCompatibleWithFamily`, `resolveTechniqueInspirationAfterTraining`.
- `lib/src/plugins/martial_arts/style_centre.dart` — `styleCentre(styleId,
  familyId)` + its table.
- tests under `test/plugins/technique/`,
  `test/plugins/build_interpretation/`, `test/plugins/martial_arts/`,
  `test/plugins/game/`.

**Changed**

- `lib/src/plugins/combat/combat_action.dart` — `sourceRef` getter on
  `CombatAction` (default `=> null`) + `sourceRef` param/field on
  `AttackAction` (same file).
- `lib/src/plugins/build_interpretation/self_effect_action.dart` —
  `sourceRef` param + field.
- `lib/src/plugins/build_interpretation/technique_action_interpreter.dart`
  — set `sourceRef: ref` on every built action.
- `lib/src/plugins/technique/technique_events.dart` —
  `TechniqueVariantInspired`.
- `lib/src/plugins/technique/technique_vocabulary.dart` — the seven
  tuning constants (§6.3) + `techniqueFamilyTagPrefix`.
- `lib/src/plugins/technique/technique_variant_lifecycle.dart` —
  `removeTechniqueVariant` drops the usage entry; rename `_requireVariant`
  → public `requireTechniqueVariant` and `_familyOf` → public
  `techniqueFamilyOf` (visibility only).
- `lib/technique_plugin.dart` — barrel exports for `technique_usage.dart`
  + `technique_inspiration.dart`.
- `lib/martial_arts_plugin.dart` — barrel export for `style_centre.dart`.
- `lib/src/plugins/game/combat_stage.dart` — extend the existing
  `ActionCompleted` subscription to record technique-variant usage.
- `lib/src/plugins/game/training_stage.dart` — one
  `resolveTechniqueInspirationAfterTraining` call after the evolution
  block; new `styleId` constructor field.
- `lib/src/plugins/game/game_run.dart` — pass `styleId` to `TrainingStage`.
- `CHANGELOG.md`, `ARCHITECTURE.md`.

No file under `lib/src/plugins/technique/` gains a Combat or MartialArts
import — `architecture_dependency_test` still passes unchanged.

---

## 14. Testing

**`TechniqueInspirationResolver`** (pure):

*Eligibility*
- Zero eligible → `InspirationResult.none`.
- Exactly one eligible → discovery possible (a single strong inspirer),
  `concentration == 1.0`.
- Two+ eligible → blended discovery.
- A newborn-style inspirer (`mastery 0` / `usage 0`) is filtered out.

*Weighting (damped)*
- Mastery increases weight (mastery 3 > mastery 1 at equal usage).
- Usage increases weight (usage 25 > usage 4 at equal mastery).
- Diminishing returns: with mastery fixed, the weight for
  `usage ∈ {1, 4, 9, 25, 100}` is strictly increasing but **sub-linear**
  — `w(4)/w(1) == 2`, `w(9)/w(1) == 3`, `w(100)/w(1) == 10` (i.e.
  `w ∝ √usage`), not `4×`, `9×`, `100×`.
- `usage == 0` contributes exactly `0`.

*Emphasis & trade-offs*
- A `bear`-like inspirer (`{power: 6, speed: -1}`) contributes to `E`'s
  `power` and never subtracts from `E`'s `speed` (positive-only).
- The resolver returns descriptor **ids**, not a profile; a follow-up
  test on the *minted* variant (integration) confirms `axisProfile`
  still carries the negative axes (§3) — SP0b strips nothing.

*Concentration*
- One dominant inspirer → `c` near 1.0.
- Weights `{6, 3, 1}` → `c == 0.6`; `{1, 1, 1}` → `c ≈ 0.333`.
- `p` is monotonic in `c` and stays within `[0, 1]` at the extremes.

*Compatibility*
- A descriptor tagged `family:basic_kick` is never drawn for a
  `basic_punch` training.
- A descriptor tagged `family:basic_punch` **can** be drawn for a
  `basic_punch` training.
- A descriptor with no `family:` tag is eligible for any family.
- All pooled descriptors restricted away from the trained family →
  `InspirationResult.none`.

*Descriptor count*
- Single ordinary source → 1.
- Single strong source (mastery ≥ bar, weight ≥ bar) → still 1.
- Two+ distinct sources → 2.
- Two+ sources that are also strong → 3.
- Never exceeds 3; never below 1; `min(k, compatiblePoolSize)`.

*Draw / duplicates / determinism*
- With `E` all on `power`, a fixed seed draws a `power` descriptor,
  never a pure-`endurance` one.
- Pool of one aligned descriptor, `k == 3` → result has 1 descriptor,
  `discovered: true`.
- Pass the only reachable blend in `exclude` → after
  `kInspirationExcludeRetries` re-rolls → `InspirationResult.none`; a
  non-matching `exclude` set → unaffected; a near-duplicate
  (`{strong, fast}` vs an owned `{strong, swift}`) is **not** excluded.
- Identical `trainedFamilyId` + `inspirers` + `descriptorPool` +
  `RngService(seed)` → identical `discovered` and `descriptorIds`, twice.

**`TechniqueUsageComponent` + subscription:**

- `ActionCompleted` whose `action.sourceRef` has
  `referenceType == techniqueReferenceType` and a non-null
  `instanceEntityId` → `techniqueVariantUsage` for that instance +1 on
  the actor.
- `sourceRef == null`, `referenceType != techniqueReferenceType` (item
  origin), or `instanceEntityId == null` (pre-SP0a) → no change.
- No count from `ActionStarted` alone (a condition-failed action that
  never completes).
- Two different instances tracked independently.
- `unregister` then `initialize` on the same context → no double count.
- `removeTechniqueVariant` drops the usage entry (`usage == 0` after, no
  dangling map key).

**`TechniqueActionInterpreter`:**

- Each built `AttackAction` / `SelfEffectAction` carries `sourceRef`
  equal to the `BuildComponentRef` it came from (`contentId` +
  `instanceEntityId`).
- The bare-handed fallback carries `sourceRef == null`.
- A combat run's outcome (damage log, turn order, kills) is identical
  with `sourceRef` populated vs a build with no instance ids — the §4.3
  behaviour-neutrality regression guard.

**`resolveTechniqueInspirationAfterTraining` (integration):**

- **Cross-pollination:** mint two high-mastery, high-usage Punch variants
  (heavy + swift), train a **Kick**, fixed seed → a new **Kick** variant
  whose descriptors reflect power/speed; the event fires once with the
  two Punch inspirer ids.
- **Single-source:** one strong Heavy Jab (mastery 3, usage 30) alone,
  train that family, fixed seed → one new variant.
- **Newborn cannot chain:** immediately after a discovery, call the hook
  again with the same (still `mastery 0` / `usage 0`) new variant among
  the candidates → it is not an eligible inspirer; no second discovery
  from it.
- **One per session:** a single hook call mints at most one variant and
  publishes at most one event, on any inspirer state.
- **Lifecycle:** the minted variant has `mastery 0`, `usage 0`, the right
  `owner`, no Tome placement; every inspirer's `descriptorIds`,
  `axisProfile`, and mastery are unchanged.
- **Event payload:** `owner`, `instanceId` (the new one), `familyId`
  (trained family), `descriptorIds` (the drawn set),
  `inspirerInstanceIds` (the eligible inspirers) — all correct.
- **No discovery → no event:** below-threshold inspirers, a failed roll,
  and an all-excluded pool each publish nothing and mint nothing.
- **Coexistence:** `resolveTechniqueEvolutionAfterTraining` behaves
  exactly as before in the same flow.
- **Tradeoff preservation:** a discovered variant seeded by a `bear`-like
  descriptor still has the negative `speed` axis in its `axisProfile`.

**Whole-suite:** `dart test test/` stays green; `dart analyze` clean;
the `architecture_dependency_test` still passes (no new cross-plugin
import — `technique/` imports neither `combat` nor `martial_arts`).

---

## 15. Open questions (settle during planning / playtest)

1. **Tuning constants** (`kInspirationBaseChance`,
   `kInspirationConcentrationGain`, `kInspirationStrongMasteryBar`,
   `kInspirationStrongWeightBar`, `kMinMasteryToInspire`,
   `kMinUsageToInspire`, `kInspirationExcludeRetries`) — placeholders;
   tuned against `game_run` balance sweeps.
2. **`family:<base>` tag naming** — `family:basic_kick` (the full base id)
   vs `family:kick` (the family-tag vocab techniques already use). The
   spec assumes the full base id; confirm during planning against what
   reads cleanest in content. No launch descriptor carries one either way.
3. **`martial_arts` table completeness** — every shipped style × 6 base
   families; some pairs may legitimately be `{}`.
4. **`techniqueFamilyOf` visibility** — promoting SP0a's `_familyOf`
   from private; behaviour unchanged, visibility only.
5. **`Inspirer.instanceId` in the resolver** — carried only so the result
   can report `inspirerInstanceIds`; it never enters the math. Confirm
   the resolver stays otherwise pure of entity identity.
