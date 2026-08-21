# Build Engine — Plugin System

## The `GamePlugin` interface

```dart
abstract class GamePlugin {
  String get id;
  String get version;
  List<String> get dependencies => const [];

  void register(PluginContext context) {}
  void initialize(PluginContext context) {}
  void start(PluginContext context) {}
  void stop(PluginContext context) {}
  void unregister(PluginContext context) {}
}
```

`id` and `version` must be overridden. `dependencies` and every lifecycle
method have no-op defaults — a plugin overrides only what it needs.

`dependencies` lists the `id`s of plugins that must be registered,
initialized, and started before this one (and stopped/unregistered after
it). Declare a dependency here whenever your plugin calls into another
plugin's public contract during `register`, `initialize`, or `start`.

## Lifecycle

Driven entirely by `PluginManager`, always in dependency order (see below)
for the forward phases and reverse dependency order for the teardown
phases:

1. **register** (dependency order) — declare things; every plugin's
   `register` runs before any plugin's `initialize`.
2. **initialize** (dependency order) — safe to assume every plugin has
   already `register`ed.
3. **start** (dependency order) — begin active behavior (subscribing to
   ongoing events, etc.).
4. **stop** (reverse dependency order) — the mirror image of `start`.
5. **unregister** (reverse dependency order) — the mirror image of
   `register`; undo anything registered.

`PluginManager.initialize(context)` runs phases 1 and 2 (as two full passes
over the resolved order). `start`, `stop`, and `unregister` are each called
separately by whoever owns the `PluginManager` — for example, a game loop
calls `start` once, then `stop`/`unregister` at shutdown.

## PluginContext

```dart
class PluginContext {
  final EntityRegistry entities;
  final ComponentStore components;
  final EventBus events;
}
```

The only access a plugin's lifecycle methods get to core services. Exposes
exactly the services that exist — no placeholder getters for services
(rules, effects, modifiers, spatial, resources, assets, rng, save/load)
that haven't been built yet. When those services are built, `PluginContext`
grows to expose them.

## Dependency resolution

`PluginManager.register(plugin)` adds a plugin to the registry (throws
`DuplicatePluginException` for a repeated `id`) but does not run any
lifecycle method yet.

`PluginManager.resolveLoadOrder()` topologically sorts every registered
plugin's `id` by `dependencies`, via depth-first traversal in registration
order (registration order is preserved because the internal registry is
insertion-ordered, so the result is deterministic for a fixed sequence of
`register` calls). It throws:

- `MissingPluginDependencyException` if a plugin depends on an `id` that was
  never registered.
- `CyclicPluginDependencyException` if dependencies form a cycle — the
  exception carries the dependency path that led to the cycle, in traversal
  order, with the id that closed the cycle repeated at the end (the path
  may include ids that are not themselves part of the cycle, e.g. a
  non-cyclic prefix leading into it).

`initialize`, `start`, `stop`, and `unregister` all call
`resolveLoadOrder()` internally, so you never call it yourself in normal
use — it's public so dependency resolution can be tested and inspected on
its own.

## Adding a plugin

```dart
class MyPlugin extends GamePlugin {
  @override
  String get id => 'my_plugin';

  @override
  String get version => '0.1.0';

  @override
  List<String> get dependencies => const ['some_other_plugin'];

  @override
  void initialize(PluginContext context) {
    final entity = context.entities.create();
    // ...
  }
}

final manager = PluginManager();
manager.register(MyPlugin());
manager.register(SomeOtherPlugin());
manager.initialize(context);
manager.start(context);
```

## Plugins must not reach into each other's private implementation

A plugin's only sanctioned way to affect another plugin's behavior is
through `PluginContext`'s public services (entities, components, events) —
never by importing another plugin's package internals directly. This
engine does not yet enforce that at the language level; it's a convention
until/unless a stronger enforcement mechanism is added.
