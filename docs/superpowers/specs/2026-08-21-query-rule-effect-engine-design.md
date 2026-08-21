# Build Engine — Query / Condition / Rule / Effect Engine Design

Date: 2026-08-21
Status: Approved

## Purpose

Extend the `build_engine` foundation (EntityId, EntityRegistry, ComponentStore,
EventBus, plugin system — all shipped) with the next module: a Query Engine,
a composable Condition system, a Rule Engine, and an Effect Engine, per
`claude.md`'s core service list. This module lets content plugins define
generic `Rule { trigger, conditions, effects }` objects entirely out of
composable, reusable, non-game-specific building blocks — the engine itself
never branches on any content-specific value.

No martial-arts, magic, cultivation, or other game-specific code. No
Modifier Engine, Spatial/Container Engine, Resource Engine (as its own
service — see below), Scheduler, Asset/Data Registry, or Serialization —
each remains a separate future pass.

## Extensibility Model (decided with the user)

Condition and Effect are public abstract interfaces. Plugins implement them
as ordinary Dart classes and compose `Rule` objects directly in code — no
registry, no string-keyed factories, no data-driven (JSON-like) rule
deserialization. "Register additional conditions and effects" means the
interfaces are public and pluggable, the same way `GamePlugin` already is.
Data-driven rule loading from files is explicitly future work, belonging to
the (not-yet-built) Asset/Data Registry + Serialization passes.

## New Supporting Data (prerequisite, not separately requested, but required)

None of `HasTag`, `ResourceAbove`, `HealthBelow`, `StatusActive`,
`ModifyStat`, etc. mean anything without somewhere to read/write. These are
plain, generic, immutable value-object components — no game-specific
defaults or hardcoded names anywhere in their code — stored via the
existing `ComponentStore`. New directory `lib/src/components/` (distinct
from `lib/src/component/`, which holds the storage mechanism itself):

- `TagSet { Set<String> tags }`
- `HealthComponent { num current, num max }`
- `ResourceComponent { Map<String, num> resources }` — named numeric pools;
  the engine never hardcodes a resource name.
- `StatComponent { Map<String, num> stats }` — named numeric attributes.
  **Explicitly a stopgap**: CLAUDE.md's Modifier System says stats should
  be `base + modifiers = derived`, which is Modifier Engine's job and isn't
  built this pass. `ModifyStat` (below) does a direct raw mutation on this
  component until Modifier Engine supersedes it — documented as temporary
  in both the doc comment and `ARCHITECTURE.md`.
- `StatusComponent { Set<String> activeStatuses }` — named status-effect
  flags, no duration/stacking (Scheduler/Modifier territory, out of scope).

All five are immutable (`final` fields, `const` constructors where
practical); every effect that "mutates" one constructs a new instance and
overwrites via `ComponentStore.add` — consistent value-object treatment,
no split between mutate-in-place and replace-on-write components.

## EventBus Extension (touches previously-merged code)

`RuleEngine` must subscribe using a `Type` value it only knows at runtime
(a `Rule`'s `trigger` field), but `EventBus.subscribe<T>()` requires a
compile-time type parameter — Dart generics can't be instantiated from a
runtime `Type`. Add one new, purely additive method to
`lib/src/event/event_bus.dart`:

```dart
EventSubscription subscribeDynamic(Type type, void Function(Object event) handler) {
  final handlers = _handlers.putIfAbsent(type, () => <void Function(Object?)>[]);
  void wrapped(Object? event) => handler(event!);
  handlers.add(wrapped);
  return EventSubscription._(() => handlers.remove(wrapped));
}
```

Uses the exact same internal storage (`Map<Type, List<void Function(Object?)>>`)
introduced by the Task-3 fix in the foundation pass. `subscribe<T>` and
`publish<T>`'s existing behavior and tests are completely unaffected —
this is a new entry point, not a change to an existing one.

## RngService (new, minimal)

Required for `RandomChance` and for the "rules execute deterministically"
requirement. A thin injectable wrapper — the *only* place `dart:math`'s
`Random` is permitted to appear in this package; everything else asks
`RngService`, never `dart:math` directly (this supersedes the foundation
pass's blanket "no Random() anywhere" constraint — this pass explicitly
builds the sanctioned boundary CLAUDE.md's Determinism section describes).

```dart
class RngService {
  RngService(int seed) : _random = Random(seed);
  final Random _random;
  double nextDouble() => _random.nextDouble();
  int nextInt(int max) => _random.nextInt(max);
  bool chance(double probability) => _random.nextDouble() < probability;
}
```

## EventCounter (new, minimal)

Required for `EventCount`. Subscribes to a specific event type only once
asked (`trackType`), tallies occurrences, and reports them (`countOfType`).
Counting starts from zero at the moment `trackType` is called, not
retroactively — `RuleEngine` calls `trackType` automatically for every
`EventCount` condition's named event type, at the moment the owning rule is
registered, so tracking is always active before any rule that depends on it
can fire.

```dart
class EventCounter {
  EventCounter(this._events);
  final EventBus _events;
  final Map<Type, int> _counts = {};

  void trackType(Type type) {
    if (_counts.containsKey(type)) return;
    _counts[type] = 0;
    _events.subscribeDynamic(type, (_) => _counts[type] = (_counts[type] ?? 0) + 1);
  }

  int countOfType(Type type) => _counts[type] ?? 0;
}
```

## Query Engine

Composable predicates over a **single entity**, independently useful and
testable without any Rule involved (e.g. "find every entity with tag
`enemy` whose health is below 50").

```dart
class QueryScope {
  const QueryScope({required this.components});
  final ComponentStore components;
}

abstract class Query {
  bool matches(EntityId id, QueryScope scope);
}

class HasComponentQuery<T extends Object> implements Query { ... }
class HasTagQuery implements Query { final String tag; ... }
class ResourceAboveQuery implements Query { final String resource; final num threshold; ... }  // strictly greater than: value > threshold
class ResourceBelowQuery implements Query { final String resource; final num threshold; ... }  // strictly less than: value < threshold
class HealthBelowQuery implements Query { final num threshold; ... }   // strictly less than, compares HealthComponent.current, absolute value, not a % of max
class StatusActiveQuery implements Query { final String status; ... }
class AndQuery implements Query { final List<Query> queries; ... }
class OrQuery implements Query { final List<Query> queries; ... }
class NotQuery implements Query { final Query query; ... }

class QueryEngine {
  const QueryEngine(this.scope);
  final QueryScope scope;
  Iterable<EntityId> evaluate(Iterable<EntityId> candidates, Query query) =>
      candidates.where((id) => query.matches(id, scope));
}
```

`QueryEngine` takes any `Iterable<EntityId>` of candidates (typically
`EntityRegistry.all`) rather than holding an `EntityRegistry` itself —
consistent with `ComponentStore` not knowing about `EntityRegistry` either.

An entity with no `ResourceComponent` at all, or one whose `resources` map
has no entry for the named resource, is treated as if that resource were
`0` for `ResourceAboveQuery`/`ResourceBelowQuery` (so `ResourceBelow` with
any positive threshold matches an entity that never had the resource set
up at all — this is intentional and documented, not a gap). Same default
applies to the `ResourceAbove`/`ResourceBelow` conditions below.

## Condition System

Rule-scoped boolean checks against a `RuleContext`. The six entity-scoped
conditions are thin wrappers delegating to the matching `Query` (reuse, not
duplication); `EventCount` and `RandomChance` are not entity queries and
implement `Condition` directly.

```dart
class RuleContext {
  const RuleContext({
    required this.subject,
    required this.triggerEvent,
    required this.entities,
    required this.components,
    required this.events,
    required this.rng,
    required this.eventCounts,
  });
  final EntityId? subject;
  final Object triggerEvent;
  final EntityRegistry entities;
  final ComponentStore components;
  final EventBus events;
  final RngService rng;
  final EventCounter eventCounts;
}

abstract class Condition {
  bool evaluate(RuleContext context);
}

class HasTag implements Condition { final String tag; ... }              // wraps HasTagQuery
class HasComponent<T extends Object> implements Condition { ... }         // wraps HasComponentQuery<T>
class ResourceAbove implements Condition { final String resource; final num threshold; ... }
class ResourceBelow implements Condition { final String resource; final num threshold; ... }
class HealthBelow implements Condition { final num threshold; ... }
class StatusActive implements Condition { final String status; ... }

enum CountComparison { greaterThan, greaterThanOrEqual, lessThan, lessThanOrEqual, equal }

class EventCount implements Condition {
  final Type eventType;
  final CountComparison comparison;
  final int threshold;
  // evaluate: compares context.eventCounts.countOfType(eventType) against threshold per comparison
}

class RandomChance implements Condition {
  final double probability; // 0.0-1.0
  // evaluate: context.rng.chance(probability)
}
```

Every entity-scoped condition returns `false` if `context.subject` is
`null` (no crash, no exception — a rule with no resolvable subject simply
never satisfies an entity-scoped condition).

## Effect System

```dart
abstract class Effect {
  void apply(RuleContext context);
}

class Damage implements Effect { final num amount; ... }
class Heal implements Effect { final num amount; ... }
class ModifyStat implements Effect { final String stat; final num delta; ... }   // stopgap direct mutation, see above
class ModifyResource implements Effect { final String resource; final num delta; ... }
class ApplyStatus implements Effect { final String status; ... }
class RemoveStatus implements Effect { final String status; ... }
class AddTag implements Effect { final String tag; ... }
class RemoveTag implements Effect { final String tag; ... }
class CreateEntity implements Effect { final Set<String> tags; ... }      // creates a NEW entity, not the subject
class DestroyEntity implements Effect { /* destroys context.subject */ }
class TransformEntity implements Effect { final Set<String> newTags; ... } // wholesale TagSet replacement
```

- Every subject-scoped effect (`Damage`, `Heal`, `ModifyStat`,
  `ModifyResource`, `ApplyStatus`, `RemoveStatus`, `AddTag`, `RemoveTag`,
  `DestroyEntity`, `TransformEntity`) no-ops if `context.subject` is `null`.
- `Damage`/`Heal` clamp `HealthComponent.current` to `[0, max]`, always
  publish `EntityDamaged`/`EntityHealed` (new event classes — CLAUDE.md
  lists them; they don't exist yet), and `Damage` additionally publishes
  `EntityKilled` when `current` reaches exactly `0`. Neither effect calls
  `entities.destroy()` — death-triggered destruction stays a policy
  decision for whoever reacts to `EntityKilled`.
- `AddTag`/`RemoveTag`/`ApplyStatus`/`RemoveStatus`/`ModifyStat`/
  `ModifyResource` each: read the existing component (treating absence as
  an empty/zero default), construct the updated value, and
  `ComponentStore.add` it back (overwrite semantics, not in-place
  mutation, since the components are immutable value objects).
- `CreateEntity` creates a new entity via `context.entities.create()` and,
  if `tags` is non-empty, attaches a `TagSet`. No further arbitrary
  component-initialization hook — that would be speculative; further setup
  happens by reacting to the `EntityCreated` event another rule/plugin
  already gets from `EntityRegistry`.
- `DestroyEntity` just calls `context.entities.destroy(subject)` —
  component cleanup stays the caller's job via the `EntityDestroyed`
  subscription pattern `ARCHITECTURE.md` already documents; this effect
  doesn't special-case it.

## Rule + RuleEngine

```dart
class Rule {
  const Rule({
    required this.trigger,      // Type — the event class this rule listens for
    this.subjectOf,             // EntityId? Function(Object event)?
    this.conditions = const [],
    required this.effects,
  });
  final Type trigger;
  final EntityId? Function(Object event)? subjectOf;
  final List<Condition> conditions;
  final List<Effect> effects;
}

class RuleEngine {
  RuleEngine({
    required EntityRegistry entities,
    required ComponentStore components,
    required EventBus events,
    required RngService rng,
  });

  void register(Rule rule);
}
```

`register(rule)`:
1. For every condition in `rule.conditions` that is an `EventCount`, calls
   `eventCounts.trackType(condition.eventType)` — a small, direct type
   check in `RuleEngine`, not a generic marker-interface mechanism (only
   one condition type needs this; a marker interface for a single
   implementor would be speculative).
2. Subscribes via `events.subscribeDynamic(rule.trigger, (event) => _fire(rule, event))`.

`_fire(rule, event)`: resolves `subject = rule.subjectOf?.call(event)`,
builds a `RuleContext`, evaluates every condition (AND — all must pass),
and if they do, runs every effect **in list order** (deterministic). No
`unregister` capability yet — not requested, nothing in this pass needs to
tear a rule down.

## Testing

Unit tests for every new class (components, `RngService`, `EventCounter`,
every `Query`/combinator, every `Condition`, every `Effect`, `Rule`/
`RuleEngine`'s registration and dispatch). One integration test proving the
full requested chain end-to-end with real (non-fake) services:

Event → Rule (subscribed via `RuleEngine.register`) → Condition (`HasTag`
+ `HealthBelow` both pass) → Effect (`Damage`) → State change (`HealthComponent.current`
decreases, `EntityDamaged` published) — using a small test-only trigger
event class (not a new production event type), since the trigger itself is
a plugin/content concern, not something the engine defines.

## Documentation Deliverables

Amend `ARCHITECTURE.md`'s "Services implemented so far" and "What's
deliberately not here yet" sections to reflect the new services and
correctly move Query Engine/Rule Engine/Effect Engine out of the
not-yet-built list (Modifier Engine, Spatial/Container Engine, Resource
Engine *as a dedicated service*, Scheduler, RNG Service *as the general
concept beyond this minimal wrapper*, Asset/Data Registry, Serialization
remain not-yet-built). No new top-level doc file — this module's detail
fits as new sections in `ARCHITECTURE.md` alongside the existing ones,
matching how Query/Condition/Rule/Effect are one cohesive "module" per the
user's framing.

## Explicitly Out of Scope

Modifier Engine (base+modifier stat derivation — `ModifyStat` is a
deliberate stopgap pending it), Spatial/Container Engine, a dedicated
Resource Engine service (this pass adds only the `ResourceComponent` data
shape, not a management service), Scheduler, Asset/Data Registry,
Serialization, any registry/factory/data-driven rule deserialization
mechanism, `Rule.unregister`, and any game-specific content of any kind.
