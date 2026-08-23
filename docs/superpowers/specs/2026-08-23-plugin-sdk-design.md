# Plugin SDK — Design

## Purpose

Make it easy to write a new content plugin without touching Core, per
`claude.md`'s CORE PROVIDES VERBS / PLUGINS PROVIDE NOUNS principle and
its PLUGIN SYSTEM section (`PluginContext` "provides controlled access
to" a named list of services, including `assets`/`localization`). Two
deliverables:

1. `PluginSdk` — a convenience façade over `PluginContext`, covering the
   9 registration categories requested: component, event, effect,
   condition, rule, tag, content, asset, localization.
2. `ExampleElementalPlugin` — a minimal Fire/Water/Lightning plugin built
   entirely with the SDK, depending on nothing but Core (not Combat, not
   MartialArts), serving as the reference a third-party developer copies
   from.

Plus documentation: `PLUGIN_SYSTEM.md` gains an SDK section and a
step-by-step "writing a plugin" walkthrough.

## Why this needs zero Core changes

Every existing plugin (Combat, MartialArts) already reaches everything it
needs through `PluginContext`'s existing public services. What
`MartialArtsPlugin` hand-rolls is bookkeeping: a `List<EventSubscription>`
filled during `initialize`, drained during `unregister`
(`lib/src/plugins/martial_arts/martial_arts_plugin.dart`). `PluginSdk`'s
entire job is to eliminate exactly that boilerplate and give the 9
requested categories discoverable, named methods — it is built entirely
from `PluginContext`'s already-public surface (`entities`, `components`,
`events`, `rules`, `content`) plus its own internal bookkeeping. It lives
in `lib/src/plugin/` (Core, since it is pure mechanical wiring — no game
vocabulary — matching `GamePlugin`/`PluginContext`/`PluginManager`
already there), but adding it requires editing no other Core file.

### Asset and localization: sugar over `ContentRegistry`, not new services

`claude.md`'s numbered core-service list has **one** combined entry,
"12. Asset/Data Registry" — not two separate services. `ContentRegistry`
(built in the prior pass) already *is* that combined registry: a
`type` field is an opaque label Core never interprets, so "asset" and
"localization" are simply two more `type` values, no different in kind
from "skill" or "item". `PluginSdk.registerAsset`/`registerLocalization`
are therefore sugar — fixed-shape calls into `context.content.load` —
not new Core services. This is also the reading that satisfies "without
touching the Core" in the strongest sense: the SDK itself edits no
existing Core file, either.

One consequence worth stating plainly: `ContentRegistry` has no
"unregister a factory" or "unload a definition" operation today (it never
has — content and rule ids, once loaded, stay loaded; effect/condition/
trigger factories, once registered, stay registered). `PluginSdk` does
not change that. A plugin's *removability* guarantee — proven by
`MartialArtsPlugin`'s existing integration test — covers what
`disposeAll()` actually undoes: event subscriptions, cleanup
subscriptions, and rule registrations. It does not cover factory
registrations or loaded content, because nothing in the engine can undo
those yet. The docs say this explicitly rather than overselling it.

## `PluginSdk`

```dart
class PluginSdk {
  PluginSdk(this.context);

  final PluginContext context;
}
```

One instance per plugin, typically constructed once in `initialize` and
kept on the plugin as `late final PluginSdk sdk`.

### Component registration

```dart
EventSubscription registerComponentCleanup<T extends Object>();
```

Subscribes `EntityDestroyed` and calls `context.components.remove<T>` for
every destroyed entity — the manual step `ARCHITECTURE.md`'s
"Integrating EntityRegistry and ComponentStore" section currently
documents as something every consumer must wire by hand. Tracked
internally for `disposeAll()`.

### Event registration

```dart
EventSubscription registerEvent<T>(void Function(T event) handler);
```

Thin wrapper over `context.events.subscribe<T>`, tracked for
`disposeAll()`. Exists for symmetry/discoverability with the other
`register*` methods and so a plugin author never needs to manage a
subscription list by hand.

### Effect / condition registration

```dart
void registerEffect(
    String key, Effect Function(Map<String, dynamic> params) factory);
void registerCondition(
    String key, Condition Function(Map<String, dynamic> params) factory);
```

Delegate directly to `context.content.registerEffectFactory`/
`registerConditionFactory` — named identically to the requested
categories, so a plugin author reading `claude.md`'s EFFECTS/CONDITIONS
vocabulary finds a matching SDK method immediately. Not tracked for
`disposeAll()` — see "no undo" note above.

### Rule registration

```dart
EventSubscription registerRule(Rule rule);
```

Delegates to `context.rules.register`, tracked for `disposeAll()` — this
is the exact call `MartialArtsPlugin.initialize` makes today, just
bookkept automatically instead of by hand.

### Tag registration

```dart
void registerTag(String tag, {String description = ''});
Map<String, String> get tags; // unmodifiable view
```

Purely a documentation/introspection registry local to this `PluginSdk`
instance — Core does not interpret tags (`claude.md`'s TAGS section:
"The engine does not interpret these tags. It only provides querying and
matching") and this does not change that. It exists so a plugin can state
its own tag vocabulary once, in code, for tooling/discoverability, rather
than tags only ever appearing as string literals scattered through
content data.

### Content registration

```dart
ContentDefinition registerContent(Map<String, dynamic> json);
List<ContentDefinition> registerContentBatch(
    List<Map<String, dynamic>> jsonList);
```

Delegate directly to `context.content.load`/`loadAll`.

### Asset registration

```dart
ContentDefinition registerAsset({
  required String id,
  required Map<String, dynamic> data,
});
```

Loads `{...data, 'id': id, 'type': 'asset'}` through `context.content` —
`id`/`type` are applied *after* spreading `data`, so a plugin's own data
can never accidentally override the id/type this method fixes. `data`
carries whatever shape the plugin wants (`{'path': 'assets/fire.png'}`,
etc.) — Core still never interprets it; it lands in the resulting
`ContentDefinition.extra` exactly like any other unrecognized field,
matching `ContentDefinition.extra`'s already-documented behavior.

### Localization registration

```dart
ContentDefinition registerLocalization({
  required String locale,
  required String key,
  required String value,
});
String? localize(String locale, String key);
```

Loads `{'id': '$locale:$key', 'type': 'localization', 'locale': locale,
'key': key, 'value': value}` — the `locale`/`key`/`value` fields are not
otherwise interpreted by `ContentDefinition`'s parser, so they land in
`extra` verbatim, exactly like `components.attack` did in the prior
pass's `iron_sword` example. `localize` looks the definition back up by
the same `'$locale:$key'` id and reads `extra['value']`, returning `null`
if no such definition (or a definition of a different `type`) exists.

### Teardown

```dart
void disposeAll();
```

Cancels every `EventSubscription` tracked by `registerComponentCleanup`/
`registerEvent`/`registerRule`, in registration order, then clears the
tracking list. Idempotent-safe to call twice (the list is empty the
second time, so nothing happens).

## `ExampleElementalPlugin`

`lib/src/plugins/example_elemental/` — depends on nothing but Core
(`dependencies => const []`), unlike MartialArts (`-> combat`). This
makes it the simplest possible reference: a third-party developer reading
"how do I write a plugin with the SDK" copies this one, not MartialArts.

### Elements

```dart
abstract final class Elements {
  static const fire = 'fire';
  static const water = 'water';
  static const lightning = 'lightning';
}
```

Mirrors `MartialStyles`. `attuneToElement(entity, element, affinity,
context)` grants the `element:<id>` tag (via `AddTag`, through the same
`_standaloneContext` helper `martial_item.dart` already establishes) and
merges `affinity` into the entity's `ElementalAffinityComponent`
(creating it if absent).

### Component

```dart
class ElementalAffinityComponent {
  const ElementalAffinityComponent(this.affinities);
  final Map<String, num> affinities; // element id -> affinity level
}
```

A plugin's own component type — the thing `registerComponentCleanup`
exists to clean up.

### Condition

```dart
class HasElementalAffinity implements Condition {
  const HasElementalAffinity(this.element, this.threshold);
  final String element;
  final num threshold;

  @override
  bool evaluate(RuleContext context) {
    final subject = context.subject;
    if (subject == null) return false;
    final affinity =
        context.components.get<ElementalAffinityComponent>(subject);
    return (affinity?.affinities[element] ?? 0) >= threshold;
  }
}
```

Same shape as core's `ResourceAbove`/`HealthBelow` — a plugin condition
reading a plugin component.

### Effect

```dart
class ApplyElementalStatus implements Effect {
  const ApplyElementalStatus(this.element);
  final String element;

  @override
  void apply(RuleContext context) => ApplyStatus(_statusFor(element)).apply(context);

  static String _statusFor(String element) => switch (element) {
        'fire' => 'status:burning',
        'water' => 'status:soaked',
        'lightning' => 'status:shocked',
        _ => 'status:$element',
      };
}
```

Composes core's existing `ApplyStatus` — demonstrating that a plugin
effect need not reimplement state mutation from scratch, the same way
MartialArts' rules compose `Heal`/`Damage`.

### Rule ("water conducts")

```
WHEN EntityDamaged
IF subject HasTag('status:soaked')
THEN ApplyElementalStatus('lightning')
```

Reacts to Core's own `EntityDamaged` event (published by core's `Damage`
effect) — needs no Combat at all, unlike MartialArts' `EntityDamaged`
rules which exist alongside a Combat dependency for other reasons.
`buildElementalRules()` returns this as a one-element `List<Rule>`,
mirroring `buildMartialArtsRules()`'s shape.

### Content definitions

Three data-loaded "spell" definitions, one per element, each mixing a
*built-in* `ContentRegistry` factory (`damage`) with this plugin's *own*
factories (`applyElementalStatus`, `hasElementalAffinity`):

```json
{
  "id": "fireball",
  "type": "spell",
  "tags": ["element:fire", "attack"],
  "components": { "cost": { "resource": "mana", "amount": 4 } },
  "conditions": [
    { "type": "hasElementalAffinity", "element": "fire", "threshold": 1 }
  ],
  "effects": [
    { "type": "damage", "amount": 12 },
    { "type": "applyElementalStatus", "element": "fire" }
  ]
}
```

`tidal_wave` (water, mana 3, damage 8) and `spark_bolt` (lightning, mana
5, damage 10) follow the identical shape. `elementalContentDefinitions`
is the `List<Map<String, dynamic>>` of all three, loaded via
`sdk.registerContentBatch` in `initialize` — so registering all three
must succeed atomically (proving last session's `loadAll` atomicity work
composes cleanly with this one).

### `ExampleElementalPlugin` itself

```dart
class ExampleElementalPlugin extends GamePlugin {
  @override
  String get id => 'example_elemental';

  @override
  String get version => '0.1.0';

  late final PluginSdk sdk;

  @override
  void initialize(PluginContext context) {
    sdk = PluginSdk(context);
    sdk.registerComponentCleanup<ElementalAffinityComponent>();
    sdk.registerEffect('applyElementalStatus', ...);
    sdk.registerCondition('hasElementalAffinity', ...);
    sdk.registerTag('element:fire', description: '...');
    sdk.registerTag('element:water', description: '...');
    sdk.registerTag('element:lightning', description: '...');
    for (final rule in buildElementalRules()) {
      sdk.registerRule(rule);
    }
    sdk.registerContentBatch(elementalContentDefinitions);
  }

  @override
  void unregister(PluginContext context) => sdk.disposeAll();
}
```

`lib/example_elemental_plugin.dart` is the public export barrel, mirroring
`lib/martial_arts_plugin.dart`.

## Test plan

- `PluginSdk`: each registration category (component cleanup actually
  removes the component on `EntityDestroyed`; event registration actually
  fires; effect/condition factories are reachable via
  `context.content.load` after registration; rule registration actually
  fires through `RuleEngine`; tag registration records and lists; content/
  batch registration delegates correctly including a validation-failure
  case; asset registration's `id`/`type` cannot be overridden by `data`;
  localization registers and `localize` round-trips, including the
  not-found case); `disposeAll()` cancels every tracked subscription and
  is safe to call twice.
- `ExampleElementalPlugin`: `Elements`/`attuneToElement` (tag + component
  merge, including attuning to a second element without clobbering the
  first); `HasElementalAffinity` (threshold true/false, missing
  component); `ApplyElementalStatus` (correct status per element);
  `buildElementalRules()`'s rule firing end-to-end through a real
  `RuleEngine`; the three content definitions loading successfully via
  `registerContentBatch` and resolving through `ContentRegistry`
  correctly (cost/conditions/effects, including the custom factories);
  plugin registration/initialization/unregistration (removability,
  mirroring `MartialArtsPlugin`'s existing test).
- Integration test: `PluginManager` with only `ExampleElementalPlugin`
  registered (no Combat, no MartialArts) — attune an entity to Fire,
  resolve `fireball`'s cost/conditions/effects against real
  entities/components, confirm damage + `status:burning` both land, then
  confirm `unregister` stops the "water conducts" rule from firing.
