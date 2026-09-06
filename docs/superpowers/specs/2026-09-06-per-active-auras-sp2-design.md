# SP2 — Per-active auras ("do X each turn while hung")

**Status:** design, pending review
**Date:** 2026-09-06
**Depends on:** `2026-09-02-tiered-component-effects-design.md` (parent decomposition, §1.2 row **SP2**), which depends on SP1 "Tiered Component Effects" (merged — `EffectProfile` / `EffectContributor` / `ResolvedBuild`).

---

## 1. Problem

SP1 gave a hung component a way to contribute **numbers** — a stat delta
folded once, at build-resolve time, into a static `CombatAction` list
(`CombatStage.runFight`: `tome.resolve` → `interpreter.interpret` →
`List<CombatAction>`). SP1 explicitly deferred anything that *does
something each action* — regen, chip damage, a periodic status — to SP2
(`2026-09-02-tiered-component-effects-design.md` §2.2, §13).

Those effects cannot be a `EffectProfile` entry: they are behaviour over
time, not a scalar. The parent design's own sketch (§13) is: *"'Heal 2
each turn while hung' is a `Rule` on `TurnStarted` … SP2 adds the content
and rules; it reads hung-ness the same way."*

**Goal:** a hung item or technique can carry one or more `Rule`s that are
live **only while that component is in `ResolvedBuild.active`**, fired
through the existing `RuleEngine` off Combat's existing per-turn /
per-action events, authored as **content data**, targeting the build
owner or the owner's current opponent — with no new effect/condition
primitives, no change to `RuleEngine`, and no change to Core's
architecture contract.

## 2. Resolved design decisions

Settled during brainstorming (2026-09-06):

| # | Decision |
|---|----------|
| D1 | An aura is declared the **same way an `EffectProfile` is**: an interface on the component's definition/instance type, resolved off `ResolvedBuild.active` by the build-interpretation layer. **No** `active:<id>` / `equipped:<id>` tag projection. **No** hand-maintained per-plugin rule list. |
| D2 | "While hung" is **not a new concept** — it means the ref is in `ResolvedBuild.active`, the exact membership SP1's `active` tier already uses. |
| D3 | The aura **rule body is an unmodified Core `Rule`** — no bespoke replacement type, no `RuleEngine` change. The contributor returns a thin `AuraRule` record = that raw `Rule` + one `scope` enum + its source id; `scope` is the only piece of aura-specific metadata. |
| D4 | An aura has a **bind → dispose lifecycle** (unlike an `EffectProfile`, which is a stateless fold). Rules are registered with `RuleEngine` when the build resolves and unregistered when the binding is disposed — mirroring the `subscription.cancel()` already in `CombatStage.runFight`. |
| D5 | Aura rule **bodies are content data**, authored through the existing `ContentRegistry.loadRule` DSL (`trigger` / `conditions` / `effects` keys, built-in factories). A component's content references them by id via a new `auras` field. |
| D6 | Aura effects may target the build **owner** (`scope: "self"`, default) **or the owner's current opponent** (`scope: "opponent"`). Cross-entity beyond "the opponent" is out of scope. |
| D7 | `Tome_client` adoption of the binder is **SP4** (the "client surfacing" sub-project). SP2 ships the engine mechanism, the headless-run wiring, and tests. |

> **Refinement note.** Mid-brainstorm the interface was to return raw
> `List<Rule>` with the content author owning `subjectOf`/owner-scoping.
> Once D5 (bodies come from the `loadRule` DSL, whose `subjectOf` is fixed
> by the trigger descriptor) and D6 (owner/opponent scoping) were settled,
> scoping moved to the binder's `_wire` step (§5.4) and the identity-free
> rule body stays fully serializable. D3 above is the resolved form. The
> `auraRules()` accessor is parameterless, matching
> `EffectContributor.effectProfile()`.

## 3. Scope

### 3.1 In scope

- A new Core module `lib/src/aura/` holding `AuraContributor` and the
  `AuraRule` / `AuraScope` value types — no vocabulary. Plus one generic
  `SubjectIs` condition added to `lib/src/rule/system_conditions.dart`.
- `AuraContributor` implemented (via a composing wrapper that holds the
  `ContentRegistry`) for the same two live, Tome-equippable plugins SP1
  wired: generic **Item** (`ItemAuraContributor` over `ItemDefinition`)
  and generic **Technique** (`TechniqueAuraContributor` over the base
  `TechniqueDefinition`).
- An `auras: [<ruleId>, …]` content field on item and technique content
  definitions, resolved against `RuleDefinition`s loaded through the
  existing `loadRule` DSL.
- Combat registering the `TurnStarted` / `TurnEnded` / `ActionCompleted` content
  triggers (keys match the existing `EntityDamaged` convention; only Core
  events are registered today).
- `BuildActionInterpreter` contract gaining an abstract `auraRules(…)`
  method; `ItemActionInterpreter` / `TechniqueActionInterpreter` doing the
  real work; `CompositeBuildActionInterpreter` aggregating.
- A new `AuraBinder` / `AuraBinding` pair in `build_interpretation/`.
- `CombatStage.runFight` binding auras after `tome.resolve` and disposing
  after the fight.
- A **content pass**: auras on a representative subset of the generic
  item/technique roster the headless run loads, covering both `self` and
  `opponent` scopes and both `item` and `technique` reference types.
- Tests (see §9).

### 3.2 Explicitly out of scope

- Any new `Effect` or `Condition` primitive, or new content factory,
  **beyond the single generic `SubjectIs`**. The existing built-in
  factories (`heal`, `damage`, `modifyStat`, `modifyResource`,
  `applyStatus`, `removeStatus`, `addTag`, `removeTag`, `randomChance`,
  `hasTag`, `healthBelow`, `resourceAbove/Below`, `statusActive`, …)
  cover every aura in the content pass.
- **Anti-goal:** aura-oriented Core conditions such as `OwnerIs`,
  `OpponentIs`, `ComponentIsHung`, or `AuraActive`. Any of these would be
  scope/binding logic leaking into Core. `SubjectIs` is acceptable
  *precisely because* it is a generic `context.subject == entity` check
  with no aura, combat, or Tome vocabulary. All owner/opponent/hung
  semantics stay in `AuraBinder._wire` and the interpreter's
  `build.active` filter.
- Any change to `RuleEngine`, `RuleContext`, or `Rule`.
- `Tome_client` — reward affixes rolling an aura, a detail-sheet "while
  active" line, the client feeding `bind`. **SP4.**
- MartialArts' own `equipItem` / `equipped:<id>` / `_passiveResourceRegenRule`
  path (`martial_arts_rules.dart`). That is a separate, style-scoped
  content set that `build_interpretation/` never consumes — the same
  boundary SP1 drew (`2026-09-02-tiered-component-effects-design.md`
  §15.1). Migrating it to the aura interface is a later, explicit
  extension, not implied here.
- Auras that persist **across** fights, or fire outside combat. The
  binding lifecycle is per resolved build (per fight, in the headless
  run).
- Persistence of an `AuraBinding`. Aura `RuleDefinition`s serialize
  through the DSL's existing `ContentRegistry.toJson`; the *binding* is
  transient runtime state derived from a `ResolvedBuild`.
- `EffectProfile` changes. SP2 sits beside the `active`/`supporting`
  tiers, it does not touch them.

## 4. Contract fit (`claude.md`)

| Rule | How SP2 complies |
|------|------------------|
| *Core provides verbs; plugins provide nouns.* | The new Core surface is `AuraContributor` / `AuraRule` / `AuraScope` (a raw Core `Rule` plus a two-value enum) and the `SubjectIs` comparison condition. All aura vocabulary (which item, which effect, "poison", "braced") lives in plugin content JSON. |
| *Gameplay communication must use events.* | Auras fire off `RuleEngine` subscriptions to Combat's existing published events. Nothing intercepts `AttackAction` / `Damage` directly. |
| *Rules must be data-driven where possible.* | Aura bodies are `RuleDefinition`s parsed by the existing `loadRule` DSL from JSON. No aura logic is compiled into the engine. |
| *Never introduce speculative abstractions without a concrete use case.* | One interface, one helper condition, one binder. Concrete uses land immediately in the content pass (both scopes, both ref types). |
| *Composition over inheritance.* | `ItemAuraContributor` / `TechniqueAuraContributor` **compose** a definition + the `ContentRegistry` and **implement** `AuraContributor`. Nothing extends anything. `AuraBinder` is a plain service. |
| *Dependencies point downward.* | `lib/src/aura/` depends only on Core (`Rule`, `Condition`, `EntityId`). `AuraBinder` lives in `build_interpretation/` (plugin layer). It imports no Combat symbol and reads no `TurnStarted`/`ActionCompleted` field — the one Combat-shaped fact it uses, "the trigger descriptor's `subjectOf` yields the acting entity", is the content-registry contract (§5.5). Opponents are **passed in** by the caller, not derived from combat state. |

## 5. Design

### 5.1 `AuraContributor` + `AuraRule` (Core — `lib/src/aura/`)

```dart
enum AuraScope { self, opponent }

/// One aura: an unmodified Core [Rule] body (trigger + conditions +
/// effects, straight from the loadRule DSL) plus the single piece of
/// aura-specific metadata the binder needs to scope it.
class AuraRule {
  const AuraRule({ required this.rule, required this.scope, required this.sourceRuleId });
  final Rule rule;
  final AuraScope scope;
  final String sourceRuleId; // diagnostics ONLY — never a sort key (see §8)
}

/// A component type that can declare rules which are live only while the
/// component is in `ResolvedBuild.active`. The "implement the interface,
/// no registry" pattern `EffectContributor` / `Condition` / `Effect` /
/// `CombatAction` already use. Parameterless, mirroring
/// `EffectContributor.effectProfile()` — owner/opponent identity is
/// injected later by the binder's `_wire` step (§5.4), so the rule body
/// stays identity-free and serializable.
abstract interface class AuraContributor {
  List<AuraRule> auraRules();
}
```

`lib/src/aura/` imports only Core (`Rule`). `AuraScope` / `AuraRule`
carry no vocabulary.

### 5.2 Implementers — composing wrappers (need the `ContentRegistry`)

Resolving `auras` ids → `RuleDefinition` needs `ContentRegistry`, so — as
with `ItemEffectContributor` for items — the interface is implemented by
a **composing wrapper**, not by `ItemDefinition` / `TechniqueVariant`
directly:

```dart
class ItemAuraContributor implements AuraContributor {
  const ItemAuraContributor(this.definition, this.content);
  final ItemDefinition definition;
  final ContentRegistry content;

  @override
  List<AuraRule> auraRules() => [
        for (final ruleId in definition.auraRuleIds)
          AuraRule(
            rule: content.rule(ruleId).rule,
            scope: _scopeOf(content.rule(ruleId)),   // raw['scope'] ?? self
            sourceRuleId: ruleId,
          ),
      ];
}
```

`TechniqueAuraContributor(TechniqueDefinition, ContentRegistry)` is the
exact analogue, reading `auraRuleIds` off the base `TechniqueDefinition`.
(`TechniqueVariant` keeps implementing `EffectContributor` directly — that
needs no registry — but not `AuraContributor`. The asymmetry is the same
one items already have between `ItemInstance`/`ItemEffectContributor`.)

**This asymmetry is deliberate and must be explained in the code
comments** so a later "simplification" does not inject `ContentRegistry`
into `ItemDefinition` / `TechniqueVariant` (Core-adjacent value objects):

| | `EffectContributor` | `AuraContributor` |
|---|---|---|
| does | value calculation | rule-**id** lookup |
| needs | component state only — can be implemented on the state object itself | `ContentRegistry` to resolve ids → `RuleDefinition` — therefore a wrapper, never the state object |

Both `ItemDefinition` and `TechniqueDefinition` gain
`final List<String> auraRuleIds` — parsed from the content JSON `auras`
list, `const []` default, same parsing shape as `trainingWeights` /
`properties`.

`_scopeOf` reads `RuleDefinition.raw['scope']` (`"self"` default,
`"opponent"` the only other accepted value; anything else → validation
error). `scope` is a plain extra key the DSL's own parser already ignores.

> Sub-decision left to the plan: whether `auraRuleIds` can also live on a
> `TechniqueVariant` instance (e.g. an inspired descriptor granting an
> aura). **Default for SP2: definition only** — an inspired/evolved
> *family* still reads its own definition's `auras`. Instance-level aura
> ids need no interface change later (the wrapper can union them in).

### 5.3 `BuildActionInterpreter.auraRules` + composite

```dart
abstract class BuildActionInterpreter {
  List<CombatAction> interpret({ required ResolvedBuild build, /* … */ });

  /// `AuraRule`s to keep live while their owning component is hung. Only
  /// refs in [build.active] are considered.
  List<AuraRule> auraRules({
    required ResolvedBuild build,
    required PluginContext context,
  });
}
```

`auraRules` is **abstract** (no default body) — every existing
`BuildActionInterpreter` in the repo uses `implements`, not `extends`, so
a default would not propagate anyway. All three implementers define it:
`ItemActionInterpreter` / `TechniqueActionInterpreter` do the real work
below; `CompositeBuildActionInterpreter` concatenates its children.

- `ItemActionInterpreter.auraRules` iterates `build.active`, keeps
  `referenceType == itemReferenceType`, resolves the `ItemDefinition`
  with the **same** `context.content.find` call it already makes in
  `profileFor`, builds `ItemAuraContributor(definition, context.content)`,
  and returns its `auraRules()`.
- `TechniqueActionInterpreter.auraRules` does the analogue for
  `techniqueReferenceType` via `TechniqueAuraContributor`.
- `CompositeBuildActionInterpreter.auraRules` concatenates its children's
  results **in child-list order** (`[TechniqueActionInterpreter(),
  ItemActionInterpreter()]` today) → deterministic, then `build.active`
  order within each child, then `auraRuleIds` order within each ref.

### 5.4 `AuraBinder` / `AuraBinding` (`build_interpretation/aura_binder.dart`)

```dart
class AuraBinder {
  const AuraBinder();

  AuraBinding bind({
    required ResolvedBuild build,
    required BuildActionInterpreter interpreter, // the composite
    required PluginContext context,
    List<EntityId> opponents = const [],
  }) {
    final subs = <EventSubscription>[];
    for (final aura in interpreter.auraRules(build: build, context: context)) {
      final wired = _wire(aura, owner: build.owner, opponents: opponents);
      if (wired == null) continue; // opponent-scope aura with no opponent
      subs.add(context.rules.register(wired));
    }
    return AuraBinding(subs);
  }
}

class AuraBinding {
  AuraBinding(this._subs);
  final List<EventSubscription> _subs;
  var _disposed = false;

  /// Idempotent: calling twice (or on an empty binding) never throws and
  /// never leaves a subscription live. Combat setup/cleanup grows
  /// early-return and error paths over time; a binding must be safe to
  /// dispose from any of them, including a `finally` that also runs on
  /// the happy path.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    for (final s in _subs) s.cancel();
    _subs.clear();
  }
}
```

**`_wire(aura, {owner, opponents}) → Rule?`** builds the `Rule` handed to
`RuleEngine.register`, scoping it so a content author never touches
identity. It is the **only** place owner/opponent identity enters an aura
— the `RuleDefinition` body stays identity-free and serializable.

- **`scope: self`** — `subjectOf` pinned to `owner`; a prepended
  `SubjectIs(owner)` guard so a `TurnStarted` aura ticks only on the
  owner's own turn. Effects act on `context.subject == owner`.
- **`scope: opponent`** —
  - `opponents.isEmpty` → `_wire` returns `null`; the aura is **not
    registered** (an opponent-scope aura with nobody to hit is inert, not
    an error).
  - `opponents.length == 1` → the only valid case. `subjectOf` pinned to
    that opponent; guard: *the event's own actor is `owner`* so the aura
    ticks on the owner's turn/action, not the opponent's. The "event's
    actor" is obtained **generically** from the aura rule's already-set
    `subjectOf` (the trigger descriptor's actor extractor, `aura.rule
    .subjectOf`), so `_wire` needs **zero knowledge of `TurnStarted` /
    `ActionCompleted` field shapes**. See §5.5.
  - `opponents.length > 1` → **assertion / `ArgumentError`**. SP2's
    harness is strictly 1‑v‑1; a future multi-enemy mode must define its
    own opponent-selection policy explicitly rather than inherit a silent
    "first wins". This is a deliberate compatibility guard, not a general
    combat rule.
- The aura's own content `conditions` (`healthBelow`, `randomChance`, …)
  are appended **after** the scope guard, so a failing scope guard
  short-circuits first (deterministic, cheap).

**Combat's responsibility vs the binder's.** Combat owns trigger
registration and the event→actor (`subjectOf`) mapping (§5.6). The binder
consumes that mapping and is *handed* the opponent set by its caller — it
does not reconstruct combat semantics. The only Combat-shaped fact the
binder relies on is "the trigger descriptor's `subjectOf` yields the
acting entity", which is the registry's documented contract, not an
event-class detail.

**`AuraBinding` is immutable in membership after `bind`.** A binding is
bound to exactly the `ResolvedBuild.owner` and `opponents` list passed at
`bind` time, and its subscription set never changes afterward. There is
no "update this binding for the new Tome state" path — when the build
changes (a placement moves, a new fight resolves a fresh
`ResolvedBuild`), the sequence is always **dispose old → resolve new →
`bind` new**. `AuraBinder` holds no state between calls (`const
AuraBinder()`); each `bind` produces a self-contained `AuraBinding`. This
rules out a future shortcut that mutates a live binding and silently
crosses owner/opponent identity between fights.

### 5.5 `SubjectIs` (Core — `lib/src/rule/system_conditions.dart`, with the other generic conditions)

```dart
/// Matches when the rule's resolved subject is exactly [entity].
class SubjectIs implements Condition {
  const SubjectIs(this.entity);
  final EntityId entity;
  @override
  bool evaluate(RuleContext context) => context.subject == entity;
}
```

Trivial, generic, no vocabulary — `context.subject == entity`, nothing
more. Used by `_wire` for the `self` guard; also independently useful.
**Do not** grow an aura-specific condition family alongside it
(`OwnerIs`, `OpponentIs`, `ComponentIsHung`, `AuraActive` — see §3.2
anti-goal).

The `opponent`-scope "the event's actor is `owner`" guard is a
**private** condition in `aura_binder.dart` — but it stays event-shape
agnostic. It is constructed with the aura rule's own actor extractor
(`aura.rule.subjectOf`, set by the trigger descriptor) and the `owner`
id, and evaluates `actorExtractor(context.triggerEvent) == owner`. It
never names `TurnStarted` / `ActionCompleted` or reads their fields —
that knowledge lives only in Combat's `registerTrigger` calls (§5.6).

### 5.6 Trigger registration (Combat)

`CombatPlugin.initialize` registers:

| key | event | `subjectOf` |
|-----|-------|-------------|
| `TurnStarted` | `TurnStarted` | `(e) => (e as TurnStarted).actor` |
| `TurnEnded` | `TurnEnded` | `(e) => (e as TurnEnded).actor` |
| `ActionCompleted` | `ActionCompleted` | `(e) => (e as ActionCompleted).actor` |

via `context.content.registerTrigger(...)`. These are Combat's events, so
Combat owns their trigger keys — the same reason Core's built-in triggers
live in `built_in_content_factories.dart`. Idempotent-guard like
`ItemPlugin`'s content-load guard if `initialize` can run twice.

### 5.7 Harness wiring (`CombatStage.runFight`)

```dart
final build = context.tome.resolve(character, ownedRefs: ownedComponentRefs(character, context));
events.publish(ActiveBuildResolved(build.asActiveBuild.components));
final playerActions = interpreter.interpret(build: build, actor: character, targets: [enemyEntity], context: context);
final auras = const AuraBinder().bind(                                   // NEW
  build: build, interpreter: interpreter, context: context, opponents: [enemyEntity],
);
try {
  // … existing fight setup + run …
  controller.runUntilBattleEnds();
} finally {
  subscription.cancel();
  auras.dispose();                                                      // NEW
}
```

`enemyEntity` already exists (`spawnEnemy`'s return). `CombatStage` needs
no new field — `const AuraBinder()` is stateless. The binding is disposed
in a `finally`-equivalent path so it is torn down on **every** exit from
`runFight` — happy path, early return, or throw — and `dispose()` is
idempotent (§5.4) so an added path that also disposes is harmless. The
plan converts `runFight`'s current straight-line body to this
try/finally shape (small, mechanical).

## 6. Event flow (all contracts unchanged)

```
tome.resolve ─▶ ResolvedBuild{owner, active, owned}
     │
     ├─▶ interpreter.interpret(...)        → static CombatActions      (SP1, unchanged)
     └─▶ AuraBinder.bind(...)              → for each active item/technique aura rule:
                                             RuleEngine.register(_wire(rule))
                                             ─▶ EventSubscription

  … fight runs; Combat publishes TurnStarted / ActionCompleted / … as today …
       └─▶ each registered aura rule fires iff its scope guard + content
           conditions pass, applying its content effects to owner or opponent
           and publishing whatever those effects already publish
           (EntityHealed, EntityDamaged, ResourceChanged, StatusApplied, …)

  fight ends ─▶ AuraBinding.dispose() ─▶ every EventSubscription.cancel()
```

No new event types. Aura effects reuse the events their `Effect`
implementations already publish, so `HeadlessGameAlmanacBridge` and the
encounter trail observe them with no bridge change.

## 7. Content pass

Auras added to the generic roster `game_run` loads (`run_content.dart`
starting kit + reward pool + their evolution targets in
`item_content.dart` / `technique_content.dart`). Exact effect keys and
amounts are a content-balance detail for the implementation plan; the
requirement is **coverage**: both scopes, both reference types, at least
one gated (conditional) aura.

| Component | Aura (`aura.<id>`) | trigger | scope | effect sketch |
|-----------|--------------------|---------|-------|---------------|
| `cloth_armor` | `aura.regen_weave` | `TurnStarted` | self | `heal 1` |
| `training_staff` | `aura.braced` | `TurnStarted` | self | `applyStatus "braced"` |
| `training_shoes` | `aura.quickstep` | `TurnStarted` | self | `applyStatus "quickstep"` |
| `warlords_iron_sword` (evo) | `aura.bleed` | `TurnStarted` | opponent | `damage 1` |
| `crushing_gauntlets` (evo) | `aura.thorns` | `ActionCompleted` | opponent | `damage 2` (retaliate) |
| `basic_guard` family | `aura.guard_regen` | `TurnStarted` | self | `healthBelow 20` → `heal 2` |
| one evolved/inspired technique family | `aura.venom` | `TurnStarted` | opponent | `randomChance 0.5` → `damage 2` |

Aura `RuleDefinition`s are loaded in the owning plugin's `initialize`
(Item / Technique), alongside the existing `buildItemUsabilityRules`
registration, via `context.content.loadRule(...)`. They are **not**
`RuleEngine.register`ed at load time — only the binder registers them,
per ref, per fight.

## 8. Determinism

- Aura firing order is fixed by, in this exact precedence:
  child-list order → `build.active` order → `auraRuleIds` order →
  `EventBus` subscription (= registration) order. All are already
  deterministic lists / append-only.
- `RuleEngine.register` → `EventBus.subscribeDynamic` appends; `EventBus`
  dispatches in subscription order. So for a given resolved build, aura
  firing order within one event is fixed by the chain above.
- **`AuraRule.sourceRuleId` is not part of that chain.** It exists for
  diagnostics/logging only. Implementation code must **never** sort or
  re-order `AuraRule`s by `sourceRuleId` (or by any other key) — doing so
  would silently change the ordering guarantee. The list is consumed in
  the order the interpreters produce it.
- Every aura effect that rolls (`randomChance`, any future roll) goes
  through `RuleContext.rng` — the engine's injected `RngService`, never
  `dart:math`. A run stays reproducible from seed + initial state +
  actions.
- `_wire`'s guards are pure comparisons. No ordering nondeterminism
  introduced.
- **Golden impact:** adding auras to shipped content changes headless-run
  outcomes for a fixed seed (extra healing/damage per turn shifts fight
  length and reward timing). This is expected and sanctioned the same way
  SP1's §7 golden shift was — regenerate goldens, review the diff, note
  it in the plan's completion criteria.

## 9. Tests

**Core / `lib/src/aura/`**
- `SubjectIs`: matches / doesn't match / null subject.
- `AuraContributor` is exported from `package:build_engine/build_engine.dart`.

**Item / Technique contributors**
- `ItemAuraContributor.auraRules()` / `TechniqueAuraContributor.auraRules()`
  return one `AuraRule` per `auraRuleIds` entry, with `rule` = the loaded
  body and `scope` from `raw['scope']` (default `self`); `[]` when
  `auraRuleIds` is empty.
- `ItemDefinition` / `TechniqueDefinition` parse `auras` from JSON;
  absent `auras` → `const []`; unknown rule id → `ContentNotFoundException`
  at contributor resolve (or load-time validation — plan decides);
  `scope` other than `self` / `opponent` → validation error.

**`AuraBinder`**
- Registers exactly the rules of refs in `build.active` — a loose
  (`owned`-only) aura item contributes nothing.
- `dispose()` cancels every subscription; after dispose the aura no
  longer fires.
- **`dispose()` is idempotent** — calling it twice, and calling it on a
  binding that registered nothing, never throws and leaves no
  subscription live.
- Re-`bind` after a placement change swaps the live rule set; the prior
  binding's `dispose()` fully detaches the old set. A binding's
  subscription set does not change after `bind` — the only supported flow
  is dispose old → resolve new → `bind` new (no in-place update path).
- Ordering is stable across `AuraRule`s with lexically out-of-order
  `sourceRuleId`s — i.e. nothing sorts by it.
- `scope: self` aura does nothing on the opponent's `TurnStarted`; fires
  on the owner's.
- `scope: opponent`, **1 opponent** → hits only that opponent; ticks on
  the owner's turn/action, not the opponent's.
- `scope: opponent`, **0 opponents** → not registered; no firing, no
  throw.
- `scope: opponent`, **>1 opponents** → `bind` throws `ArgumentError`
  (SP2 compatibility guard).
- The opponent actor-guard works for **both** `TurnStarted` and
  `ActionCompleted` triggers via the generic `subjectOf` extractor — no
  event-type branching in the binder.
- Deterministic firing order with ≥2 active auras on the same event.

**Trigger registration**
- `TurnStarted` / `TurnEnded` / `ActionCompleted` resolve to the right
  event `Type` and `subjectOf` after `CombatPlugin.initialize`.

**Integration (`game_run` / `CombatStage`)**
- A fight with `cloth_armor` hung shows per-turn healing in the encounter
  trail; unhanging it stops the healing.
- A `scope: opponent` aura item shortens a fight vs. the same seed
  without it.
- Two headless runs, same seed → identical `RunResult` (determinism).

**Serialization**
- An aura `RuleDefinition` (with its extra `scope` key) round-trips
  through `ContentRegistry.toJson` → `loadRule`.

**Architecture guards (must stay green)**
- Core-without-plugins, MartialArts-without-Magic, plugin load/unload,
  plugin-state serialization, deterministic-RNG reproducibility — the
  seven `claude.md` integration proofs.
- `lib/src/aura/` imports nothing from `lib/src/plugins/`.

## 10. Rollout / sequencing (for the implementation plan)

1. `SubjectIs` + `AuraScope` / `AuraRule` / `AuraContributor` (Core,
   `lib/src/aura/`), exported. Tests.
2. `BuildActionInterpreter.auraRules` default (`const []`). Tests.
3. `auras` field on `ItemDefinition` + `TechniqueDefinition` parsing;
   `ItemAuraContributor` + `TechniqueAuraContributor`. Tests.
4. `ItemActionInterpreter.auraRules` + `TechniqueActionInterpreter.auraRules`
   + composite aggregation. Tests.
5. `AuraBinder` / `AuraBinding` + `_wire` (both scopes; idempotent
   `dispose`; 0 / 1 / >1 opponent handling; generic actor-guard). Tests.
6. Combat trigger registration (`TurnStarted` / `TurnEnded` /
   `ActionCompleted`). Tests.
7. `CombatStage.runFight` wiring — convert the body to try/finally so the
   binding is disposed on every exit path. Integration test (self-scope
   aura visible in the trail).
8. Content pass — load aura `RuleDefinition`s in Item / Technique
   `initialize`; add `auras` to the §7 components. Regenerate goldens,
   review diff.
9. `CHANGELOG.md` (public surface: `AuraContributor`, `SubjectIs`,
   `AuraBinder` / `AuraBinding`, `BuildActionInterpreter.auraRules`,
   `auras` content field, `TurnStarted` / `TurnEnded` / `ActionCompleted`
   triggers). `ARCHITECTURE.md` — new "Per-active auras" section. Explicit
   dependency guard test.

Commit after every step. Branch: `per-active-auras-sp2`.

## 11. Completion criteria

- `AuraContributor` + `AuraBinder` let a hung item/technique carry
  content-authored rules that fire only while hung, targeting owner or
  opponent, with no `RuleEngine` / `Rule` / contract change.
- The headless run demonstrates at least one `self` and one `opponent`
  aura end-to-end, observable in the encounter trail and reproducible
  from seed.
- All existing tests green (goldens deliberately regenerated, diff
  reviewed); new tests per §9.
- `CHANGELOG.md` + `ARCHITECTURE.md` updated.
- No new effect/condition/factory primitive **beyond `SubjectIs`**; no
  `lib/src/aura/` → plugin import; `aura_binder.dart` imports no Combat
  symbol.
- The contributor-asymmetry rationale (§5.2 table) is present in the code
  comments of `ItemAuraContributor` / `TechniqueAuraContributor`.

## 12. Acceptance invariant ("per-active" means exactly this)

Implementation is complete only when a single integration test
demonstrates the whole chain for a fixed seed + fixed decisions:

| Situation | Required behaviour |
|-----------|--------------------|
| Component owned + loose (in `owned`, not `active`) | aura does **not** fire |
| Component owned + hung (in `active`) | aura fires on its trigger |
| Component unhung mid-run | aura **stops** on the next event after the re-`bind` |
| Fight ends | every aura subscription disposed (none survive into teardown) |
| Next fight | only fresh bindings exist — no leakage from the previous fight |
| Same seed + same decisions, run twice | identical aura event/effect sequence (and identical `RunResult`) |
