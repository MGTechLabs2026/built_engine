# Combat Plugin — Design

## Purpose

Implement Combat as an ordinary plugin on top of the existing Build Engine
core (Entity Registry, Component Store, Event Bus, Query Engine, Rule
Engine, Modifier Engine, Resource data, RNG Service). Core remains
completely unaware of "combat", "turn", "battle", "action", or "attack" —
those concepts are defined entirely inside the Combat plugin, per
`claude.md`'s CORE PROVIDES VERBS / PLUGINS PROVIDE NOUNS contract.

Combat must not implement martial arts, magic, cultivation, or weapons.
Those are separate future plugins that will *depend on* Combat (per
claude.md's DEPENDENCY RULE: `Magic -> Combat -> Core`, never the reverse).

## Context: what already exists

The engine (package `build_engine`, Dart) already has, independent of any
plugin: `EntityRegistry`/`EntityId`, `ComponentStore`, `EventBus`,
`RngService`, `Query`/`QueryEngine` (with `HasComponentQuery`, `HasTagQuery`,
`ResourceAboveQuery`, `ResourceBelowQuery`, `HealthBelowQuery`,
`StatusActiveQuery`), `Condition`/`Effect`/`Rule`/`RuleEngine`/`RuleContext`
(with `Damage`, `Heal`, `ModifyStat`, `ModifyResource`, `ApplyStatus`,
`RemoveStatus`, `AddTag`, `RemoveTag`, `CreateEntity`, `DestroyEntity`,
`TransformEntity` effects, and `HasTag`, `HasComponent`, `ResourceAbove`,
`ResourceBelow`, `HealthBelow`, `StatusActive`, `EventCount`,
`RandomChance` conditions), `Modifier`/`ModifierCollection`/
`ModifierResolver`, and a generic `Container`/spatial system. `GamePlugin`/
`PluginContext`/`PluginManager` implement the plugin lifecycle, but no real
plugin has been built yet — Combat is the first.

`PluginContext` currently exposes only `entities`, `components`, `events`
— RngService, RuleEngine, QueryEngine, and ModifierCollection exist in core
but aren't reachable from a plugin's lifecycle methods yet. `ARCHITECTURE.md`
explicitly anticipates this: "When those services are built, `PluginContext`
grows to expose them."

## Core change: extend `PluginContext`

Add four fields to `PluginContext` (`lib/src/plugin/plugin_context.dart`):

```dart
class PluginContext {
  const PluginContext({
    required this.entities,
    required this.components,
    required this.events,
    required this.rng,
    required this.rules,
    required this.queries,
    required this.modifiers,
  });

  final EntityRegistry entities;
  final ComponentStore components;
  final EventBus events;
  final RngService rng;
  final RuleEngine rules;
  final QueryEngine queries;
  final ModifierCollection modifiers;
}
```

`ModifierResolver` is deliberately **not** added — it's a stateless pure
function (`const ModifierResolver()`), instantiated locally wherever it's
needed rather than shared as a service.

This is additive but source-breaking for existing direct `PluginContext(...)`
constructor calls (test setup code) — those call sites are updated as part
of this work, not left broken. No plugin lifecycle signatures change.

## New plugin: `lib/src/plugins/combat/`

Combat lives in the same package (no workspace/multi-package tooling exists
yet, and nothing in `claude.md` requires separate packages — the plugin
boundary is enforced by the `GamePlugin`/`PluginContext` contract and the
"plugins use only public contracts" convention, not by package boundaries).
Combat imports core exclusively via the public `package:build_engine/build_engine.dart`
barrel, never `src/`, keeping the same isolation discipline
`PLUGIN_SYSTEM.md` already asks of plugin-to-plugin access.

```
lib/src/plugins/combat/
  combatant_component.dart
  combat_state_component.dart
  combat_events.dart
  combat_action.dart
  combat_system.dart
  combat_plugin.dart
  illegal_action_exception.dart
lib/combat_plugin.dart   # public export barrel for this plugin
```

### `CombatantComponent`

```dart
class CombatantComponent {
  const CombatantComponent({required this.team, this.initiative = 0});
  final String team;     // arbitrary label; Combat never interprets its value
  final num initiative;  // turn order: higher acts first
}
```

### `CombatStateComponent`

Attached to a **battle entity** — a battle is itself an `EntityId`, so
multiple concurrent battles are supported with zero extra machinery.

```dart
class CombatStateComponent {
  const CombatStateComponent({
    required this.participants,      // List<EntityId>, fixed initiative order
    required this.currentTurnIndex,
    required this.round,
    required this.active,
  });
}
```

Both components get `toJson`/`fromJson` (entity ids serialized as their
stable `int` `.value`), mirroring `Container.toJson`/`fromJson`'s precedent
of module-local, stable-ID-based serialization — not an integration point
for the engine-wide Serialization service (still deferred, per
`ARCHITECTURE.md`).

### Events (`combat_events.dart`)

Plain, generic event classes — no content vocabulary:

- `ActionStarted(EntityId battle, EntityId actor, List<EntityId> targets, CombatAction action)`
- `ActionCompleted(EntityId battle, EntityId actor, List<EntityId> targets, CombatAction action)`
- `TurnStarted(EntityId battle, EntityId actor, int round)`
- `TurnEnded(EntityId battle, EntityId actor, int round)`
- `BattleStarted(EntityId battle, List<EntityId> participants)`
- `BattleWon(EntityId battle, String team)`
- `BattleLost(EntityId battle, String team)`

`ActionStarted`/`ActionCompleted` fire whether or not the action's
conditions passed, so observers can distinguish "attempted but failed
conditions" (both events, no `EntityDamaged`/etc. in between) from "never
attempted" (an `IllegalActionException` was thrown instead, nothing
published).

### Action / Target model (`combat_action.dart`)

No dedicated `Target` class — a target set is just `List<EntityId>`, chosen
by whichever caller builds the action (AI, UI, a future plugin). This is a
deliberate YAGNI call: nothing today needs "all opponents"/"self" resolver
strategies, and adding one later is non-breaking.

`CombatAction` is abstract, mirroring the existing `Condition`/`Effect`
pattern ("plugins implement this directly — no registry required"):

```dart
abstract class CombatAction {
  EntityId get actor;
  List<EntityId> get targets;

  /// Checked against [actor] before anything else applies. Every
  /// condition must pass (AND) for costEffects/target effects to run.
  List<Condition> get conditions => const [];

  /// Applied once to [actor] if [conditions] all pass.
  List<Effect> get costEffects => const [];

  /// Applied once per entry in [targets] if [conditions] all pass.
  /// [context] is the owning PluginContext — passed here (rather than
  /// resolved once at construction) so an action can read
  /// execution-time state, e.g. Modifier Engine-derived values, exactly
  /// when it actually runs.
  List<Effect> effectsFor(EntityId target, PluginContext context);
}
```

A caller models "chance to miss" by adding a `RandomChance(p)` condition —
no bespoke accuracy mechanism needed; RNG usage falls straight out of the
existing `Condition` system.

Concrete actions use `extends CombatAction`, not `implements` — `implements`
would silently discard `conditions`/`costEffects`'s default bodies (Dart
only inherits a method's implementation through `extends`), the same
reason `Query`'s own concrete subclasses (`HasComponentQuery`, etc.)
already `extend Query` rather than `implement` it elsewhere in this
codebase.

`AttackAction` is the required generic demonstration — no Sword/Punch/
Fireball, and no core change beyond the `PluginContext` extension above:

```dart
class AttackAction extends CombatAction {
  AttackAction({
    required this.actor,
    required this.targets,
    required this.baseDamage,
    required this.damageStat,
    this.conditions = const [],
    this.costEffects = const [],
  });

  @override
  final EntityId actor;
  @override
  final List<EntityId> targets;
  final num baseDamage;
  final String damageStat;
  @override
  final List<Condition> conditions;
  @override
  final List<Effect> costEffects;

  @override
  List<Effect> effectsFor(EntityId target, PluginContext context) {
    final resolved = const ModifierResolver().resolve(
      baseDamage,
      context.modifiers.activeModifiersFor(actor, damageStat, context.components),
    );
    return [Damage(resolved)];
  }
}
```

Feeding `baseDamage` directly into `ModifierResolver.resolve`'s `base`
parameter (rather than resolving a bonus separately and adding it) is the
same `base + modifiers = derived` convention `claude.md`'s MODIFIER SYSTEM
section and `ModifierResolver`'s own pipeline already define — it's also
what makes `multiply`/`override`/`min`/`max` modifiers behave correctly
against the real damage value. `AttackAction` reuses the existing core
`Damage` effect unmodified. This is the concrete payoff of routing damage
through the Modifier Engine: a future Magic or Cultivation plugin can
register a `Modifier(target: actor, stat: damageStat, operation: multiply,
value: 1.25)` and Combat's damage calculation picks it up automatically,
with zero Combat-side knowledge that Magic exists — and it needed no
changes to `RuleContext` or `RuleEngine`, only the `PluginContext`
extension already planned above.

"Healing" (the other concept `claude.md` asks Combat to implement) needs no
dedicated `HealAction` class — any `CombatAction` implementation whose
`effectsFor` returns `[Heal(x)]` runs through the exact same
`CombatSystem.executeAction` pipeline as `AttackAction`. The integration
test proves this directly rather than adding a speculative production
class nothing else asks for.

### `CombatSystem` (`combat_system.dart`)

Constructed once by `CombatPlugin.initialize()` and exposed as a public
getter on the plugin instance (`combatPlugin.system`) — there's no
service-locator in core, so callers hold the `CombatPlugin` object directly,
same as any `PluginManager` caller already does.

- **`startBattle(List<EntityId> participants) → EntityId`** — creates the
  battle entity, stable-sorts `participants` by descending
  `CombatantComponent.initiative` (ties broken by input order — same
  convention `ModifierResolver` already uses), stores `CombatStateComponent`,
  publishes `BattleStarted`, then `TurnStarted` for the first participant.

- **`executeAction(EntityId battle, CombatAction action)`**:
  1. Throws `IllegalActionException` if the battle is inactive or it isn't
     `action.actor`'s turn (programmer-error case — mirrors `Spatial`'s
     `InvalidPlacementException` convention: illegal *use* throws, a
     legal-but-unsuccessful *outcome* does not).
  2. Publishes `ActionStarted`.
  3. Evaluates `action.conditions` against `actor` via a `RuleContext`
     (`subject: actor`, `triggerEvent: action`, `rng`/`eventCounts` from
     `context.rng`/`context.rules.eventCounts`) — the same public
     `RuleContext` type `RuleEngine` itself uses, no new machinery.
  4. If conditions pass: applies `action.costEffects` to `actor`, then for
     each entry in `action.targets` calls `action.effectsFor(target,
     context)` and applies the returned effects via their own
     `RuleContext(subject: target, ...)` — reusing `Damage`/`Heal`/
     `ModifyResource` etc. as-is. Any `EntityKilled` this raises is caught
     by `CombatSystem`'s subscription, but the resulting team-elimination
     check is deferred rather than run immediately — see Defeat/battle end
     below.
  5. Runs the team-elimination check for `battle` exactly once (whether or
     not any kill happened) — may publish `BattleWon`/`BattleLost` and mark
     the battle inactive.
  6. Publishes `ActionCompleted`.
  7. Advances the turn: publishes `TurnEnded` for the current actor
     unconditionally (their turn genuinely ended regardless of what
     happens next), then — only if the battle is still active — skips any
     participant that's no longer living and publishes `TurnStarted` for
     the next one. If the battle ended in step 5, no `TurnStarted` follows.

- **Defeat / battle end**: `CombatSystem` subscribes to core's
  `EntityKilled` at construction, for deaths caused by anything other than
  a Combat-mediated action (e.g. a future Status plugin's independent
  poison-tick rule) — on such a kill, for every active battle containing
  that entity as a participant, it runs the team-elimination check below
  immediately. While `executeAction` is applying an action's own effects,
  that per-kill check is suppressed (a simple in-flight flag), and
  `executeAction` instead runs the check exactly once, after every
  `costEffects`/`effectsFor` effect for the action has been applied and
  before `ActionCompleted`/turn advancement. This matters because a single
  action can target — and kill — multiple different-team entities in one
  call (e.g. an area effect); checking after each individual `EntityKilled`
  would let the first death's check run before the second death has
  landed, misjudging a mutual-kill as a normal win. Checking once per
  action batch instead, after every target's effects are in, is always
  correct because a single `EntityKilled` from outside `executeAction`,
  by construction, isn't part of any such batch.

  The check itself: recompute living participants via
  `QueryEngine.evaluate(participants, HealthBelowQuery(1).not())` (reusing
  the existing Query system rather than inventing an "IsAlive" query
  type), group them by `CombatantComponent.team`. If the number of
  distinct teams remaining is ≤ 1: mark the battle inactive, publish
  `BattleWon(battle, team)` for the sole surviving team (if any), and
  `BattleLost(battle, team)` for every team that had a living participant
  at battle start but has none now. Mutual annihilation (zero teams
  remaining) publishes `BattleLost` for every starting team and no
  `BattleWon`.

## Plugin (`combat_plugin.dart`)

```dart
class CombatPlugin extends GamePlugin {
  @override
  String get id => 'combat';

  @override
  String get version => '0.1.0';

  // No dependencies — Combat sits directly on Core, matching
  // claude.md's `Combat -> Core` (never `Combat -> Magic`).

  late final CombatSystem system;

  @override
  void initialize(PluginContext context) {
    system = CombatSystem(context);
  }
}
```

## Testing plan

- Unit tests: `CombatantComponent`, `CombatStateComponent` (including
  `toJson`/`fromJson` round-trips), `AttackAction.effectsFor` (flat damage
  with no modifiers registered, and modifier-resolved damage once a
  `Modifier` is registered against the actor's chosen stat), `CombatSystem`
  turn-order (initiative sort + ties), `executeAction` illegal-use throwing,
  condition-gated cost (insufficient resource via `ResourceBelow` → no
  `ModifyResource`/`Damage` applied, turn still advances), RNG-gated miss
  via `RandomChance` (same: effects skipped, events still fire), and a
  minimal test-only `CombatAction` implementation whose `effectsFor`
  returns `[Heal(x)]` to prove the same execution pipeline handles healing
  without a dedicated `HealAction` class.
- Plugin lifecycle tests: registration/initialization, `dependencies` is
  empty, Combat boots and runs correctly with **no other plugin present**
  (mirrors `core_boots_without_plugins_test.dart`'s pattern, applied one
  level up).
- Integration test: two generic combatants only (`CombatantComponent(team:
  "alpha"/"beta")`, `HealthComponent`, `TagSet` optionally) — start a
  battle, run `AttackAction`s back and forth, assert
  `ActionStarted`/`ActionCompleted`/`EntityDamaged`/`TurnEnded`/
  `TurnStarted` fire in order, reduce one side to 0 health, assert
  `EntityKilled` → `BattleWon`/`BattleLost` and the battle goes inactive.
  No Sword/Punch/Fireball or any domain vocabulary appears anywhere in this
  test.

## Explicitly out of scope

- Serialization into the engine-wide save format (still deferred generally;
  Combat's own `toJson`/`fromJson` on its two components is local-only,
  same as `Container`'s).
- Multi-action turns, fleeing, AI decision-making, targeting-resolver
  strategies (`AllOpponents`, `Self`, etc.) — nothing today needs them, and
  `List<EntityId>` targets keeps the door open for a non-breaking future
  addition.
- Any martial-arts/magic/cultivation/weapon content — those are separate
  future plugins that depend on Combat.
