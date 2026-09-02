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
| **Trigger** | After a training session — a parallel hook to today's `resolveTechniqueEvolutionAfterTraining`. **Exactly one** discovery roll per call; **at most one** new variant per training session. No cooldown, no discovery-lock component — the single roll is the whole cap (§8). |
| **Usage signal** | A variant instance *performed a combat action* (hung **and** it struck / guarded in a resolved fight), counted from `ActionCompleted`. |
| **Inspirers** | `0` eligible → no discovery. `1` eligible → **focused** inspiration (a single well-practiced technique alone can inspire); concentration `== 1.0` by construction (§6.2 step 3), which is exactly right — one source *is* maximally focused behaviour. `2+` → **blended**. |
| **Weighting** | `w = masteryLevel × √usage` — mastery is the linear proficiency signal, usage the recent-behaviour signal with **diminishing returns**; `mastery 0` or `usage 0` → `w == 0` (§6.2 step 1). |
| **Seed blend** | Weighted draw over the descriptors **compatible** with the trained family; each candidate's weight tracks how much its *positive* axes overlap the axes your inspirers emphasize. RNG via `RngService`. |
| **Family** | Always the **trained** technique's family (train a kick → a kick variant, seeded by your heavy/fast Punch usage — cross-pollination preserved). |
| **Descriptor count** | Behaviour-driven, chosen **before** the weighted draw: `1` single-source; `2` multi-source below the strong-blend bar; `3` multi-source **and** mean eligible mastery `>= kInspirationStrongMasteryBar` **and** total damped weight `>= kInspirationStrongWeightBar`. Clamped `<= 3`, then `min(k, compatiblePoolSize)`. |
| **Discovery odds** | `p = clamp(kInspirationBaseChance + kInspirationConcentrationGain · concentration, 0, 1)`, where `concentration = max inspirer weight / total inspirer weight` — deterministic, monotonic, bounded `[0, 1]`. With the shipped constants: `c == 0 → p == 0.05`; `c == 1 → p == 0.60`. |
| **Result placement** | Minted **owned but loose**; the player hangs it. Never a replacement, never a Tome eviction; the inspirers are never mutated (§13). |
| **Attribution** | `inspirerInstanceIds` reports only the eligible inspirers that **actually contributed** the winning positive-axis support to a drawn descriptor (§6.2 step 9), not every eligible variant — so a client can name the real sources ("Heavy Jab + Swift Jab inspired this"). Deterministic, no extra RNG. |

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
  pool + rng → `InspirationResult`. Includes deterministic, RNG-free
  source attribution (§6.2 step 9) so `inspirerInstanceIds` names only the
  variants that actually shaped the result.
- `descriptorCompatibleWithFamily` — the `family:<base>` allow-list check
  (§6.2 step 5), assuming content already validated.
- A **content-validation** check that every `family:<id>` tag on a
  `technique_descriptor` names a real `TechniqueIds.bases` member
  (§14.0) — reuses existing family vocabulary, adds no framework.
- `resolveTechniqueInspirationAfterTraining` — the one authoritative
  post-training hook. Gathers inspirers, calls the resolver, mints on a
  hit, publishes `TechniqueVariantInspired`.
- `TechniqueVariantInspired` event (five fields, locked — §8).
- Tuning constants + `techniqueFamilyTagPrefix` in
  `technique_vocabulary.dart`.
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
    required this.instanceId,    // the variant entity — reported back iff it is an attributed source
    required this.axisProfile,   // the variant's stored TechniqueVariant.axisProfile (signed)
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
    required this.inspirerInstanceIds,  // the eligible inspirers that ACTUALLY contributed
                                        // the winning positive-axis support to a drawn
                                        // descriptor (§6.2 step 9) — a subset of the
                                        // eligible set, ascending eligible-index order;
                                        // [] when !discovered
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
cannot run away with every future discovery. `masteryLevel_i == 0` →
`w_i == 0`; `usage_i == 0` → `w_i == 0`. If `Σ w_i == 0` →
`InspirationResult.none`.

The `sqrt` damping is the whole point — hold mastery fixed and the usage
contribution grows sub-linearly:

| `usage` | `sqrt(usage)` | vs `usage 1` |
|---|---|---|
| 1 | 1 | ×1 |
| 4 | 2 | ×2 (not ×4) |
| 9 | 3 | ×3 (not ×9) |
| 25 | 5 | ×5 (not ×25) |
| 100 | 10 | ×10 (not ×100) |

Do not "fix" this to linear during implementation unless a test proves a
defect — it is a deliberate anti-runaway design choice.

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

**Exactly one eligible inspirer → `c == 1.0`, by construction and on
purpose.** `max_i(w_i) == Σ_i(w_i)` when there is one term. There is **no
special single-source branch** — the formula already yields the intended
result: one heavily-drilled, heavily-used technique *is* maximally
focused behaviour, so it earns the maximum discovery probability
(`p == 0.60` with the shipped constants). Do not add a `case
eligible.length == 1` anywhere.

**Step 4 — discovery roll (the one and only roll).**
`p = clamp(kInspirationBaseChance + kInspirationConcentrationGain * c,
0, 1)` — monotonic in `c`, bounded `[0, 1]`. With the shipped constants
(`0.05`, `0.55`): `c == 0 → p == 0.05`, `c == 1 → p == 0.60`. Draw
`rng.nextDouble()` **once**; if `>= p` → `InspirationResult.none`. This is
the single roll that gives §8's one-discovery-per-training guarantee — no
second roll anywhere in the resolver, no roll added for event
attribution (§6.2 step 9).

**Step 5 — compatible descriptor pool.**
`compatible = descriptorPool where descriptorCompatibleWithFamily(d,
trainedFamilyId)`. The rule has exactly two cases:

- **No family restriction** — `d.tags` contains no tag with the
  `techniqueFamilyTagPrefix` (`family:`) prefix → `d` is eligible for
  **every valid technique base family**, including `trainedFamilyId`.
- **Family-restricted** — `d.tags` contains one or more
  `family:<baseId>` tags → `d` is compatible **iff** one of them is
  exactly `family:<trainedFamilyId>` (the *full base id*, e.g.
  `family:basic_kick` — see §15 open question #2, now closed: the suffix
  is the full base id so it matches `techniqueFamilyOf`'s return with no
  extra mapping).

The tag suffix `<baseId>` is always assumed to name a **valid** technique
base family. An `family:<id>` tag whose `<id>` is **not** one of
`TechniqueIds.bases` is a **content error**, caught by content validation
(§14.0) before any resolver call — it is *never* a resolver-time
"incompatible" outcome. The resolver does not distinguish "restricted
away" from "invalid": it only asks "does any `family:` tag equal
`family:<trainedFamilyId>`?" and trusts the content is valid.

A descriptor explicitly restricted away from the trained family is never
selected. No launch descriptor carries a `family:` tag today, so every
current descriptor is universal; this is forward-looking content vocab,
not a launch-content change. If `compatible` is empty →
`InspirationResult.none`.

**Step 6 — descriptor count `k` (chosen *before* the weighted draw).**
The full contract, using aggregates already computed in steps 1 and 3 —
no new scoring system:

```
meanMastery = mean(eligible[i].masteryLevel)          // step 0 set
strong      = eligible.length >= 2
              && meanMastery >= kInspirationStrongMasteryBar
              && Σ w_i        >= kInspirationStrongWeightBar   // Σ w_i from step 1

k = 1                       if eligible.length == 1           // single-source
k = 3                       if strong                         // strong multi-source blend
k = 2                       otherwise (eligible.length >= 2, not strong)

k = min(k, 3)               // hard cap, always
k = min(k, compatible.length)
```

So: single source (ordinary *or* strong) → 1; multiple sources below the
strong bar → 2; multiple sources **and** `meanMastery >=
kInspirationStrongMasteryBar` **and** `Σ w_i >= kInspirationStrongWeightBar`
→ 3. Never above 3, never below 1, never above the compatible-pool size.

**Step 7 — weighted draw, `k` times, without replacement, over
`compatible`.** For each remaining candidate `d`,
`weight(d) = Σ_axis E[axis] * max(0, d.axes[axis])`. A `d` with no
positive overlap has weight 0. Pick: `total = Σ weight(remaining)`;
`t = rng.nextDouble() * total`; walk the remaining candidates in a stable
order accumulating `weight`, take the first whose running sum `> t` — the
normalized-cumulative pick `RewardResolver`'s `weightedPick` already
does. Remove the picked `d` and repeat. If every remaining candidate has
weight 0, stop early — a result with ≥ 1 descriptor still stands; 0
descriptors → `InspirationResult.none`. The weighted draw's
probabilities are **never** adjusted to make step 9 attribution tidier.

**Step 8 — exclusion retry.** If the drawn set is set-equal to any entry
in `exclude`, discard it and redo step 7 (with the *already-advanced*
`rng`; `k` is unchanged). Repeat at most `kInspirationExcludeRetries` (3)
times; if still excluded or empty, `InspirationResult.none`. This guards
only **exact** descriptor-set duplicates for the trained family;
near-duplicates (`{strong, swift}` vs `{strong, fast}`) are allowed to
coexist (§14 / §16).

**Step 9 — source attribution (post-draw, no RNG).** For each drawn
descriptor `d`, let `A(d)` be its positive axes (`{axis : d.axes[axis] >
0}`). For each eligible inspirer `i`, its **support** for `d` is

```
support_i(d) = Σ_{axis ∈ A(d)}  w_i * max(0, axisProfile_i[axis])
```

— exactly the share of `E`'s mass on `d`'s axes that came from `i`, using
the `w_i` from step 1. The inspirer with the greatest `support_i(d)` is
`d`'s attributed source; on an exact tie, the inspirer earliest in the
resolver's `eligible` order (lowest index — the order the caller supplied
them, which for the hook is `ownedTechniqueVariants` order, stable within
a run) wins. `inspirerInstanceIds` is the **union** of the attributed
sources across all drawn descriptors, in ascending `eligible`-index
order, deduplicated.

Because every drawn `d` has `weight(d) > 0` (step 7), at least one `E`
axis it touches is positive, so at least one inspirer has
`support_i(d) > 0` — attribution always yields ≥ 1 id, and
`inspirerInstanceIds` is a **subset** of the eligible inspirers that is
often smaller (an eligible inspirer whose positive axes never overlap any
drawn descriptor is correctly **omitted**).

**Result:** `InspirationResult(discovered: true, familyId:
trainedFamilyId, descriptorIds: {the drawn ids}, inspirerInstanceIds:
[attributed source ids, ascending eligible-index order])`.

Every step is pure arithmetic over `num` plus a single `rng` draw. Same
`rng` state + same inputs → identical `discovered`, `descriptorIds`,
**and** `inspirerInstanceIds` — a two-runs-equal test locks all three.

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

Magnitudes are tuned against `game_run` balance sweeps; each is a named
constant, never inline in the resolver. The **shapes** they lock,
however, are not up for renegotiation during implementation:
`kInspirationBaseChance + kInspirationConcentrationGain == 0.60` is the
`c == 1` probability ceiling by design; `sqrt(usage)` damping (§6.2
step 1) stays sub-linear; `kMinMasteryToInspire`/`kMinUsageToInspire`
are the *only* eligibility gate (no `canInspire` state).

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
///   - publishes [TechniqueVariantInspired] exactly once, carrying the
///     result's `descriptorIds` and `inspirerInstanceIds` **verbatim**
///     (the latter is already narrowed to the actually-contributing
///     sources by §6.2 step 9 — the hook does no further filtering).
/// Exactly one call → one resolver roll → **at most one** minted variant
/// and **at most one** event. No cooldown, no discovery-lock component,
/// no mutable state of any kind; the single roll is the entire cap (§8).
/// Returns the [InspirationResult] snapshot; the caller owns telemetry / UI.
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
  context))`. Pass the whole set in `ownedTechniqueVariants` order (stable
  within a run — it seeds the step 9 tie-break); the resolver filters
  (§6.2 step 0). A **newly minted** variant has `masteryLevel == 0` and
  `usage == 0`, so it fails the eligibility filter and **cannot inspire**
  until it independently crosses `kMinMasteryToInspire` /
  `kMinUsageToInspire` — there is no `canInspire` flag and none is to be
  added; the "newborn can't chain" behaviour falls out of the eligibility
  numbers alone.
- **Descriptor pool:** `context.content.allOfType('technique_descriptor')`
  parsed via `techniqueDescriptorFromContent`. Content has already passed
  the descriptor-family validation (§14.0), so every `family:` tag in the
  pool names a real base family; the resolver applies the compatibility
  filter (§6.2 step 5) and then the axis weighting without re-checking
  validity.
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
  client hangs it later. It is a **new** `TechniqueVariant` entity — never
  an in-place edit of an inspiring one.
- **Inspirer immutability (hard invariant).** For every inspirer the
  resolver read, all four of these are byte-identical before and after
  the hook: its `descriptorIds`, its `axisProfile`, its per-instance
  mastery, its per-instance usage. No descriptor edit, no mastery reset,
  no usage reset, no replacement, no Tome change. The `Inspirer` value
  objects the resolver builds are read-only snapshots; the resolver never
  holds an `EntityId` for anything but reporting (§15 #5). A test asserts
  all four on a real discovery.
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
    required this.instanceId,
    required this.familyId,
    required this.descriptorIds,
    required this.inspirerInstanceIds,
  });
  final EntityId owner;               // owner of the newly minted variant
  final EntityId instanceId;          // the newly minted variant entity
  final String familyId;              // the trained family (== the new variant's base family)
  final Set<String> descriptorIds;    // the descriptors selected for the new variant
  final List<EntityId> inspirerInstanceIds; // the variants whose attributes actually
                                            // caused the generated descriptor selection
                                            // (§6.2 step 9) — NOT every eligible variant
}
```

**Payload is locked to exactly these five fields.** `inspirerInstanceIds`
is the resolver's `InspirationResult.inspirerInstanceIds` verbatim: the
eligible variants that actually contributed the winning positive-axis
support to a drawn descriptor, ascending `eligible`-index order,
deduplicated. It is a subset of the eligible inspirers — an eligible
variant that did **not** shape any drawn descriptor is absent, so a
client can say *"Heavy Jab + Swift Jab inspired this"* and be **true**,
never crediting a Guard that sat in the eligible set but contributed
nothing.

Not exposed: the RNG state, the discovery probability `p`, the emphasis
profile `E`, per-inspirer weights, or any intermediate score. If a future
client needs a "why" breakdown, that is a separate additive event — this
one stays minimal.

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
                                                             │        c = max(w_i) / Σ(w_i)   → p = base + gain·c → one roll
                                                             │        compatibility filter → k (source count + blend strength, 1..3, pre-draw)
                                                             │        weighted draw → exact-duplicate exclusion (bounded retry)
                                                             │        attribution: per-descriptor argmax support_i → inspirerInstanceIds (no roll)
                                                             ├─ mintTechniqueVariant(owner, familyId, descriptorIds,
                                                             │     styleId, styleCentre)          ← SP0a  (owned, loose; inspirers untouched)
                                                             └─ publish TechniqueVariantInspired(owner, instanceId, familyId,
                                                                   descriptorIds, inspirerInstanceIds)
```

---

## 12. Edge cases

| Case | Behaviour |
|------|-----------|
| Zero eligible inspirers | `InspirationResult.none`, no event, no mint, **no `rng` draw** (return precedes step 4). |
| Exactly one eligible inspirer | Focused inspiration — discovery is possible; concentration `c == 1.0` by construction (§6.2 step 3); no special-case branch. |
| Newly minted variant (`mastery 0`, `usage 0`) as a candidate inspirer | Fails the eligibility filter; cannot inspire until it independently reaches `kMinMasteryToInspire` / `kMinUsageToInspire`. No `canInspire` state exists or is added. |
| Inspirer with `masteryLevel == 0` but high `usage` | `w_i == 0` (mastery is a factor); it also fails the eligibility gate. Contributes nothing. |
| Every eligible inspirer all-neutral / all-negative (`Σ E == 0`) | `InspirationResult.none`. |
| `Σ w_i == 0` (every eligible inspirer has `usage == 0`) | `InspirationResult.none`. (Also unreachable via eligibility: `kMinUsageToInspire == 3 > 0`.) |
| Compatible descriptor pool empty (all pooled descriptors restricted away from the trained family) | `InspirationResult.none`. |
| A descriptor carries `family:<id>` where `<id>` is **not** a real base family | **Content error** — fails descriptor-family validation (§14.0) at content-load time; never reaches the resolver, so there is no "resolver-time incompatible" case for it. |
| Weighted draw runs out of positive-weight candidates before `k` | Stop early; a result with ≥ 1 descriptor still `discovered: true`; 0 → `InspirationResult.none`. |
| Drawn set set-equal to an `exclude` entry | Re-roll step 7 (`k` unchanged), at most `kInspirationExcludeRetries` times; still excluded/empty → `InspirationResult.none`. Exact sets only — near-duplicates (`{strong,swift}` vs `{strong,fast}`) coexist. |
| Eligible inspirer that shaped **no** drawn descriptor | Absent from `inspirerInstanceIds` — attribution (§6.2 step 9) reports only actual contributors, not the whole eligible set. |
| Two eligible inspirers tie exactly on `support_i(d)` for a drawn descriptor | The one earliest in the resolver's `eligible` order (lowest index) is attributed; deterministic, no `rng`. |
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
  `test/plugins/game/` — including the descriptor family-reference
  validation check (§14.0) beside the existing descriptor-content tests.

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

### 14.0 Descriptor family-reference validation (content)

A new content-validation check, using the **existing** Technique family
vocabulary — not a new compatibility framework:

> Every `family:<id>` tag on any `technique_descriptor` content
> definition must have `<id> ∈ TechniqueIds.bases`.

- All shipped `techniqueDescriptorContentDefinitions` pass (none carries a
  `family:` tag today — the check is vacuously green now and guards future
  content).
- A fixture descriptor tagged `family:not_a_family` **fails** the check.
- A fixture descriptor tagged `family:basic_kick` passes.
- Lives beside the existing descriptor-content assertions (e.g.
  `content_expansion_audit_test.dart` / a `technique_descriptor_content_test.dart`).
- The resolver's `descriptorCompatibleWithFamily` does **not** re-validate
  — it assumes this check has run, so an invalid `family:` reference is a
  content error, never a resolver-time "incompatible" result (§6.2 step 5,
  §12).

### 14.1 `TechniqueInspirationResolver` (pure)

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
- **Exactly one eligible inspirer → `c == 1.0` exactly** (not "near") and
  `p == kInspirationBaseChance + kInspirationConcentrationGain` (`0.60`
  with the shipped constants) — the single-source case rides the shared
  formula, no special branch.
- Weights `{6, 3, 1}` → `c == 0.6`; `{1, 1, 1}` → `c ≈ 0.333`.
- `p` is monotonic in `c` and stays within `[0, 1]` at the extremes;
  `c == 0 → p == 0.05`.

*Compatibility*
- A descriptor tagged `family:basic_kick` is never drawn for a
  `basic_punch` training.
- A descriptor tagged `family:basic_punch` **can** be drawn for a
  `basic_punch` training.
- A descriptor with no `family:` tag is eligible for any family.
- All pooled descriptors restricted away from the trained family →
  `InspirationResult.none`.
- (Invalid `family:` references are covered by §14.0, not here — the
  resolver never sees one.)

*Descriptor count* (chosen before the draw)
- Single source (`eligible.length == 1`), ordinary → 1.
- Single source, even with `mastery ≥ kInspirationStrongMasteryBar` and
  `w ≥ kInspirationStrongWeightBar` → still 1 (strong needs
  `eligible.length >= 2`).
- Two+ sources, `meanMastery < kInspirationStrongMasteryBar` **or**
  `Σ w_i < kInspirationStrongWeightBar` → 2.
- Two+ sources, `meanMastery >= kInspirationStrongMasteryBar` **and**
  `Σ w_i >= kInspirationStrongWeightBar` → 3.
- Never exceeds 3; never below 1; final `k == min(k, compatiblePoolSize)`.

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
  `RngService(seed)` → identical `discovered`, `descriptorIds`, **and**
  `inspirerInstanceIds`, twice.

*Source attribution (`inspirerInstanceIds`)*
- Eligible set `{power-inspirer, speed-inspirer, endurance-inspirer}`,
  drawn descriptors touch only `power` + `speed` → `inspirerInstanceIds`
  is exactly `{power-inspirer, speed-inspirer}`; the endurance one is
  **absent**.
- Single drawn `power` descriptor, two eligible `power` inspirers with
  different `w_i * axisProfile[power]` → the higher-support one is
  attributed; the lower is absent.
- Exact `support_i(d)` tie between two inspirers → the lower `eligible`
  index is attributed; swapping the caller's inspirer order swaps which
  id appears (locks the documented tie-break).
- `inspirerInstanceIds` is always non-empty on `discovered: true` and is
  ordered ascending by `eligible` index.
- Attribution adds **no** `rng` draw: run the resolver twice from
  `RngService(seed)`; the post-roll `rng` state is identical whether or
  not attribution ran (i.e. the draw count is unchanged from the
  pre-refinement resolver).

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
- **Attribution excludes a non-contributor:** the owner also holds an
  eligible endurance-heavy variant that shapes none of the drawn
  descriptors → it is **absent** from `event.inspirerInstanceIds`, which
  contains only the heavy + swift Punch ids.
- **Single-source:** one strong Heavy Jab (mastery 3, usage 30) alone,
  train that family, fixed seed → one new variant; `inspirerInstanceIds`
  is exactly `[that Heavy Jab]`.
- **Newborn cannot chain:** immediately after a discovery, call the hook
  again with the same (still `mastery 0` / `usage 0`) new variant among
  the candidates → it is not an eligible inspirer; it never appears in a
  subsequent `inspirerInstanceIds`; no second discovery from it.
- **One per session:** a single hook call mints at most one variant and
  publishes at most one event, on any inspirer state; no discovery-lock
  component is written to the fighter.
- **Lifecycle:** the minted variant has `mastery 0`, `usage 0`, the right
  `owner`, no Tome placement; every inspirer's `descriptorIds`,
  `axisProfile`, per-instance mastery, and per-instance usage are
  **unchanged** (assert all four).
- **Event payload:** `owner` (of the new variant), `instanceId` (the new
  one), `familyId` (trained family), `descriptorIds` (the drawn set),
  `inspirerInstanceIds` (the actual contributing inspirers, a subset of
  the eligible set) — all correct; no other fields.
- **No discovery → no event:** below-threshold inspirers, a failed roll,
  and an all-excluded pool each publish nothing and mint nothing.
- **Coexistence:** `resolveTechniqueEvolutionAfterTraining` behaves
  exactly as before in the same flow.
- **Tradeoff preservation:** a discovered variant seeded by a `bear`-like
  descriptor (`{power: 6, speed: -1}`) still has the negative `speed` axis
  in its `axisProfile` — SP0b converts nothing to combat numbers (that is
  SP1).

**Whole-suite:** `dart test test/` stays green; `dart analyze` clean;
the `architecture_dependency_test` still passes (no new cross-plugin
import — `technique/` imports neither `combat` nor `martial_arts`).

---

## 15. Open questions

### Still open (playtest only — not implementation blockers)

1. **Tuning-constant magnitudes** (`kInspirationBaseChance`,
   `kInspirationConcentrationGain`, `kInspirationStrongMasteryBar`,
   `kInspirationStrongWeightBar`, `kMinMasteryToInspire`,
   `kMinUsageToInspire`, `kInspirationExcludeRetries`) — the *values* are
   tuned against `game_run` balance sweeps. The *shapes* they lock (§6.3)
   are fixed.
2. **`martial_arts` style-centre magnitudes** — every shipped style × 6
   base families gets an entry (possibly `{}`); the specific nudges are
   playtest-tuned.

### Closed by this refinement pass

3. **`family:<base>` tag suffix** — CLOSED: the **full base id**
   (`family:basic_kick`), so it matches `techniqueFamilyOf`'s return with
   no extra mapping. `techniqueFamilyTagPrefix = 'family:'` is the one
   named constant. An `<id>` outside `TechniqueIds.bases` is a content
   error (§14.0), not a resolver concern.
4. **`techniqueFamilyOf` / `requireTechniqueVariant` visibility** —
   CLOSED: promote SP0a's `_familyOf` / `_requireVariant` from private to
   public; behaviour unchanged, visibility only.
5. **`Inspirer.instanceId` in the resolver** — CLOSED: it is used in
   exactly two places, both deterministic and RNG-free — (a) building
   `inspirerInstanceIds` from the §6.2-step-9 attribution, (b) the
   attribution tie-break (lowest `eligible` index). It never enters the
   weighting, emphasis, concentration, roll, or draw arithmetic.
6. **`inspirerInstanceIds` semantics** — CLOSED: the **actual
   contributing** inspirers (per-descriptor argmax `support_i(d)`, unioned;
   §6.2 step 9), a subset of the eligible set — never "every eligible
   variant".
