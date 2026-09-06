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
| D3 | Two of the same consumable placed = two Tome cells = **charges summed** for that fight (2 uses). |
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
  `ConsumableDefinition`, `consumableContentDefinitions`), mirroring
  `ItemPlugin`. Owns `consumableReferenceType`; `context.resources.define`s
  the charge resources; depends only on Core.
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
- `CombatStage.runFight` wiring: bind consumable charges per fight, dispose
  in the fight's `finally`; use the new scorer in `CombatPolicy.scored`.
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
/// build owner. One key per content id — two copies of the same
/// consumable share (and sum into) one pool.
String consumableChargeResource(String contentId) => 'consumable:$contentId';
```

**`ConsumableDefinition`** — immutable, content-derived, exactly the shape
of `ItemDefinition`:

```dart
class ConsumableDefinition {
  const ConsumableDefinition({
    required this.id,
    required this.tags,
    this.charges = 1,
    this.priority = 0,
    this.target = ConsumableTarget.self,
    required this.effect,   // ConsumableEffectSpec — the one shape below
  });
  final String id;
  final Set<String> tags;
  final int charges;
  final num priority;
  final ConsumableTarget target;         // self | enemy
  final ConsumableEffectSpec effect;
}
```

**`ConsumableEffectSpec`** — a small closed sum type the interpreter maps to
a `CombatAction`. One of:

| variant | content JSON | interpreter builds |
|---|---|---|
| `heal(amount)` | `{"heal": 20}` | `SelfEffectAction([Heal(20)])` |
| `attack(damage, stat)` | `{"attack": {"damage": 15, "stat": "thrown"}}` | `AttackAction(baseDamage: 15, damageStat: "thrown")` |
| `grantModifier(stat, operation, value)` | `{"grant": {"stat": "thrown", "op": "add", "value": 6}}` | `SelfEffectAction([GrantModifier("thrown", ModifierOperation.add, 6, sourceKey: "consumable:<id>")])` |
| `removeAllStatuses()` | `{"removeAllStatuses": true}` | `SelfEffectAction([RemoveAllStatuses()])` |

Kept a closed set (not open plugin-registered) because it maps 1:1 to a
fixed set of `CombatAction` shapes the interpreter knows; a new variant is
a deliberate SP-level change, like `EffectTier`'s fixed enum.

`ConsumablePlugin.initialize`:
- `sdk.registerTag('consumable', …)`.
- Idempotency-guarded `sdk.registerContentBatch(consumableContentDefinitions)`
  (same `if (context.content.find(<first id>) == null)` guard `ItemPlugin`
  uses).
- For each consumable, `context.resources.define(ResourceDefinition(
  id: consumableChargeResource(id), min: 0, max: <charges>))` — a bounded
  resource so `ResourcePool.set` clamps and `canAfford` is well-defined.
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
- for `attack`/`enemy`-target: `targets: targets` (the enemy list the
  interpreter is handed); for `self`: `SelfEffectAction`'s `targets`
  getter already returns `[actor]`.

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

**`RuleContext` change** (`lib/src/rule/rule_context.dart`): add a
non-nullable `ModifierCollection modifiers` field, defaulted in the factory
to a fresh `ModifierCollection()` when unsupplied — exactly how `resources`
/ `mastery` / `progression` / `discovery` already default. Two call sites:

- `PluginContextRuleContext.ruleContextFor` (`plugin_context.dart`) passes
  `modifiers: modifiers` — `PluginContext` has held a `ModifierCollection`
  all along. **This is the path `CombatSystem.executeAction` uses** to
  build the `RuleContext` it applies an action's effects with, so a
  `GrantModifier` in a consumable action reaches the real collection.
- `RuleEngine._fire` — **unchanged**; its `RuleContext` gets the empty
  default. A `GrantModifier` inside a data-defined `Rule` therefore writes
  to a collection nothing reads. Documented on `GrantModifier`; wiring
  `RuleEngine` (via `CoreServices`) is future work that would also unlock
  SP2 buff-auras. SP3 never puts `GrantModifier` in a `Rule`.

**`GrantModifier`** (`lib/src/rule/effect.dart`):

```dart
/// Adds one source-scoped [Modifier] on the subject via the Modifier
/// Engine. [sourceKey] namespaces the modifier so a caller can later
/// remove exactly this contribution with
/// `modifiers.removeBySource(ModifierSource('$sourceKey:${subject.value}'))`.
/// Re-applying with the same subject + [sourceKey] replaces (never
/// stacks): `apply` does `removeBySource` before `add`.
///
/// Requires `RuleContext.modifiers` to be the real collection — true when
/// the context comes from `PluginContext.ruleContextFor` (e.g. a
/// `CombatAction`'s effects run by `CombatSystem`). Inside a
/// `RuleEngine`-dispatched `Rule` the collection is an unobserved default
/// (see §5.4 of the SP3 design) — do not use `GrantModifier` in a `Rule`
/// until `RuleEngine` threads a real `ModifierCollection`.
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

- Uses `ResourcePool.set` (overwrite), so charges never accumulate across
  fights even if `dispose` were somehow skipped and the next `grant` ran.
- `dispose()` still zeroes them, and removes buff modifiers, so a
  consumable *removed from the Tome between fights* leaves no residue.
- Membership fixed at `grant` (no update path), mirroring `AuraBinding`.

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

**`combat_stage.dart` — `CombatStage.runFight`:** after the existing
`auraBinding` line and inside the same lifecycle:

```dart
final auraBinding = const AuraBinder().bind(build: build, interpreter: interpreter, context: context, opponents: [enemyEntity]);
final consumableCharges = const ConsumableBinder().grant(build: build, context: context);   // NEW
try {
  // … fight …
  controller.runUntilBattleEnds();
} finally {
  subscription.cancel();
  auraBinding.dispose();
  consumableCharges.dispose();                                                              // NEW
}
```

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

**`consumable` plugin**
- `consumableDefinitionFromContent` parses each `effect` variant; defaults
  (`charges: 1`, `priority: 0`, `target: self`) apply on absence.
- `ConsumablePlugin.initialize`: registers the tag, loads content once
  (idempotent on a second `initialize`), `define`s a bounded charge
  resource per consumable. Runs standalone (no Combat) without throwing.
- Architecture: `lib/src/plugins/consumable/` imports no other plugin
  barrel.

**`ConsumableActionInterpreter`**
- One `CombatAction` per hung `consumable` ref; `heal`→`SelfEffectAction`
  with a `Heal`, `attack`→`AttackAction` targeting the passed enemy,
  `grant`→`SelfEffectAction` with a `GrantModifier` (correct `sourceKey`),
  `removeAllStatuses`→`SelfEffectAction` with `RemoveAllStatuses`.
- Every produced action carries `ConsumeResource(consumable:<id>,1)` in
  `costEffects`, the content `priority`, and `sourceRef == ref`.
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
- `grant` sets `consumable:<id>` on the owner to the summed charge count;
  two hung `heal_potion` refs → charge pool = 2.
- Only `build.active` consumables count; an `owned`-only one grants
  nothing.
- `dispose()` zeroes every granted pool and `removeBySource`es every
  `consumable:<id>:<owner>` modifier; idempotent (twice, and on an empty
  binding).
- Re-`grant` after a placement change resets pools to the new sum (via
  `set`, not `add`).

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

**Integration (`game_run` / `CombatStage`)**
- A run with `heal_potion` hung: the player's `EntityHealed` count
  attributable to `Heal(20)` is `> 0` and `≤ (number of that consumable's
  charges granted across all fights)` — proving both that the action fires
  and that charges are per-fight-bounded (not leaking).
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
   parser + a minimal `consumableContentDefinitions` (1 entry),
   `ConsumablePlugin`. Barrel `lib/consumable_plugin.dart`. Tests +
   architecture guard.
4. `ConsumableActionInterpreter` + add to `build_interpretation.dart`
   barrel; implement the SP2 `auraRules` contract method as `const []`.
   Tests.
5. `ConsumableBinder` / `ConsumableCharges` + barrel. Tests.
6. `ConsumableAwareActionScorer` (`auto_combat/`) + barrel. Tests
   (including the plain-`AttackAction` regression).
7. `game_run.dart` wiring: init `ConsumablePlugin`, composite gains the
   interpreter; `combat_stage.dart` grants/disposes charges and uses the
   new scorer. Integration test (`heal_potion` visible in the run) with
   the mutation check.
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
- All existing tests green (goldens regenerated, diff reviewed,
  determinism preserved); new tests per §9.
- `CHANGELOG.md` + `ARCHITECTURE.md` updated.

## 12. Acceptance invariant ("per-fight consumable" means exactly this)

| Situation | Required behaviour |
|-----------|--------------------|
| Consumable owned but not hung | produces no action; grants no charge |
| Consumable hung, fight starts | charge pool = Σ `charges` over hung refs of that id; the action is selectable while the pool ≥ 1 |
| Consumable used N times in a fight (N = charge total) | the (N+1)th selection is filtered out (`_isAvailable` = false) and, if forced, `CombatSystem` no-ops it |
| Fight ends | every consumable charge pool → 0; every `consumable:<id>:<owner>` modifier removed |
| Next fight starts | charge pool re-set to the full Σ `charges` (refreshed, not depleted) |
| Same seed + same decisions, run twice | identical `RunResult` and identical consumable-use / heal / damage event sequence |
