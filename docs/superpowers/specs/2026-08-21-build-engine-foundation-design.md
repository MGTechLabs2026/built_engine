# Build Engine — Foundation Bootstrap Design

Date: 2026-08-21
Status: Approved

## Purpose

Bootstrap the Build Engine repository per `CLAUDE.md`'s architecture contract.
This spec covers **only** the engine foundation — Entity Registry, Component
Store, Event Bus, and the Plugin system (interface, manager, context, basic
dependency resolution). No martial-arts, magic, combat, or other game-specific
content is in scope. No rule/effect/modifier/query/spatial/resource/scheduler/
RNG/serialization services are in scope for this pass — those are future
subsystems built on top of this foundation.

## Context

The repository was empty except for `CLAUDE.md` at the time of writing. It was
also not its own git repository — it was nested inside the user's home
directory git repo (confirmed via `git rev-parse --show-toplevel` resolving to
`/Users/m4maxpro`). Per the user's standing rule to never commit into the home
repo, this bootstrap includes initializing a dedicated repo for this project.

Language/runtime and git isolation were decided with the user directly:
- **Dart** (not TypeScript) — matches the user's 15-year Flutter background.
  Dart 3.7.2 is installed locally (bundled with the Flutter SDK), being
  upgraded to latest as part of this task.
- **Dedicated git repo**, initialized in this folder, separate from the home
  directory repo.

## Package Structure

A single pure-Dart package (no Flutter SDK dependency) named `build_engine` at
the repo root. Pure Dart, not a Flutter package, because the engine must
remain usable headless and free of any presentation-framework dependency —
Flutter is a presentation concern, and CLAUDE.md's core/plugin separation
means the engine core must not depend on it. A monorepo (e.g. via `melos`)
is not used yet — that structure is easy to grow into later once real content
plugins exist (move `lib/` under `packages/core/lib/`); creating it now would
be a speculative abstraction with no current consumer.

```
build_engine/
  lib/
    build_engine.dart              # barrel export of public API
    src/
      entity/entity_id.dart
      entity/entity_registry.dart
      component/component_store.dart
      event/event_bus.dart
      plugin/game_plugin.dart
      plugin/plugin_context.dart
      plugin/plugin_manager.dart
      plugin/plugin_exceptions.dart
  test/
    entity_id_test.dart
    entity_registry_test.dart
    component_store_test.dart
    event_bus_test.dart
    plugin_manager_test.dart
    integration/core_boots_without_plugins_test.dart
  ARCHITECTURE.md
  PLUGIN_SYSTEM.md
  pubspec.yaml
  analysis_options.yaml
```

## Components

### EntityId
Immutable value type wrapping a monotonically increasing `int`. Not a random
UUID: CLAUDE.md's Determinism section requires a run to be reproducible from
seed + initial state + player actions, and deterministic ID assignment
(sequential, in creation order) supports that; random UUIDs would not.
Overrides `==`/`hashCode`, implements `Comparable<EntityId>` for stable
ordering, and exposes its underlying `int` for serialization (stable IDs per
CLAUDE.md's Serialization section).

### EntityRegistry
- `EntityId create()` — allocates the next ID, marks it alive, emits
  `EntityCreated`.
- `void destroy(EntityId id)` — marks the ID dead, emits `EntityDestroyed`.
  Throws if the ID is not alive.
- `bool isAlive(EntityId id)`
- `Iterable<EntityId> get all` — currently-alive entities.

Takes an `EventBus` at construction (dependency injection, not a singleton)
and publishes lifecycle events through it.

### ComponentStore
Generic store keyed by component runtime `Type`, independent of
`EntityRegistry` and `EventBus` — no direct reference to either, so it can be
constructed and tested in isolation.
- `void add<T extends Object>(EntityId id, T component)`
- `T? get<T extends Object>(EntityId id)`
- `bool has<T extends Object>(EntityId id)`
- `void remove<T extends Object>(EntityId id)`
- `Iterable<EntityId> entitiesWith<T extends Object>()`

Cleanup on entity destruction is **not** hardwired between the two services.
`ARCHITECTURE.md` documents the expected integration pattern — a consumer
subscribes to `EntityDestroyed` and calls `componentStore.remove` for each
component type the entity held — rather than baking a dependency between two
otherwise-independent core services.

### EventBus
- `EventSubscription subscribe<T>(void Function(T event) handler)` — returns
  a handle with `.cancel()`.
- `void publish<T>(T event)` — dispatches to all handlers subscribed for the
  exact runtime type of `event`.

Dispatch is by exact type match (no polymorphic dispatch across a class
hierarchy) — sufficient for the concrete event types CLAUDE.md lists
(`EntityCreated`, `ItemAdded`, `TurnStarted`, etc.); can be revisited if a
future plugin needs hierarchy-aware dispatch.

### GamePlugin (interface)
```dart
abstract class GamePlugin {
  String get id;
  String get version;
  List<String> get dependencies;
  void register(PluginContext context);
  void initialize(PluginContext context);
  void start(PluginContext context);
  void stop(PluginContext context);
  void unregister(PluginContext context);
}
```

### PluginContext
Read-only handle passed to every lifecycle call, exposing only the services
that exist after this pass: `entities` (EntityRegistry), `components`
(ComponentStore), `events` (EventBus). No placeholder getters are added for
unbuilt services (rules, effects, modifiers, queries, spatial, resources,
assets, localization, rng, save/load) — those are added when those services
are actually built, per CLAUDE.md's "no speculative abstractions" guidance.

### PluginManager
- `void register(GamePlugin plugin)` — adds to the registry; throws
  `DuplicatePluginException` if `id` is already registered.
- `List<String> resolveLoadOrder()` — topological sort over `dependencies`;
  throws `MissingPluginDependencyException` for an unresolvable dependency id,
  or `CyclicPluginDependencyException` for a cycle. Deterministic given a
  fixed registration order (stable sort, no reliance on hash-map iteration
  order for tie-breaking).
- `void initialize(PluginContext context)` — for each plugin in load order:
  calls `register(context)`; then, in a second full pass over load order,
  calls `initialize(context)`. Two passes so a plugin's `initialize` can rely
  on every plugin having already `register`-ed.
- `void start(PluginContext context)` — calls `start(context)` on each plugin
  in load order.
- `void stop(PluginContext context)` — calls `stop(context)` on each plugin in
  **reverse** load order.
- `void unregister(PluginContext context)` — calls `unregister(context)` on
  each plugin in reverse load order, then clears the registry.

## Error Handling

Three plugin-system exceptions, all extending a common
`PluginSystemException`: `DuplicatePluginException`,
`MissingPluginDependencyException`, `CyclicPluginDependencyException`. Each
carries the offending plugin id(s) in its message. `EntityRegistry.destroy`
throws `StateError` for a dead/unknown id (programmer error, not a recoverable
game condition — consistent with CLAUDE.md's "trust internal code" guidance
for boundaries that are entirely internal to the engine).

## Testing

`package:test`. One test file per service plus one integration test:

- `entity_id_test.dart` — equality, hashing, comparison, sequential
  allocation.
- `entity_registry_test.dart` — create/destroy/isAlive, double-destroy
  throws, `EntityCreated`/`EntityDestroyed` events fire with the right id.
- `component_store_test.dart` — add/get/has/remove/entitiesWith across
  multiple component types and entities, independent of EntityRegistry.
- `event_bus_test.dart` — subscribe/publish/cancel, multiple subscribers,
  no cross-type leakage (a `TypeA` subscriber never sees a `TypeB` publish).
- `plugin_manager_test.dart` — registration (including duplicate-id
  rejection), dependency-order resolution (including missing-dependency and
  cycle detection), full lifecycle ordering (register→initialize→start, then
  stop→unregister in reverse) via fake plugins that record call order.
- `integration/core_boots_without_plugins_test.dart` — covers two items from
  CLAUDE.md's testing list that are in scope this pass: (1) core runs with
  zero plugins registered, (2) plugins can be loaded and unloaded — using two
  fake plugins with a dependency edge between them, asserting call order.

Out of scope this pass (explicitly deferred, not silently skipped): Martial
Arts/Magic coexistence tests, serialization round-trip tests, RNG determinism
tests — none of the underlying content plugins or RNG/Serialization services
exist yet.

## Tooling

- `dart pub get` / `dart test` / `dart analyze`.
- `package:lints` recommended ruleset in `analysis_options.yaml`.
- No `build_runner` / codegen — nothing in this pass needs it.
- Dart/Flutter SDK upgraded to latest stable as part of this task.

## Documentation Deliverables

- `ARCHITECTURE.md` — engine service responsibilities, the dependency rule
  (plugins depend on core, never the reverse), and the
  EntityRegistry/ComponentStore integration pattern noted above.
- `PLUGIN_SYSTEM.md` — the `GamePlugin` interface, full lifecycle, dependency
  resolution algorithm and its exceptions, and what `PluginContext` exposes.

## Git

`git init` in this folder (separate from the home directory repo). First
commit made after the foundation is implemented and all tests/analysis pass.

## Explicitly Out of Scope

No martial-arts, magic, combat, or other game-specific code. No Rule Engine,
Effect Engine, Modifier Engine, Query Engine, Spatial/Container Engine,
Resource Engine, Scheduler, RNG Service, Asset/Data Registry, or
Serialization service — those are future subsystems, each to be brainstormed
and planned separately when the next subsystem is picked up.
