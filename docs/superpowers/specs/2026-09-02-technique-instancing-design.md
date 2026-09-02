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

---

## 2. Scope

### 2.1 In scope

- A **technique instance** entity minted per variant a player holds,
  referenced from the Tome via `BuildComponentRef.instanceEntityId`.
- A plugin component `TechniqueVariant` holding the instance's
  **descriptor set** and its resolved **axis profile**.
- **Descriptors** as content data: `{id, axis, magnitude}` (`bear → power
  +N`, `hawkseye → precision +N`). Many descriptors, few axes.
- **Axes** as an open, string-keyed set. Launch content: `power`,
  `speed`, `endurance`, `precision`.
- A pure resolver: descriptor set (+ a style centre) → axis profile.
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
| *No giant classes (Player, Sword, Potion).* | `TechniqueVariant` is a small component: a descriptor id list + a `Map<String, num>` axis profile. No behaviour. |
| *No speculative abstraction.* | Instances, descriptors, and per-instance mastery each have an immediate use (personal variants now; SP0b/SP1 consume them next). Axes launch with exactly the 4 the content needs. |
| *Smallest stable API.* | One component type, one content shape (descriptor), one pure resolver. Reuses `MasteryTracker`, `BuildComponentRef.instanceEntityId`, `ContentRegistry` unchanged. |
| *Composition over inheritance; pure functions; explicit deps.* | `TechniqueVariant` is composed onto an instance entity. The descriptor→axis resolver is pure, like `BuildResolver`. No new `PluginContext`/`RuleContext` wiring. |
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
/// Per-instance variant state for one technique the owner holds.
/// Pure data — no behaviour.
class TechniqueVariant {
  const TechniqueVariant({
    required this.baseFamilyId,     // e.g. 'basic_punch'
    required this.descriptorIds,    // e.g. {'bear', 'thunder'}
    required this.axisProfile,      // resolved: {'power': 6, 'speed': -1}
    this.styleId,                   // null for a basic; set for a derived
  });

  final String baseFamilyId;
  final Set<String> descriptorIds;
  final Map<String, num> axisProfile;
  final String? styleId;
}
```

`axisProfile` is **stored**, not recomputed on read — it is the resolved
result of `descriptorIds` (+ style centre) at mint time, so a later
content change to a descriptor does not silently restat every existing
instance. Re-resolving is an explicit operation.

### 4.3 Descriptors (content data)

```dart
/// A thematic modifier a variant can carry. Content, loaded via
/// ContentRegistry like TechniqueDefinition.properties already is.
class TechniqueDescriptor {
  const TechniqueDescriptor({
    required this.id,        // 'bear', 'thunder', 'hawkseye', ...
    required this.axis,      // 'power', 'speed', 'endurance', 'precision'
    required this.magnitude, // signed num
    this.tags = const {},    // free thematic tags for SP0b matching
  });
}
```

Launch content (illustrative, final list set during implementation):

| Axis | Descriptors |
|------|-------------|
| `power` | bear, elephant, strong, destruction, thunder, iron, mountain-fist |
| `speed` | swift, fast, lightning, light, flash |
| `endurance` | immortal, wall, mountain, undead, rooted |
| `precision` | bullseye, hawkseye, one-hit, needle, focused |

A descriptor may be **negative on another axis** (e.g. `bear`: power +6,
speed −1) — authored per descriptor, not derived.

### 4.4 Axes

Open, string-keyed — `power`, `speed`, `endurance`, `precision` to start.
The plugin owns the list; adding one is a content change, no code change.
Core never sees them.

### 4.5 The resolver

```dart
/// Pure. descriptor set (+ optional style centre) -> axis profile.
class TechniqueVariantResolver {
  const TechniqueVariantResolver();

  /// Sums each descriptor's (axis, magnitude) onto `styleCentre`
  /// (a per-family baseline axis profile, empty for a basic).
  Map<String, num> resolve({
    required Iterable<TechniqueDescriptor> descriptors,
    Map<String, num> styleCentre = const {},
  });
}
```

Additive, commutative, deterministic. SP0b decides *which* descriptors and
*what* style centre; SP0a just needs `resolve` and a way to call it at
mint time.

---

## 5. Per-instance mastery

- Subject id: `techniqueInstanceSubject(EntityId) => 'technique:instance:<value>'`
  — a new vocabulary string beside the existing `techniqueSubject` /
  `techniqueKnowledgeSubject`.
- On mint, register a `MasteryDefinition(subject: <that>, thresholds:
  techniqueMasteryThresholds)` — the existing `[5, 15, 30]` curve, one
  shared curve, one `define` call per instance.
- `trainTechniqueMastery` / `techniqueMasteryLevel` gain instance-aware
  overloads (or a parallel pair) that key on the instance subject.
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
mintTechniqueVariant(owner, baseFamilyId, descriptorIds, {styleId, styleCentre})
  -> EntityId
     - create entity
     - resolve axisProfile via TechniqueVariantResolver
     - attach TechniqueVariant component
     - register per-instance MasteryDefinition
     - publish TechniqueVariantMinted(owner, instanceId, baseFamilyId)

hangTechniqueVariant(owner, slot, instanceId)
     - isTechniqueLearned(baseFamily) gate for a basic;
       derived variants have no learning gate (mirrors evolved branches)
     - tome.insert(owner, slot,
         BuildComponentRef(referenceType: 'technique',
                           contentId: baseFamilyId,
                           instanceEntityId: instanceId))
     - publish TechniqueAddedToTome (existing event, now carries an instance)

removeTechniqueVariant(owner, instanceId)
     - tome.remove any slot holding it
     - clear + unregister its mastery subject
     - destroy the entity
     - publish TechniqueVariantRemoved
```

`TechniqueAddedToTome` / `technique_events.dart` gain an optional
`instanceId` field (additive, like `BuildComponentRef.instanceEntityId`
was).

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
style seed / SP0b            content
  descriptorIds  ─┐        TechniqueDescriptor{axis,magnitude}
                  ├─► TechniqueVariantResolver.resolve ─► axisProfile
  styleCentre  ───┘              (pure)                      │
                                                             ▼
                          entity + TechniqueVariant{baseFamilyId,
                                     descriptorIds, axisProfile, styleId}
                                                             │
                          register MasteryDefinition(technique:instance:<id>)
                                                             │
                    Tome slot ◄── BuildComponentRef{contentId: baseFamilyId,
                                                    instanceEntityId: <id>}
                                                             │
                             (SP1) interpreter reads TechniqueVariant
                                   -> EffectProfile -> combat calc
```

---

## 9. Edge cases

| Case | Behaviour |
|------|-----------|
| Basic technique | Instance with `descriptorIds = {}`, `axisProfile = {}`, `styleId = null`. Still an instance, still hangable, still has a (flat) per-instance mastery track. |
| Two variants, same base + same descriptors | Two distinct instances, two mastery subjects. Allowed — they may diverge in mastery. (SP0b decides whether to *offer* a duplicate; SP0a permits it.) |
| Descriptor unknown at mint | `mintTechniqueVariant` throws `UnknownTechniqueDescriptorException` (mirrors `UnknownContentFactoryException`). No silent drop. |
| Conflicting descriptors on one axis | Summed additively; net may be negative. No conflict resolution — content's responsibility. |
| Instance removed while hung | `removeTechniqueVariant` removes the Tome placement first, then clears the mastery-subject progress, then removes the `TechniqueVariant` component, then `entities.destroy` — symmetric, no dangling ref. `EntityRegistry.destroy` does **not** cascade component cleanup (documented), so the component removal is explicit. |
| Content changes a descriptor's magnitude later | Existing instances keep their stored `axisProfile`. A future explicit `reresolveVariant(instanceId)` is the only way to pick up the change. Not built in SP0a. |
| Determinism | `resolve` is pure additive; mint publishes events in a fixed order; no RNG in SP0a (the roll lives in SP0b). |

---

## 10. Testing

Per `claude.md`'s per-plugin requirements.

### 10.1 `TechniqueVariantResolver`

- empty descriptors + empty centre → empty profile.
- one descriptor → its `{axis: magnitude}`.
- multiple descriptors on the same axis → sum.
- negative magnitude subtracts.
- style centre is the additive base.
- determinism: two runs, identical inputs, equal profile.

### 10.2 `TechniqueVariant` component

- construction, immutability, stored `axisProfile` independent of a later
  descriptor-content change.

### 10.3 Lifecycle

- `mintTechniqueVariant` creates an entity, attaches `TechniqueVariant`,
  registers a per-instance `MasteryDefinition`, publishes
  `TechniqueVariantMinted`.
- `hangTechniqueVariant` writes a `BuildComponentRef` with
  `instanceEntityId` set; basic gate enforced, derived not gated.
- `removeTechniqueVariant` clears the Tome slot, drops mastery progress,
  unregisters the definition, destroys the entity — asserted no dangling
  `MasteryComponent` entry, no `TomePlacement`, no live entity.
- per-instance mastery: two instances of the same base, train one,
  `techniqueMasteryLevel` diverges.

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

- `lib/src/plugins/technique/technique_variant.dart` — the component.
- `lib/src/plugins/technique/technique_descriptor.dart` — content type +
  ContentRegistry factory.
- `lib/src/plugins/technique/technique_variant_resolver.dart` — pure
  resolver.
- `lib/src/plugins/technique/technique_variant_lifecycle.dart` — mint /
  hang / remove.
- `lib/src/plugins/technique/technique_descriptor_content.dart` — launch
  descriptor set.
- barrel additions in `lib/technique_plugin.dart`.
- `test/plugins/technique/technique_variant_*_test.dart`.

**Changed**

- `lib/src/plugins/technique/technique_vocabulary.dart` —
  `techniqueInstanceSubject`, retain existing subjects.
- `lib/src/plugins/technique/technique_lifecycle.dart` — instance-aware
  `trainTechniqueMastery` / `techniqueMasteryLevel`; `addTechniqueToTome`
  learns to carry an `instanceEntityId`.
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
   continuous vs triple") — descriptor axes like power/speed, or a
   separate structural field on `TechniqueVariant`? Proposal: descriptors
   (`{hooking, precision -1, power +1}`, `{continuous, speed +2, power
   -1}`) so the model stays one-dimensional. Confirm.
4. **Style centre** — where authored? A `MartialStyle` → per-family
   `Map<String,num>` table in the `martial_arts` plugin. Confirm it
   belongs there and not in `technique`.
5. **How many descriptors may one instance carry?** A cap (e.g. 3) keeps
   variants legible and bounds `axisProfile`. Set in SP0b, or here?
6. **Mastery-subject cleanup on run end.** `removeTechniqueVariant` clears
   per-instance progress but cannot unregister the `MasteryDefinition`
   (no `undefine`). A run uses a fresh `PluginContext`, so `_definitions`
   resets between runs regardless; confirm no long-lived context reuses a
   `MasteryTracker` across runs.
