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
| **Trigger** | After a training session — a parallel hook to today's `resolveTechniqueEvolutionAfterTraining`. |
| **Usage signal** | A variant instance *performed a combat action* (hung **and** it struck / guarded in a resolved fight). |
| **Seed blend** | Weighted draw: each candidate descriptor's weight tracks how much its axes overlap the axes your high-mastery, high-usage variants emphasize. RNG. |
| **Family** | The **trained** technique's family (train a kick → the inspired variant is a kick, seeded by your heavy/fast usage from elsewhere — cross-pollination). |
| **Descriptor count** | 1–3, scaling with the inspiring variants' mastery. Hard cap 3. |
| **Discovery odds** | Shaped by **concentration** of usage — a focused pattern → high chance, scattered → low. |
| **Result placement** | Added to the roster (owned, loose); the player hangs it. Not a replacement. |

---

## 2. Scope

### 2.1 In scope

- `CombatAction.sourceRef: BuildComponentRef?` (optional), set by
  `TechniqueActionInterpreter`. The SP1 active-tier seam, brought forward.
- `TechniqueUsageComponent` — per-variant combat-action counts, on the
  fighter entity; an `ActionCompleted` subscription in `TechniquePlugin`
  that maintains it; a `techniqueVariantUsage` accessor.
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
| *Dependencies point downward.* | `technique/` still never imports `combat` or `martial_arts`. The `ActionCompleted` subscription uses only Combat's public event vocabulary via the shared `EventBus` (the pattern `MartialArtsPlugin` already uses). `styleCentre` is *passed into* `resolveTechniqueInspirationAfterTraining` by a caller that has it — the technique plugin never looks it up. |
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

### 5.2 Subscription

`TechniquePlugin.initialize` subscribes to `ActionCompleted`:

```
on ActionCompleted(actor, action):
  final ref = action.sourceRef;
  if (ref == null || ref.referenceType != techniqueReferenceType) return;
  final instance = ref.instanceEntityId;
  if (instance == null) return;                 // pre-SP0a placement — ignore
  final existing = components.get<TechniqueUsageComponent>(actor);
  final next = { ...?existing?.byInstance };
  next[instance] = (next[instance] ?? 0) + 1;
  components.add(actor, TechniqueUsageComponent(next));
```

`ActionCompleted` is chosen over `ActionStarted` so a condition-failed
action (evaluated but not performed) does not count — `CombatSystem`
publishes `ActionCompleted` only after the effects apply.

The `EventSubscription` is captured on a plugin field and cancelled in
`unregister` (mirrors `MartialArtsPlugin`'s teardown), so re-`initialize`
after `unregister` does not double-count.

### 5.3 Accessor + cleanup

```dart
int techniqueVariantUsage(EntityId instanceId, PluginContext context);
```

Owner derived from the instance's `TechniqueVariant.owner` (rule 5); `0`
if no `TechniqueUsageComponent` or no entry. Throws
`TechniqueVariantNotFoundException` for an unknown instance id (via the
shared `_requireVariant`, made available to this file).

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
    required this.axisProfile,   // the variant's stored TechniqueVariant.axisProfile
    required this.masteryLevel,  // per-instance mastery level, 0..3
    required this.usage,         // combat actions performed this run, >= 0
  });
  final Map<String, num> axisProfile;
  final int masteryLevel;
  final int usage;
}

class InspirationResult {
  const InspirationResult({
    required this.discovered,
    required this.familyId,          // == trainedFamilyId; '' when !discovered
    required this.descriptorIds,     // 1..3 ids when discovered, empty otherwise
  });
  final bool discovered;
  final String familyId;
  final Set<String> descriptorIds;
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
trained family (the duplicate guard, §7). The resolver's draw retries
past an excluded outcome a bounded number of times, then gives up
(`discovered: false`).

### 6.2 Algorithm

Let `n = descriptorPool`'s distinct axis count (the axes any pooled
descriptor touches).

**Step 0 — eligibility filter.** `eligible = inspirers where masteryLevel
>= kMinMasteryToInspire && usage >= kMinUsageToInspire`. If
`eligible.length < 2` → `InspirationResult(discovered: false, familyId:
'', descriptorIds: {})`. Nothing to blend.

**Step 1 — emphasis profile `E`.** For each eligible inspirer,
`w_i = masteryLevel_i * usage_i`. For each axis,
`E[axis] = Σ_i w_i * max(0, axisProfile_i[axis])`. Negative axis values
(a descriptor's trade-off) contribute nothing to "what you emphasize".
If `Σ E == 0` (every eligible inspirer is all-neutral / all-negative) →
`discovered: false`. Otherwise normalize: `E[axis] /= Σ E`.

**Step 2 — concentration `c`.** `h = Σ_axis E[axis]^2` (Herfindahl over
the axes present in `E`; let `m = ` that count). Rescale
`c = (h - 1/m) / (1 - 1/m)` for `m > 1`, else `c = 1`. `c ∈ [0, 1]`:
1 when all emphasis is on one axis, 0 when spread evenly.

**Step 3 — discovery roll.** `p = clamp(kBaseChance + kConcentrationGain
* c, 0, 1)`. Draw `rng.nextDouble()`. If `>= p` → `discovered: false`.

**Step 4 — descriptor count `k`.**
`meanMastery = mean(eligible.masteryLevel)` (a double).
`k = clamp(meanMastery.round(), 1, 3)`, then `k = min(k, number of
descriptors in the pool)`.

**Step 5 — weighted draw, `k` times, without replacement.** For each
remaining candidate descriptor `d`,
`weight(d) = Σ_axis E[axis] * max(0, d.axes[axis])`. A `d` with no
positive overlap has weight 0. Pick: `total = Σ weight(remaining)`;
`t = rng.nextDouble() * total`; walk the remaining candidates in a
stable order accumulating `weight`, take the first whose running sum
`> t` — the same normalized-cumulative pick `RewardResolver` uses over
`rng.nextDouble()`. Remove the picked `d` and repeat. If every remaining
candidate has weight 0, stop early — a result with ≥ 1 descriptor still
stands; 0 descriptors → `discovered: false`.

**Step 6 — exclusion retry.** If the drawn set is set-equal to any entry
in `exclude`, discard it and redo steps 4–5 with the *already-advanced*
`rng`. Repeat at most `kInspirationExcludeRetries` (3) times; if still
excluded or empty, `discovered: false`.

**Result:** `InspirationResult(discovered: true, familyId:
trainedFamilyId, descriptorIds: {the drawn ids})`.

All steps are pure arithmetic over `num` plus `rng`. Given the same
`rng` state and inputs, the result is identical — verified by a
two-runs-equal test.

### 6.3 Tuning constants (`technique_vocabulary.dart`)

```dart
const kInspirationBaseChance = 0.05;       // p at zero concentration
const kInspirationConcentrationGain = 0.55; // p rises to ~0.60 at c == 1
const kMinMasteryToInspire = 1;            // a variant must be at least level 1
const kMinUsageToInspire = 3;             // ...and have acted 3+ times this run
const kInspirationExcludeRetries = 3;     // draw re-rolls past a duplicate blend
```

Placeholder values — tuned in playtesting, not load-bearing for the
design. Grouped and named so they are never magic numbers in the
resolver body.

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
/// [TechniqueInspirationResolver], and on a hit:
///   - runs the duplicate guard (below),
///   - `mintTechniqueVariant(owner, familyId, descriptorIds, context,
///      styleId: <char style>, styleCentre: styleCentre)`,
///   - publishes [TechniqueVariantInspired] exactly once.
/// Returns the [InspirationResult] snapshot; the caller owns any
/// telemetry / UI.
InspirationResult resolveTechniqueInspirationAfterTraining(
  EntityId owner,
  TechniqueDefinition trainedTechnique,
  Map<String, num> styleCentre,
  PluginContext context, {
  String? styleId,
});
```

- **Trained family:** the SP0a `_familyOf(trainedTechnique.id, context)`
  helper (promoted from private to a reusable `techniqueFamilyOf`).
- **Inspirers:** `for (final e in ownedTechniqueVariants(owner, context))`
  build `Inspirer(v.axisProfile, techniqueVariantMasteryLevel(e, context),
  techniqueVariantUsage(e, context))`. Pass the whole set; the resolver
  filters (§6.2 step 0).
- **Descriptor pool:** `context.content.allOfType('technique_descriptor')`
  parsed via `techniqueDescriptorFromContent`. Irrelevant descriptors get
  weight 0 and are effectively excluded by the draw.
- **Duplicate guard:** build `exclude` = `{ v.descriptorIds : v in
  owned variants where v.baseFamilyId == trainedFamilyId }` and pass it to
  `resolve`. The resolver's step 6 handles the retry / give-up; the caller
  just supplies the set. A `discovered: false` result publishes nothing
  and mints nothing.
- **Mint:** the discovered variant gets `styleId` set, so
  `hangTechniqueVariant` treats it as **derived** (no learning gate) —
  it has descriptors and a style.
- **Callers:** the engine's reference training flow
  (`game_run` / `training_stage`) and, in the client, `TrainingAdapter`,
  each add one call immediately after their existing
  `resolveTechniqueEvolutionAfterTraining` call. `styleId` / `styleCentre`
  come from the character's chosen style.

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
    required this.instanceId,     // the freshly minted variant
    required this.familyId,       // its base family (== the trained family)
    required this.inspirerIds,    // the eligible variants whose mastery x usage seeded it
  });
  final EntityId owner;
  final EntityId instanceId;
  final String familyId;
  final List<EntityId> inspirerIds;
}
```

---

## 9. `martial_arts` — style-centre table

```dart
/// The per-style, per-base-family axis nudge applied to a minted variant.
/// Content-shaped (a const table today; a ContentRegistry batch later if
/// it grows). `{}` for an unknown style/family pair.
Map<String, num> styleCentre(String styleId, String familyId);
```

Backing data: one small table, e.g.

| style | family | centre |
|---|---|---|
| `boxing` | `basic_punch` | `{power: 3}` |
| `wing_chun` | `basic_punch` | `{speed: 2, precision: 1}` |
| `tai_chi` | `basic_guard` | `{endurance: 3}` |
| … | … | … |

Every `(shipped style) × (6 base families)` pair gets an entry (possibly
`{}`). The caller of `resolveTechniqueInspirationAfterTraining` reads it
and passes the result in. SP0a's starting-variant seeding may use the
same function.

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
   per-instance mastery (SP0a) ─────────────────────────┘    ├─ TechniqueInspirationResolver.resolve(..., rng)  → InspirationResult
                                                             │        emphasis E → concentration c → p → roll
                                                             │        k = round(meanMastery) → weighted draw of k descriptors
                                                             ├─ duplicate guard
                                                             ├─ mintTechniqueVariant(owner, familyId, descriptorIds,
                                                             │     styleId, styleCentre)          ← SP0a
                                                             └─ publish TechniqueVariantInspired(owner, instanceId, familyId, inspirerIds)
```

---

## 12. Edge cases

| Case | Behaviour |
|------|-----------|
| Fewer than 2 eligible inspirers | `discovered: false`, no event, no mint. |
| Every eligible inspirer all-neutral / all-negative (`Σ E == 0`) | `discovered: false`. |
| Weighted draw runs out of positive-weight candidates before `k` | Stop early; a result with ≥ 1 descriptor still `discovered: true`; 0 → `discovered: false`. |
| Duplicate blend (same family + descriptor set the owner already has) | Re-roll steps 4–5 once; still duplicate/empty → `discovered: false`. |
| Trained technique is a base family, not an evolved id | `techniqueFamilyOf` returns it unchanged; the inspired variant is of that family. Fine. |
| A technique action with `sourceRef.instanceEntityId == null` (pre-SP0a placement) | Usage handler ignores it — no tally, no crash. |
| Bare-handed fallback strike (`sourceRef == null`) | Ignored by the usage handler. |
| `removeTechniqueVariant` on an instance with a usage entry | The entry is dropped alongside the mastery-progress trim. |
| Same seed, same owner state, same trained technique | Identical `InspirationResult` — no wall-clock, no hidden state, one `RngService`. |
| Combat outcome with `sourceRef` populated vs not | Identical — `sourceRef` never enters damage / modifier / ordering. |

---

## 13. Files

**New**

- `lib/src/plugins/technique/technique_usage.dart` — `TechniqueUsageComponent`,
  the `ActionCompleted` handler, `techniqueVariantUsage`.
- `lib/src/plugins/technique/technique_inspiration.dart` — `Inspirer`,
  `InspirationResult`, `TechniqueInspirationResolver`,
  `resolveTechniqueInspirationAfterTraining`.
- tests under `test/plugins/technique/` and
  `test/plugins/build_interpretation/`.

**Changed**

- `lib/src/plugins/combat/combat_action.dart` — `sourceRef` getter.
- `lib/src/plugins/combat/attack_action.dart` — `sourceRef` param + field.
- `lib/src/plugins/build_interpretation/self_effect_action.dart` —
  `sourceRef` param + field.
- `lib/src/plugins/build_interpretation/technique_action_interpreter.dart`
  — set `sourceRef: ref` on every built action.
- `lib/src/plugins/technique/technique_events.dart` —
  `TechniqueVariantInspired`.
- `lib/src/plugins/technique/technique_vocabulary.dart` — the four
  tuning constants; promote `_familyOf` → public `techniqueFamilyOf`.
- `lib/src/plugins/technique/technique_variant_lifecycle.dart` —
  `removeTechniqueVariant` drops the usage entry; expose `_requireVariant`
  / `techniqueFamilyOf` to the new files.
- `lib/src/plugins/technique/technique_plugin.dart` — subscribe /
  teardown the usage handler.
- `lib/technique_plugin.dart` — barrel exports for the two new files.
- `lib/src/plugins/martial_arts/…` — `styleCentre(styleId, familyId)` +
  its table; barrel export in `lib/martial_arts_plugin.dart`.
- `CHANGELOG.md`, `ARCHITECTURE.md`.

---

## 14. Testing

**`TechniqueInspirationResolver`** (pure):

- < 2 eligible inspirers → `discovered: false` (both "too few total" and
  "filtered below 2 by mastery/usage").
- Emphasis: a `bear`-heavy inspirer (`{power: 6, speed: -1}`) at
  mastery 2 / usage 5 and a `swift` inspirer (`{speed: 5}`) at
  mastery 2 / usage 5 → `E` has `power` and `speed`, no `speed` penalty
  from `bear`'s negative (clamped).
- Concentration → probability: two inspirers emphasizing the *same*
  axis produce a higher `p` than two emphasizing different axes; assert
  `p` at a fixed emphasis profile against the formula.
- `k` vs mean mastery: mean 1 → `k == 1`; mean ~2 → `k == 2`; mean 3 →
  `k == 3`; capped at 3 and at pool size.
- Weighted draw favours aligned descriptors: with `E` all on `power`,
  a fixed seed draws a `power` descriptor, never a pure-`endurance` one.
- Determinism: identical inputs + `RngService(seed)` → identical result,
  twice.
- Draw exhaustion: pool of one aligned descriptor, `k == 3` → result has
  1 descriptor, `discovered: true`.
- Exclusion: pass the only reachable blend in `exclude` → after
  `kInspirationExcludeRetries` re-rolls the resolver returns
  `discovered: false`; pass a non-matching set → unaffected.

**`TechniqueUsageComponent` + subscription:**

- `ActionCompleted` whose `action.sourceRef` is a technique instance →
  `techniqueVariantUsage` for that instance goes up by 1 on the actor.
- `sourceRef == null` or `referenceType != 'technique'` or
  `instanceEntityId == null` → no change.
- Two different instances tracked independently.
- `unregister` then `initialize` on the same context → no double count on
  the next action.
- `removeTechniqueVariant` drops the usage entry (assert `usage == 0`
  after, and no dangling map key).

**`TechniqueActionInterpreter`:**

- Each built `AttackAction` / `SelfEffectAction` carries `sourceRef` equal
  to the `BuildComponentRef` it came from (right `contentId` +
  `instanceEntityId`).
- The bare-handed fallback carries `sourceRef == null`.
- A combat run's damage log is byte-identical with the field populated
  vs a build with no instance ids (regression guard on §4.3).

**`resolveTechniqueInspirationAfterTraining` (integration):**

- Mint two variants of different families, give them mastery + usage
  above the thresholds, train a *third* family, fixed seed → a new
  variant of the trained family with a specific descriptor set; the event
  fires once with the two inspirer ids.
- Below-threshold inspirers → no discovery, no event.
- Duplicate guard: force a state where the only reachable blend equals an
  existing variant → `discovered: false`.
- The discovered variant has `styleId` set and hangs without a learning
  gate.
- `resolveTechniqueEvolutionAfterTraining` still behaves exactly as
  before when called in the same flow (coexistence).

**Whole-suite:** `dart test test/` stays green; `dart analyze` clean;
the `architecture_dependency_test` still passes (no new cross-plugin
import — `technique/` imports neither `combat` nor `martial_arts`).

---

## 15. Open questions (settle during planning / playtest)

1. **Tuning constants** (`kInspirationBaseChance` etc.) — placeholders;
   tuned against `game_run` balance sweeps.
2. **`styleId` on the resolver call** — passed by the caller (it has the
   character). Confirm the signature carries `styleId` (for the mint) as
   well as `styleCentre`.
3. **`martial_arts` table completeness** — every shipped style × 6 base
   families. Some pairs may legitimately be `{}`.
4. **`techniqueFamilyOf` visibility** — promoting SP0a's `_familyOf`
   from private. Confirm no behaviour change, just visibility.
5. **`meanMastery.round()` tie-break** — Dart's `round()` is
   round-half-away-from-zero; `2.5 → 3`. Acceptable; documented.
