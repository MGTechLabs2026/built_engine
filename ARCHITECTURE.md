# Build Engine — Architecture

This document describes the engine foundation implemented so far. See
`claude.md` for the full architecture contract this engine follows, and
`PLUGIN_SYSTEM.md` for the plugin lifecycle in detail.

## Core Principle

The core provides generic verbs (create an entity, attach a component,
publish/subscribe to an event, register a plugin). It has no knowledge of
any specific game content — no martial arts, no magic, no combat. All of
that belongs in plugins, built on top of this foundation, in later work.

## Services implemented so far

### EntityId (`lib/src/entity/entity_id.dart`)
An immutable value wrapping a sequential `int`, assigned in creation order.
Sequential (not random) so a run can be reproduced from seed + initial
state + actions.

### EntityRegistry (`lib/src/entity/entity_registry.dart`)
Tracks which `EntityId`s are currently alive. `create()` allocates a new id
and publishes `EntityCreated`; `destroy(id)` removes it and publishes
`EntityDestroyed`. Takes an `EventBus` via constructor injection — there is
no global/singleton event bus.

### ComponentStore (`lib/src/component/component_store.dart`)
Generic storage for components, keyed by the component's runtime `Type`.
Deliberately has **no reference to `EntityRegistry` or `EventBus`** — it is
independently constructible and testable. This is a boundary worth keeping:
it means you can reason about "how components are stored" completely
separately from "how entities are created and destroyed".

### EventBus (`lib/src/event/event_bus.dart`)
Typed publish/subscribe. `subscribe<T>(handler)` registers a handler for
events whose exact runtime type is `T`; `publish<T>(event)` dispatches to
every such handler. There is no dispatch across a type hierarchy (a
subscriber for a supertype will not receive a subtype's events) — every
event type used so far is a concrete, non-hierarchical class, so this has
not been a limitation. Revisit if a future plugin needs otherwise.
`subscribeDynamic(Type, handler)` also exists, for callers that only know
the event type at runtime rather than at compile time (e.g. `RuleEngine`
dispatching on a `Rule.trigger` value read from data).

### Plugin system (`lib/src/plugin/`)
`GamePlugin`, `PluginContext`, and `PluginManager` — see `PLUGIN_SYSTEM.md`
for the full lifecycle, dependency-resolution algorithm, and exception
types. In brief: `PluginManager` topologically sorts registered plugins by
their declared `dependencies` and drives `register`/`initialize`/`start`
(forward, dependency order) and `stop`/`unregister` (reverse order).

### Supporting components (`lib/src/components/`)
`TagSet`, `HealthComponent`, `ResourceComponent`, `StatComponent`,
`StatusComponent` — plain immutable value objects stored via
`ComponentStore`, no game-specific defaults. `StatComponent` is a
stopgap: it's a raw value store until a future Modifier Engine adds
proper `base + modifiers = derived` stat computation; `ModifyStat`
mutates it directly for now.

### RngService (`lib/src/rng/rng_service.dart`)
The only place `dart:math`'s `Random` is allowed to appear in this
package. Seeded and injectable — gameplay code asks `RngService` for
randomness, never `dart:math` directly, so a run stays reproducible from
its seed.

### EventCounter (`lib/src/rule/event_counter.dart`)
Tallies published-event counts per `Type`, but only for types explicitly
`trackType`-registered — there is no retroactive counting. `RuleEngine`
auto-tracks whatever type an `EventCount` condition names, at the moment
the owning rule is registered.

### Query Engine (`lib/src/query/`)
`Query` is a composable predicate over a single entity (`and`/`or`/`not`
combinators plus six concrete queries: `HasComponentQuery`, `HasTagQuery`,
`ResourceAboveQuery`, `ResourceBelowQuery`, `HealthBelowQuery`,
`StatusActiveQuery`). `QueryEngine.evaluate(candidates, query)` finds
every matching entity in a candidate set (typically `EntityRegistry.all`)
— independently useful without any Rule involved.

### Condition / Rule / Effect Engine (`lib/src/rule/`)
`Condition` and `Effect` are public interfaces — plugins implement them
directly, compose `Rule` objects (`trigger`, `subjectOf`, `conditions`,
`effects`) in code, and hand them to `RuleEngine.register`. The six
entity-scoped conditions (`HasTag`, `HasComponent`, `ResourceAbove`,
`ResourceBelow`, `HealthBelow`, `StatusActive`) delegate to the matching
`Query`; `EventCount` and `RandomChance` are not entity queries and
implement `Condition` directly. `RuleEngine` subscribes each rule via
`EventBus.subscribeDynamic` (dispatch on a `Type` known only at runtime),
evaluates every condition (AND) in list order, and runs every effect (in
list order) only if they all pass — no other source of nondeterminism
beyond whatever `RngService` itself produces. There is no registry:
plugins register their own conditions/effects simply by implementing the
public `Condition`/`Effect` interfaces, the same way `GamePlugin` already
is public.

## Integrating EntityRegistry and ComponentStore

Because `ComponentStore` does not know about `EntityRegistry`, component
cleanup on entity destruction is not automatic. Wire them together by
subscribing to `EntityDestroyed`:

```dart
final events = EventBus();
final registry = EntityRegistry(events);
final components = ComponentStore();

events.subscribe<EntityDestroyed>((event) {
  // Call components.remove<T>(event.id) for every component type your
  // application actually uses — ComponentStore has no registry of "every
  // type that has ever been added", so this list is the caller's to know.
  components.remove<SomeComponentType>(event.id);
});
```

This is also the pattern for bootstrapping the three core services together
for a `PluginContext` — construct one `EventBus`, pass the same instance to
both `EntityRegistry` and the `PluginContext`, so plugins that subscribe via
`context.events` actually see entity lifecycle events:

```dart
final events = EventBus();
final context = PluginContext(
  entities: EntityRegistry(events),
  components: ComponentStore(),
  events: events,
);
```

## Dependency rule

Plugins depend on core; core never depends on any plugin. Within core,
services depend only downward toward more primitive services — for
example `EntityRegistry` depends on `EventBus`, never the reverse. See
`PLUGIN_SYSTEM.md` for how this applies across plugins.

## Determinism

`EntityId` allocation is sequential, not random, specifically so that a
run's entity ids are reproducible given the same sequence of `create()`
calls. All randomness is centralized in `RngService` (see above) — gameplay
code asks it for random values, never `dart:math`'s `Random()` directly, so
a run stays reproducible from its seed plus initial state plus actions.

## What's deliberately not here yet

Modifier Engine (proper `base + modifiers` stat derivation — `ModifyStat`
is a deliberate stopgap pending it), Spatial/Container Engine, a
dedicated Resource Engine *service* (this pass added only the
`ResourceComponent` data shape), Scheduler, Asset/Data Registry,
Serialization, and any registry/factory/data-driven rule deserialization
mechanism. Each is a separate future subsystem, to be brainstormed and
planned on its own rather than stubbed out speculatively here.
