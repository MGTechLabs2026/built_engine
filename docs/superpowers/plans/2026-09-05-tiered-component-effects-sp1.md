# Tiered Component Effects SP1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give the engine one authoritative numeric-effect path — `EffectProfile`/`EffectTier`/`EffectContributor`/`EffectProfileResolver` — and migrate the two existing parallel numeric paths (`ItemInstance.statBonuses → affix:*` modifiers, `TechniqueVariant.axisProfile['power'] → direct damage arithmetic`) onto it, with identical combat numbers.

**Architecture:** A new pure Core module (`lib/src/effect_profile/`) with zero domain vocabulary. `BuildResolver` grows from producing `ActiveBuild` (hung only) to `ResolvedBuild` (`owned` + `active`, `active ⊆ owned` by construction). The `build_interpretation/` composition seam — already the one place both Item and Technique plugins meet Combat — resolves each owned/hung ref to an `EffectContributor`, and folds tiered contributions into the *existing* `ModifierResolver`/`AttackAction` pipeline. No new wiring on `PluginContext`/`RuleEngine`; no new pipeline.

**Tech Stack:** Dart 3.7, `package:test`. `dart test` / `dart analyze` from the repo root.

**Spec:** `docs/superpowers/specs/2026-09-02-tiered-component-effects-design.md` (read the whole file, including §15 — the 2026-09-05 validation addendum that corrects three parts of the original design against the current codebase). Read alongside `docs/superpowers/specs/2026-09-04-sp1-techniquevariant-first-game-run-design.md` for background on `TechniqueVariant`/`sourceRef`, which this plan builds on and does not re-explain.

## Global Constraints

- `lib/src/effect_profile/` may import **only** other Core modules (`entity/`, etc.) — never `combat`, `item`, `technique`, `martial_arts`, `game`, `almanac`, `Tome_client`. No vocabulary strings (`'blade'`, `'power'`, `'damage'`) appear in this directory; those are content, supplied by callers.
- `EffectTier` is exactly `{ permanent, active, supporting }` — fixed, not plugin-extensible.
- `EffectProfile` is a small immutable value type; `EffectProfileResolver` is `const`, pure, storage-free; `EffectContributor` is an interface only (no registry).
- No new `PluginContext`/`RuleContext`/`RuleEngine` wiring. No global mutable state, no service locator.
- No new `Component`/`Item`/`Potion`-style base class.
- Ownership is derived **only** from `ItemInstance.owner` / `TechniqueVariant.owner` — never a second roster.
- `ResolvedBuild.active ⊆ ResolvedBuild.owned` holds **by construction** (see Task 2's union design — not an assert bolted on after the fact).
- The **real, live** Item/Technique plugins are `lib/src/plugins/item/item_definition.dart` (`ItemDefinition`) + `ItemInstance`, and `lib/src/plugins/technique/technique_definition.dart` (`TechniqueDefinition`) + `TechniqueVariant`. The separate `lib/src/plugins/martial_arts/martial_item.dart` / `martial_technique_content.dart` content is **not** wired into `runGame`'s combat path (confirmed: nothing in `build_interpretation/` reads it) — out of scope for this plan.
- `CombatAction.sourceRef` already exists (SP0a/SP0b) and is the identity carrier for the `active` tier — do **not** add a `sourceProfile` field to `CombatAction`/`AttackAction`.
- `attack_action.dart` does not exist; `AttackAction` is defined inline in `lib/src/plugins/combat/combat_action.dart`. Any change to `AttackAction` lands there.
- One path only: after this plan, `grep -rn "affix:" lib/` and `grep -rn "axisProfile\['power'\]" lib/` must return **zero** hits outside `EffectContributor` implementations reading `axisProfile` as *source data* (i.e. `TechniqueVariant`'s own `effectProfile()` may read `axisProfile['power']` — that is the one authorized read; `TechniqueActionInterpreter` may not).
- No RNG introduced anywhere in this feature. No serialization of `EffectProfile`.
- Do not touch `Tome_client`, Devvit, any backend, any UI. Do not modify `claude.md`.
- This is a migration, not a redesign: do not refactor `ModifierResolver`, do not redesign `ItemInstance`/`TechniqueVariant`, do not implement SP2 (hooks/auras) or SP3 (potions) content.
- Commit after every task. Branch: `tiered-component-effects-sp1` (already created, pushed).
- Commit message trailer for every commit:
  ```
  Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
  Claude-Session: https://claude.ai/code/session_01A6XWn159FKTxxmDWuyRQo8
  ```

---

## File Structure

| File | Responsibility | Task |
|---|---|---|
| `lib/src/effect_profile/effect_tier.dart` | `enum EffectTier` | 1 |
| `lib/src/effect_profile/effect_profile.dart` | `EffectProfile` value type | 1 |
| `lib/src/effect_profile/effect_profile_resolver.dart` | `EffectProfileResolver` pure function | 1 |
| `lib/src/effect_profile/effect_contributor.dart` | `EffectContributor` interface | 1 |
| `lib/build_engine.dart` | barrel export for the 4 files above | 1 |
| `test/effect_profile/effect_profile_test.dart`, `effect_profile_resolver_test.dart` | Core unit tests | 1 |
| `lib/src/tome/build_resolver.dart` | `ResolvedBuild`, `ownedRefs` param, `ActiveBuild` compat getter | 2 |
| `test/tome/build_resolver_test.dart` (new or extended) | owned/active subset tests | 2 |
| `lib/src/tome/tome_service.dart` | `resolve` gains required `ownedRefs` | 3 |
| `lib/src/plugins/game/game_run.dart`, `combat_stage.dart`, `tome_manager.dart` | compute + pass `ownedRefs` at the composition seam | 3 |
| 6 existing test files calling `context.tome.resolve(` | pass `ownedRefs` (mostly `const []`) | 3 |
| `lib/src/plugins/build_interpretation/build_action_interpreter.dart` | `interpret({required ResolvedBuild build, ...})` | 4 |
| `composite_build_action_interpreter.dart`, `item_action_interpreter.dart`, `technique_action_interpreter.dart` | signature follow-through | 4 |
| existing interpreter tests | call-site follow-through | 4 |
| `lib/src/plugins/game/tome_manager.dart` (`placeItem`) | item Tome placement carries `instanceEntityId` | 5 |
| `lib/src/plugins/item/item_definition.dart`, `item_instance.dart` | `ItemEffectContributor` wrapper implementing `EffectContributor` | 6 |
| `lib/src/plugins/build_interpretation/item_action_interpreter.dart` | migrate off `affix:*`/direct `attack` modifier to `EffectProfileResolver` | 6 |
| `lib/src/plugins/technique/technique_variant.dart` | `TechniqueVariant` implements `EffectContributor` | 7 |
| `lib/src/plugins/build_interpretation/technique_action_interpreter.dart` | migrate off direct `axisProfile['power']` read | 7 |
| `test/plugins/build_interpretation/*` (migration parity + scenarios) | Task 8 |
| `CHANGELOG.md`, `ARCHITECTURE.md`, `test/integration/architecture_dependency_test.dart` | docs + new dependency guard | 9 |

---

### Task 1: Core `effect_profile/` module

**Files:**
- Create: `lib/src/effect_profile/effect_tier.dart`
- Create: `lib/src/effect_profile/effect_profile.dart`
- Create: `lib/src/effect_profile/effect_profile_resolver.dart`
- Create: `lib/src/effect_profile/effect_contributor.dart`
- Modify: `lib/build_engine.dart` (4 new exports)
- Create: `test/effect_profile/effect_profile_test.dart`
- Create: `test/effect_profile/effect_profile_resolver_test.dart`

**Interfaces:**
- Produces: `enum EffectTier { permanent, active, supporting }`; `class EffectProfile` with `const EffectProfile(Map<EffectTier, Map<String, num>>)`, `factory EffectProfile.of(Map<EffectTier, Map<String, num>>)` (defensive deep-copy for non-const callers), `static const empty`, `Map<String, num> tier(EffectTier)`, `num amount(EffectTier, String)`, `EffectProfile merge(EffectProfile)`; `class EffectProfileResolver` with `const EffectProfileResolver()` and `num resolve({required Iterable<EffectProfile> owned, required Iterable<EffectProfile> hung, EffectProfile? usedThisCalculation, required String stat})`; `abstract interface class EffectContributor { EffectProfile effectProfile(); }`.
- Consumes: nothing outside `dart:core`.

**Context:** This is the pure Core primitive every later task builds on. `EffectProfile`'s `const` constructor must stay usable for `static const empty = EffectProfile({})` (a genuinely empty compile-time-const map is trivially immutable), but general callers building a profile from computed values need protection against accidental external mutation of the maps they hand in — hence the `EffectProfile.of` factory that deep-copies into `Map.unmodifiable` wrappers. Later tasks (6, 7) always construct through `.of(...)`, never the bare const constructor with a non-literal map.

- [ ] **Step 1: Write the failing tests**

Create `test/effect_profile/effect_profile_test.dart`:

```dart
import 'package:build_engine/build_engine.dart';
import 'package:test/test.dart';

void main() {
  test('empty profile returns zero/empty for every lookup', () {
    expect(EffectProfile.empty.tier(EffectTier.permanent), isEmpty);
    expect(EffectProfile.empty.amount(EffectTier.active, 'damage'), 0);
  });

  test('tier() returns exactly what was constructed', () {
    final p = EffectProfile.of({
      EffectTier.supporting: {'blade': 3, 'fist': -1},
    });
    expect(p.tier(EffectTier.supporting), {'blade': 3, 'fist': -1});
    expect(p.tier(EffectTier.permanent), isEmpty);
  });

  test('amount() returns 0 for an absent tier or an absent stat key', () {
    final p = EffectProfile.of({
      EffectTier.active: {'damage': 5},
    });
    expect(p.amount(EffectTier.active, 'damage'), 5);
    expect(p.amount(EffectTier.active, 'unknown_stat'), 0);
    expect(p.amount(EffectTier.permanent, 'damage'), 0);
  });

  test('negative amounts are legal', () {
    final p = EffectProfile.of({
      EffectTier.supporting: {'blade': -4},
    });
    expect(p.amount(EffectTier.supporting, 'blade'), -4);
  });

  test('tier() and the profile itself are immutable to external mutation', () {
    final source = {
      EffectTier.permanent: {'damage': 1},
    };
    final p = EffectProfile.of(source);
    source[EffectTier.permanent]!['damage'] = 999; // mutate the ORIGINAL map
    expect(p.amount(EffectTier.permanent, 'damage'), 1); // unaffected

    expect(() => p.tier(EffectTier.permanent)['damage'] = 999,
        throwsUnsupportedError); // returned map itself is unmodifiable
  });

  test('merge is additive, tier-by-tier, stat-by-stat', () {
    final a = EffectProfile.of({
      EffectTier.supporting: {'blade': 3, 'fist': 2},
      EffectTier.permanent: {'initiative': 1},
    });
    final b = EffectProfile.of({
      EffectTier.supporting: {'blade': 1},
      EffectTier.active: {'damage': 5},
    });
    final merged = a.merge(b);
    expect(merged.tier(EffectTier.supporting), {'blade': 4, 'fist': 2});
    expect(merged.amount(EffectTier.permanent, 'initiative'), 1);
    expect(merged.amount(EffectTier.active, 'damage'), 5);
  });

  test('merge with empty is a no-op', () {
    final a = EffectProfile.of({
      EffectTier.active: {'damage': 5},
    });
    expect(a.merge(EffectProfile.empty).amount(EffectTier.active, 'damage'), 5);
    expect(EffectProfile.empty.merge(a).amount(EffectTier.active, 'damage'), 5);
  });
}
```

Create `test/effect_profile/effect_profile_resolver_test.dart`:

```dart
import 'package:build_engine/build_engine.dart';
import 'package:test/test.dart';

void main() {
  const resolver = EffectProfileResolver();

  EffectProfile p({num permanent = 0, num active = 0, num supporting = 0}) =>
      EffectProfile.of({
        EffectTier.permanent: {'stat': permanent},
        EffectTier.active: {'stat': active},
        EffectTier.supporting: {'stat': supporting},
      });

  test('permanent is counted from owned, regardless of hung', () {
    final result = resolver.resolve(
      owned: [p(permanent: 3)],
      hung: const [],
      stat: 'stat',
    );
    expect(result, 3);
  });

  test('supporting is counted from hung only — an owned-but-unhung '
      "profile's supporting tier does not count", () {
    final ownedOnly = p(supporting: 4);
    final result = resolver.resolve(
      owned: [ownedOnly],
      hung: const [], // not hung
      stat: 'stat',
    );
    expect(result, 0);

    final resultHung = resolver.resolve(
      owned: [ownedOnly],
      hung: [ownedOnly],
      stat: 'stat',
    );
    expect(resultHung, 4);
  });

  test('active is counted only when passed as usedThisCalculation', () {
    final component = p(active: 7);
    expect(
      resolver.resolve(owned: [component], hung: [component], stat: 'stat'),
      0, // no usedThisCalculation -> active never counted
    );
    expect(
      resolver.resolve(
        owned: [component],
        hung: [component],
        usedThisCalculation: component,
        stat: 'stat',
      ),
      7,
    );
  });

  test('all three tiers sum independently for one stat', () {
    final a = p(permanent: 1, supporting: 2, active: 3);
    final b = p(permanent: 10);
    final result = resolver.resolve(
      owned: [a, b],
      hung: [a],
      usedThisCalculation: a,
      stat: 'stat',
    );
    // permanent: a(1) + b(10) = 11
    // supporting: a(2) (only a is hung)
    // active: a(3) (usedThisCalculation)
    expect(result, 16);
  });

  test('empty inputs return 0', () {
    expect(
      resolver.resolve(owned: const [], hung: const [], stat: 'stat'),
      0,
    );
  });

  test('negative amounts subtract', () {
    final result = resolver.resolve(
      owned: [p(permanent: -5)],
      hung: const [],
      stat: 'stat',
    );
    expect(result, -5);
  });

  test('determinism: two runs, identical inputs, equal output', () {
    final owned = [p(permanent: 2, supporting: 1), p(permanent: 3)];
    final hung = [owned.first];
    final a = resolver.resolve(owned: owned, hung: hung, stat: 'stat');
    final b = resolver.resolve(owned: owned, hung: hung, stat: 'stat');
    expect(a, b);
  });
}
```

- [ ] **Step 2: Run — expect FAIL (compile: types undefined)**

Run: `dart test test/effect_profile/`
Expected: compile errors — `EffectProfile`/`EffectTier`/`EffectProfileResolver` undefined.

- [ ] **Step 3: Implement `effect_tier.dart`**

```dart
/// When a component's numeric effects are counted into a calculation.
/// Core-owned and fixed at three — each tier's inclusion rule is
/// calculation logic, not content, so a plugin cannot add tiers.
enum EffectTier {
  /// Counted while the owner *has* the component, hung or not.
  permanent,

  /// Counted only on a calculation that *uses* this component (e.g. the
  /// combat action performed with it).
  active,

  /// Counted while the component is *hung* (in the active build), on
  /// every calculation, whether or not the component itself is used.
  supporting,
}
```

- [ ] **Step 4: Implement `effect_profile.dart`**

```dart
import 'effect_tier.dart';

/// A component's numeric contributions, grouped by tier. The inner map
/// is open, string-keyed (`'initiative'`, `'damage'`, ...) — Core never
/// enumerates the keys, the same treatment `TrainingProfile.dimensions`
/// and `MasteryComponent.progress` already get. A consumer reads the
/// keys it cares about; an unknown key is simply never asked for.
///
/// Recursively immutable. The bare `const` constructor is for
/// compile-time-const literals only (e.g. [empty]) — general callers
/// building a profile from computed maps MUST use [EffectProfile.of],
/// which deep-copies into unmodifiable maps so external mutation of the
/// caller's own map can never desync a profile after construction.
class EffectProfile {
  const EffectProfile(this._byTier);

  /// Deep-copies [byTier] into unmodifiable maps at both levels. The
  /// safe general-purpose constructor.
  factory EffectProfile.of(Map<EffectTier, Map<String, num>> byTier) =>
      EffectProfile(Map.unmodifiable({
        for (final entry in byTier.entries)
          entry.key: Map<String, num>.unmodifiable(entry.value),
      }));

  final Map<EffectTier, Map<String, num>> _byTier;

  static const empty = EffectProfile({});

  /// Every stat contribution declared for [tier]. Empty map if none.
  Map<String, num> tier(EffectTier tier) => _byTier[tier] ?? const {};

  /// Convenience for one (tier, stat) lookup. 0 if absent.
  num amount(EffectTier tier, String stat) => _byTier[tier]?[stat] ?? 0;

  /// Merge two profiles tier-by-tier, stat-by-stat (additive union).
  /// Used when one component has more than one contributor feeding its
  /// profile (e.g. an item's base stat plus its rolled affix).
  EffectProfile merge(EffectProfile other) {
    final result = <EffectTier, Map<String, num>>{};
    for (final t in EffectTier.values) {
      final a = tier(t);
      final b = other.tier(t);
      if (a.isEmpty && b.isEmpty) continue;
      final combined = <String, num>{...a};
      b.forEach((stat, value) => combined[stat] = (combined[stat] ?? 0) + value);
      result[t] = combined;
    }
    return EffectProfile.of(result);
  }
}
```

- [ ] **Step 5: Implement `effect_profile_resolver.dart`**

```dart
import 'effect_profile.dart';
import 'effect_tier.dart';

/// Pure. Mirrors `ModifierResolver`/`BuildResolver`'s "function, no
/// storage" shape.
///
/// This function has no way to see component *identity* (it only
/// receives already-extracted [EffectProfile] values), so it cannot
/// itself assert "every hung profile's owner also appears in owned" —
/// that invariant is established one layer up, at [ResolvedBuild]
/// construction (`lib/src/tome/build_resolver.dart`), where `hung` is
/// derived as a subset of `owned` by construction rather than checked
/// after the fact. This resolver trusts its caller.
class EffectProfileResolver {
  const EffectProfileResolver();

  /// The total contribution to [stat] from a set of components:
  ///
  ///   Σ permanent[stat]  over `owned`
  /// + Σ supporting[stat] over `hung`
  /// + active[stat]       of `usedThisCalculation` (if any)
  num resolve({
    required Iterable<EffectProfile> owned,
    required Iterable<EffectProfile> hung,
    EffectProfile? usedThisCalculation,
    required String stat,
  }) {
    num total = 0;
    for (final profile in owned) {
      total += profile.amount(EffectTier.permanent, stat);
    }
    for (final profile in hung) {
      total += profile.amount(EffectTier.supporting, stat);
    }
    if (usedThisCalculation != null) {
      total += usedThisCalculation.amount(EffectTier.active, stat);
    }
    return total;
  }
}
```

- [ ] **Step 6: Implement `effect_contributor.dart`**

```dart
import 'effect_profile.dart';

/// A component type that can declare tiered numeric effects. Implemented
/// directly by a plugin's own definition/instance type — the "implement
/// the interface, no registry" pattern already used by `Condition`,
/// `Effect`, `CombatAction`, `TrainingExercise`.
abstract interface class EffectContributor {
  /// This component's contributions. The implementer folds in whatever
  /// of its own domain state matters (item class/grade/affixes,
  /// technique axis profile, etc.). Core never sees that state, only the
  /// returned profile.
  EffectProfile effectProfile();
}
```

- [ ] **Step 7: Export from the barrel**

In `lib/build_engine.dart`, add (alphabetically, between the `discovery/` and `entity/` export groups):

```dart
export 'src/effect_profile/effect_contributor.dart';
export 'src/effect_profile/effect_profile.dart';
export 'src/effect_profile/effect_profile_resolver.dart';
export 'src/effect_profile/effect_tier.dart';
```

- [ ] **Step 8: Run the new tests — expect PASS**

Run: `dart test test/effect_profile/`
Expected: PASS.

- [ ] **Step 9: `dart analyze` — expect clean**

Run: `dart analyze`

- [ ] **Step 10: Commit**

```bash
git add lib/src/effect_profile/ lib/build_engine.dart test/effect_profile/
git commit -m "feat(core): EffectTier/EffectProfile/EffectProfileResolver/EffectContributor

The tiered-effects primitive: a pure value type + pure resolver + a
no-registry interface. Zero domain vocabulary. Nothing consumes it yet.
<trailer>"
```

---

### Task 2: `BuildResolver` → `ResolvedBuild`

**Files:**
- Modify: `lib/src/tome/build_resolver.dart`
- Create: `test/tome/build_resolver_test.dart`

**Interfaces:**
- Consumes: `EntityId`, `BuildComponentRef`, `TomePlacement`, `ActiveBuild` (all pre-existing).
- Produces: `class ResolvedBuild { final EntityId owner; final List<BuildComponentRef> active; final List<BuildComponentRef> owned; ActiveBuild get asActiveBuild; }`; `class BuildResolver { const BuildResolver(); ResolvedBuild resolve(EntityId owner, List<TomePlacement> placements, {List<BuildComponentRef> ownedRefs = const []}); }`.

**Context:** Today: `BuildResolver.resolve(owner, placements) -> ActiveBuild(owner, components: [placements' refs])`. `active` (hung) always comes from `placements`, unchanged. `owned` is defined as the union of the caller-supplied `ownedRefs` and the hung refs — this makes `active ⊆ owned` true **by construction**, not by an assert: every hung ref is trivially a member of `owned` because it's unioned in. No test can ever violate the invariant through this API; there is nothing to assert. `ownedRefs` defaults to `const []` so existing pure/placement-only callers (tests, Task 3's compat pass) need no immediate change to `BuildResolver` itself — only `TomeService.resolve` (Task 3) forces its callers to think about ownership.

- [ ] **Step 1: Write the failing tests**

Create `test/tome/build_resolver_test.dart`:

```dart
import 'package:build_engine/build_engine.dart';
import 'package:test/test.dart';

void main() {
  const resolver = BuildResolver();
  const owner = EntityId(1);
  const slotA = SlotId('a');
  const itemRef = BuildComponentRef(referenceType: 'item', contentId: 'knife');
  const looseRef = BuildComponentRef(referenceType: 'item', contentId: 'shield');

  TomePlacement placement(SlotId slot, BuildComponentRef ref) => TomePlacement(
        slot: slot,
        buildComponentRef: ref,
        size: const ItemSize(1, 1),
        rotation: Rotation.deg0,
      );

  test('active is exactly the hung refs, as ActiveBuild is today', () {
    final resolved = resolver.resolve(owner, [placement(slotA, itemRef)]);
    expect(resolved.active, [itemRef]);
  });

  test('ownedRefs not placed on the Tome appear in owned, absent from active', () {
    final resolved = resolver.resolve(
      owner,
      [placement(slotA, itemRef)],
      ownedRefs: [itemRef, looseRef],
    );
    expect(resolved.owned, containsAll([itemRef, looseRef]));
    expect(resolved.active, isNot(contains(looseRef)));
  });

  test('active is always a subset of owned, even if the caller never '
      'mentions a hung ref in ownedRefs', () {
    final resolved = resolver.resolve(
      owner,
      [placement(slotA, itemRef)],
      ownedRefs: const [], // caller forgot / has nothing else owned
    );
    expect(resolved.active.every(resolved.owned.contains), isTrue);
  });

  test('asActiveBuild compat getter matches the old ActiveBuild shape', () {
    final resolved = resolver.resolve(owner, [placement(slotA, itemRef)]);
    final compat = resolved.asActiveBuild;
    expect(compat.owner, owner);
    expect(compat.components, [itemRef]);
  });

  test('empty placements + empty ownedRefs -> both lists empty', () {
    final resolved = resolver.resolve(owner, const []);
    expect(resolved.active, isEmpty);
    expect(resolved.owned, isEmpty);
  });
}
```

- [ ] **Step 2: Run — expect FAIL**

Run: `dart test test/tome/build_resolver_test.dart`
Expected: compile error — `ResolvedBuild`/`asActiveBuild`/`ownedRefs` undefined.

- [ ] **Step 3: Implement**

Replace `lib/src/tome/build_resolver.dart`:

```dart
import '../entity/entity_id.dart';
import 'active_build.dart';
import 'build_component_ref.dart';
import 'tome_placement.dart';

/// A Tome's current placements PLUS every component instance the owner
/// merely *has* — not just what's hung. [active] means currently hung
/// (what `ActiveBuild` used to mean, alone); [owned] means every owned
/// component instance, hung or loose. `active` is a subset of `owned`
/// by construction (see [BuildResolver.resolve]) — there is nothing to
/// assert, it cannot be otherwise through this API.
class ResolvedBuild {
  const ResolvedBuild({required this.owner, required this.active, required this.owned});

  final EntityId owner;

  /// Hung — what is on the Tome. Fed to Combat as today's `ActiveBuild`.
  final List<BuildComponentRef> active;

  /// Everything the owner has, hung or not. [active] is always a subset.
  final List<BuildComponentRef> owned;

  /// Backward-compat projection for callers that only ever wanted the
  /// hung set (today's `ActiveBuild` shape) — unchanged behaviour for
  /// every caller that doesn't yet care about ownership.
  ActiveBuild get asActiveBuild => ActiveBuild(owner: owner, components: active);
}

/// A pure function transforming a Tome's current placements (plus the
/// caller-supplied ownership roster) into a [ResolvedBuild] snapshot —
/// no storage dependency, mirroring `ModifierResolver`'s own "pure
/// function, no storage" shape. Calling [resolve] twice with the same
/// inputs (in the same order) always yields the same [ResolvedBuild].
///
/// Ownership is *passed in*, not fetched — `BuildResolver` (Core) never
/// imports `ItemInstance`/`TechniqueVariant` (plugin types). The caller
/// (the `build_interpretation` composition seam, which already holds a
/// `PluginContext`) derives [ownedRefs] from each instance entity's own
/// `owner` field — the single source of truth for "owner has this".
class BuildResolver {
  const BuildResolver();

  ResolvedBuild resolve(
    EntityId owner,
    List<TomePlacement> placements, {
    List<BuildComponentRef> ownedRefs = const [],
  }) {
    final active = [for (final placement in placements) placement.buildComponentRef];
    // Union, not a separate roster: every hung ref is automatically part
    // of `owned` even if the caller's ownedRefs forgot to list it — this
    // is what makes `active ⊆ owned` true by construction rather than by
    // an assert checked after the fact.
    final owned = <BuildComponentRef>[
      ...ownedRefs,
      for (final ref in active)
        if (!ownedRefs.contains(ref)) ref,
    ];
    return ResolvedBuild(owner: owner, active: active, owned: owned);
  }
}
```

- [ ] **Step 4: Run — expect PASS**

Run: `dart test test/tome/build_resolver_test.dart`
Expected: PASS.

- [ ] **Step 5: `dart analyze lib/src/tome/`**

Expected clean. (`tome_service.dart` will now fail to compile — `_resolver.resolve(owner, inspect(owner))` returns `ResolvedBuild`, not `ActiveBuild`, and `TomeService.resolve`'s own return type is still declared `ActiveBuild`. This is expected and fixed in Task 3 — do not fix it here.)

- [ ] **Step 6: Commit**

```bash
git add lib/src/tome/build_resolver.dart test/tome/build_resolver_test.dart
git commit -m "feat(tome): BuildResolver produces ResolvedBuild {owned, active}

active is a subset of owned by construction (union, not an assert).
ActiveBuild kept as a compat projection. TomeService.resolve itself is
not yet updated — that is the next task.
<trailer>"
```

---

### Task 3: `TomeService.resolve` gains `ownedRefs` — update every call site

**Files:**
- Modify: `lib/src/tome/tome_service.dart`
- Modify: `lib/src/plugins/game/game_run.dart` (new `ownedComponentRefs` helper)
- Modify: `lib/src/plugins/game/combat_stage.dart`
- Modify: `lib/src/plugins/game/tome_manager.dart` (the `snapshot()` call to `context.tome.resolve`)
- Modify: `test/integration/technique_end_to_end_test.dart`
- Modify: `test/integration/item_combine_end_to_end_test.dart`
- Modify: `test/integration/build_interpretation_end_to_end_test.dart` (2 call sites)
- Modify: `test/integration/item_end_to_end_test.dart`
- Modify: `test/integration/support/vertical_slice_runner.dart` (2 call sites)

**Interfaces:**
- Consumes: `ResolvedBuild`, `BuildResolver` (Task 2).
- Produces: `TomeService.resolve(EntityId owner, {required List<BuildComponentRef> ownedRefs}) -> ResolvedBuild`. A new composition-layer helper `List<BuildComponentRef> ownedComponentRefs(EntityId character, PluginContext context)` in `game_run.dart`, combining owned items + owned technique variants into one ref list.

**Context:** `TomeService.resolve` is currently a one-liner: `ActiveBuild resolve(EntityId owner) => _resolver.resolve(owner, inspect(owner));`. It becomes `ResolvedBuild resolve(EntityId owner, {required List<BuildComponentRef> ownedRefs}) => _resolver.resolve(owner, inspect(owner), ownedRefs: ownedRefs);` — `required`, not optional, per the validated spec's own resolution of its open question 3 (no silent "you forgot ownership" default). Every current caller (`grep -rn "\.tome\.resolve(" lib/ test/` — 3 `lib/` + 6 `test/` call sites) must pass something. The **only** caller with real ownership to report is the composition layer (`game_run.dart`/`combat_stage.dart`/`tome_manager.dart`, which hold a `PluginContext`); every test call site that doesn't care about ownership passes `ownedRefs: const []` (Task 2 guarantees `active ⊆ owned` even then, since hung refs union in regardless).

- [ ] **Step 1: `TomeService.resolve`**

In `lib/src/tome/tome_service.dart`, change:

```dart
  ActiveBuild resolve(EntityId owner) => _resolver.resolve(owner, inspect(owner));
```
to:
```dart
  /// [ownedRefs] is every component instance [owner] has, hung or not —
  /// derived by the caller from each instance's own `owner` field
  /// (`ItemInstance.owner`/`TechniqueVariant.owner`; see
  /// `ResolvedBuild`'s own doc comment). `TomeService` itself never
  /// queries those plugin-owned component types — Core doesn't know they
  /// exist.
  ResolvedBuild resolve(EntityId owner, {required List<BuildComponentRef> ownedRefs}) =>
      _resolver.resolve(owner, inspect(owner), ownedRefs: ownedRefs);
```

Update the class-level doc comment's "the only thing it produces... is an `ActiveBuild` snapshot via `resolve`" to say `ResolvedBuild`.

- [ ] **Step 2: Run — expect FAIL everywhere `resolve(` is called with no `ownedRefs`**

Run: `dart analyze`
Expected: errors at every current call site (3 lib, 6 test) — missing required named argument `ownedRefs`, plus (for the 3 lib call sites) `.components`/`ActiveBuild`-shaped usage that needs updating to read `.active` or `.asActiveBuild.components`.

- [ ] **Step 3: Add the composition-layer ownership helper in `game_run.dart`**

Near the existing `ownedItemIds`/`knownTechniqueIds` functions in `lib/src/plugins/game/game_run.dart`, add:

```dart
/// Every component instance [character] owns, hung or not — one
/// [BuildComponentRef] per owned [ItemInstance]/`TechniqueVariant`
/// entity, each carrying that entity's own id as `instanceEntityId`.
/// Passed as `ResolvedBuild.ownedRefs`; the single place in this run
/// that turns "who owns what" into the ref shape `BuildResolver` wants.
List<BuildComponentRef> ownedComponentRefs(EntityId character, PluginContext context) => [
      for (final e in context.components.entitiesWith<ItemInstance>())
        if (context.components.get<ItemInstance>(e)!.owner == character)
          BuildComponentRef(
            referenceType: itemReferenceType,
            contentId: context.components.get<ItemInstance>(e)!.definitionId,
            instanceEntityId: e,
          ),
      for (final e in ownedTechniqueVariants(character, context))
        BuildComponentRef(
          referenceType: techniqueReferenceType,
          contentId: context.components.get<TechniqueVariant>(e)!.baseFamilyId,
          instanceEntityId: e,
        ),
    ];
```

(`ItemInstance`/`itemReferenceType` already reachable via the existing `item_plugin.dart` import; `TechniqueVariant`/`ownedTechniqueVariants`/`techniqueReferenceType` via the existing `technique_plugin.dart` import — both already imported by this file.)

- [ ] **Step 4: Update the 3 `lib/` call sites**

`lib/src/plugins/game/combat_stage.dart:71` — inside `runFight`:
```dart
    final build = context.tome.resolve(character, ownedRefs: ownedComponentRefs(character, context));
```
(`build` is now a `ResolvedBuild`; Task 4 changes what `interpreter.interpret(build: ...)` expects it to be — for *this* task, keep the call site compiling by using `build.asActiveBuild` wherever the rest of `runFight` still expects `ActiveBuild`-shaped access, e.g. `events.publish(ActiveBuildResolved(build.asActiveBuild.components));` if that's the current call — read the file to match exactly.)

`lib/src/plugins/game/game_run.dart:289` (`finalBuild: context.tome.resolve(character).components`):
```dart
      finalBuild: context.tome
          .resolve(character, ownedRefs: ownedComponentRefs(character, context))
          .active,
```

`lib/src/plugins/game/tome_manager.dart:51` (`snapshot`'s `final snapshotComponents = context.tome.resolve(character).components;`):
```dart
    final snapshotComponents = context.tome
        .resolve(character, ownedRefs: ownedComponentRefs(character, context))
        .active;
```

(`ownedComponentRefs` needs importing into `tome_manager.dart` — it's a top-level function in `game_run.dart`; add `import 'game_run.dart' show ownedComponentRefs;` or move the helper to a shared location if a direct import creates a cycle. Check: does `game_run.dart` import `tome_manager.dart`? Yes (`import 'tome_manager.dart';`). Dart does not allow the reverse (`tome_manager.dart` importing `game_run.dart`) if that would be circular *only if* `game_run.dart` needs something from `tome_manager.dart` at the top level that would recurse back — Dart permits mutual imports between library files in the same package as long as there's no cyclic *part-of* relationship, but check for compile errors here. If a cycle warning appears, move `ownedComponentRefs` into `tome_manager.dart` itself instead, and have `game_run.dart` call `tomeManager` — but `tome_manager.dart` doesn't hold `character` at the free-function level. Simplest fix if a cycle bites: define `ownedComponentRefs` in a new tiny file `lib/src/plugins/game/owned_component_refs.dart` with no dependency on either, imported by both. Use your judgment; report which approach you took.)

- [ ] **Step 5: Update the 6 test call sites**

For each of these, the pattern is identical — add `ownedRefs: const []` (none of these tests exercise ownership-based effects; they only care about the hung set) and adapt `.components` reads to `.active`:

- `test/integration/technique_end_to_end_test.dart:64`
- `test/integration/item_combine_end_to_end_test.dart:78`
- `test/integration/build_interpretation_end_to_end_test.dart:74` and `:138`
- `test/integration/item_end_to_end_test.dart:69`
- `test/integration/support/vertical_slice_runner.dart:209` and `:330`

Example (read each file to match its exact surrounding code — do not guess variable names):
```dart
final build = context.tome.resolve(character, ownedRefs: const []);
// then wherever `build.components` was read: `build.active`
```

- [ ] **Step 6: Run — expect PASS on everything except `build_interpretation/` interpreter call sites**

Run: `dart analyze`
Expected: clean except inside `item_action_interpreter.dart`/`technique_action_interpreter.dart`/`composite_build_action_interpreter.dart`/`build_action_interpreter.dart` and their tests, which still declare `interpret({required ActiveBuild build, ...})` — a `ResolvedBuild`/`.active` mismatch at the `interpreter.interpret(build: build, ...)` call sites in `combat_stage.dart` and the updated test files. **This is expected and fixed in Task 4** — for now, at each such call site, pass `build.asActiveBuild` (the Task 2 compat getter) so everything *else* compiles and the existing interpreter tests stay green through this task. Do not touch the interpreter files themselves in this task.

Run: `dart test` (full suite) — expect **all green**, since Task 3 only changes the shape ownership travels in, not what any interpreter reads yet (everything still flows through `.asActiveBuild`).

- [ ] **Step 7: Commit**

```bash
git add lib/src/tome/tome_service.dart lib/src/plugins/game/ test/integration/
git commit -m "feat(tome): TomeService.resolve requires ownedRefs, returns ResolvedBuild

Composition-layer ownedComponentRefs() derives the roster from
ItemInstance.owner / TechniqueVariant.owner (never a second store). All
call sites updated; every one still consumes .asActiveBuild for now —
build_interpretation itself starts reading ResolvedBuild in the next task.
<trailer>"
```

---

### Task 4: `BuildActionInterpreter` reads `ResolvedBuild`

**Files:**
- Modify: `lib/src/plugins/build_interpretation/build_action_interpreter.dart`
- Modify: `lib/src/plugins/build_interpretation/composite_build_action_interpreter.dart`
- Modify: `lib/src/plugins/build_interpretation/item_action_interpreter.dart` (signature only — behaviour migrates in Task 6)
- Modify: `lib/src/plugins/build_interpretation/technique_action_interpreter.dart` (signature only — behaviour migrates in Task 7)
- Modify: `lib/src/plugins/game/combat_stage.dart` (drop the `.asActiveBuild` from Task 3)
- Modify: every test that implements/calls `BuildActionInterpreter`/`CompositeBuildActionInterpreter` directly: `test/plugins/build_interpretation/composite_build_action_interpreter_test.dart`, `item_action_interpreter_test.dart`, `technique_action_interpreter_test.dart`, `technique_action_interpreter_source_ref_test.dart`, `technique_action_interpreter_variant_test.dart`

**Interfaces:**
- Consumes: `ResolvedBuild` (Task 2).
- Produces: `abstract class BuildActionInterpreter { List<CombatAction> interpret({required ResolvedBuild build, required EntityId actor, required List<EntityId> targets, required PluginContext context}); }` — same shape, `build`'s type changed from `ActiveBuild` to `ResolvedBuild`. Every implementer that only needs the hung set reads `build.active` where it used to read `build.components`.

**Context:** This is a pure signature/re-keying task — no interpreter changes its *decisions* yet (Item still only reacts to hung refs for its existing modifier; Technique still only reacts to hung refs for its existing action-building). The only observable change after this task: `interpret` receives `owned` too, unused until Tasks 6-7.

- [ ] **Step 1: `build_action_interpreter.dart`**

```dart
abstract class BuildActionInterpreter {
  List<CombatAction> interpret({
    required ResolvedBuild build,
    required EntityId actor,
    required List<EntityId> targets,
    required PluginContext context,
  });
}
```
Update the doc comment's "Tome -> ActiveBuild -> Build Interpreter" line to "Tome -> ResolvedBuild -> Build Interpreter".

- [ ] **Step 2: `composite_build_action_interpreter.dart`**

Change `build: ActiveBuild` to `build: ResolvedBuild` in both the class's own `interpret` signature and the forwarded call to each sub-interpreter — the body otherwise unchanged (still just concatenates).

- [ ] **Step 3: `item_action_interpreter.dart` / `technique_action_interpreter.dart` — signature only**

In both files, change `interpret({required ActiveBuild build, ...})` to `interpret({required ResolvedBuild build, ...})`, and every `build.components` read inside to `build.active.components`... actually `build.active` is already `List<BuildComponentRef>` (not wrapped), so `for (final ref in build.components)` becomes `for (final ref in build.active)`. Do not change anything else in these two files this task — their bodies still only ever look at the hung set.

- [ ] **Step 4: `combat_stage.dart`**

Change the call site from Task 3's `interpreter.interpret(build: build.asActiveBuild, ...)` back to `interpreter.interpret(build: build, ...)` — `build` is already the `ResolvedBuild` from `context.tome.resolve(...)`, no projection needed now that the interpreter interface accepts it directly.

- [ ] **Step 5: Update the 5 interpreter test files**

Read each file first. The mechanical change in each: wherever a test constructs `ActiveBuild(owner: ..., components: [...])` and passes it as `build:` to `.interpret(...)`, wrap it as a `ResolvedBuild`:
```dart
ResolvedBuild _build(EntityId owner, List<BuildComponentRef> refs) =>
    ResolvedBuild(owner: owner, active: refs, owned: refs);
```
(a small test-local helper — `owned == active` is the correct choice for these existing tests, since none of them are testing ownership-based tiers yet; that's Tasks 6-8's job). Replace each test's `ActiveBuild(...)` construction with a call to this helper (or an equivalent inline `ResolvedBuild(...)`), keeping every existing assertion unchanged.

- [ ] **Step 6: Run the whole `build_interpretation` + `game` + `integration` suites**

Run: `dart test test/plugins/build_interpretation/ test/plugins/game/ test/integration/ test/game/`
Expected: all green, 0 regressions — this task changes only how the hung set travels through the interface, not any interpreter's decisions.

- [ ] **Step 7: `dart analyze` + full suite**

Run: `dart analyze && dart test`
Expected: clean, full suite green.

- [ ] **Step 8: Commit**

```bash
git add lib/src/plugins/build_interpretation/ lib/src/plugins/game/combat_stage.dart test/plugins/build_interpretation/
git commit -m "refactor(build-interpretation): BuildActionInterpreter reads ResolvedBuild

Pure re-keying — interpret() now receives owned+active; no interpreter
changes its decisions yet. No behaviour change, full suite green.
<trailer>"
```

---

### Task 5: Item Tome placement carries `instanceEntityId`

**Files:**
- Modify: `lib/src/plugins/game/tome_manager.dart` (`placeItem`)
- Create: `test/plugins/game/tome_manager_item_instance_test.dart`

**Interfaces:**
- Consumes: `addItemToTome(..., {EntityId? instanceEntityId})` (already exists, unused by the harness today), `context.components.entitiesWith<ItemInstance>()`.
- Produces: `TomeManager.placeItem(ItemDefinition item, String stepName)` now resolves a specific owned-but-unplaced `ItemInstance` for `item.id` and passes its entity id through to `addItemToTome`, mirroring the existing `_ownedBaseVariantFor`/`placeTechniqueVariant` pattern for techniques.

**Context:** Confirmed by inspection: `TomeManager.placeItem` today calls `addItemToTome(character, slot, item, context)` with no `instanceEntityId`, even though `ItemInstance` entities exist (created by `ownItem`) and `addItemToTome` already accepts an optional `instanceEntityId`. Decided 2026-09-05: wire this up now (rather than leave item placements instance-blind) so `ResolvedBuild`'s owned/hung match works by instance identity for items exactly as it already does for techniques — required for `permanent`/`supporting` to be computed correctly per-copy when a player owns multiple copies of one item with divergent `statBonuses` (a real Combine scenario). This is the one place this plan's scope extends slightly beyond the interpreter files themselves.

- [ ] **Step 1: Write the failing test**

Create `test/plugins/game/tome_manager_item_instance_test.dart`:

```dart
import 'package:build_engine/build_engine.dart';
import 'package:build_engine/game.dart';
import 'package:build_engine/item_plugin.dart';
import 'package:test/test.dart';

import '../../support/policies.dart';

({PluginContext ctx, EntityId character, TomeManager mgr}) _setup() {
  final events = EventBus();
  final entities = EntityRegistry(events);
  final components = ComponentStore();
  final rng = RngService(1);
  final shared = CoreServices(components: components, events: events);
  final ctx = PluginContext(
    entities: entities, components: components, events: events, rng: rng,
    rules: RuleEngine(
      entities: entities, components: components, events: events,
      rng: rng, shared: shared),
    queries: QueryEngine(QueryScope(components: components)),
    modifiers: ModifierCollection(),
    content: ContentRegistry(),
    shared: shared,
  );
  ItemPlugin().initialize(ctx);
  final character = ctx.characters.create();
  ctx.tome.defineTome(TomeDefinition.namedSlots(
      id: 't', slotIds: ['slot_1', 'slot_2']));
  ctx.tome.createTome(character, 't');
  final mgr = TomeManager(
    character: character,
    context: ctx,
    recordingPolicy: RecordingDecisionPolicy(const DefaultRunDecisionPolicy()),
    events: events,
    unlockedSlots: [SlotId('slot_1'), SlotId('slot_2')],
  );
  return (ctx: ctx, character: character, mgr: mgr);
}

void main() {
  test('placeItem hangs a specific owned ItemInstance, not a null-instance ref',
      () {
    final s = _setup();
    final item = itemDefinition(ItemIds.knife, s.ctx);
    ownItem(s.character, item.id, s.ctx);
    s.mgr.placeItem(item, 'test place');

    final placements = s.ctx.tome.inspect(s.character);
    expect(placements, hasLength(1));
    expect(placements.single.buildComponentRef.instanceEntityId, isNotNull);
  });

  test('two owned copies of one item place as two distinct instances', () {
    final s = _setup();
    final item = itemDefinition(ItemIds.knife, s.ctx);
    final first = ownItem(s.character, item.id, s.ctx);
    final second = ownItem(s.character, item.id, s.ctx);
    expect(first, isNot(second));

    s.mgr.placeItem(item, 'place first');
    final placedAfterFirst =
        s.ctx.tome.inspect(s.character).single.buildComponentRef.instanceEntityId;
    expect(placedAfterFirst, anyOf(first, second));

    // Placing again picks the OTHER still-unplaced copy, not the same one.
    s.mgr.placeItem(item, 'place second');
    final placedIds = s.ctx.tome
        .inspect(s.character)
        .map((p) => p.buildComponentRef.instanceEntityId)
        .toSet();
    expect(placedIds, {first, second});
  });
}
```

- [ ] **Step 2: Run — expect FAIL**

Run: `dart test test/plugins/game/tome_manager_item_instance_test.dart`
Expected: first test FAILS (`instanceEntityId` is `null`).

- [ ] **Step 3: Implement**

Read the current `placeItem` in `lib/src/plugins/game/tome_manager.dart` first. Add a private helper (next to wherever `_ownedBaseVariantFor`-style helpers would live if this file had one — it doesn't yet, add fresh):

```dart
  /// An owned [ItemInstance] of [definitionId] not already referenced by
  /// any current Tome placement, or `null` if every owned copy is
  /// already placed (or none is owned). Mirrors the technique-variant
  /// "find an unplaced owned instance" pattern
  /// (`TrainingStage._ownedBaseVariantFor`).
  EntityId? _ownedUnplacedItemInstance(String definitionId) {
    final placedInstances = {
      for (final p in context.tome.inspect(character))
        if (p.buildComponentRef.instanceEntityId != null)
          p.buildComponentRef.instanceEntityId!,
    };
    for (final e in context.components.entitiesWith<ItemInstance>()) {
      final instance = context.components.get<ItemInstance>(e)!;
      if (instance.owner == character &&
          instance.definitionId == definitionId &&
          !placedInstances.contains(e)) {
        return e;
      }
    }
    return null;
  }
```

Then in `placeItem`, change the `addItemToTome(character, slot, item, context);` call to:
```dart
    addItemToTome(character, slot, item, context,
        instanceEntityId: _ownedUnplacedItemInstance(item.id));
```
(`_ownedUnplacedItemInstance` returning `null` — e.g. a caller placing an item it doesn't actually own, which would already have failed `isItemUsable`/thrown before reaching this line in every real call path — preserves exactly today's null-instance behaviour; this is a strictly additive improvement, never a regression.)

- [ ] **Step 4: Run the new tests + full existing suite**

Run: `dart test test/plugins/game/tome_manager_item_instance_test.dart`
Expected: PASS.

Run: `dart test` (full suite)
Expected: green. `technique_end_to_end_test.dart`/`item_end_to_end_test.dart`/`item_combine_end_to_end_test.dart`/almanac tests that read item placements should be unaffected — they either don't check `instanceEntityId` for items or (per `almanac_bridge.dart`'s own doc comment) already tolerate a non-null one by preferring it over the live-ECS-state fallback. If anything unexpectedly fails, read it before assuming it's fine to fix — a real regression here would be surprising and worth stopping for.

- [ ] **Step 5: `dart analyze`**

- [ ] **Step 6: Commit**

```bash
git add lib/src/plugins/game/tome_manager.dart test/plugins/game/tome_manager_item_instance_test.dart
git commit -m "feat(game): item Tome placement carries instanceEntityId

Mirrors the technique-variant instance-identity placement already in
place. Required for ResolvedBuild's owned/hung match to work by instance
identity for items, not just techniques — matters once a player owns
multiple copies of one item with divergent statBonuses (Combine).
<trailer>"
```

---

### Task 6: Item `EffectContributor` + migrate `ItemActionInterpreter`

**Files:**
- Create: `lib/src/plugins/item/item_effect_contributor.dart` (the "small wrapper over `ItemDefinition` + `ItemInstance`" the validated spec's §15.1 names)
- Modify: `lib/src/plugins/build_interpretation/item_action_interpreter.dart`
- Create: `test/plugins/item/item_effect_contributor_test.dart`
- Modify: `test/plugins/build_interpretation/item_action_interpreter_test.dart`

**Interfaces:**
- Consumes: `EffectProfile`, `EffectTier`, `EffectContributor`, `EffectProfileResolver` (Task 1); `ResolvedBuild` (Task 2/4).
- Produces: `class ItemEffectContributor implements EffectContributor { const ItemEffectContributor(this.definition, this.instance); final ItemDefinition definition; final ItemInstance? instance; @override EffectProfile effectProfile(); }` — `instance` nullable for a null-`instanceEntityId` legacy ref (rare after Task 5, but the type must not crash on one). `ItemActionInterpreter.interpret` stops emitting `affix:*`/the direct `attack` modifier; instead computes one `effectprofile:item:<stat>` modifier per distinct stat key appearing in any owned item's profile.

**Context:** Today (`item_action_interpreter.dart`, pre-Task-4-signature-change): for each **hung** item, `attack = item.scaledProperties(itemClass)['attack']` becomes one `Modifier(source: 'build:<id>:<actor>', stat: _statFor(item), value: attack)`, and each `instance.statBonuses` entry becomes one `Modifier(source: 'affix:<instanceValue>:<stat>', stat: stat, value: value)` — both only while hung. This task expresses both as the item's `supporting` tier (matching the validated design's own classification: "nothing an item declares is `active` yet; nothing is `permanent` yet — the tiers exist, Item simply populates one for now") and replaces the per-item/per-affix modifiers with one summed modifier per stat, computed from `ResolvedBuild.owned`/`.active` via `EffectProfileResolver`.

- [ ] **Step 1: Write the failing tests**

Create `test/plugins/item/item_effect_contributor_test.dart`:

```dart
import 'package:build_engine/build_engine.dart';
import 'package:build_engine/item_plugin.dart';
import 'package:test/test.dart';

void main() {
  test('scaled attack + statBonuses fold into the supporting tier, keyed '
      "by the item's combat stat / raw bonus keys", () {
    final def = ItemDefinition(
      id: 'knife', category: 'weapon', tags: {'blade'},
      properties: {'attack': 4},
    );
    final instance = const ItemInstance(
      definitionId: 'knife', owner: EntityId(1), itemClass: 1,
      statBonuses: {'blade': 2, 'initiative': 1},
    );
    final profile = ItemEffectContributor(def, instance).effectProfile();
    expect(profile.tier(EffectTier.supporting), {
      'blade': 6, // 4 (scaled attack, class 1 -> no scaling) + 2 (statBonuses)
      'initiative': 1,
    });
    expect(profile.tier(EffectTier.permanent), isEmpty);
    expect(profile.tier(EffectTier.active), isEmpty);
  });

  test('an item with no attack property and no statBonuses yields an '
      'empty profile', () {
    final def = ItemDefinition(
      id: 'cloth_armor', category: 'armor', tags: const {}, properties: const {},
    );
    final profile = ItemEffectContributor(def, null).effectProfile();
    expect(profile.tier(EffectTier.supporting), isEmpty);
  });

  test('itemClass scaling is reflected in the profile, matching '
      'scaledProperties', () {
    final def = ItemDefinition(
      id: 'sword', category: 'weapon', tags: {'blade'},
      properties: {'attack': 10}, classScalingPercent: 20,
    );
    final instance = const ItemInstance(
        definitionId: 'sword', owner: EntityId(1), itemClass: 3);
    final profile = ItemEffectContributor(def, instance).effectProfile();
    // 10 * (1 + 0.20 * (3-1)) = 14
    expect(profile.amount(EffectTier.supporting, 'blade'), 14);
  });

  test('a null instance (legacy placement) still yields the definition-only '
      'part of the profile — attack scales at class 1', () {
    final def = ItemDefinition(
      id: 'knife', category: 'weapon', tags: {'blade'}, properties: {'attack': 4},
    );
    final profile = ItemEffectContributor(def, null).effectProfile();
    expect(profile.amount(EffectTier.supporting, 'blade'), 4);
  });
}
```

- [ ] **Step 2: Run — expect FAIL**

Run: `dart test test/plugins/item/item_effect_contributor_test.dart`
Expected: `ItemEffectContributor` undefined.

- [ ] **Step 3: Implement `ItemEffectContributor`**

Create `lib/src/plugins/item/item_effect_contributor.dart`:

```dart
import 'package:build_engine/build_engine.dart';

import 'item_definition.dart';
import 'item_instance.dart';

/// [ItemDefinition] + optional [ItemInstance] as one `EffectContributor`
/// — an item needs both content-level state (scaled `attack`, its combat
/// stat tag) and per-copy state (`itemClass`, `statBonuses`) to compose
/// its profile, and neither type alone can see both, so this is a thin
/// composing wrapper rather than either type implementing the interface
/// directly. [instance] is `null` for a legacy null-`instanceEntityId`
/// placement — scaling then falls back to class 1 (today's own fallback,
/// `itemClass ?? 1`), and `statBonuses` contributes nothing (there is no
/// copy to read them from).
///
/// Everything an item currently contributes is `supporting` — counted
/// while hung, nothing yet while merely owned or specifically "used"
/// (this migration is representation-only; see spec §5).
class ItemEffectContributor implements EffectContributor {
  const ItemEffectContributor(this.definition, this.instance);

  final ItemDefinition definition;
  final ItemInstance? instance;

  @override
  EffectProfile effectProfile() {
    final itemClass = instance?.itemClass ?? 1;
    final supporting = <String, num>{};

    final attack = definition.scaledProperties(itemClass)['attack'];
    if (attack != null) {
      final stat = _statFor(definition);
      supporting[stat] = (supporting[stat] ?? 0) + attack;
    }

    instance?.statBonuses.forEach((stat, value) {
      supporting[stat] = (supporting[stat] ?? 0) + value;
    });

    if (supporting.isEmpty) return EffectProfile.empty;
    return EffectProfile.of({EffectTier.supporting: supporting});
  }

  String _statFor(ItemDefinition item) =>
      WeaponStatTags.matchOrFallback(item.tags, 'item:${item.id}');
}
```

(`WeaponStatTags` lives in `lib/src/plugins/build_interpretation/weapon_stat_tags.dart` — check whether `lib/src/plugins/item/` importing it creates a layering problem: `build_interpretation` already imports `item_plugin`, so `item` importing `build_interpretation` back would be circular. **Do not create that cycle.** Instead move `WeaponStatTags` down into a location both `item` and `build_interpretation` can import without a cycle — the cleanest fix is relocating `weapon_stat_tags.dart` from `lib/src/plugins/build_interpretation/` to `lib/src/plugins/item/` itself (it's already shared "shared vocabulary, not shared import" content per its own doc comment, and `TechniqueActionInterpreter` — which lives in `build_interpretation` — can still reach it via a plain import of `item_plugin.dart`'s barrel, since `technique_action_interpreter.dart` already imports that barrel today for other reasons — verify, and export `weapon_stat_tags.dart` from `lib/item_plugin.dart`'s barrel). Read both files' current imports before deciding; report which approach you took and why in your task report.)

- [ ] **Step 4: Run — expect PASS**

Run: `dart test test/plugins/item/item_effect_contributor_test.dart`
Expected: PASS.

- [ ] **Step 5: Migrate `ItemActionInterpreter`**

Read the current file (post-Task-4, `build: ResolvedBuild`). Replace the per-ref direct-modifier body with:

```dart
class ItemActionInterpreter implements BuildActionInterpreter {
  const ItemActionInterpreter();

  @override
  List<CombatAction> interpret({
    required ResolvedBuild build,
    required EntityId actor,
    required List<EntityId> targets,
    required PluginContext context,
  }) {
    EffectProfile profileFor(BuildComponentRef ref) {
      if (ref.referenceType != itemReferenceType) return EffectProfile.empty;
      final definition = context.content.find(ref.contentId);
      if (definition == null) return EffectProfile.empty;
      final item = itemDefinitionFromContent(definition);
      final instance = ref.instanceEntityId == null
          ? null
          : context.components.get<ItemInstance>(ref.instanceEntityId!);
      return ItemEffectContributor(item, instance).effectProfile();
    }

    final ownedItemRefs = [for (final r in build.owned) if (r.referenceType == itemReferenceType) r];
    final activeItemRefs = [for (final r in build.active) if (r.referenceType == itemReferenceType) r];
    final ownedProfiles = [for (final r in ownedItemRefs) profileFor(r)];
    final activeProfiles = [for (final r in activeItemRefs) profileFor(r)];

    final stats = <String>{
      for (final p in ownedProfiles) ...p.tier(EffectTier.permanent).keys,
      for (final p in ownedProfiles) ...p.tier(EffectTier.supporting).keys,
    };
    const resolver = EffectProfileResolver();
    for (final stat in stats) {
      final value = resolver.resolve(owned: ownedProfiles, hung: activeProfiles, stat: stat);
      final source = ModifierSource('effectprofile:item:$stat');
      context.modifiers.removeBySource(source);
      context.modifiers.add(Modifier(
        source: source, target: actor, stat: stat,
        operation: ModifierOperation.add, value: value,
      ));
    }
    return const [];
  }
}
```

Delete the old `_statFor` private (now lives in `ItemEffectContributor`), the old per-`statBonuses` loop, and the old direct `attack`/`_statFor` block — nothing in this file should reference `statBonuses` or a bare `attack` property lookup any more. Update the class doc comment to describe the new one-modifier-per-stat, `ResolvedBuild`-driven flow instead of the old per-item-ref direct modifier.

- [ ] **Step 6: Update `item_action_interpreter_test.dart`**

Read the current file. Update every test's `ActiveBuild`/(post-Task-4) `ResolvedBuild` construction to include the item as both `owned` and `active` where the old test hung it, and `owned`-only where the old test wanted to prove "not hung -> no modifier" (that assertion's *meaning* changes: under the new supporting-only-while-hung model, an owned-but-unhung item still contributes **0** to `supporting` — same outcome as before, now via a different mechanism — assert `context.modifiers.activeModifiersFor(...)` is empty/zero exactly as the old test did). Update modifier-source assertions from `'build:<id>:<actor>'`/`'affix:<instance>:<stat>'` to `'effectprofile:item:<stat>'`.

- [ ] **Step 7: Run — expect PASS, then full regression**

Run: `dart test test/plugins/item/ test/plugins/build_interpretation/`
Expected: PASS.

Run: `dart test` (full suite), `dart analyze`
Expected: green/clean. If `test/integration/item_combine_end_to_end_test.dart` or `item_end_to_end_test.dart` assert on the OLD modifier source strings (`'build:'`/`'affix:'`), update those specific assertions the same way, with a one-line comment noting the source-string change is intentional (spec §9's "one path instead of two").

- [ ] **Step 8: Commit**

```bash
git add lib/src/plugins/item/item_effect_contributor.dart lib/src/plugins/build_interpretation/item_action_interpreter.dart test/plugins/item/ test/plugins/build_interpretation/item_action_interpreter_test.dart
git commit -m "feat(item): ItemEffectContributor + migrate ItemActionInterpreter off affix:*

Item's scaled attack and per-copy statBonuses both fold into the
supporting tier now. One effectprofile:item:<stat> modifier per stat,
summed via EffectProfileResolver over owned+hung item refs, replaces the
old per-ref 'build:'/'affix:' modifiers. Same combat numbers, one path.
<trailer>"
```

---

### Task 7: Technique `EffectContributor` + migrate `TechniqueActionInterpreter`

**Files:**
- Modify: `lib/src/plugins/technique/technique_variant.dart` (`TechniqueVariant implements EffectContributor`)
- Modify: `lib/src/plugins/build_interpretation/technique_action_interpreter.dart`
- Modify: `test/plugins/technique/technique_variant_test.dart` (add `effectProfile()` coverage)
- Modify: `test/plugins/build_interpretation/technique_action_interpreter_variant_test.dart` (SP1's own test — update to the new mechanism, same outcomes)

**Interfaces:**
- Consumes: `EffectProfile`, `EffectTier`, `EffectContributor` (Task 1).
- Produces: `class TechniqueVariant implements EffectContributor { ...; @override EffectProfile effectProfile(); }` — maps `axisProfile['power']` to `EffectTier.active`, keyed by the technique family's own combat stat (the same `damageStat` `TechniqueActionInterpreter` already derives via `WeaponStatTags.matchOrFallback`/`techniqueSubject`). `TechniqueActionInterpreter._actionFor` stops reading `variant.axisProfile` directly; it reads `variant.effectProfile().amount(EffectTier.active, damageStat)` instead, same floor-at-1 clamp.

**Context:** This is the direct generalization of the SP1 (TechniqueVariant-first game run) power-fold. Per the resolved decision (2026-09-05), it **replaces** that ad hoc read, it does not run alongside it. `TechniqueVariant` needs to know its own `damageStat` to build the profile — but `damageStat` is derived from the base family's *tags* (`WeaponStatTags.matchOrFallback(technique.tags, techniqueSubject(technique.id))`), which lives on `TechniqueDefinition`, not `TechniqueVariant` itself. `TechniqueVariant.effectProfile()` cannot take a `TechniqueDefinition` parameter (the interface has zero parameters — `EffectProfile effectProfile()`), so the damage-stat key must be resolved by the **caller** (the interpreter, which already has both the definition and the variant) rather than baked into the profile by `TechniqueVariant` itself. Two ways to reconcile this without changing the `EffectContributor` interface:

1. `TechniqueVariant.effectProfile()` keys its `active` contribution by a **fixed, generic key** (e.g. `'power'`) rather than the family-specific `damageStat`, and the interpreter reads `variant.effectProfile().amount(EffectTier.active, 'power')` then applies it to whatever `damageStat` it already computed — the profile describes "how much power this variant contributes," not "how much of stat X"; the interpreter still owns translating that into the actual combat stat.
2. Widen `TechniqueVariant` with a small non-interface helper that takes the definition and does the stat-keyed mapping, called by the interpreter instead of the bare `effectProfile()`.

**Decision: use (1).** It keeps `EffectContributor`'s contract genuinely parameterless (matching Item's own contributor, which needs no external input either since `ItemDefinition`'s tags are enough to self-derive its stat key) and keeps `axisProfile`'s `'power'` key as the one vocabulary word both the profile and the interpreter agree on — no interface change, no second contributor-like helper type.

- [ ] **Step 1: Write the failing tests**

Add to `test/plugins/technique/technique_variant_test.dart` (read the current file first to match its existing construction/import style):

```dart
  group('effectProfile (EffectContributor)', () {
    test('axisProfile power maps to the active tier under the "power" key', () {
      const variant = TechniqueVariant(
        owner: EntityId(1), baseFamilyId: 'basic_punch',
        descriptorIds: {'strong'}, axisProfile: {'power': 4, 'speed': -1},
      );
      final profile = variant.effectProfile();
      expect(profile.amount(EffectTier.active, 'power'), 4);
      expect(profile.tier(EffectTier.permanent), isEmpty);
      expect(profile.tier(EffectTier.supporting), isEmpty);
    });

    test('no power axis -> active tier empty (not a missing-key crash)', () {
      const variant = TechniqueVariant(
        owner: EntityId(1), baseFamilyId: 'basic_guard',
        descriptorIds: {}, axisProfile: {},
      );
      expect(variant.effectProfile().amount(EffectTier.active, 'power'), 0);
    });

    test('other axes (speed/precision/endurance) are not surfaced by '
        'effectProfile — SP1 (tiered effects) introduces no new stat keys',
        () {
      const variant = TechniqueVariant(
        owner: EntityId(1), baseFamilyId: 'basic_kick',
        descriptorIds: {}, axisProfile: {'speed': 5, 'precision': 3},
      );
      final profile = variant.effectProfile();
      expect(profile.tier(EffectTier.active), {}); // no 'power' key present at all
    });
  });
```

- [ ] **Step 2: Run — expect FAIL**

Run: `dart test test/plugins/technique/technique_variant_test.dart`
Expected: `TechniqueVariant` doesn't implement `EffectContributor` / no `effectProfile()` method.

- [ ] **Step 3: Implement**

In `lib/src/plugins/technique/technique_variant.dart`, add the interface and method:

```dart
class TechniqueVariant implements EffectContributor {
  const TechniqueVariant({
    required this.owner,
    required this.baseFamilyId,
    required this.descriptorIds,
    required this.axisProfile,
    this.styleId,
  });

  // ...existing fields unchanged...

  /// This variant's tiered contribution. SP1 (tiered effects) maps only
  /// the `power` axis, to the `active` tier, under the generic `'power'`
  /// key — the caller (`TechniqueActionInterpreter`) already knows which
  /// concrete combat stat (`damageStat`) that power applies to; this
  /// profile deliberately doesn't guess it, keeping `EffectContributor`
  /// parameterless. `speed`/`precision`/`endurance` are not surfaced —
  /// no new stat keys in this migration (spec §14.2).
  @override
  EffectProfile effectProfile() {
    final power = axisProfile['power'];
    if (power == null || power == 0) return EffectProfile.empty;
    return EffectProfile.of({
      EffectTier.active: {'power': power},
    });
  }
}
```

(`EffectContributor`/`EffectProfile`/`EffectTier` come from `package:build_engine/build_engine.dart`, already imported at the top of this file.)

- [ ] **Step 4: Run — expect PASS**

Run: `dart test test/plugins/technique/technique_variant_test.dart`
Expected: PASS.

- [ ] **Step 5: Migrate `TechniqueActionInterpreter`**

Read the current `_actionFor` (post-SP1, post-Task-4-signature-change). Replace:

```dart
    final power = variant?.axisProfile['power'] ?? 0;
    final folded = base + power;
    final damage = folded < 1 ? 1 : folded;
```
with:
```dart
    final power = variant?.effectProfile().amount(EffectTier.active, 'power') ?? 0;
    final folded = base + power;
    final damage = folded < 1 ? 1 : folded;
```

This is the **entire** behavioural change in this file for this task — same numbers, one fewer direct `axisProfile` read. Update `interpret()`'s signature (if Task 4 left a stray `ActiveBuild` reference — it shouldn't, verify) and the class doc comment's mention of "SP1 power fold" to note it now flows through `EffectProfile`/`EffectTier.active`.

Also verify: does this file need `build.owned` for anything yet (a standing per-stat technique modifier, mirroring Item's Task 6)? **No** — per §5 of the validated spec, "nothing an item declares is active yet; nothing is permanent yet" mirrors technique too: today's `TechniqueVariant.effectProfile()` only ever populates `active`, never `permanent`/`supporting`, so there is nothing for a standing modifier to sum (Item needed one because `statBonuses`/scaled `attack` are genuinely `supporting`; Technique has no such source yet). Do not add a standing per-stat modifier for techniques in this task — there is nothing to add it for, and inventing one would be exactly the kind of unrequested future-tier speculation the spec forbids (§2.2, §3).

- [ ] **Step 6: Update `technique_action_interpreter_variant_test.dart`**

This is SP1's own test file (Task 2 of the *other* SP1). Read it — its existing tests construct a `TechniqueVariant` with a given `axisProfile['power']` and assert `AttackAction.baseDamage`. Those assertions' **outcomes** are unchanged (same numbers); only internal mechanism moved. No test body should need to change unless one directly inspects `variant.axisProfile` as part of its own assertion (unlikely — re-check by running first).

- [ ] **Step 7: Run — expect PASS, then full regression**

Run: `dart test test/plugins/technique/ test/plugins/build_interpretation/`
Expected: PASS, identical outcomes to before this task.

Run: `dart test`, `dart analyze`
Expected: full suite green, clean.

- [ ] **Step 8: Verify the "one path" invariant**

Run:
```bash
grep -rn "axisProfile\['power'\]" lib/
```
Expected: exactly one hit, inside `technique_variant.dart`'s own `effectProfile()` (the authorized source-data read). Zero hits in `lib/src/plugins/build_interpretation/`.

- [ ] **Step 9: Commit**

```bash
git add lib/src/plugins/technique/technique_variant.dart lib/src/plugins/build_interpretation/technique_action_interpreter.dart test/plugins/technique/technique_variant_test.dart test/plugins/build_interpretation/technique_action_interpreter_variant_test.dart
git commit -m "feat(technique): TechniqueVariant is an EffectContributor; interpreter reads it

axisProfile['power'] -> EffectTier.active under the generic 'power' key.
TechniqueActionInterpreter no longer reads variant.axisProfile directly
— replaces the SP1 (TechniqueVariant-first game run) ad hoc fold, per
the 2026-09-05 resolved decision. Identical combat numbers.
<trailer>"
```

---

### Task 8: Migration parity + double-counting scenario tests

**Files:**
- Create: `test/integration/effect_profile_migration_parity_test.dart`
- Create: `test/integration/effect_profile_double_counting_test.dart`

**Interfaces:** none new — this task only adds tests proving Tasks 6-7's consolidation is numerically exact and that no scenario double-counts.

**Context:** Per spec §11.3/§11.4 and the brief's Steps 12/14. Uses real combat setup (a real `PluginContext`, real `CombatPlugin`, real interpreters), not mocks.

- [ ] **Step 1: Migration parity — same numbers, old path vs. new path**

Create `test/integration/effect_profile_migration_parity_test.dart`:

```dart
/// Proves Task 6/7's consolidation changed no combat number: an item
/// with a scaled attack + a statBonuses affix, hung and used in a real
/// attack, resolves to the exact same final damage this repo's own
/// pre-migration numbers would have produced (computed by hand from the
/// same inputs, not by re-deriving the old code path).
import 'package:build_engine/build_engine.dart';
import 'package:build_engine/build_interpretation.dart';
import 'package:build_engine/combat_plugin.dart';
import 'package:build_engine/item_plugin.dart';
import 'package:test/test.dart';

PluginContext _ctx() {
  final events = EventBus();
  final entities = EntityRegistry(events);
  final components = ComponentStore();
  final rng = RngService(1);
  final shared = CoreServices(components: components, events: events);
  final c = PluginContext(
    entities: entities, components: components, events: events, rng: rng,
    rules: RuleEngine(
      entities: entities, components: components, events: events,
      rng: rng, shared: shared),
    queries: QueryEngine(QueryScope(components: components)),
    modifiers: ModifierCollection(),
    content: ContentRegistry(),
    shared: shared,
  );
  ItemPlugin().initialize(c);
  return c;
}

void main() {
  test('a hung, affixed item folds attack + statBonuses into one modifier '
      'equal to their hand-computed sum', () {
    final ctx = _ctx();
    final owner = ctx.entities.create();
    final knife = itemDefinition(ItemIds.knife, ctx); // scaled 'attack' at class 1
    final instanceId = ownItem(owner, knife.id, ctx);
    // Give this specific copy an affix bonus on the same stat the knife's
    // own scaled attack already targets.
    final tags = knife.tags;
    final stat = WeaponStatTags.matchOrFallback(tags, 'item:${knife.id}');
    ctx.components.add<ItemInstance>(instanceId, ItemInstance(
      definitionId: knife.id, owner: owner, itemClass: 1,
      statBonuses: {stat: 3},
    ));

    ctx.tome.defineTome(TomeDefinition.namedSlots(id: 't', slotIds: ['s0']));
    ctx.tome.createTome(owner, 't');
    ctx.tome.insert(owner, const SlotId('s0'),
        BuildComponentRef(referenceType: itemReferenceType, contentId: knife.id,
            instanceEntityId: instanceId));

    const interp = ItemActionInterpreter();
    final build = ctx.tome.resolve(owner, ownedRefs: [
      BuildComponentRef(referenceType: itemReferenceType, contentId: knife.id,
          instanceEntityId: instanceId),
    ]);
    interp.interpret(build: build, actor: owner, targets: const [], context: ctx);

    final expected = knife.scaledProperties(1)['attack']! + 3; // hand-computed
    final resolved = const ModifierResolver().resolve(
      0, ctx.modifiers.activeModifiersFor(owner, stat, ctx.components),
    );
    expect(resolved, expected);
  });
}
```

- [ ] **Step 2: Double-counting scenarios A-E**

Create `test/integration/effect_profile_double_counting_test.dart` covering exactly the 5 scenarios from the brief, using the real `CombatStage`/`TrainingStage`-free minimal harness (`PluginContext` + `ItemPlugin`/`TechniquePlugin` + the two interpreters), one `test(...)` per scenario:

```dart
import 'package:build_engine/build_engine.dart';
import 'package:build_engine/build_interpretation.dart';
import 'package:build_engine/combat_plugin.dart';
import 'package:build_engine/item_plugin.dart';
import 'package:build_engine/technique_plugin.dart';
import 'package:test/test.dart';

PluginContext _ctx() {
  final events = EventBus();
  final entities = EntityRegistry(events);
  final components = ComponentStore();
  final rng = RngService(1);
  final shared = CoreServices(components: components, events: events);
  final c = PluginContext(
    entities: entities, components: components, events: events, rng: rng,
    rules: RuleEngine(
      entities: entities, components: components, events: events,
      rng: rng, shared: shared),
    queries: QueryEngine(QueryScope(components: components)),
    modifiers: ModifierCollection(),
    content: ContentRegistry(),
    shared: shared,
  );
  ItemPlugin().initialize(c);
  TechniquePlugin().initialize(c);
  return c;
}

num _stat(PluginContext ctx, EntityId owner, String stat) => const ModifierResolver()
    .resolve(0, ctx.modifiers.activeModifiersFor(owner, stat, ctx.components));

void main() {
  test('Scenario A — a loose (owned, unhung) item: supporting does not count',
      () {
    final ctx = _ctx();
    final owner = ctx.entities.create();
    final knife = itemDefinition(ItemIds.knife, ctx);
    final instanceId = ownItem(owner, knife.id, ctx);
    ctx.tome.defineTome(TomeDefinition.namedSlots(id: 't', slotIds: ['s0']));
    ctx.tome.createTome(owner, 't');
    // NOT inserted into the Tome — stays loose.
    const interp = ItemActionInterpreter();
    final build = ctx.tome.resolve(owner, ownedRefs: [
      BuildComponentRef(referenceType: itemReferenceType, contentId: knife.id,
          instanceEntityId: instanceId),
    ]);
    interp.interpret(build: build, actor: owner, targets: const [], context: ctx);
    final stat = WeaponStatTags.matchOrFallback(knife.tags, 'item:${knife.id}');
    expect(_stat(ctx, owner, stat), 0);
  });

  test('Scenario B — a hung item: supporting counts', () {
    final ctx = _ctx();
    final owner = ctx.entities.create();
    final knife = itemDefinition(ItemIds.knife, ctx);
    final instanceId = ownItem(owner, knife.id, ctx);
    ctx.tome.defineTome(TomeDefinition.namedSlots(id: 't', slotIds: ['s0']));
    ctx.tome.createTome(owner, 't');
    ctx.tome.insert(owner, const SlotId('s0'),
        BuildComponentRef(referenceType: itemReferenceType, contentId: knife.id,
            instanceEntityId: instanceId));
    const interp = ItemActionInterpreter();
    final build = ctx.tome.resolve(owner, ownedRefs: [
      BuildComponentRef(referenceType: itemReferenceType, contentId: knife.id,
          instanceEntityId: instanceId),
    ]);
    interp.interpret(build: build, actor: owner, targets: const [], context: ctx);
    final stat = WeaponStatTags.matchOrFallback(knife.tags, 'item:${knife.id}');
    expect(_stat(ctx, owner, stat), greaterThan(0));
  });

  test('Scenario C — a loose technique variant: neither supporting nor '
      'active counts (nothing hung, nothing acted)', () {
    final ctx = _ctx();
    final owner = ctx.entities.create();
    final instanceId = mintTechniqueVariant(owner, 'basic_punch', {'strong'}, ctx);
    // Not hung; no AttackAction built from it.
    expect(
      requireTechniqueVariant(instanceId, ctx).effectProfile().tier(EffectTier.supporting),
      isEmpty,
    );
  });

  test('Scenario D — a hung, used technique variant: active folds into '
      "this action's own baseDamage", () {
    final ctx = _ctx();
    final owner = ctx.entities.create();
    final instanceId = mintVariantForLegacyEvolvedId(owner, 'heavy_punch', ctx);
    final ref = BuildComponentRef(
        referenceType: techniqueReferenceType, contentId: 'basic_punch',
        instanceEntityId: instanceId);
    const interp = TechniqueActionInterpreter();
    final build = ResolvedBuild(owner: owner, active: [ref], owned: [ref]);
    final actions = interp.interpret(
        build: build, actor: owner, targets: [const EntityId(999)], context: ctx);
    final variant = requireTechniqueVariant(instanceId, ctx);
    final power = variant.effectProfile().amount(EffectTier.active, 'power');
    expect((actions.single as AttackAction).baseDamage,
        techniqueDefinition('basic_punch', ctx).properties['damage']! + power);
  });

  test('Scenario E — two variants of the same family stay distinct: one '
      "variant's active power never leaks into the other's action", () {
    final ctx = _ctx();
    final owner = ctx.entities.create();
    final strong = mintVariantForLegacyEvolvedId(owner, 'heavy_punch', ctx); // +power
    final base = mintTechniqueVariant(owner, 'basic_punch', const {}, ctx); // +0 power
    const interp = TechniqueActionInterpreter();

    final strongRef = BuildComponentRef(
        referenceType: techniqueReferenceType, contentId: 'basic_punch',
        instanceEntityId: strong);
    final baseRef = BuildComponentRef(
        referenceType: techniqueReferenceType, contentId: 'basic_punch',
        instanceEntityId: base);

    final strongAction = interp.interpret(
      build: ResolvedBuild(owner: owner, active: [strongRef], owned: [strongRef, baseRef]),
      actor: owner, targets: [const EntityId(999)], context: ctx,
    ).single as AttackAction;
    final baseAction = interp.interpret(
      build: ResolvedBuild(owner: owner, active: [baseRef], owned: [strongRef, baseRef]),
      actor: owner, targets: [const EntityId(999)], context: ctx,
    ).single as AttackAction;

    expect(strongAction.baseDamage, greaterThan(baseAction.baseDamage));
  });
}
```

(`requireTechniqueVariant` is already exported from `technique_plugin.dart`, per SP1.)

- [ ] **Step 3: Run — expect PASS**

Run: `dart test test/integration/effect_profile_migration_parity_test.dart test/integration/effect_profile_double_counting_test.dart`
Expected: PASS.

- [ ] **Step 4: Full regression**

Run: `dart test`, `dart analyze`
Expected: full suite green, clean.

- [ ] **Step 5: Commit**

```bash
git add test/integration/effect_profile_migration_parity_test.dart test/integration/effect_profile_double_counting_test.dart
git commit -m "test(effect-profile): migration parity + double-counting scenarios A-E
<trailer>"
```

---

### Task 9: Docs + architecture-dependency guard

**Files:**
- Modify: `CHANGELOG.md`
- Modify: `ARCHITECTURE.md`
- Modify: `test/integration/architecture_dependency_test.dart`

**Interfaces:** none new.

**Context:** Document the new public surface; add the one new architecture check the spec's own contract-fit table (§3) implies but no existing test covers: `lib/src/effect_profile/` must import no plugin.

- [ ] **Step 1: `CHANGELOG.md`**

Add an entry (follow the file's existing format/heading style — read it first) noting the additions: `EffectTier`, `EffectProfile`, `EffectContributor`, `EffectProfileResolver`, `ResolvedBuild`; and the migration: `ItemInstance.statBonuses` and `TechniqueVariant.axisProfile['power']` now flow through `EffectProfile` instead of direct `Modifier`/arithmetic.

- [ ] **Step 2: `ARCHITECTURE.md`**

Add a new section "Tiered Component Effects" (follow the file's existing section style/depth) summarizing: the three tiers, `EffectContributor`'s "implement, don't register" pattern, `ResolvedBuild`'s owned/active split and why `active ⊆ owned` by construction, and the one-path principle (no parallel numeric-effect system).

- [ ] **Step 3: Architecture test**

In `test/integration/architecture_dependency_test.dart`, add a new group (following the file's existing `_assertNoPluginImport`/`_assertNoSubstringInDirectory` pattern):

```dart
  group('effect_profile/ is pure Core — no plugin, no vocabulary import', () {
    const pluginBarrels = [
      'combat_plugin.dart', 'item_plugin.dart', 'technique_plugin.dart',
      'martial_arts_plugin.dart', 'elemental_plugin.dart', 'physique_plugin.dart',
      'auto_combat_plugin.dart', 'build_interpretation.dart', 'game.dart',
      'almanac.dart', 'almanac_file.dart',
    ];
    for (final barrel in pluginBarrels) {
      test('effect_profile/ does not reference $barrel', () {
        _assertNoSubstringInDirectory(barrel, 'lib/src/effect_profile');
      });
    }
    test('effect_profile/ does not escape into any plugins/ directory', () {
      _assertNoSubstringInDirectory('plugins/', 'lib/src/effect_profile');
    });
  });
```

(This mirrors group H's existing `coreDirectories` loop — `lib/src/effect_profile` should already be swept by that loop automatically once it exists, since group H enumerates every `lib/src` subdirectory except `plugins`; verify by running the test BEFORE adding the new explicit group — if group H already covers it, the explicit group above is redundant defence-in-depth, not strictly required, but keep it for a directory-specific failure message. Confirm and note which in your report.)

- [ ] **Step 4: Run**

Run: `dart test test/integration/architecture_dependency_test.dart`
Expected: PASS, including the new group.

- [ ] **Step 5: Commit**

```bash
git add CHANGELOG.md ARCHITECTURE.md test/integration/architecture_dependency_test.dart
git commit -m "docs(effect-profile): CHANGELOG/ARCHITECTURE + explicit dependency guard
<trailer>"
```

---

### Task 10: Full regression + final gate

**Files:** none (verification only).

- [ ] **Step 1: Full suite + analyze**

```bash
dart analyze
dart test
```
Expected: 0 issues, 100% green.

- [ ] **Step 2: Architecture/dependency suite explicitly**

```bash
dart test test/integration/architecture_dependency_test.dart
```
Expected: green.

- [ ] **Step 3: One-path verification**

```bash
grep -rn "affix:" lib/
grep -rn "axisProfile\['power'\]" lib/
```
Expected: `affix:` → zero hits anywhere in `lib/` (the old modifier-source string is gone). `axisProfile['power']` → exactly one hit, in `technique_variant.dart`'s own `effectProfile()`.

- [ ] **Step 4: Core-without-content + cross-plugin suites**

```bash
dart test test/integration/core_boots_without_plugins_test.dart test/integration/cross_plugin_synergy_test.dart
```
Expected: green, unaffected by this migration.

- [ ] **Step 5: Commit (if Step 1-4 required any fix)**

If everything was already green, no commit needed for this task — it's a verification gate. If a fix was required, commit it with a message explaining exactly what regression was found and why the fix is correct (never a compatibility branch).

---

## Self-Review

**1. Spec coverage**

| Spec / brief section | Task |
|---|---|
| §4 core primitive (`EffectTier`/`EffectProfile`/`EffectProfileResolver`) | 1 |
| §5 `EffectContributor` template | 1, 6, 7 |
| §6 owned set / `ResolvedBuild` / `active ⊆ owned` by construction | 2, 3 |
| §7 combat integration (`sourceRef`, not `sourceProfile` — §15.2) | 7 (the fold already lives in the interpreter, unchanged mechanism, just re-sourced) |
| §9 `ItemInstance.statBonuses` migration, one path | 6 |
| §10 error handling (empty profile, unknown key, negative amounts) | 1 |
| §11 testing (core, BuildResolver, plugins, migration parity, integration) | 1, 2, 6, 7, 8 |
| §12 files | all — see File Structure table |
| §15.1 naming corrections (real types, not `MartialItemDefinition`/`MartialTechniqueDefinition`) | 6, 7 |
| §15.2 `sourceRef` not `sourceProfile` | 7 (no `combat_action.dart` change needed — confirmed in Task 7's audit) |
| §15.3 the `active` tier replaces, not runs alongside, SP1's power-fold | 7 |
| Brief step 4 (item Tome placement instance identity) | 5 |
| Brief step 13 (architecture validation) | 9, 10 |
| Brief step 14 (scenarios A-E) | 8 |
| Brief step 15 (determinism) | 1 (resolver determinism test), 8 (no RNG anywhere in new code — verified by inspection: no file in Tasks 1-9 imports `RngService`) |
| Brief step 16 (full validation) | 10 |

**2. Placeholder scan:** no TBD/TODO. Task 6 Step 3 and Task 3 Step 4 both flag a genuine open implementation choice (avoiding an import cycle) with a concrete instruction ("read both files' current imports before deciding; report which approach you took") rather than leaving it unspecified — this is a real judgment call the implementer resolves from real files, not a placeholder.

**3. Type consistency:** `ResolvedBuild{owner, active, owned, asActiveBuild}` — same shape used in Tasks 2, 3, 4, 8. `EffectProfile.of`/`EffectProfile.empty`/`.tier()`/`.amount()`/`.merge()` — same signatures used in Tasks 1, 6, 7, 8. `BuildActionInterpreter.interpret({required ResolvedBuild build, ...})` — consistent across Tasks 4, 6, 7, 8. `ItemEffectContributor(definition, instance)` and `TechniqueVariant.effectProfile()` — no signature drift between where they're defined (Tasks 6, 7) and where they're consumed (Task 6 Step 5, Task 7 Step 5, Task 8).
