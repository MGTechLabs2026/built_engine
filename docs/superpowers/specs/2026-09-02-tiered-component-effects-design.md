# Tiered Component Effects — SP1 design

**Date:** 2026-09-02
**Status:** draft — awaiting review
**Repo:** `build_engine` (`Tome:RougelikeGame`)
**Consumers:** `Tome_client` (SP4), any future content plugin

---

## 1. Why this exists

### 1.1 The trigger

A reward-granted technique in `Tome_client` shows a rolled prefix/suffix on
the loot card, but once taken the affix does nothing lasting. It was made a
one-shot boon on purpose (`Tome_client` commit `6cc0fa2`, "technique affix
leak") because a technique is not an instanced entity, so an earlier
persistent-modifier implementation had no per-copy home and nothing removed
the buff when the technique was unhung or dropped.

The desired behaviour is broader than "make technique affixes persist like
item affixes." Effects on any component — item, armour, technique, and
future potions and auras — should fall into one of three timing tiers:

1. **Permanent** — counts while the component is *owned*, whether or not it
   is placed on the Tome.
2. **Active** — counts only on a combat action that *uses* that component.
   Hung but unused contributes nothing.
3. **Supporting** — counts while the component is *hung*, on every action,
   whether or not the component itself is used.

### 1.2 The decomposition

This is too large for one change. It is split into four sub-projects, each
with its own spec → plan → implementation cycle:

| SP  | Scope | Depends on |
|-----|-------|------------|
| SP0a | Technique instancing + descriptor/axis variant attributes + per-instance mastery. `2026-09-02-technique-instancing-design.md`. | — |
| SP0b | The inspiration / discovery path that generates derived technique variants from play. | SP0a |
| **SP1** (this doc) | The tiered-effect value type, the core calculation, the owned-set input, migration of `ItemInstance.statBonuses`. **Numbers only.** | SP0a |
| SP2 | Per-action hooks / auras ("do X each turn while hung") via the existing Rule engine. | SP1 |
| SP3 | Consumables / potions — new reference type, consume-on-use lifecycle, auto-combat trigger story. | SP1 |
| SP4 | `Tome_client` surfacing — reward affixes roll a tier, detail sheet shows effects by tier, Tome feeds the owned set. Closes the original bug. | SP1 |

SP1 depends only on SP0a (for instanced techniques); SP2–SP4 follow it.

---

## 2. Scope

### 2.1 In scope

- A new core module `lib/src/effect_profile/` holding a pure value type
  and a pure resolver. No vocabulary.
- A core enum `EffectTier { permanent, active, supporting }`.
- A public interface `EffectContributor` that a plugin's component type
  implements to expose its `EffectProfile`.
- `BuildResolver` emitting the owned-component set alongside the active
  (hung) set.
- The combat calculation folding tiered contributions into the existing
  `ModifierResolver` pipeline.
- Migrating `ItemInstance.statBonuses` to be an input to the item's
  `supporting` tier — one path, no parallel system.
- `Item` and `Technique` plugins implementing `EffectContributor`.
- Tests.

### 2.2 Explicitly out of scope

- Any effect that *does something each action* (regen, chip damage, status
  application). SP1 sums numbers into a stat; it does not run per-turn
  behaviour. That is SP2, built on the existing `Rule` / `Effect` engine.
- Consumable lifecycle, a potion reference type, an `onUse` effect kind —
  SP3.
- Any `Tome_client` change — SP4.
- Reward affixes rolling a tier — SP4. SP1 leaves the current
  `Tome_client` reward-affix behaviour untouched.
- Persistence / serialization of an `EffectProfile` (profiles are derived
  from already-serialized definition + instance state, not stored).
- Any change to `claude.md`'s architecture contract. This design is
  written to fit the existing contract; see §3.

---

## 3. Contract fit

`claude.md` constrains this design and it is built to comply:

| Rule | How SP1 complies |
|------|------------------|
| *Core provides verbs; plugins provide nouns.* | The core primitive is `Map<EffectTier, Map<String, num>>` — arithmetic, no domain terms. All vocabulary (class, grade, affix, tier, mastery, blade, fist, jab) stays in the plugin that owns it. |
| *Do NOT create giant classes such as Potion.* | `EffectProfile` is a small immutable value type. There is no `Component` / `Item` / `Potion` base class. Plugins keep their own definition/instance types and merely *implement an interface*. |
| *Never introduce speculative abstractions without a concrete use case.* | Three concrete uses land immediately (Item affixes, Technique affixes, the SP2/SP3/SP4 features that were specified before this doc). The tier enum is exactly 3, fixed — not an open extensibility hook. |
| *Favor the smallest stable API that can support future plugins.* | One value type, one enum, one interface, one pure resolver, one added field on the build snapshot. Mirrors the size of the `Mastery` and `Reward` passes. |
| *Pure functions, small services, explicit dependencies.* | The resolver is a pure function like `ModifierResolver` / `BuildResolver`. No new `PluginContext` / `RuleContext` / `RuleEngine` wiring (see §7.3). |
| *Composition over inheritance.* | Plugins *compose* an `EffectProfile` and *implement* `EffectContributor`; nothing extends anything. |

This primitive is a structured layer over the Modifier Engine, not a rival
to it: its output is fed to `ModifierResolver.resolve` as ordinary `add`
contributions.

---

## 4. The core primitive (`lib/src/effect_profile/`)

Module name is provisional; `effect_profile` is chosen because
`lib/src/component/` is `ComponentStore` and `BuildComponentRef` already
owns "component". Rename candidates: `contribution`, `tiered_effects`.

### 4.1 `EffectTier`

```dart
/// When a component's numeric effects are counted into a calculation.
/// Core-owned and fixed at three — each tier's inclusion rule is
/// calculation logic, not content, so a plugin cannot add tiers.
enum EffectTier {
  /// Counted while the owner *has* the component, hung or not.
  permanent,

  /// Counted only on a calculation that *uses* this component
  /// (e.g. the combat action performed with it).
  active,

  /// Counted while the component is *hung* (in the ActiveBuild), on
  /// every calculation, whether or not the component itself is used.
  supporting,
}
```

### 4.2 `EffectProfile`

```dart
/// A component's numeric contributions, grouped by tier.
///
/// The inner map is open, string-keyed (`'initiative'`, `'damage'`,
/// `'recovery'`, ...). Core never enumerates the keys — the same
/// treatment `TrainingProfile.dimensions` and `MasteryComponent.progress`
/// already get. A consumer reads the keys it cares about; an unknown key
/// is simply never asked for.
class EffectProfile {
  const EffectProfile(this._byTier);

  final Map<EffectTier, Map<String, num>> _byTier;

  static const empty = EffectProfile({});

  /// Every stat contribution declared for [tier]. Empty map if none.
  Map<String, num> tier(EffectTier tier) =>
      _byTier[tier] ?? const {};

  /// Convenience for one (tier, stat) lookup. 0 if absent.
  num amount(EffectTier tier, String stat) =>
      _byTier[tier]?[stat] ?? 0;

  /// Merge two profiles tier-by-tier, stat-by-stat (add). Used when one
  /// component has more than one contributor feeding its profile
  /// (e.g. an item's base stat plus its rolled affix).
  EffectProfile merge(EffectProfile other) { /* additive union */ }
}
```

Immutable. No behaviour beyond lookup and additive merge. Determinism is
free: all reads are pure, and every combination is commutative addition.

### 4.3 `EffectProfileResolver`

```dart
/// Pure. Mirrors ModifierResolver / BuildResolver's "function, no
/// storage" shape.
class EffectProfileResolver {
  const EffectProfileResolver();

  /// The total contribution to [stat] from a set of components.
  ///
  ///   Σ permanent[stat]  over `owned`
  /// + Σ supporting[stat]  over `hung`
  /// + active[stat]        of `usedThisCalculation` (if any)
  ///
  /// `hung` MUST be a subset of `owned`; the caller guarantees it
  /// (BuildResolver, §6). A profile in `hung` but not `owned` is a
  /// caller bug — asserted in debug, its `permanent` tier ignored in
  /// release (its `supporting` tier still counts, since it is in `hung`).
  num resolve({
    required Iterable<EffectProfile> owned,
    required Iterable<EffectProfile> hung,
    EffectProfile? usedThisCalculation,
    required String stat,
  });
}
```

Returns a plain `num` — the caller decides whether that is an additive
term, the `base`, or an `add` `Modifier` (see §8). SP1 always folds it in
as an `add` contribution to the existing pipeline.

---

## 5. The plugin template (`EffectContributor`)

```dart
/// A component type that can declare tiered numeric effects.
///
/// Implemented directly by a plugin's own definition/instance type —
/// the "implement the interface, no registry" pattern already used by
/// Condition, Effect, CombatAction, TrainingExercise.
abstract interface class EffectContributor {
  /// This component's contributions. The implementer folds in whatever
  /// of its own domain state matters — item class/grade/affixes,
  /// technique tier/mastery, etc. Core never sees that state, only the
  /// returned profile.
  EffectProfile effectProfile();
}
```

- **Item.** `MartialItemDefinition` (or a small wrapper over
  `ItemDefinition` + `ItemInstance`) implements `effectProfile()`. A
  weapon's scaled `attack` and its per-copy `ItemInstance.statBonuses`
  (today applied only while hung — §9) map to the `supporting` tier keyed
  by the item's combat stat. Armour's mitigation maps to `supporting`.
  Nothing an item declares is `active` yet (a weapon "used this action" is
  SP-later polish); nothing is `permanent` yet. The tiers exist; Item
  simply populates one for now.
- **Technique.** `MartialTechniqueDefinition` implements
  `effectProfile()`. A technique's own damage/effect numbers derived from
  its `tier` string and its mastery level map to `supporting`. When SP4
  adds affixes-with-tiers, a rolled `permanent` affix on a technique lands
  in the `permanent` tier here and is picked up automatically.
- **Core `AttackAction` with no component source** (bare-handed strike):
  no `EffectContributor`, contributes nothing — `usedThisCalculation` is
  `null`.

Each plugin's interpreter (`ItemActionInterpreter`,
`TechniqueActionInterpreter` in `lib/src/plugins/build_interpretation/`)
already resolves a `BuildComponentRef` to its own definition via
`context.content.find(ref.contentId)`. That resolved definition is the
`EffectContributor`; the interpreter calls `effectProfile()` on it.

---

## 6. The owned set (`BuildResolver`)

Today: `BuildResolver.resolve(owner, placements) -> ActiveBuild {owner,
components}` — `components` is the hung set only. `permanent`-tier effects
need the owned-but-unhung components too.

### 6.1 Change

`BuildResolver` stays a pure, storage-free function (its documented
shape). Ownership is *passed in*, not fetched:

```dart
class ResolvedBuild {
  final EntityId owner;
  /// Hung — what is on the Tome. Fed to Combat as today's ActiveBuild.
  final List<BuildComponentRef> active;
  /// Everything the owner has, hung or not. `active` is a subset.
  final List<BuildComponentRef> owned;
}

ResolvedBuild BuildResolver.resolve(
  EntityId owner,
  List<TomePlacement> placements, {
  required List<BuildComponentRef> ownedRefs,
});
```

**Ownership is one authoritative relationship (SP0a rule 5).** There is a
single source of truth for "owner *has* this component instance": the
instance entity's own `owner` field — `ItemInstance.owner` for an item,
`TechniqueVariant.owner` for a technique. `ownedRefs` is *derived* from
that relationship, not a separate roster:

```
ownedRefs(owner) =
    [ ref(e) for e in components.entitiesWith<ItemInstance>()   if e.owner == owner ]
  + [ ref(e) for e in components.entitiesWith<TechniqueVariant>() if e.owner == owner ]
```

`active` (hung) is then simply the subset of those instances that a Tome
placement references (`placement.ref.instanceEntityId == e`), so
`active ⊆ owned` holds by construction — the exact precondition
`EffectProfileResolver` documents (§4.3). There is no "roster ∪ hung"
union to keep consistent; "owned but not hung" is an owned instance no
placement points at.

**`instanceEntityId` invariant (SP0a rule 4).** Every technique
`BuildComponentRef` this system reads carries a non-null
`instanceEntityId` pointing at a live instance. A null one is a pre-SP0a
placement: the interpreter treats it as the bare base definition —
`EffectProfile.empty`, no per-instance mastery. Items have carried
`instanceEntityId` since they were instanced; a null there is likewise
"no per-copy data".

**Deriving a technique's `EffectProfile` (§5).** The technique plugin
maps that instance's `TechniqueVariant.axisProfile` plus its per-instance
mastery level to the three `EffectProfile` tiers — SP0a stores the axis
profile and mastery; SP1 defines the axis-key → (tier, stat-key) mapping.

`ActiveBuild` is kept as a type for backward compatibility — `ResolvedBuild
.active` can be exposed as an `ActiveBuild` via a thin getter so existing
Combat call sites are untouched. New code reads `ResolvedBuild`.

### 6.2 Flow

```
Tome placements ──────────────┐
                              ├─► BuildResolver.resolve ─► ResolvedBuild ─► Combat
ownedRefs (derived from        ┘         (pure)             {active, owned}
  *Instance.owner, per rule 5)
```

One-way, as today. No new import direction: `BuildResolver` gains a
parameter, not a dependency. The caller that computes `ownedRefs` is the
`build_interpretation` layer, which already holds a `PluginContext`.

---

## 7. Combat integration

### 7.1 Where the calculation happens

`lib/src/plugins/build_interpretation/` is the seam that already turns
`ActiveBuild.components` into `Modifier`s and `CombatAction`s each combat
setup. It gains:

1. **Input:** the `ResolvedBuild` (so it sees `owned`, not just `active`).
2. **Per stat that combat reads** (`damage`, `initiative`, plus whatever
   armour/recovery keys combat already consumes), call
   `EffectProfileResolver().resolve(owned: <profiles of owned>, hung:
   <profiles of active>, usedThisCalculation: null, stat: s)` and register
   the result as one `add` `Modifier` on the actor with a stable
   `ModifierSource('effectprofile:<stat>')` — `removeBySource` then `add`,
   idempotent, exactly as `ItemActionInterpreter` already does for its
   attack modifier.

   This covers `permanent` (from `owned`) and `supporting` (from `hung`)
   in one standing modifier per stat, refreshed each setup.

### 7.2 The `active` tier

`active` cannot be a standing modifier — it depends on which action is
being performed. The concrete action carries its source:

```dart
// CombatAction gains an optional field, default null.
final EffectProfile? sourceProfile;
```

`AttackAction` / `MartialTechniqueAction` are constructed by the
interpreter, which already knows the originating `BuildComponentRef` — it
passes that component's `EffectProfile` as `sourceProfile`. Inside
`effectsFor`, where `AttackAction` already calls
`ModifierResolver().resolve(baseDamage, ...)`, it additionally adds
`sourceProfile?.amount(EffectTier.active, damageStat) ?? 0` to the base
before resolving. Bare-handed strike: `sourceProfile` is null, adds 0.

No new machinery — `sourceProfile` is one nullable field and one addition
in the one place damage is already computed.

### 7.3 No new wiring

Like the Training, Evolution, and Reward passes: nothing is added to
`PluginContext` / `RuleContext` / `RuleEngine`. `EffectProfileResolver` is
a `const` pure function the interpreter constructs inline. `EffectProfile`
travels as a plain value on `CombatAction` and in the interpreter's local
scope.

---

## 8. Data flow (end to end)

```
                 ┌───────────────── build_interpretation (combat setup) ─────────────────┐
Tome placements  │                                                                       │
   + ownership ──┼─► BuildResolver ─► ResolvedBuild ─► for each ref:                      │
                 │      (pure)         {active, owned}    content.find → EffectContributor│
                 │                                        → EffectProfile                 │
                 │                                                                        │
                 │   per stat s combat reads:                                             │
                 │     EffectProfileResolver.resolve(                                     │
                 │        owned:  profiles(owned),                                        │
                 │        hung:   profiles(active),        ─► num  ─► Modifier(add, s)    │
                 │        stat:   s)                            on actor, stable source   │
                 │                                                                        │
                 │   per action built from a ref:                                         │
                 │     AttackAction(..., sourceProfile: profileOf(ref))                   │
                 └───────────────────────────────────────────────────────────────────────┘
                                                   │
                        AttackAction.effectsFor:   ▼
                        base = baseDamage + sourceProfile.amount(active, damageStat)
                        ModifierResolver.resolve(base, actor's modifiers incl. the add above)
                        → Damage effect
```

`permanent` + `supporting` ride the standing per-stat modifier; `active`
rides the action's own `sourceProfile`. All three end up in the same
`ModifierResolver` pipeline that already exists.

---

## 9. Migration of `ItemInstance.statBonuses`

Today (`item_action_interpreter.dart`): for each hung item with an
instance, each `statBonuses` entry becomes an `add` `Modifier` on the
actor with `ModifierSource('affix:<instanceValue>:<stat>')`, "applied
only while it's in the build (hung)".

That is exactly the `supporting` tier. Migration:

- `MartialItemDefinition.effectProfile()` folds `ItemInstance.statBonuses`
  into `EffectProfile.tier(supporting)` keyed by the same stat strings.
- `item_action_interpreter.dart` stops emitting the per-`statBonuses`
  modifiers directly; the single per-stat `effectprofile:<stat>` modifier
  from §7.1 now carries them (summed with everything else `supporting`).
- `ItemInstance.statBonuses` the field is unchanged — it is still where a
  rolled item affix's numbers live and still rides through `combineItems`
  (`item_combine.dart` already carries `statBonuses` onto the survivor).
  Only the *path from that field into combat* moves.
- `combineItems` needs no change: the survivor's `statBonuses` is
  preserved, so its `effectProfile()` is preserved.

Net: identical combat numbers for items that have affixes today, via one
code path instead of two.

---

## 10. Error handling & edge cases

| Case | Behaviour |
|------|-----------|
| `EffectProfile.empty` / a tier with no entries | Contributes 0. No special-casing. |
| Unknown stat key in a profile | Never read; inert. No validation pass, no throw — matches `TrainingProfile` / `MasteryComponent`. |
| Profile in `hung` but not `owned` | Caller bug. `assert` in debug; release ignores its `permanent` tier, still counts its `supporting` tier (it *is* hung). |
| Negative amounts | Allowed — a component may declare a penalty. Flows through `add` like any negative modifier. |
| `sourceProfile == null` (bare-handed) | `active` contribution is 0. |
| Same component owned in two copies (two `ItemInstance`s) | Two refs in `owned`/`active`, two profiles, summed — same as two modifiers today. |
| No content plugins loaded | `effect_profile/` compiles and its resolver runs on empty inputs; the "core runs without content" integration test is unaffected (nothing in core *calls* the resolver — the interpreter plugin does). |
| Determinism | All-additive, pure; map iteration is insertion-ordered in Dart. No RNG. A determinism test runs identical inputs through two resolvers and asserts equality. |

---

## 11. Testing

Following `claude.md`'s per-service and per-plugin requirements.

### 11.1 Core — `test/effect_profile/`

- `EffectProfile`: construction, `tier`/`amount` lookups, `empty`,
  `merge` (additive union, tier-by-tier, stat-by-stat), immutability.
- `EffectProfileResolver.resolve`:
  - permanent counted from `owned`, not gated on `hung`.
  - supporting counted from `hung` only; an owned-but-unhung profile's
    `supporting` tier does not count.
  - active counted only when passed as `usedThisCalculation`.
  - the three sum independently for one stat.
  - empty inputs → 0.
  - negative amounts subtract.
  - `hung ⊄ owned` → assert in debug.
  - determinism: two runs, identical inputs, equal output.

### 11.2 `BuildResolver`

- `resolve` returns `ResolvedBuild` with `active ⊆ owned`.
- `ownedRefs` not placed on the Tome still appear in `owned`, absent from
  `active`.
- existing `ActiveBuild`-shaped call sites still work via the compat
  getter.

### 11.3 Plugins

- `Item` registration/behaviour test: `MartialItemDefinition`
  `effectProfile()` puts scaled `attack` and `statBonuses` in
  `supporting`, keyed by the item's combat stat; an item with no bonuses
  yields `EffectProfile.empty`.
- `Technique` behaviour test: `effectProfile()` reflects tier + mastery
  in `supporting`.
- Migration parity: a hung affixed item produces the *same* final
  `damage` through the new single `effectprofile:<stat>` modifier as it
  did through the old per-`statBonuses` modifiers. A golden/numeric
  assertion.

### 11.4 Integration

- `build_interpretation` combat-setup test: owned-but-unhung component
  with a (test-only) `permanent` entry raises the actor's stat; unhanging
  a component with a `supporting` entry drops it; an `active` entry only
  bites on that component's own action.
- Full existing combat + martial-arts integration suites stay green.
- "Core runs without content plugins" and "MartialArts runs without
  Magic" unaffected.

---

## 12. Files

**New**

- `lib/src/effect_profile/effect_tier.dart`
- `lib/src/effect_profile/effect_profile.dart`
- `lib/src/effect_profile/effect_profile_resolver.dart`
- `lib/src/effect_profile/effect_contributor.dart`
- barrel export in `lib/build_engine.dart`
- `test/effect_profile/*`

**Changed**

- `lib/src/tome/build_resolver.dart` — `ResolvedBuild`, `ownedRefs` param,
  `ActiveBuild` compat getter.
- `lib/src/tome/*` — `resolve` call sites / `TomeService.resolve`
  signature.
- `lib/src/plugins/combat/combat_action.dart` — `EffectProfile?
  sourceProfile` field.
- `lib/src/plugins/combat/attack_action.dart` — add `active` contribution
  to base before `ModifierResolver.resolve`.
- `lib/src/plugins/build_interpretation/item_action_interpreter.dart` —
  consume `ResolvedBuild`; emit one `effectprofile:<stat>` modifier per
  stat; stop emitting per-`statBonuses` modifiers.
- `lib/src/plugins/build_interpretation/technique_action_interpreter.dart`
  — same consumption; pass `sourceProfile` when building actions.
- `lib/src/plugins/martial_arts/martial_item.dart` /
  `martial_item_content.dart` — implement `EffectContributor`.
- `lib/src/plugins/martial_arts/martial_technique*.dart` — implement
  `EffectContributor`.
- `CHANGELOG.md` — public-surface additions (`EffectProfile`,
  `EffectTier`, `EffectContributor`, `ResolvedBuild`).
- `ARCHITECTURE.md` — new "Tiered Component Effects" section.

---

## 13. Downstream preview (not built in SP1)

- **SP2 — hooks/auras.** A component profile is numbers only. "Heal 2 each
  turn while hung" is a `Rule` on `TurnStarted` gated by an
  `equipped:<id>` tag (the pattern MartialArts trinkets already use), not
  an `EffectProfile` entry. SP2 adds the content and rules; it reads
  hung-ness the same way.
- **SP3 — potions.** New `referenceType: 'consumable'`, an `onUse` that
  removes the ref after the action, and an auto-combat rule for when the
  action selector fires it. Its passive numbers (if any) still flow as an
  `EffectProfile`.
- **SP4 — client.** Reward affixes roll `(tier, {stat: amount})` and
  attach to the component's `EffectProfile`; `component_detail_sheet`
  groups effects by tier ("+3 damage · permanent", "+4 initiative · while
  hung"); `Tome_client` supplies `ownedRefs` to `BuildResolver`. The
  original technique-reward-affix bug closes here.

---

## 14. Open questions

1. **Naming.** `EffectProfile` / `EffectTier` / `EffectContributor` /
   `EffectProfileResolver` / `ResolvedBuild` / module `effect_profile/` —
   all provisional. Alternatives: `Contribution`, `TieredEffects`,
   `BuildContribution`.
2. **Stat keys.** SP1 introduces **no new stat keys** — the resolver is
   key-agnostic, and the interpreter only emits `effectprofile:<stat>`
   modifiers for keys combat already reads (`damage`, `initiative`, the
   armour/mitigation factors). A key like `recovery` is a separate combat
   change, out of SP1 scope. The exact existing key list is confirmed
   against `AttackAction` during planning; it does not change this design.
3. **`TomeService.resolve` signature.** Default: `TomeService.resolve`
   gains a `required List<BuildComponentRef> ownedRefs` parameter and
   forwards it to `BuildResolver.resolve`. Callers that only have
   placements (pure placement preview, tests) can call `BuildResolver`
   directly with `ownedRefs: const []`. Confirmed during planning.
