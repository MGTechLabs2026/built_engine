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
  final RngService rng;
  final RuleEngine rules;
  final QueryEngine queries;
  final ModifierCollection modifiers;
  final ContentRegistry content;
}
```

The only access a plugin's lifecycle methods get to core services. Exposes
exactly the services that exist — no placeholder getters for services
(spatial, resources, save/load) that haven't been built yet. When those
services are built, `PluginContext` grows to expose them. `content` (a
`ContentRegistry`, `claude.md`'s Asset/Data Registry) was the most recent
addition — see `ARCHITECTURE.md`'s Content Registry section.

## Plugin SDK

`PluginSdk` (`lib/src/plugin/plugin_sdk.dart`) is a convenience façade
over `PluginContext` for writing a plugin without touching Core. It adds
no new Core capability — every method delegates to a service
`PluginContext` already exposes — it only gives the categories
`claude.md`'s PLUGIN SYSTEM section names discoverable, named methods,
and automatically tracks subscriptions so a plugin author never has to
manage a `List<EventSubscription>` by hand the way `MartialArtsPlugin`
originally did.

Construct one per plugin, typically once in `initialize`:

```dart
class MyPlugin extends GamePlugin {
  @override
  String get id => 'my_plugin';
  @override
  String get version => '0.1.0';

  late PluginSdk sdk;

  @override
  void initialize(PluginContext context) {
    sdk = PluginSdk(context);
    // sdk.register... calls go here
  }

  @override
  void unregister(PluginContext context) => sdk.disposeAll();
}
```

| Category | Method | Delegates to |
|---|---|---|
| component | `registerComponentCleanup<T extends Object>()` | subscribes `EntityDestroyed` → `components.remove<T>` |
| event | `registerEvent<T>(handler)` | `events.subscribe<T>` |
| effect | `registerEffect(key, factory)` | `content.registerEffectFactory` |
| condition | `registerCondition(key, factory)` | `content.registerConditionFactory` |
| rule | `registerRule(rule)` | `rules.register` |
| tag | `registerTag(tag, {description})` | records your plugin's own tag vocabulary (Core never interprets tags either way) |
| content | `registerContent(json)` / `registerContentBatch(list)` | `content.load` / `loadAll` |
| asset | `registerAsset({id, data})` | `content.load` with `type: 'asset'` fixed |
| localization | `registerLocalization({locale, key, value})` / `localize(locale, key)` | `content.load`/`find` with `type: 'localization'` fixed |

`registerComponentCleanup`/`registerEvent`/`registerRule` are tracked
internally; `sdk.disposeAll()` cancels all of them in one call — that's
the whole content of a typical plugin's `unregister`. Effect/condition
factory registration and loaded content are **not** undone by
`disposeAll()` — `ContentRegistry` has no factory-removal or unload
operation today, so a plugin's removability guarantee covers its
subscriptions and rules, not its factories or data. `asset`/
`localization` registration are sugar over `content` (`claude.md`'s
core-service list already merges "Asset" and "Data" into one registry,
#12) — not separate services.

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

## Writing a third-party plugin

`ElementalPlugin` (`lib/src/plugins/elemental/`,
`lib/elemental_plugin.dart`) is the reference: Fire/Water/
Lightning, built entirely with `PluginSdk`, depending on nothing but
Core — not Combat, not MartialArts. Copy it, not `MartialArtsPlugin`, as
your starting point; `MartialArtsPlugin` additionally demonstrates
depending on another plugin (`-> combat`), which most third-party
plugins won't need on day one.

Steps, in the order `ElementalPlugin` follows them:

1. **Define your component(s)**, if any — plain state, no logic (see
   `ElementalAffinityComponent`).
2. **Define your tags** as `static const` string constants on an
   `abstract final class` (see `Elements`), and a small helper that
   grants them via core's `AddTag` effect through a standalone
   `RuleContext` (see `attuneToElement` — the same pattern
   `martial_item.dart`'s `equipItem` already established).
3. **Define your `Condition`/`Effect` classes**, implementing Core's
   interfaces directly (see `HasElementalAffinity`,
   `ApplyElementalStatus`) — compose Core's existing effects
   (`ApplyStatus`, `Damage`, `Heal`, ...) where you can, rather than
   reimplementing state mutation.
4. **Define your `Rule`s** as a `List<Rule> buildXRules()` function (see
   `buildElementalRules`) — react to Core's own events
   (`EntityDamaged`/`EntityHealed`/`EntityKilled`/`EntityCreated`/
   `EntityDestroyed`) rather than trying to intercept another plugin's
   effects directly; see `ARCHITECTURE.md`'s MartialArts section for why
   that's the right shape when a real cross-plugin need arises.
5. **Define your content** as a `List<Map<String, dynamic>>` of
   JSON-shaped definitions (see `elementalContentDefinitions`), mixing
   `ContentRegistry`'s built-in effect/condition factories with your
   own.
6. **Wire it all up in your `GamePlugin.initialize`** via `PluginSdk` —
   one `sdk.register*` call per thing you defined above (see
   `ElementalPlugin.initialize`) — and call `sdk.disposeAll()` in
   `unregister`.
7. **Export a barrel** (`lib/my_plugin.dart`) so consumers import your
   plugin the same way they import `combat_plugin.dart`/
   `martial_arts_plugin.dart`/`elemental_plugin.dart` — never
   `lib/src/...` directly.

Test the same way every plugin in this engine is tested (see
`claude.md`'s TESTING section): registration, initialization, behavior,
serialization where applicable, dependency, and — if you react to
another plugin's events like MartialArts does — an integration test
proving your plugin is fully removable (see
`test/integration/elemental_end_to_end_test.dart` and
`test/integration/martial_arts_end_to_end_test.dart` for the pattern).

## Plugins must not reach into each other's private implementation

A plugin's only sanctioned way to affect another plugin's behavior is
through `PluginContext`'s public services (entities, components, events,
rng, rules, queries, modifiers) —
never by importing another plugin's package internals directly. This
engine does not yet enforce that at the language level; it's a convention
until/unless a stronger enforcement mechanism is added.
