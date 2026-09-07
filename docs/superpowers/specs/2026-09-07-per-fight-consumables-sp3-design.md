# SP3 — Per-fight limited-use consumables

**Status:** design, pending review
**Date:** 2026-09-07
**Depends on:** `2026-09-02-tiered-component-effects-design.md` (parent decomposition, §1.2 row **SP3**), which depends on SP1 "Tiered Component Effects" (merged). Independent of SP2 "Per-active auras" (merged) — no shared surface beyond the pattern.

---

## 1. Problem

The parent design (`2026-09-02-tiered-component-effects-design.md` §1.2, §13)
carves out SP3: *"Consumables / potions — new reference type, consume-on-use
lifecycle, auto-combat trigger story."* Its §13 sketch assumed a true
potion: *"New `referenceType: 'consumable'`, an `onUse` that removes the ref
after the action, and an auto-combat rule for when the action selector
fires it."*

**Brainstorming (2026-09-07) chose a different lifecycle:** a consumable is
a **per-fight limited-use item** — it grants N uses per battle and refreshes
when the next battle begins. It is never removed from the Tome. This makes
"consume" a per-fight resource, not a run-lifetime deletion, and removes the
need for the parent sketch's ref-removal rule entirely.

**Goal:** a hung `consumable` component produces a `CombatAction` the
headless auto-combat can choose to use, limited to N uses per fight, with
the AI choosing *when* to use it by the shape of the effect (heal when hurt,
throw for damage, buff early) — reusing the existing `ConsumeResource` /
`ScoredActionSelector` / `CombatSystem` machinery, with the smallest
possible new Core surface.

## 2. Resolved design decisions

Settled during brainstorming (2026-09-07):

| # | Decision |
|---|----------|
| D1 | New `referenceType: 'consumable'` — a third Tome content category alongside `item` / `technique`. **Diverges from parent §13**: consumables are per-fight charges, refreshed each battle; never removed from the Tome. |
| D2 | Charges are a **per-fight `ResourcePool` resource**. The consumable's `CombatAction` carries `costEffects: [ConsumeResource('consumable:<contentId>', 1)]`. `ScoredActionSelector._isAvailable` already skips actions the actor cannot afford, and `CombatSystem.executeAction` already no-ops an unaffordable cost — so **no `RuleEngine`, no ref removal, no new filtering code**. |
| D3 | Two of the same consumable placed = two Tome cells = **charges summed** for that fight. `ConsumableDefinition.charges` is a **per-copy capacity**; the `consumable:<id>` resource holds the **aggregate**, so its `ResourceDefinition.max` is `double.infinity` — a finite single-copy max would clamp the sum (§5.1.1). |
| D3a | `effect` × `target` compatibility is fixed and **checked at content-parse time**: `heal` / `grantModifier` / `removeAllStatuses` are `self`-only, `attack` is `enemy`-only (§5.1.2). A `ConsumableEffectSpec` has **exactly one** variant, or parsing throws (§5.1.3). |
| D3b | `runFight`'s per-fight setup is **exception-safe as a unit**: every binder call inside one `try`, disposed in reverse order in the `finally` behind nullable locals, so a throw in `ConsumableBinder.grant` after `AuraBinder.bind` still disposes the aura binding (§5.7). |
| D4 | AutoCombat trigger: a new **`ConsumableAwareActionScorer`** that composes `DefaultActionScorer`, then adds `+ K·(1 − actorHpFraction)` per `Heal` effect and `+ buffBonus` per `ApplyStatus` effect found in `action.effectsFor(...)`. Shape-based on Core effect types (`Heal` / `ApplyStatus`), the same category as the base scorer's existing `action is AttackAction` check. No domain vocabulary, no new `CombatAction` field. It applies to **any** heal/buff action, not only consumables. |
| D5 | Two new generic Core primitives, **both `Effect`s**: **`RemoveAllStatuses`** (clears the subject's `StatusComponent`) and **`GrantModifier`** (adds one source-scoped `Modifier` on the subject). To let `GrantModifier` be an `Effect`, **`RuleContext` gains a `modifiers` field** — see §5.4. This is the one place SP3 expands a central Core type; §4 argues it is the natural completion of `RuleContext` (every other core service is already on it), not scope creep. |
| D6 | A consumable contributes **no `EffectProfile` passive tier** in SP3. `ItemActionInterpreter` / `ItemEffectContributor` skip the `consumable` `referenceType`; a future passive consumable just implements `EffectContributor`, no interface change. |

> **Why `GrantModifier` needs `RuleContext.modifiers`.** A modifier grant
> has to reach `ModifierCollection`. Two facts: `Effect.apply` takes a
> `RuleContext`, which today carries every core service *except* the
> Modifier Engine; and nothing in `lib/` ticks `Modifier.duration`
> (lifetime is managed by source-scoped `removeBySource`). The earlier
> "make it a `CombatAction` whose `effectsFor` side-effects" avoids the
> `RuleContext` change but forces `ConsumableAwareActionScorer` — which
> calls `effectsFor` to read effect shape (§5.6) — to either apply the
> buff for free during scoring, or learn concrete `build_interpretation`
> action types (an `auto_combat` → `build_interpretation` up-dependency).
> Adding `modifiers` to `RuleContext` (5 lines, §5.4) keeps `GrantModifier`
> a pure, reusable `Effect`, keeps the scorer trivially safe, and matches
> the brainstorming answer literally. `RuleEngine._fire` keeps constructing
> a `RuleContext` without a real `ModifierCollection` (its default empty
> one) — a rule-dispatched `GrantModifier` writes to an unobserved
> collection; wiring `RuleEngine`'s real one is noted as future work
> (it would also let SP2 auras grant modifiers).

## 3. Scope

### 3.1 In scope

- A new content plugin `lib/src/plugins/consumable/` (`ConsumablePlugin`,
  `ConsumableDefinition`, `ConsumableEffectSpec`, `ConsumableTarget`,
  `consumableContentDefinitions`), mirroring `ItemPlugin`. Owns
  `consumableReferenceType`; `context.resources.define`s the charge
  resources **unbounded above** (§5.1.1); depends only on Core.
- Strict content validation in `consumableDefinitionFromContent`:
  exactly-one-`effect`-variant (§5.1.3) and `effect` × `target`
  compatibility (§5.1.2), both failing at content-parse time.
- A new `ConsumableActionInterpreter` (`BuildActionInterpreter`) in
  `build_interpretation/`, added to `game_run.dart`'s composite.
- A new `ConsumableBinder` / `ConsumableCharges` in `build_interpretation/`
  (sibling of `AuraBinder`): grants per-fight charges from `build.active`,
  clears them + any consumable-sourced `Modifier`s on `dispose()`.
- `RemoveAllStatuses` and `GrantModifier` — two new Core `Effect`s in
  `lib/src/rule/effect.dart`, plus a `modifiers` field on `RuleContext`
  (and `PluginContextRuleContext.ruleContextFor` passing it) so
  `GrantModifier` can reach the Modifier Engine.
- `ConsumableAwareActionScorer` in `lib/src/plugins/auto_combat/`.
- `CombatStage.runFight` wiring: an **exception-safe** per-fight setup
  (§5.7) that binds auras + consumable charges inside one `try` and
  disposes both (reverse order) in the `finally`; use the new scorer in
  `CombatPolicy.scored`. This also closes SP2's logged deferred minor
  about `auraBinding` being created before its `try`.
- Run content: `rewardPoolConsumableIds`, a `consumable` case in
  `RewardStage.resolveReward`, `TomeManager.placeConsumable` (mirrors
  `placeItem`).
- A 5-consumable content pass: `heal_potion`, `firebomb`, `power_tonic`,
  `swift_draught`, `cleanse_tonic`.
- Tests (see §9).

### 3.2 Explicitly out of scope

- Removing a consumable from the Tome on use, or any run-lifetime
  consume/deplete lifecycle. Charges are per-fight only.
- A `consumable` `EffectProfile` passive tier (D6).
- Any `RuleEngine` change; any `Rule` change; any `RuleContext` change
  **beyond adding the `modifiers` field** (§5.4). `RuleEngine._fire` is
  not rewired to pass a real `ModifierCollection` — a rule-dispatched
  `GrantModifier` is a documented no-op-into-the-void for now.
- `Modifier.duration` / `ModifierCollection.tick()` — unused in `lib/`
  today; SP3 keeps modifier lifetime managed by source-scoped
  `removeBySource` (`ConsumableCharges.dispose()`), and does not introduce
  ticking.
- `Tome_client` surfacing (reward-affix tiers, detail sheet) — **SP4**.
- Targeting UI / player-chosen consumable use — the headless auto-combat
  is the only consumer in SP3; the client story is SP4.
- Enemy consumables. Only the player's build produces consumable actions
  in SP3 (`CombatStage` interprets `character`'s build; enemies get a bare
  attack).
- Consumable rarity / drop weighting beyond a flat `rewardPoolConsumableIds`
  list.
- `SP2` auras on consumables. A consumable is not an `AuraContributor`.

## 4. Contract fit (`claude.md`)

| Rule | How SP3 complies |
|------|------------------|
| *Core provides verbs; plugins provide nouns.* | New Core surface is two generic `Effect`s — `RemoveAllStatuses` (status-clear) and `GrantModifier` (stat-modifier grant) — and one field (`modifiers`) added to `RuleContext`. "Consumable", "potion", "firebomb", "tonic" live entirely in the `consumable` plugin's content. |
| *`RuleContext` change is completion, not creep.* | `RuleContext` already exposes `resources`, `mastery`, `progression`, `discovery`, `events`, `components`, `rng`, `eventCounts` — every core service *except* the Modifier Engine, which `PluginContext` has held all along. Adding `modifiers` closes that gap so any `Effect` (SP3's `GrantModifier`, a future rule/aura buff) can use it. `ruleContextFor` already holds a `ModifierCollection` to pass; only `RuleEngine._fire`'s path stays on the empty default (documented). |
| *Plugins provide nouns; every feature is a plugin.* | `ConsumablePlugin` is a content plugin depending only on Core — the fourth proof after Elemental / Item / Technique. The interpreter/binder/scorer live in the same bridging layers Item/Technique already use (`build_interpretation/`, `auto_combat/`). |
| *Never introduce speculative abstractions without a concrete use case.* | `RemoveAllStatuses` → `cleanse_tonic`. `GrantModifier` → `power_tonic` + `swift_draught`. The scorer's `Heal` / `ApplyStatus` branches → `heal_potion` + the buff tonics. Every new type has ≥1 immediate content use. |
| *Composition over inheritance.* | The interpreter *composes* existing `CombatAction` types (`SelfEffectAction`, `AttackAction`) carrying the new `Effect`s; the scorer *composes* `DefaultActionScorer`. Nothing extends anything, and no new `CombatAction` subtype is introduced. |
| *Dependencies point downward.* | `consumable/` → Core only. `build_interpretation/` → Core + Combat + Item + Technique + (new) Consumable — it is the layer that already depends on every content plugin. `auto_combat/` → Core + Combat. Combat unchanged. |
| *Determinism.* | No new randomness. `ConsumeResource`, `ResourcePool`, `ModifierResolver` are pure. The scorer reads `HealthComponent` / the Modifier Engine, both deterministic. A run stays reproducible from seed + decisions. |

## 5. Design

### 5.1 `consumable` plugin (`lib/src/plugins/consumable/`)

Mirrors `ItemPlugin` (`item_plugin.dart` + `item_definition.dart` +
`item_content.dart` + `item_vocabulary.dart`).

```dart
const consumableReferenceType = 'consumable';

/// The per-fight resource key a consumable's charges live under, on the
/// build owner. One key per content id — every hung copy of the same
/// consumable sums into this one pool.
String consumableChargeResource(String contentId) => 'consumable:$contentId';
```

**`ConsumableDefinition`** — immutable, content-derived, exactly the shape
of `ItemDefinition`:

```dart
class ConsumableDefinition {
  const ConsumableDefinition({
    required this.id,
    required this.tags,
    this.charges = 1,      // PER-COPY charge capacity (see §5.1.1)
    this.priority = 0,
    required this.target,  // resolved by the parser (§5.1.2), never a blanket default
    required this.effect,  // ConsumableEffectSpec — exactly one variant (§5.1.3)
  });
  final String id;
  final Set<String> tags;
  final int charges;
  final num priority;
  final ConsumableTarget target;         // self | enemy — always consistent with `effect`
  final ConsumableEffectSpec effect;
}
```

`target` has **no blanket default** on the value object.
`consumableDefinitionFromContent` sets it: if the content supplies
`target`, it is validated against the effect's legal value (§5.1.2) and a
mismatch throws; if omitted, it is filled with the effect's only legal
value. So a constructed `ConsumableDefinition` is always internally
consistent — the interpreter never has to reconcile `target` against
`effect`.

**`ConsumableEffectSpec`** — a small **closed** sum type the interpreter
maps 1:1 to a `CombatAction`. Exactly one of:

| variant | content JSON | `target` | interpreter builds |
|---|---|---|---|
| `heal(amount)` | `{"heal": 20}` | `self` only | `SelfEffectAction([Heal(20)])` |
| `attack(damage, stat)` | `{"attack": {"damage": 15, "stat": "thrown"}}` | `enemy` only | `AttackAction(baseDamage: 15, damageStat: "thrown")` |
| `grantModifier(stat, operation, value)` | `{"grant": {"stat": "thrown", "op": "add", "value": 6}}` | `self` only | `SelfEffectAction([GrantModifier("thrown", ModifierOperation.add, 6, sourceKey: "consumable:<id>")])` |
| `removeAllStatuses()` | `{"removeAllStatuses": true}` | `self` only | `SelfEffectAction([RemoveAllStatuses()])` |

Closed (not open plugin-registered) because each variant maps to a fixed
`CombatAction` shape the interpreter already knows; a new variant is a
deliberate SP-level change, like `EffectTier`'s fixed enum. Represent it
in Dart however the plan prefers (a sealed class hierarchy or a tagged
value object) — the contract is "parsing yields **exactly one**
`ConsumableEffectSpec`, or throws".

#### 5.1.1 Charge resource semantics (per-copy capacity vs aggregate pool)

- `ConsumableDefinition.charges` is **per-copy charge capacity** — how
  many uses *one* placed copy contributes.
- `consumableChargeResource(id)` names **one** `ResourcePool` value on the
  owner, holding the **aggregate current-fight charges** — the sum over
  every hung copy of that content id.
- Therefore the resource maximum **cannot** be the single-copy `charges`.
  `ConsumablePlugin.initialize` registers it **unbounded above**:

  ```dart
  context.resources.define(ResourceDefinition(
    id: consumableChargeResource(id),
    min: 0,
    max: double.infinity,
  ));
  ```

  Rationale: `ResourcePool.set` clamps to `[min, max]`. A finite
  single-copy `max` would clamp the aggregate back down, silently
  discarding the charges of every copy after the first.
- The authoritative aggregate write is `ConsumableBinder.grant()`'s
  `resources.set(owner, key, Σcharges)` at fight start (§5.5).
  `ConsumableCharges.dispose()` `set`s it back to `0` at fight end.
- Tome placement is what determines the aggregate — one Tome cell per
  copy. A hard cap on simultaneous copies, if ever wanted, is a
  placement / content-policy concern, **not** this resource definition.

Invariant (`heal_potion`, `charges: 1`):

```
1 hung heal_potion ref  → pool = 1
2 hung heal_potion refs  → pool = 2
3 hung heal_potion refs  → pool = 3
```

`ResourcePool.set` must not clamp these aggregate values back to `1`.
(`define` gives `min: 0`, `max: double.infinity` — `set` is then a pure
assignment for any non-negative aggregate.)

#### 5.1.2 Valid `target` / `effect` combinations

`ConsumableTarget` is `{ self, enemy }`. Only these pairings are legal —
any other pairing **throws during content parsing / definition
construction**, never silently retargets at interpretation time:

| `effect` | `self` | `enemy` |
|---|---|---|
| `heal` | valid | **invalid** |
| `grantModifier` | valid | **invalid** |
| `removeAllStatuses` | valid | **invalid** |
| `attack` | **invalid** | valid |

So in SP3: `heal` / `grantModifier` / `removeAllStatuses` are **self
only**; `attack` is **enemy only**. `target` may be omitted in content
and defaults to the effect's only legal value (the plan may make
`target` implicit rather than a required-and-checked field — either is
fine as long as an explicit contradictory `target` is rejected).

`consumableDefinitionFromContent` performs this check — see §5.1.3 for the
concrete exception types.

#### 5.1.3 Malformed / ambiguous `ConsumableEffectSpec` — and the exception contract

Parsing the `effect` object (or its absence) into a `ConsumableEffectSpec`,
and checking `target` against §5.1.2, is strict. Every one of these is a
**content-validation error**, not a best-effort parse:

- **Zero recognized variants.** `effect` absent, `{}`, or an object with
  only unknown keys.
- **More than one recognized variant.** e.g. `{"heal": 20, "attack": {…}}`.
  No "first key wins", no precedence.
- **Unknown keys** anywhere in the `effect` object (alongside a valid
  variant or alone).
- **Malformed nested object.** `{"attack": {}}` (missing `damage` / `stat`),
  `{"attack": {"damage": 15}}` (missing `stat`), `{"grant": {"stat": "x"}}`
  (missing `op` / `value`), `{"grant": {"op": "bogus", …}}` (unknown
  `ModifierOperation`).
- **Wrong value types.** `{"heal": "20"}`, `{"attack": {"damage": "15", …}}`.
- **Out-of-range numbers.** `heal` amount, `attack.damage`, and a
  `grant.value` with `op: add` must be **≥ 0**. (`grant` with
  `op: multiply` / `min` / `max` is allowed any finite number; the plan
  decides whether SP3 content uses anything but `add`.)

Must be invalid: `{}`, `{"heal": 20, "attack": {"damage": 15, "stat": "thrown"}}`,
`{"attack": {}}`.

**Exception types (existing, no new class).** `consumableDefinitionFromContent`
parses `effect` / `target` with the `ContentField.*` helpers
(`lib/src/content/json_helpers.dart` — `requireString` / `requireNum` /
`requireMap`, which already raise **`ContentFieldException`** on a
missing/wrong-typed field) plus its own explicit checks for the
consumable-specific rules (zero/multiple variants, unknown keys,
`op` not a `ModifierOperation`, negative amounts, §5.1.2 mismatch), each
throwing **`ContentFieldException(path, problem)`** with a `path` that
names where in `effect` the problem is.

`ConsumablePlugin.initialize` invokes `consumableDefinitionFromContent`
per entry inside a `try { … } on ContentFieldException catch (e) { throw
ContentValidationException(id, e); }` — **byte-for-byte the pattern
`ContentRegistry._parse` uses** (`content_registry.dart`). So a bad
consumable surfaces as **`ContentValidationException`** ("Invalid content
'<id>': <field> — <problem>"), the same top-level type the generic
content path produces. (`itemDefinitionFromContent` today does raw `as`
casts and would cast-crash instead — SP3 does it properly; do not copy the
item parser's un-checked style.)

`consumableDefinitionFromContent` produces **exactly one**
`ConsumableEffectSpec` or throws — there is no partial/degraded
definition.

`ConsumablePlugin.initialize`:
- `sdk.registerTag('consumable', …)`.
- Idempotency-guarded `sdk.registerContentBatch(consumableContentDefinitions)`
  (same `if (context.content.find(<first id>) == null)` guard `ItemPlugin`
  uses). The batch load is where §5.1.2 / §5.1.3 validation fires.
- For each consumable,
  `context.resources.define(ResourceDefinition(
  id: consumableChargeResource(id), min: 0, max: double.infinity))`
  — unbounded above, per §5.1.1; `canAfford` is still well-defined
  (`current >= amount`).
- No Combat dependency, no trigger registration, no order constraint
  against other plugins (unlike SP2 aura content).

### 5.2 `ConsumableActionInterpreter` (`build_interpretation/`)

A `BuildActionInterpreter`, exactly the shape of
`TechniqueActionInterpreter`:

```dart
class ConsumableActionInterpreter implements BuildActionInterpreter {
  const ConsumableActionInterpreter();

  @override
  List<CombatAction> interpret({
    required ResolvedBuild build,
    required EntityId actor,
    required List<EntityId> targets,
    required PluginContext context,
  }) {
    final actions = <CombatAction>[];
    for (final ref in build.active) {
      if (ref.referenceType != consumableReferenceType) continue;
      final definition = context.content.find(ref.contentId);
      if (definition == null) continue;
      final consumable = consumableDefinitionFromContent(definition);
      final action = _actionFor(consumable, actor, targets, ref, context);
      if (action != null) actions.add(action);
    }
    return actions;
  }

  // no auras: the SP2 contract method returns const []
  @override
  List<AuraRule> auraRules({required ResolvedBuild build, required PluginContext context}) => const [];
}
```

`_actionFor` maps `consumable.effect` → the `CombatAction` from §5.1's
table (every non-`attack` variant is a `SelfEffectAction`), and in every
case attaches:

- `costEffects: [ConsumeResource(consumableChargeResource(consumable.id), 1)]`
- `priority: consumable.priority`
- `sourceRef: ref` (so SP4 / telemetry can attribute a consumable use)
- for `attack` (`enemy` target): `targets: targets` (the enemy list the
  interpreter is handed); for the self variants: `SelfEffectAction`'s
  `targets` getter already returns `[actor]`.

**`_actionFor` returns `null` for an `attack` consumable when `targets` is
empty** — the interpreter simply contributes no action for it that turn,
rather than constructing an `AttackAction` with an empty target list that
`AutoCombatController.step` would filter out anyway. No `CombatSystem`
change; this mirrors how `TechniqueActionInterpreter._actionFor` already
returns `null` for a damage technique with `targets.isEmpty`. (The
`§5.1.2` validation has already guaranteed a `heal` / `grantModifier` /
`removeAllStatuses` consumable can never reach this branch — those are
`self`-only and always have `[actor]`.)

`AttackAction` / `SelfEffectAction` gain no new fields — they already carry
`costEffects`, `priority` (`CombatAction` default), and `sourceRef`. No new
`CombatAction` subtype is introduced.

Added to `game_run.dart`'s composite:
`CompositeBuildActionInterpreter([TechniqueActionInterpreter(),
ItemActionInterpreter(), ConsumableActionInterpreter()])` — appended last,
deterministic ordering preserved (technique actions, then item modifiers,
then consumable actions).

### 5.3 `RemoveAllStatuses` (`lib/src/rule/effect.dart`)

```dart
/// Clears every active status on the subject — removes its
/// `StatusComponent` outright. No-op if the subject has none. The
/// wholesale counterpart to `RemoveStatus`'s single-key removal, for a
/// "cleanse" / "dispel all" action with no need to enumerate names.
class RemoveAllStatuses implements Effect {
  const RemoveAllStatuses();
  @override
  void apply(RuleContext context) {
    final subject = context.subject;
    if (subject == null) return;
    context.components.remove<StatusComponent>(subject);
  }
}
```

Also registered as a content-factory `'removeAllStatuses'` in
`built_in_content_factories.dart` (so a data-defined rule / SP2 aura could
use it too) taking no params.

### 5.4 `GrantModifier` `Effect` + `RuleContext.modifiers`

> **Hard limitation — read before using `GrantModifier`.** `GrantModifier`
> is intended for execution through a **`CombatAction` / `PluginContext`
> path only** (a consumable's `SelfEffectAction`, run by
> `CombatSystem.executeAction`, which builds its `RuleContext` via
> `PluginContext.ruleContextFor`). It **must not** be placed in
> data-defined `Rule` content (`ContentRegistry.loadRule`, an SP2 aura, a
> `RuleEngine`-dispatched rule) until `RuleEngine` is wired to a real
> `ModifierCollection`. In a `RuleEngine._fire` context its
> `context.modifiers` is a fresh, unobserved `ModifierCollection` — the
> effect *appears* to succeed and silently does nothing. SP3 does **not**
> register a `'grantModifier'` content factory, specifically so this
> misuse is not even expressible in rule JSON.

**`RuleContext` change** (`lib/src/rule/rule_context.dart`): add a
non-nullable `ModifierCollection modifiers` field, defaulted in the factory
to a fresh `ModifierCollection()` when unsupplied — exactly how `resources`
/ `mastery` / `progression` / `discovery` already default. Two call sites:

- `PluginContextRuleContext.ruleContextFor` (`plugin_context.dart`) passes
  `modifiers: modifiers` — `PluginContext` has held a `ModifierCollection`
  all along. **This is the path `CombatSystem.executeAction` uses** to
  build the `RuleContext` it applies an action's effects with, so a
  `GrantModifier` in a consumable action reaches the real collection.
- `RuleEngine._fire` — **unchanged in SP3**; its `RuleContext` gets the
  empty default. Wiring `RuleEngine` to the run's real `ModifierCollection`
  (via `CoreServices`) is explicitly out of SP3 scope; it is the future
  work that would also unlock SP2 buff-auras. Until then the limitation
  callout above stands.

**`GrantModifier`** (`lib/src/rule/effect.dart`):

```dart
/// Adds one source-scoped [Modifier] on the subject via the Modifier
/// Engine. [sourceKey] namespaces the modifier so a caller can later
/// remove exactly this contribution with
/// `modifiers.removeBySource(ModifierSource('$sourceKey:${subject.value}'))`.
/// Re-applying with the same subject + [sourceKey] replaces (never
/// stacks): `apply` does `removeBySource` before `add`.
///
/// LIMITATION: requires `RuleContext.modifiers` to be the run's real
/// collection. That holds when the context comes from
/// `PluginContext.ruleContextFor` — e.g. a `CombatAction`'s effects run by
/// `CombatSystem`, the ONLY sanctioned path. Inside a
/// `RuleEngine`-dispatched `Rule` (`ContentRegistry.loadRule`, an SP2
/// aura) `context.modifiers` is a fresh, unobserved `ModifierCollection`:
/// the effect silently no-ops. Do NOT use `GrantModifier` in `Rule`
/// content until `RuleEngine` threads a real `ModifierCollection`. There
/// is deliberately no `'grantModifier'` content factory.
class GrantModifier implements Effect {
  const GrantModifier(
    this.stat,
    this.operation,
    this.value, {
    this.priority = 0,
    this.sourceKey = 'grantmodifier',
  });

  final String stat;
  final ModifierOperation operation;
  final num value;
  final int priority;
  final String sourceKey;

  @override
  void apply(RuleContext context) {
    final subject = context.subject;
    if (subject == null) return;
    final source = ModifierSource('$sourceKey:${subject.value}');
    context.modifiers
      ..removeBySource(source)
      ..add(Modifier(
        source: source,
        target: subject,
        stat: stat,
        operation: operation,
        value: value,
        priority: priority,
      ));
  }
}
```

- Carried by a `SelfEffectAction` (`selfEffects: [GrantModifier(...)]`), so
  the consumable interpreter introduces **no new `CombatAction` type**.
- `SelfEffectAction.effectsFor` is a **pure getter** — the scorer (§5.6)
  can read the effects list to inspect shape without triggering the
  modifier add; the add happens only when `CombatSystem` applies the
  effect at execution time.
- The interpreter passes `sourceKey: 'consumable:${consumable.id}'`, so the
  live modifier source is `consumable:<contentId>:<owner.value>` — exactly
  what `ConsumableCharges.dispose()` (§5.5) removes at fight end.
- No content-factory registration in SP3 (a data-defined `Rule` can't use
  it usefully yet, per the `RuleEngine` note above).

> Open sub-decision for the plan: whether `GrantModifier` should accept a
> `target` other than the subject (buff an ally). **Default: subject only**
> — SP3 has no allies. Trivially addable.

### 5.5 `ConsumableBinder` / `ConsumableCharges` (`build_interpretation/consumable_binder.dart`)

Sibling of `AuraBinder`. Per resolved build (per fight in the harness):

```dart
class ConsumableBinder {
  const ConsumableBinder();

  ConsumableCharges grant({
    required ResolvedBuild build,
    required PluginContext context,
  }) {
    // sum charges per contentId across every hung consumable ref
    final byContent = <String, int>{};
    for (final ref in build.active) {
      if (ref.referenceType != consumableReferenceType) continue;
      final def = context.content.find(ref.contentId);
      if (def == null) continue;
      final charges = consumableDefinitionFromContent(def).charges;
      byContent[ref.contentId] = (byContent[ref.contentId] ?? 0) + charges;
    }
    for (final entry in byContent.entries) {
      // Authoritative aggregate write. The resource is defined `max:
      // double.infinity` (§5.1.1), so `set` here is a plain assignment —
      // 3 hung heal_potion refs → pool = 3, never clamped to 1.
      context.resources.set(build.owner, consumableChargeResource(entry.key), entry.value);
    }
    return ConsumableCharges._(
      owner: build.owner,
      contentIds: byContent.keys.toList(),
      modifiers: context.modifiers,
      resources: context.resources,
    );
  }
}

class ConsumableCharges {
  ConsumableCharges._({ required this.owner, required this.contentIds,
                        required this.modifiers, required this.resources });
  final EntityId owner;
  final List<String> contentIds;
  final ModifierCollection modifiers;
  final ResourcePool resources;
  var _disposed = false;

  /// Idempotent. Zeroes every charge pool this binding granted and removes
  /// every consumable-scoped `Modifier` a `GrantModifier` effect may have
  /// added this fight — so neither charges nor buffs leak into the next
  /// resolved build.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    for (final id in contentIds) {
      resources.set(owner, consumableChargeResource(id), 0);
      modifiers.removeBySource(ModifierSource('consumable:$id:${owner.value}'));
    }
  }
}
```

- `grant` may itself throw (e.g. `consumableDefinitionFromContent` on
  corrupt content). It is called inside `runFight`'s `try` (§5.7); a throw
  mid-`grant` leaves at most some `set(...)` calls applied — harmless,
  because the next fight's `grant` re-`set`s every pool and any pool for
  an id it no longer sees stays at whatever it was (a stale non-zero
  pool for a since-removed consumable is the one residue, cleaned by the
  prior `ConsumableCharges.dispose()` which always runs in the `finally`).
- Uses `ResourcePool.set` (overwrite), never `add`, so aggregate charges
  never accumulate across fights.
- `dispose()` is **idempotent** (`_disposed` guard), zeroes every pool it
  granted, and `removeBySource`es every `consumable:<id>:<owner>` modifier
  — so neither charges nor `GrantModifier` buffs leak into the next
  resolved build, and it is safe to call from `runFight`'s `finally`
  after a partial setup.
- Membership fixed at `grant` (no update path), mirroring `AuraBinding`.

**`grant()` is not an in-place reconciliation mechanism.** It only
`set`s the resource keys present in *its* `build.active`. A placement
change is applied by the standard per-fight sequence — **dispose the old
`ConsumableCharges` → resolve the new build → call `grant()` again**. The
`dispose()` is what zeroes the keys of any consumable that dropped out of
the build; `grant()` alone would leave such a key at its previous value.
The harness (§5.7) and any client (SP4) must follow this order; calling
`grant()` twice without an intervening `dispose()` is unsupported.

### 5.6 `ConsumableAwareActionScorer` (`lib/src/plugins/auto_combat/`)

```dart
class ConsumableAwareActionScorer implements ActionScorer {
  const ConsumableAwareActionScorer({
    this.base = const DefaultActionScorer(),
    this.missingHealthWeight = 40,
    this.buffBonus = 6,
  });

  final ActionScorer base;
  final num missingHealthWeight;
  final num buffBonus;

  @override
  num score(CombatAction action, EntityId actor, EntityId? preferredTarget, PluginContext context) {
    var total = base.score(action, actor, preferredTarget, context);
    final hp = context.components.get<HealthComponent>(actor);
    final missing = (hp == null || hp.max <= 0) ? 0.0 : (1 - hp.current / hp.max).clamp(0.0, 1.0);
    for (final effect in action.effectsFor(action.actor, context)) {
      if (effect is Heal) total += missingHealthWeight * missing;
      if (effect is ApplyStatus) total += buffBonus;
    }
    return total;
  }
}
```

- Composes `DefaultActionScorer` — offensive consumables are `AttackAction`,
  already scored by resolved damage there; a `GrantModifier`-carrying
  `SelfEffectAction` scores `base` (`priority`) with no extra bonus, which
  is fine (an early-use buff, gated by `priority`, not situational). If a
  buff wants situational value later, add a `GrantModifier` branch here.
- `Heal` bonus scales `0 → missingHealthWeight` as HP drops, so a heal
  potion is near-worthless at full HP and top-priority near death.
- `ApplyStatus` bonus is flat — a status buff is an early-use action.
- **`effectsFor` is safe to call here.** Every `CombatAction` SP3 scores
  has a side-effect-free `effectsFor`: `SelfEffectAction` returns its
  `selfEffects` list verbatim; `AttackAction` returns `[Damage(resolved)]`
  from a pure `ModifierResolver` read (the base scorer already does this).
  `GrantModifier`'s modifier write happens in `GrantModifier.apply`, which
  the scorer never calls — it only pattern-matches the effects list for
  `is Heal` / `is ApplyStatus` (`GrantModifier` matches neither, so it is
  ignored). No new `CombatAction` subtype means no `effectsFor` with a
  hidden side effect.

> Note (D4): this scorer changes the score of **any** action whose
> `effectsFor` contains a `Heal` or `ApplyStatus` — e.g. a guard technique
> that heals, a stance that applies a status. That is a deliberate
> improvement (the AI heals when hurt regardless of the source), and it
> shifts fixed-seed headless outcomes (§4 / §8).

### 5.7 Harness wiring (`lib/src/plugins/game/`)

**`game_run.dart`:**
- `ConsumablePlugin().initialize(context)` alongside the other content
  plugins (order-independent).
- composite gains `ConsumableActionInterpreter()` (appended last).
- `context.content.loadAll` / reward pool: see §5.8.

**`combat_stage.dart` — `CombatStage.runFight`:** the per-fight setup must
be **exception-safe as a whole**. Post-SP2, `runFight` creates
`auraBinding` *before* its `try` (SP2's own final review logged this as a
deferred minor — a throw between `bind` and `try` leaks the binding). SP3
adds a second binder, so the leak surface doubles: if `AuraBinder.bind`
succeeds and `ConsumableBinder.grant` then throws, the aura binding leaks.
Fix both at once by moving **every** binder call inside the `try` behind
nullable locals:

```dart
AuraBinding? auraBinding;
ConsumableCharges? consumableCharges;
EventSubscription? subscription;
try {
  auraBinding = const AuraBinder().bind(
      build: build, interpreter: interpreter, context: context, opponents: [enemyEntity]);
  consumableCharges = const ConsumableBinder().grant(build: build, context: context);

  // … existing fight setup: effectivePlayerActions, startBattle,
  //     AutoCombatController, the ActionCompleted subscription …
  subscription = events.subscribe<ActionCompleted>((e) { /* unchanged */ });
  controller.runUntilBattleEnds();
} finally {
  subscription?.cancel();
  consumableCharges?.dispose();   // reverse acquisition order
  auraBinding?.dispose();
}
// post-fight bookkeeping (playerHealth, won, encounters.add,
// EncounterResolved, return won) stays AFTER the finally, unchanged.
```

An equivalent nested-`try` shape is acceptable. The spec requires:

- if `AuraBinder.bind` succeeds and `ConsumableBinder.grant` throws → the
  aura binding **is disposed** (no live aura subscriptions escape);
- if both succeed and anything later throws → **both** are disposed
  (charge pools zeroed, consumable modifiers removed, aura subscriptions
  cancelled, `ActionCompleted` subscription cancelled);
- `dispose()` on both `AuraBinding` and `ConsumableCharges` is idempotent
  (already true for `AuraBinding`; §5.5 for `ConsumableCharges`);
- **no partial fight setup ever leaves a live aura subscription, a
  non-zero charge pool, or a consumable-sourced `Modifier`.**

No new lifecycle abstraction is introduced for this — it is a local
restructure of `runFight`.

**The scorer:** `CombatStage`/`game_run` builds its `CombatPolicy` as
`CombatPolicy.scored(scorer: const ConsumableAwareActionScorer())` instead
of the bare `CombatPolicy.scored()`. Confirm the exact call site in the
plan (`combat_stage.dart` currently passes `CombatPolicy.scored()`).

### 5.8 Run content

- **`run_content.dart`:** `const rewardPoolConsumableIds = [ConsumableIds.healPotion, …]`.
  Decide in the plan whether consumables also appear in `RunStartingKit`
  (default: **no** — earned as rewards only, like techniques).
- **`reward_stage.dart` — `resolveReward`:** the `RewardKind.itemOrTechnique`
  branch already switches on `entry.referenceType`; add
  `else if (entry.referenceType == consumableReferenceType) {
  tomeManager.placeConsumable(consumableDefinition(entry.contentId, context), '$stepName reward'); }`.
  The `rewardPool` list (`List<({String referenceType, String contentId})>`)
  gains the consumable entries.
- **`tome_manager.dart` — `placeConsumable`:** mirrors `placeItem` —
  builds `BuildComponentRef(referenceType: consumableReferenceType,
  contentId: c.id)` (no `instanceEntityId`), picks a slot via the policy,
  inserts. No usability gate (consumables have no mastery requirement in
  SP3); the plan confirms whether `addItemToTome`'s gating helper is
  reused or a simpler `context.tome.insert` path is called directly.
- **`RewardKind`** is unchanged — a consumable is still an
  `itemOrTechnique`-kind reward, just a third `referenceType` within it.

## 6. Event flow

```
tome.resolve ─▶ ResolvedBuild{owner, active, owned}
     │
     ├─▶ interpreter.interpret(...)         → CombatActions (incl. one per hung consumable)
     ├─▶ AuraBinder.bind(...)               → SP2, unchanged
     └─▶ ConsumableBinder.grant(...)        → resources.set(owner, 'consumable:<id>', Σcharges)
                                              ─▶ ConsumableCharges

  … fight: AutoCombatController.step() each turn …
     ScoredActionSelector:
        _isAvailable(consumableAction)  = charges pool canAfford 1   (existing check)
        ConsumableAwareActionScorer.score(...)  = base + Heal/ApplyStatus shape bonus
     CombatSystem.executeAction(consumableAction):
        costEffects  → ConsumeResource('consumable:<id>', 1)   (spends a charge)
        effectsFor   → Heal / Damage / RemoveAllStatuses / GrantModifier  (all Effect.apply)
        publishes    → EntityHealed / EntityDamaged / StatusRemoved / ActionCompleted  (existing)

  fight ends ─▶ ConsumableCharges.dispose() ─▶ resources.set(...,0) + modifiers.removeBySource(...)
```

No new event types. Consumable effects reuse the events their `Effect` /
`CombatAction` implementations already publish, so the encounter trail and
`HeadlessGameAlmanacBridge` observe them with no bridge change.

## 7. Content set

| id | `charges` | `priority` | `target` | `effect` | interpreter → action | AI picks it when |
|----|----|----|----|----|----|----|
| `heal_potion` | 1 | 8 | self | `{heal: 20}` | `SelfEffectAction([Heal(20)])` | HP low (scorer `+40·missing`) |
| `firebomb` | 1 | 4 | enemy | `{attack: {damage: 15, stat: 'thrown'}}` | `AttackAction(15, 'thrown')` | scored on resolved damage (base) |
| `power_tonic` | 1 | 6 | self | `{grant: {stat: 'thrown', op: 'add', value: 6}}` | `SelfEffectAction([GrantModifier('thrown', add, 6, sourceKey: 'consumable:power_tonic')])` | early (priority); makes a later `firebomb` hit for 21 |
| `swift_draught` | 1 | 5 | self | `{grant: {stat: '<stat AttackAction reads>', op: 'add', value: 3}}` | `SelfEffectAction([GrantModifier(...)])` | early (priority) |
| `cleanse_tonic` | 1 | 5 | self | `{removeAllStatuses: true}` | `SelfEffectAction([RemoveAllStatuses()])` | early/whenever (priority) |

Every row's `target` obeys §5.1.2 (`heal` / `grant` / `removeAllStatuses`
→ `self`; `attack` → `enemy`) and each `effect` has exactly one variant
(§5.1.3) — content that broke either rule would fail
`ConsumablePlugin.initialize`'s batch load.

- **`swift_draught`'s stat key** must be one `AttackAction.effectsFor`
  actually resolves (its `damageStat`) for the buff to be observable —
  `AttackAction` reads `activeModifiersFor(actor, damageStat)`, not
  `StatComponent` and not `CombatantComponent.initiative`. The plan pins
  the exact key against the run's technique/consumable `damageStat`s
  (candidates: `'fist'`, `'blade'`, `'thrown'`). If no shared stat makes
  `swift_draught` meaningfully distinct from `power_tonic`, the plan may
  drop it to a 4-consumable set — the mechanism coverage (heal / attack /
  grant-modifier / remove-all-statuses) is already complete at 4.
- `firebomb` `damageStat: 'thrown'` — a fresh stat key nothing else
  contributes to, so its damage is exactly `baseDamage` unless a
  `power_tonic` modifier is active. Deterministic and easy to assert.
- All `charges: 1` in the shipped set, but per-copy: two hung `heal_potion`
  refs give an aggregate pool of `2` (§5.1.1 invariant).
- Consumables are **reward-pool only** (not starting kit) unless the plan
  finds a reason otherwise.

## 8. Determinism

- No new randomness. `ConsumeResource`, `ResourcePool`, `ModifierResolver`,
  `removeBySource` are pure. The scorer's inputs (`HealthComponent`,
  `activeModifiersFor`) are deterministic.
- `ConsumableActionInterpreter` iterates `build.active` in order and is
  appended last in the composite → consumable actions have a fixed,
  reproducible position in `availableActions`.
- `ScoredActionSelector` already breaks score ties by list order — no new
  tie-break.
- **Golden impact:** the new scorer + consumables in the reward pool shift
  fixed-seed headless-run fight outcomes (a heal potion drunk near death
  wins a fight that was a loss; a firebomb shortens another). Expected and
  sanctioned exactly as SP2's was. Regenerate `output/` report artifacts,
  review the diff. `test/game/` **determinism** assertions (same seed
  twice / seed + replayed decisions → identical result) must still pass —
  a failure there is a real bug. `test/game/` / `test/integration/`
  **diversity / structure** assertions updated to the new observed values
  if they flip.

## 9. Tests

**Core**
- `RemoveAllStatuses`: clears a multi-status `StatusComponent`; no-op with
  no component / null subject. Exported from
  `package:build_engine/build_engine.dart`. Factory `'removeAllStatuses'`
  parses.
- `RuleContext.modifiers`: present and non-null; defaults to a fresh
  `ModifierCollection` when the factory is called without one;
  `PluginContext.ruleContextFor(...)` supplies the `PluginContext`'s own
  collection (assert identity in a test). Every existing `RuleContext`
  construction still compiles (the param is optional).
- `GrantModifier`: `apply` adds a `Modifier` (source
  `<sourceKey>:<subject.value>`, target = subject, given stat/op/value/
  priority); `removeBySource` before `add` so a second `apply` replaces,
  never stacks; no-op on null subject. Exported. **Not** registered as a
  content factory.

**`consumable` plugin — parsing**
- `consumableDefinitionFromContent` parses each `effect` variant to the
  right `ConsumableEffectSpec`; defaults (`charges: 1`, `priority: 0`,
  `target` = the effect's only legal value) apply on absence.
- **Ambiguous / malformed `effect` (§5.1.3) throws `ContentFieldException`**
  from `consumableDefinitionFromContent`, surfaced by
  `ConsumablePlugin.initialize` as **`ContentValidationException`** naming
  the id (§5.1.3): `{}`, `effect` absent, `{"heal": 20, "attack": {…}}`,
  `{"attack": {}}`, `{"attack": {"damage": 15}}`, `{"grant": {"stat": "x"}}`,
  `{"grant": {"op": "bogus", "stat": "x", "value": 1}}`, `{"heal": "20"}`,
  `{"heal": -5}`, `{"unknownKey": 1}`, `{"heal": 20, "junk": 1}`. Assert on
  `ContentValidationException` (via `ConsumablePlugin.initialize`) and,
  where a unit test calls the parser directly, on `ContentFieldException`.
- **Invalid `effect` × `target` (§5.1.2)** fails the same way: `heal` /
  `grant` / `removeAllStatuses` with `target: enemy`; `attack` with
  `target: self`.
- A valid single-variant `effect` with the matching `target` yields
  exactly one `ConsumableDefinition` with exactly one `ConsumableEffectSpec`.
- `ConsumablePlugin.initialize`: registers the tag, loads content once
  (idempotent on a second `initialize`), `define`s each charge resource
  with `max: double.infinity` (§5.1.1). Runs standalone (no Combat)
  without throwing. A `consumableContentDefinitions` entry that violates
  §5.1.2 / §5.1.3 makes `initialize` throw at batch load.
- Architecture: `lib/src/plugins/consumable/` imports no other plugin
  barrel.

**`consumable` plugin — charge resource semantics (§5.1.1)**
- The registered `ResourceDefinition` for `consumable:<id>` has
  `max == double.infinity`; `ResourcePool.set(owner, key, 3)` leaves the
  value at `3` (no clamp to `1`).
- `canAfford(owner, key, 1)` is `true` at `≥ 1`, `false` at `0`.

**`ConsumableActionInterpreter`**
- One `CombatAction` per hung `consumable` ref; `heal`→`SelfEffectAction`
  with a `Heal`, `attack`→`AttackAction` targeting the passed enemy,
  `grant`→`SelfEffectAction` with a `GrantModifier` (correct `sourceKey`),
  `removeAllStatuses`→`SelfEffectAction` with `RemoveAllStatuses`.
- Every produced action carries `ConsumeResource(consumable:<id>,1)` in
  `costEffects`, the content `priority`, and `sourceRef == ref`.
- **An `attack` consumable with `targets` empty → `_actionFor` returns
  `null`** (the interpreter contributes no action for it that turn); the
  self variants always produce an action (`targets` = `[actor]`).
- An owned-but-not-hung consumable produces nothing.
- A hung `item` / `technique` ref is ignored.
- Composite aggregates technique + item + consumable in that order.

**`GrantModifier` through a consumable (end to end)**
- After a `grant` consumable's `SelfEffectAction` is executed by
  `CombatSystem`, exactly one `Modifier` with source
  `consumable:<id>:<owner.value>` is live on the owner.
- A subsequent `AttackAction` on the same `stat` resolves higher by
  `value`.
- Executing it again (were charges available) leaves still exactly one
  modifier (idempotent).

**`ConsumableBinder` / `ConsumableCharges`**
- `grant` sets `consumable:<id>` on the owner to the **summed** charge
  count: 1 hung `heal_potion` → pool `1`; 2 refs → pool `2`; 3 refs →
  pool `3` (no clamp — §5.1.1).
- Two *different* consumables → two independent pools, each its own sum.
- Only `build.active` consumables count; an `owned`-only one grants
  nothing.
- `dispose()` zeroes every granted pool and `removeBySource`es every
  `consumable:<id>:<owner>` modifier; idempotent (twice, and on an empty
  binding).
- **Lifecycle:** `dispose()` old → resolve new build → `grant()` new. A
  test drives that sequence across a placement change: after dropping one
  of two `heal_potion` copies, the new binding's pool is `1` (the old
  binding's `dispose()` zeroed it, the new `grant()` re-`set` it to the
  new sum). `grant()` called twice with no intervening `dispose()` is not
  a supported path and is not tested as if it were.

**`ConsumableAwareActionScorer`**
- A `Heal`-bearing action scores `base + missingHealthWeight·missingFrac`;
  at full HP the bonus is 0; near death it is `missingHealthWeight`.
- An `ApplyStatus`-bearing action scores `base + buffBonus`.
- An `AttackAction` consumable scores exactly what `DefaultActionScorer`
  gives it (no double count).
- A plain technique `AttackAction` is unaffected (regression: same score
  as `DefaultActionScorer`).
- Scoring a `GrantModifier`-carrying `SelfEffectAction` adds **no**
  modifier (the scorer reads the effects list but never calls
  `Effect.apply`) and no bonus (it is neither `Heal` nor `ApplyStatus`).

**`ConsumeResource` gating (existing machinery, one confirming test)**
- With `consumable:<id>` pool at 0, `ScoredActionSelector` does not pick
  the consumable action even when it scores highest; at ≥1 it can.

**Exception-safe fight setup (§5.7 / D3b)**
- `AuraBinder.bind` succeeds, then `ConsumableBinder.grant` throws (inject
  by stubbing the interpreter/content so `grant` raises) → `runFight`'s
  `finally` still runs → the `AuraBinding` **is disposed**: publishing the
  aura's trigger afterward produces no aura effect (health unchanged).
- Both succeed, then the fight body throws → both `dispose()`s run:
  every `consumable:<id>` pool is `0`, no `consumable:*` `Modifier`
  remains, the aura subscription and the `ActionCompleted` subscription
  are cancelled.
- Calling the whole disposal path twice (idempotency across the pair)
  does not throw and changes nothing.

**Integration (`game_run` / `CombatStage`)**
- A run with `heal_potion` hung: the player's `EntityHealed` count
  attributable to `Heal(20)` is `> 0` and `≤ Σ(per-fight charges granted)`
  across the run — proving both that the action fires and that charges are
  per-fight-bounded (not leaking).
- A run with **two** `heal_potion` refs hung: in a single fight the
  player can be healed by `aura`… i.e. by the potion up to **2** times
  (aggregate pool = 2), and never a third in that fight.
- `firebomb` hung: at least one `EntityDamaged` of `15` (or `15 + tonic`)
  lands on an enemy from a `sourceRef.referenceType == 'consumable'`
  action.
- Same seed twice → identical `RunResult` (determinism with consumables
  live).
- Removing `ConsumableBinder().grant(...)` from `runFight` makes the
  `heal_potion` integration test fail (mutation check, documented).

**`cleanse_tonic` end-to-end**
- A synthetic self-applied `status:poison` on the player, `cleanse_tonic`
  hung → after it fires, the player has no `StatusComponent` / no active
  statuses.

**Architecture guards (must stay green)**
- The seven `claude.md` integration proofs.
- `lib/src/plugins/consumable/` references no other plugin barrel.
- `lib/src/rule/effect.dart` (with `GrantModifier`) references no content
  vocabulary and no plugin barrel.

## 10. Rollout / sequencing (for the implementation plan)

1. `RemoveAllStatuses` `Effect` + `'removeAllStatuses'` factory + export.
   Tests.
2. `RuleContext.modifiers` field (optional param, default fresh
   `ModifierCollection`) + `PluginContextRuleContext.ruleContextFor`
   passing it; **`RuleEngine._fire` unchanged**. Then `GrantModifier`
   `Effect` + export. Tests (`ruleContextFor` identity; `apply` adds one
   source-scoped modifier; idempotent re-apply; null subject; every
   existing `RuleContext` call site still compiles).
3. `consumable` plugin: `consumableReferenceType`,
   `consumableChargeResource`, `ConsumableDefinition` +
   `ConsumableEffectSpec` + `ConsumableTarget`, `consumable_content.dart`
   parser (**strict**: §5.1.2 target/effect matrix + §5.1.3
   exactly-one-variant; parser raises `ContentFieldException`,
   `ConsumablePlugin.initialize` wraps as `ContentValidationException(id,
   e)` exactly like `ContentRegistry._parse`) + a minimal
   `consumableContentDefinitions` (1 entry), `ConsumablePlugin` (defines
   each charge resource `max: double.infinity`). Barrel
   `lib/consumable_plugin.dart`. Tests (valid parse; every §9 invalid
   example throws; `set` to 3 not clamped) + architecture guard.
4. `ConsumableActionInterpreter` + add to `build_interpretation.dart`
   barrel; implement the SP2 `auraRules` contract method as `const []`.
   Tests.
5. `ConsumableBinder` / `ConsumableCharges` + barrel. Tests.
6. `ConsumableAwareActionScorer` (`auto_combat/`) + barrel. Tests
   (including the plain-`AttackAction` regression).
7. `game_run.dart` wiring: init `ConsumablePlugin`, composite gains the
   interpreter; `combat_stage.dart` restructured to the **exception-safe**
   `try` in §5.7 (both binders inside, nullable locals, reverse-order
   disposal in `finally`) and using the new scorer. Integration test
   (`heal_potion` visible in the run) with the mutation check; the
   grant-throws-after-bind-succeeds test.
8. Content pass — the 5 (or 4) consumables in
   `consumable_content.dart`; `rewardPoolConsumableIds`; the `consumable`
   branch in `resolveReward`; `TomeManager.placeConsumable`. Regenerate
   `output/`. Triage any `test/game/` diversity/structure flips; a
   determinism failure blocks.
9. `CHANGELOG.md` (public surface: `RemoveAllStatuses`, `GrantModifier`,
   `RuleContext.modifiers`, `consumable_plugin.dart` barrel + its exports,
   `ConsumableActionInterpreter`, `ConsumableBinder`/`ConsumableCharges`,
   `ConsumableAwareActionScorer`, `'removeAllStatuses'` factory).
   `ARCHITECTURE.md` — new "Per-fight consumables (SP3)" section, plus a
   line in the Rule/Effect section noting `RuleContext.modifiers` and the
   `RuleEngine._fire` caveat. Architecture guard tests.

Commit after every step. Branch: `per-fight-consumables-sp3`.

## 11. Completion criteria

- A hung `consumable` produces a `CombatAction` the headless auto-combat
  can choose, limited to N uses per fight via a `ResourcePool` charge, with
  no `RuleEngine` involvement, no `Rule` change, no `CombatSystem` change,
  and no `RuleContext` change beyond the added `modifiers` field.
- The AI uses a `heal_potion` when hurt and not at full HP, a `firebomb`
  for damage, a buff tonic early — driven by `ConsumableAwareActionScorer`
  reading Core effect shapes, no domain vocabulary in the scorer.
- The headless run demonstrates at least `heal_potion` and `firebomb`
  end-to-end, observable in the encounter trail / events and reproducible
  from seed; charges do not leak between fights.
- Only new Core primitives: `RemoveAllStatuses` + `GrantModifier`
  (`Effect`s) and one `RuleContext` field. No new `CombatAction` subtype.
  No `consumable` → other-plugin import; `lib/src/rule/` gains no plugin
  or content vocabulary.
- `consumableDefinitionFromContent` rejects — at content-parse time — an
  `effect` with zero or multiple variants, an unknown key, a malformed
  nested object, a wrong-typed or negative value, and an `effect` × `target`
  pairing outside §5.1.2. There is no partial/degraded `ConsumableDefinition`.
- The `consumable:<id>` charge resource is unbounded above; `grant`'s
  aggregate `set` is never clamped down to a single copy's `charges`.
- `runFight`'s per-fight setup is exception-safe: no throw between the two
  binder calls (or later) can leave a live aura subscription, a non-zero
  charge pool, or a `consumable:*` `Modifier`.
- All existing tests green (goldens regenerated, diff reviewed,
  determinism preserved); new tests per §9.
- `CHANGELOG.md` + `ARCHITECTURE.md` updated.

## 12. Acceptance invariant ("per-fight consumable" means exactly this)

| Situation | Required behaviour |
|-----------|--------------------|
| Consumable owned but not hung | produces no action; grants no charge |
| Consumable hung, fight starts | charge pool = Σ per-copy `charges` over every hung ref of that id; the action is selectable while the pool ≥ 1 |
| **2 identical hung consumables** (`charges: c` each) | aggregate charge pool = `2·c`; both copies' charges are usable in one fight |
| **Resource cap** | the `consumable:<id>` `ResourceDefinition` is `max: double.infinity`; `grant`'s aggregate `set` is **not** clamped to one copy's `charges` (pool of 3 stays 3) |
| Consumable used N times in a fight (N = aggregate charge total) | the (N+1)th selection is filtered out (`_isAvailable` = false) and, if forced, `CombatSystem` no-ops the cost + effects |
| Fight ends (any exit: win, loss, or a throw) | every consumable charge pool → 0; every `consumable:<id>:<owner>` modifier removed; both `dispose()`s idempotent |
| **Partial fight setup** (`AuraBinder.bind` OK, `ConsumableBinder.grant` throws) | the aura binding is disposed; no live aura subscription, no non-zero charge pool, no `consumable:*` modifier survives |
| Next fight starts | charge pool re-`set` to the full aggregate (refreshed, not depleted) |
| **Invalid content** — `effect` × `target` outside §5.1.2 | fails at content parse / `ConsumablePlugin.initialize` batch load; never reaches interpretation |
| **Ambiguous content** — `effect` with zero or ≥2 recognized variants, unknown keys, malformed nested object, wrong-typed / negative value | fails at content parse; no partial `ConsumableDefinition` is produced |
| Same seed + same decisions, run twice | identical `RunResult` and identical consumable-use / heal / damage / modifier event sequence |
