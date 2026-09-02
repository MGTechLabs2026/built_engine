# Technique Instancing & Variant Attributes — SP0a design

**Date:** 2026-09-02
**Status:** draft — awaiting review
**Repo:** `build_engine` (`Tome:RougelikeGame`)
**Blocks:** SP0b (inspiration path), SP1 (tiered effects), SP4 (client)

---

## 1. Why this exists

### 1.1 The chain

The original ask — a reward-granted technique should carry a lasting
personal character, not a throwaway boon — grew into a broader goal: a
martial-arts build should feel *personal*. Your jab is not "the jab
definition"; it is *your* jab — heavy, or fast, or continuous — shaped by
your style and by how you have fought.

`build_engine` today models a technique as a bare `contentId` on the Tome
(`BuildComponentRef(referenceType: 'technique', contentId: 'basic_punch')`
— no `instanceEntityId`). Per-owner state lives in three generic
subject-keyed axes (`technique:<id>` for Discovery and Mastery,
`technique:<id>:knowledge` for Learning). Variety is hand-authored: 6 base
families (`basic_punch/slash/guard/palm/finger/kick`) each evolve through
named definitions (`heavy_punch`, `lightning_jab`, `mountain_breaker`,
`thunder_flash`, `iron_palm`, …).

SP0a replaces the hand-authored evolved forms with **instances** carrying
**descriptor-driven attributes**, so the same base can be held in many
personal variants, and (SP0b) new variants can be generated from play.

### 1.2 Where SP0a sits

| SP | Scope | Depends on |
|----|-------|------------|
| **SP0a** (this doc) | Technique instances; the descriptor → axis attribute model; per-instance mastery; style-seeded starting variants; `instanceEntityId` on technique Tome refs. **Data + lifecycle only** — no generation, no combat numbers. | — |
| SP0b | The inspiration / discovery path: usage + mastery patterns → a new derived instance whose axis profile blends the style centre with the high-mastery instances that inspired it. | SP0a |
| SP1 | Tiered `EffectProfile` resolution. Revised: techniques are instanced, so items and techniques are symmetric; a variant's `EffectProfile` derives from its axis profile + per-instance mastery. | SP0a |
| SP2 / SP3 / SP4 | Hooks/auras, potions, client. | SP1 |

Build order: **SP0a → SP0b → SP1 → SP2/3/4.**

### 1.3 Five design rules

These keep SP0a a clean, single-direction layer that SP0b and SP1 can
build on without reaching back in:

1. **`TechniqueDescriptor` carries a map `axes: {axis → magnitude}`** —
   one descriptor can touch several axes (`bear`: `power +6, speed −1`).
2. **`TechniqueVariantResolver` is purely `descriptors → axisProfile`** —
   no style, no base, no `styleCentre` parameter.
3. **Style seed / centre composition lives outside the resolver** — a
   separate pure `composeAxisProfile(base, contribution)`; `mint` calls it.
4. **Explicit `instanceEntityId` compatibility invariant** — post-SP0a
   every technique Tome ref written by the plugin is non-null; a null one
   is a pre-SP0a placement readers must tolerate as the bare base (§6.1).
5. **Ownership is one authoritative relationship** — `TechniqueVariant.owner`
   (like `ItemInstance.owner`); "hung" is derived from the Tome, never a
   second stored list (§6.2).

The resulting pipeline:

```
CONTENT → TechniqueDescriptor → TechniqueVariantResolver → axisProfile
        → TechniqueVariant → EntityId → BuildComponentRef → Tome
```

---

## 2. Scope

### 2.1 In scope

- A **technique instance** entity minted per variant a player holds,
  referenced from the Tome via `BuildComponentRef.instanceEntityId`.
- A plugin component `TechniqueVariant` holding the instance's `owner`,
  **descriptor set**, and composed **axis profile**.
- **Descriptors** as content data: `{id, axes: {axisKey → magnitude}, tags}`
  — one `bear` can be `{power: 6, speed: -1}` (rule 1). Many descriptors,
  few axes.
- **Axes** as an open, string-keyed set. Launch content: `power`,
  `speed`, `endurance`, `precision`.
- A pure resolver `descriptors → axisProfile` (rule 2), plus a separate
  pure `composeAxisProfile(styleCentre, descriptorProfile)` (rule 3).
- **Ownership** stamped on `TechniqueVariant.owner` as the single
  authoritative relationship (rule 5); "hung" is derived from the Tome.
- **Per-instance mastery**: mastery keyed by the instance's own subject
  id, sharing one threshold curve, via the existing `MasteryTracker`.
- **Basic vs derived**: the 6 bases stay universal and keep the LEARNING
  axis; derived variants are instances, never "learned" separately
  (mirrors today's "evolved branches are never learned separately").
- Style seeds each fighter's **starting derived variants** (an initial
  descriptor set per family).
- Lifecycle: mint a variant instance, attach it to the Tome, remove it,
  clean up its mastery subject.
- Coexistence / migration path for the current hand-authored evolved
  `TechniqueDefinition`s.
- Tests.

### 2.2 Out of scope

- **Generating** new variants from play — SP0b. SP0a can mint a variant
  from an explicit descriptor set (used to seed starting variants and by
  tests); it does not decide *when* or *with which descriptors*.
- Turning an axis profile into combat numbers — SP1. SP0a stores the axis
  profile; nothing reads it into a calculation yet.
- Any `Tome_client` change — SP4.
- Removing the current evolution system (`EvolutionResolver`, evolution
  candidates). SP0a coexists with it (see §7); a later pass may retire it.
- Serialization of a `TechniqueVariant` beyond what the existing
  component-serialization story already covers.

---

## 3. Contract fit (`claude.md`)

| Rule | Compliance |
|------|-----------|
| *Core provides verbs; plugins provide nouns.* | Every new type (`TechniqueVariant`, descriptor, axis) is in `lib/src/plugins/technique/`. Core gains nothing. "power"/"bear"/"jab" never enter core. |
| *No giant classes (Player, Sword, Potion).* | `TechniqueVariant` is a small component: `owner`, `baseFamilyId`, a descriptor id set, a `Map<String, num>` axis profile, `styleId`. No behaviour. |
| *No speculative abstraction.* | Instances, descriptors, and per-instance mastery each have an immediate use (personal variants now; SP0b/SP1 consume them next). Axes launch with exactly the 4 the content needs. |
| *Smallest stable API.* | One component type, one content shape (descriptor with an `axes` map), two pure functions (`resolve`, `composeAxisProfile`). Reuses `MasteryTracker`, `BuildComponentRef.instanceEntityId`, `ContentRegistry` unchanged. |
| *Composition over inheritance; pure functions; explicit deps.* | `TechniqueVariant` is composed onto an instance entity. `resolve` and `composeAxisProfile` are pure, like `BuildResolver`. Style composition is not folded into the resolver (rule 3). No new `PluginContext`/`RuleContext` wiring. |
| *Each plugin picks its own subject-id namespace; core never interprets it.* | Per-instance mastery keys on `technique:instance:<entityValue>` — a plugin-chosen string; `MasteryTracker` treats it like any other subject. |

**Engine footprint of SP0a: effectively zero core change.** It is a
Technique-plugin feature that leans on primitives already shipped.

---

## 4. The instance model

### 4.1 Definitions vs instances

- `TechniqueDefinition` (existing) stays the **family / base form**:
  `basic_punch`, `basic_slash`, `basic_guard`, `basic_palm`,
  `basic_finger`, `basic_kick`. It keeps `id`, `name`, `tier`, `tags`,
  `properties`, `requirements`, `trainingWeights`.
- A **technique instance** is a fresh `EntityId` carrying:
  - `BuildComponentRef`-compatible identity — its `contentId` is the base
    family id; its `instanceEntityId` is this entity.
  - a `TechniqueVariant` component (§4.2).
  - its own mastery subject (§5).

The player can hold several instances of the same base family
(`basic_punch` + a heavy variant + a fast variant), each hangable, each
mastered independently. A **basic** technique is just an instance with an
empty descriptor set and a zero axis profile.

### 4.2 `TechniqueVariant` component

```dart
/// Per-instance variant state for one technique an owner holds.
/// Pure data — no behaviour.
class TechniqueVariant {
  const TechniqueVariant({
    required this.owner,            // AUTHORITATIVE ownership (see §6.2)
    required this.baseFamilyId,     // e.g. 'basic_punch'
    required this.descriptorIds,    // e.g. {'bear', 'thunder'}
    required this.axisProfile,      // composed: {'power': 6, 'speed': -1}
    this.styleId,                   // null for a basic; set for a derived
  });

  final EntityId owner;
  final String baseFamilyId;
  final Set<String> descriptorIds;
  final Map<String, num> axisProfile;
  final String? styleId;
}
```

- `owner` — the single authoritative "this owner has this instance"
  relationship (rule 5, §6.2). Mirrors `ItemInstance.owner`.
- `axisProfile` is **stored**, not recomputed on read — the composed
  result of the pure descriptor sum plus the style centre, fixed at mint
  time, so a later content change to a descriptor does not silently
  restat existing instances. Re-resolving is an explicit operation.

### 4.3 Descriptors (content data)

**Rule 1 — a descriptor carries a *map* of axis → magnitude, not a single
axis.** One `bear` can be `power +6, speed −1` in a single entry.

```dart
/// A thematic modifier a variant can carry. Content, loaded via
/// ContentRegistry like TechniqueDefinition.properties already is.
class TechniqueDescriptor {
  const TechniqueDescriptor({
    required this.id,       // 'bear', 'thunder', 'hawkseye', ...
    required this.axes,     // {'power': 6, 'speed': -1}  — signed
    this.tags = const {},   // free thematic tags for SP0b matching
  });

  final String id;
  final Map<String, num> axes;
  final Set<String> tags;
}
```

Content shape: `{'id': 'bear', 'type': 'technique_descriptor',
'tags': [...], 'axes': {'power': 6, 'speed': -1}}`.

Launch content (illustrative, final list set during implementation):

| Axis | Descriptors (primary) |
|------|-----------------------|
| `power` | bear, elephant, strong, destruction, thunder, iron |
| `speed` | swift, fast, lightning, light, flash |
| `endurance` | immortal, wall, mountain, undead, rooted |
| `precision` | bullseye, hawkseye, one_hit, needle, focused |

Any descriptor may also carry a secondary, usually-negative axis in the
same `axes` map (`bear`: `{power: 6, speed: -1}`).

### 4.4 Axes

Open, string-keyed — `power`, `speed`, `endurance`, `precision` to start.
The plugin owns the list; adding one is a content change, no code change.
Core never sees them.

### 4.5 The resolver + style composition

**Rule 2 — `TechniqueVariantResolver` is purely `descriptors → axisProfile`.**
No style, no base, no `styleCentre` parameter.

```dart
/// Pure. Sums every descriptor's axis map. Nothing else.
class TechniqueVariantResolver {
  const TechniqueVariantResolver();

  Map<String, num> resolve(Iterable<TechniqueDescriptor> descriptors);
}
```

**Rule 3 — style seed / centre composition lives *outside* the resolver.**
A separate pure helper merges a base profile (the style centre) with the
resolver's descriptor profile:

```dart
/// base ⊕ contribution, per axis, additive. Pure.
Map<String, num> composeAxisProfile(
  Map<String, num> base,
  Map<String, num> contribution,
);
```

`mintTechniqueVariant` calls `composeAxisProfile(styleCentre,
resolver.resolve(descriptors))` and stores the result. The resolver never
sees `styleCentre`; SP0b and style-seed code supply it to `mint`.

All three functions are additive, commutative, deterministic, RNG-free.

---

## 5. Per-instance mastery

- Subject id: `techniqueInstanceSubject(EntityId) => 'technique:instance:<value>'`
  — a new vocabulary string beside the existing `techniqueSubject` /
  `techniqueKnowledgeSubject`.
- On mint, register a `MasteryDefinition(subject: <that>, thresholds:
  techniqueMasteryThresholds)` — the existing `[5, 15, 30]` curve, one
  shared curve, one `define` call per instance.
- New instance-keyed helpers `trainTechniqueVariantMastery(instanceId,
  amount, context)` / `techniqueVariantMasteryLevel(instanceId, context)`
  — the owner is read from the instance's `TechniqueVariant.owner`
  (rule 5), not passed. The existing `trainTechniqueMastery` /
  `techniqueMasteryLevel` (base-family keyed) are untouched.
- The base-family Mastery subject (`technique:<familyId>`) is retained for
  "how good is this fighter at punches in general" if any consumer wants
  it, but per-instance is the axis that matters for a variant's strength.
- On instance removal (§6), the mastery subject's **progress** is cleared
  — rebuild `MasteryComponent` without that subject's entry. The
  `MasteryDefinition` stays registered: `MasteryTracker` has no `undefine`
  (adding one would be a core change SP0a avoids), a definition with no
  progress reads level `0` and is inert, and a run uses a fresh
  `PluginContext` whose `MasteryTracker._definitions` starts empty — so
  the leak is per-run and bounded by the number of variants minted in one
  run.

No `MasteryTracker` change. This is exactly "each plugin picks its own
subject-id namespace."

---

## 6. Lifecycle

```
mintTechniqueVariant(owner, baseFamilyId, descriptorIds, context,
                     {styleId, styleCentre})  -> EntityId
     - create entity
     - axisProfile = composeAxisProfile(styleCentre,
                        TechniqueVariantResolver().resolve(descriptors))
     - attach TechniqueVariant{owner, baseFamilyId, descriptorIds,
                               axisProfile, styleId}
     - register per-instance MasteryDefinition
     - publish TechniqueVariantMinted(owner, instanceId, baseFamilyId)

hangTechniqueVariant(slot, instanceId, context)          // owner from component
     - isTechniqueLearned(baseFamily) gate for a basic;
       derived variants have no learning gate (mirrors evolved branches)
     - tome.insert(owner, slot,
         BuildComponentRef(referenceType: 'technique',
                           contentId: baseFamilyId,
                           instanceEntityId: instanceId))   // NEVER null — §6.1
     - publish TechniqueAddedToTome(owner, baseFamilyId, slot,
                                    instanceId: instanceId)

removeTechniqueVariant(instanceId, context)              // owner from component
     - tome.remove any slot whose ref.instanceEntityId == instanceId
     - clear the instance's MasteryComponent progress entry
       (MasteryDefinition stays — no undefine; §5)
     - components.remove<TechniqueVariant>(instanceId)
     - entities.destroy(instanceId)
     - publish TechniqueVariantRemoved(owner, instanceId)
```

`TechniqueAddedToTome` / `technique_events.dart` gain an optional
`instanceId` field (additive, like `BuildComponentRef.instanceEntityId`
was).

### 6.1 `instanceEntityId` compatibility invariant (rule 4)

For a `BuildComponentRef` with `referenceType == 'technique'`:

- **Post-SP0a, a technique ref written by this plugin ALWAYS carries a
  non-null `instanceEntityId`.** `mintTechniqueVariant` mints an instance
  for *every* technique, basics included; `hangTechniqueVariant` is the
  only sanctioned placement path and always sets it. Its target instance
  entity is alive and carries a `TechniqueVariant`.
- **A null `instanceEntityId` on a technique ref means a pre-SP0a
  placement** — an old save, or a call to the legacy
  `addTechniqueToTome`. Every reader (the SP1 interpreter, SP4 UI) MUST
  tolerate null: treat it as the bare base definition — empty
  `axisProfile`, no per-instance mastery.
- `addTechniqueToTome` is retained for backward compatibility and is now
  **deprecated** in favour of `hangTechniqueVariant`. A later pass may
  migrate legacy placements (`mintVariantForLegacyEvolvedId` + re-hang).
- A non-null `instanceEntityId` pointing to a destroyed or
  `TechniqueVariant`-less entity is a caller bug — `assert` in debug;
  readers fall back to the null behaviour in release.

### 6.2 Ownership is one authoritative relationship (rule 5)

There is exactly **one** source of truth for "owner *has* this
component": the instance entity.

- **Owned** — an owner owns instance `X` iff `X` carries a
  `TechniqueVariant` (or, for items, an `ItemInstance`) whose `owner`
  field is that owner. `ownedTechniqueVariants(owner, context)` =
  `components.entitiesWith<TechniqueVariant>()` filtered by `.owner`.
- **Hung / contained** — derived, never stored independently: instance
  `X` is hung iff some Tome placement's `ref.instanceEntityId == X` (and
  `X` is owned — guaranteed by 6.1). "On the roster but not hung" = an
  owned instance no placement references. There is no separate roster
  list to drift.
- Consequently `hung ⊆ owned` by construction, which is the exact
  precondition SP1's `EffectProfileResolver` documents.

---

## 7. Coexistence with the current evolution system

SP0a does **not** delete `EvolutionResolver`, `EvolutionCandidate`,
`TechniqueDefinition.evolutionCandidates`, or the hand-authored evolved
ids (`heavy_punch`, `lightning_jab`, …).

- During SP0a they simply stop being the *only* way to get a non-basic
  technique. A migration shim can mint an equivalent variant instance for
  an existing evolved id (map its thematic name to a descriptor set:
  `lightning_jab → {lightning}`, `mountain_breaker → {mountain-fist,
  strong}`) so saves / tests that reference the old ids keep working.
- SP0b replaces the *generation* mechanism (usage-driven inspiration
  instead of training-profile-weighted candidate draw). Retiring
  `EvolutionResolver` is a later, separate pass once nothing calls it.

This keeps SP0a a strictly additive change — nothing that works today
breaks.

---

## 8. Data flow

```
   CONTENT
      │
  TechniqueDescriptor{id, axes: {axis: mag, ...}, tags}
      │
      ▼
  TechniqueVariantResolver.resolve(descriptors)   ── pure, descriptors only
      │
      ▼
  descriptorProfile ──┐
                      ├─► composeAxisProfile(styleCentre, descriptorProfile)
  styleCentre ────────┘        (pure, outside the resolver — rule 3)
                      │
                      ▼
                  axisProfile
                      │
                      ▼
  entity + TechniqueVariant{owner, baseFamilyId, descriptorIds,
                            axisProfile, styleId}
                      │
                  register MasteryDefinition(technique:instance:<id>)
                      │
                  EntityId  ── the one authoritative handle (owner rides on it)
                      │
                      ▼
  BuildComponentRef{contentId: baseFamilyId, instanceEntityId: <id>}  ── never null
                      │
                      ▼
                    Tome
                      │
             (SP1) interpreter reads TechniqueVariant.axisProfile
                   -> EffectProfile -> ModifierResolver -> Combat
```

---

## 9. Edge cases

| Case | Behaviour |
|------|-----------|
| Basic technique | Instance with `descriptorIds = {}`, `axisProfile = {}` (empty style centre + empty descriptor sum), `styleId = null`. Still an instance, still hangable, still has a per-instance mastery track. `instanceEntityId` is still set (rule 4). |
| Two variants, same base + same descriptors | Two distinct instances, two `owner`-stamped components, two mastery subjects. Allowed — they may diverge in mastery. (SP0b decides whether to *offer* a duplicate; SP0a permits it.) |
| Descriptor unknown at mint | `mintTechniqueVariant` throws `UnknownTechniqueDescriptorException` (mirrors `UnknownContentFactoryException`). No silent drop. |
| Descriptor touches multiple axes | Each axis in the descriptor's `axes` map is summed onto the profile independently (rule 1). |
| Conflicting descriptors on one axis | Summed additively; net may be negative. No conflict resolution — content's responsibility. |
| Legacy technique placement (null `instanceEntityId`) | Readers treat it as the bare base definition: empty `axisProfile`, no per-instance mastery (rule 4). |
| `hangTechniqueVariant` for an instance owned by someone else | `TechniqueVariant.owner` is read as the placing owner — a caller passing a mismatched owner is impossible by construction (owner is not a parameter). |
| Instance removed while hung | `removeTechniqueVariant` removes the Tome placement first, then clears the mastery-subject progress, then removes the `TechniqueVariant` component, then `entities.destroy` — symmetric, no dangling ref. `EntityRegistry.destroy` does **not** cascade component cleanup (documented), so the component removal is explicit. |
| Content changes a descriptor's magnitude later | Existing instances keep their stored `axisProfile`. A future explicit `reresolveVariant(instanceId)` is the only way to pick up the change. Not built in SP0a. |
| Determinism | `resolve` is pure additive; mint publishes events in a fixed order; no RNG in SP0a (the roll lives in SP0b). |

---

## 10. Testing

Per `claude.md`'s per-plugin requirements.

### 10.1 `TechniqueVariantResolver` + `composeAxisProfile`

- resolver: empty descriptors → empty profile.
- resolver: one descriptor with a multi-axis `axes` map → every axis
  present (rule 1).
- resolver: descriptors sharing an axis → summed; negative magnitude
  subtracts.
- resolver: no `styleCentre` parameter exists (rule 2) — compile-checked
  by the call sites.
- `composeAxisProfile(base, contribution)`: additive per-axis union;
  either side empty is identity; determinism (two runs equal).

### 10.2 `TechniqueVariant` component

- construction, immutability, stored `axisProfile` independent of a later
  descriptor-content change, `owner` field present.

### 10.3 Lifecycle

- `mintTechniqueVariant` creates an entity, attaches `TechniqueVariant`
  with `owner` stamped, composes `axisProfile` from style centre +
  descriptor sum, registers a per-instance `MasteryDefinition`, publishes
  `TechniqueVariantMinted`.
- `hangTechniqueVariant` writes a `BuildComponentRef` with a non-null
  `instanceEntityId` (rule 4); owner is read from the component; basic
  gate enforced, derived not gated.
- `removeTechniqueVariant` clears the Tome slot, drops the mastery
  progress entry, removes the `TechniqueVariant` component, destroys the
  entity — asserted no dangling `MasteryComponent` entry, no
  `TomePlacement`, no live entity.
- `ownedTechniqueVariants(owner)` returns exactly the instances stamped
  with that owner; a hung instance and a loose (owned, unplaced) instance
  both appear; another owner's instance does not (rule 5).
- per-instance mastery: two instances of the same base, train one,
  `techniqueVariantMasteryLevel` diverges.

### 10.4 Coexistence

- the migration shim mints a variant for a legacy evolved id with the
  mapped descriptor set; its `axisProfile` matches the resolver output.
- existing technique/evolution tests stay green.

### 10.5 Engine-boundary

- `test/integration/architecture_dependency_test.dart` still passes — no
  new core import, no core file touched.
- "core runs without content plugins" / "MartialArts without Magic"
  unaffected.

---

## 11. Files

**New**

- `lib/src/plugins/technique/technique_variant.dart` — the component
  (`owner`, `baseFamilyId`, `descriptorIds`, `axisProfile`, `styleId`).
- `lib/src/plugins/technique/technique_descriptor.dart` — content type
  (`axes: Map<String, num>`) + ContentRegistry factory.
- `lib/src/plugins/technique/technique_variant_resolver.dart` — pure
  `resolve(descriptors)` + pure `composeAxisProfile(base, contribution)`.
- `lib/src/plugins/technique/technique_variant_lifecycle.dart` — mint /
  hang / remove / `ownedTechniqueVariants` / variant-mastery helpers /
  legacy shim.
- `lib/src/plugins/technique/technique_descriptor_content.dart` — launch
  descriptor set.
- barrel additions in `lib/technique_plugin.dart`.
- `test/plugins/technique/technique_variant_*_test.dart`.

**Changed**

- `lib/src/plugins/technique/technique_vocabulary.dart` —
  `techniqueInstanceSubject`, retain existing subjects.
- `lib/src/plugins/technique/technique_lifecycle.dart` — none required;
  the existing `trainTechniqueMastery` / `techniqueMasteryLevel` /
  `addTechniqueToTome` are untouched (`addTechniqueToTome` is the
  deprecated legacy path, §6.1).
- `lib/src/plugins/technique/technique_events.dart` — optional
  `instanceId` on `TechniqueAddedToTome`; new `TechniqueVariantMinted` /
  `TechniqueVariantRemoved`.
- `lib/src/plugins/technique/technique_plugin.dart` — register descriptor
  content; wire lifecycle helpers.
- `CHANGELOG.md` — `TechniqueVariant`, `TechniqueDescriptor`,
  `mint/hang/removeTechniqueVariant`, event additions.
- `ARCHITECTURE.md` — Technique section: instances + descriptor/axis
  model.

---

## 12. Open questions

1. **Naming.** `TechniqueVariant` / `TechniqueDescriptor` / "axis" /
   `axisProfile` — provisional.
2. **Is a "base family" still a `TechniqueDefinition`, or a lighter
   `TechniqueFamily` type?** Proposal: keep `TechniqueDefinition` for the
   6 bases (minimal churn); drop the hand-authored evolved definitions
   over time. Decide in planning.
3. **Angle / rhythm / count** ("straight vs hook vs diagonal", "single vs
   continuous vs triple") — **resolved by rule 1**: these are ordinary
   descriptors with multi-axis `axes` maps (`hook`: `{precision: -1,
   power: 2}`; `triple`: `{speed: 3, power: -2}`). No structural field.
4. **Style centre** — where authored, and how does it reach `mint`? A
   `MartialStyle` → per-family `Map<String,num>` table, most likely in
   the `martial_arts` plugin, passed as `mintTechniqueVariant`'s
   `styleCentre` argument by the style-seed / SP0b caller (rule 3 keeps
   it out of the resolver). Confirm the table's home in planning.
5. **How many descriptors may one instance carry?** A cap (e.g. 3) keeps
   variants legible and bounds `axisProfile`. Set in SP0b, or here?
6. **Mastery-subject cleanup on run end.** `removeTechniqueVariant` clears
   per-instance progress but cannot unregister the `MasteryDefinition`
   (no `undefine`). A run uses a fresh `PluginContext`, so `_definitions`
   resets between runs regardless; confirm no long-lived context reuses a
   `MasteryTracker` across runs.
