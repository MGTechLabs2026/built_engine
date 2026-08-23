# Plugin SDK Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build `PluginSdk` (a zero-Core-change convenience façade over
`PluginContext` covering component/event/effect/condition/rule/tag/
content/asset/localization registration) and `ExampleElementalPlugin` (a
Core-only Fire/Water/Lightning reference plugin built entirely with it),
plus third-party-developer documentation.

**Architecture:** `PluginSdk` delegates every method to a service
`PluginContext` already exposes (`entities`/`components`/`events`/
`rules`/`content`) and tracks every `EventSubscription` it creates so
`disposeAll()` replaces the hand-rolled `List<EventSubscription>`
`MartialArtsPlugin` manages today. `asset`/`localization` registration
are sugar over `content` (`type: 'asset'`/`type: 'localization'`), not
new Core services — `claude.md`'s core-service list already merges
"Asset" and "Data" into one registry (#12), and `ContentRegistry` is
already that registry. `ExampleElementalPlugin` depends on nothing but
Core (not Combat, not MartialArts), making it the simplest possible
template a third-party developer copies from.

**Tech Stack:** Dart `^3.7.0`, `package:test`, package `build_engine`.

**Spec:** `docs/superpowers/specs/2026-08-23-plugin-sdk-design.md`

## Global Constraints

- Zero changes to any existing Core file's *behavior* — `PluginSdk` is
  purely additive, built entirely from `PluginContext`'s already-public
  surface.
- `ExampleElementalPlugin` must not import or depend on
  `MartialArtsPlugin`/`CombatPlugin`/any future `MagicPlugin` —
  `dependencies => const []`.
- `registerComponentCleanup`/`registerEvent`/`registerRule` track their
  `EventSubscription`; `disposeAll()` cancels all of them, in
  registration order, and is safe to call more than once.
- `registerEffect`/`registerCondition`/`registerContent`/
  `registerContentBatch`/`registerAsset`/`registerLocalization` are
  **not** undone by `disposeAll()` — `ContentRegistry` has no
  factory-removal or unload operation. Document this; do not paper over
  it.
- `registerAsset`'s `id`/`type` must win over anything with the same key
  in its `data` argument (apply them *after* spreading `data`).
- Every new public class/function needs tests, plus an end-to-end
  integration test proving `ExampleElementalPlugin` runs standalone
  (no Combat, no MartialArts registered) and is fully removable.

---

### Task 1: `PluginSdk`

**Files:**
- Create: `lib/src/plugin/plugin_sdk.dart`
- Test: `test/plugin_sdk_test.dart`
- Modify: `lib/build_engine.dart`

**Interfaces:**
- Consumes: `PluginContext` (`lib/src/plugin/plugin_context.dart`),
  `EventSubscription` (`lib/src/event/event_bus.dart`), `EntityDestroyed`
  (`lib/src/entity/entity_registry.dart`), `Effect`/`Condition`
  (`lib/src/rule/{effect,condition}.dart`), `Rule`
  (`lib/src/rule/rule.dart`), `ContentDefinition`
  (`lib/src/content/content_definition.dart`) — all pre-existing,
  unchanged.
- Produces: `class PluginSdk` with `PluginSdk(PluginContext context)` and:
  `registerComponentCleanup<T extends Object>()`,
  `registerEvent<T>(void Function(T) handler)`,
  `registerEffect(String key, Effect Function(Map<String, dynamic>) factory)`,
  `registerCondition(String key, Condition Function(Map<String, dynamic>) factory)`,
  `registerRule(Rule rule)`, `registerTag(String tag, {String description})`,
  `Map<String, String> get tags`,
  `registerContent(Map<String, dynamic> json)`,
  `registerContentBatch(List<Map<String, dynamic>> jsonList)`,
  `registerAsset({required String id, required Map<String, dynamic> data})`,
  `registerLocalization({required String locale, required String key, required String value})`,
  `String? localize(String locale, String key)`, `void disposeAll()`.

- [ ] **Step 1: Write `plugin_sdk.dart`**

```dart
import '../content/content_definition.dart';
import '../entity/entity_registry.dart';
import '../event/event_bus.dart';
import '../rule/condition.dart';
import '../rule/effect.dart';
import '../rule/rule.dart';

import 'plugin_context.dart';

/// A convenience facade over [PluginContext] for writing a content
/// plugin without touching Core. Every method here delegates to a
/// service [PluginContext] already exposes — this class adds no new
/// Core capability, only discoverable names and automatic subscription
/// bookkeeping (see [disposeAll]) in place of the `List<EventSubscription>`
/// every plugin previously had to manage by hand (see
/// `MartialArtsPlugin`'s `_subscriptions` field).
///
/// Construct one per plugin, typically once in `GamePlugin.initialize`:
/// `sdk = PluginSdk(context);`.
class PluginSdk {
  PluginSdk(this.context);

  final PluginContext context;

  final List<EventSubscription> _subscriptions = [];
  final Map<String, String> _tags = {};

  // --- component registration ---

  /// Subscribes `EntityDestroyed` and removes an entity's component of
  /// type [T] whenever it's destroyed — the manual step
  /// `ARCHITECTURE.md`'s "Integrating EntityRegistry and ComponentStore"
  /// section otherwise documents as something every consumer must wire
  /// up itself. Tracked for [disposeAll].
  EventSubscription registerComponentCleanup<T extends Object>() {
    final subscription = context.events.subscribe<EntityDestroyed>(
      (event) => context.components.remove<T>(event.id),
    );
    _subscriptions.add(subscription);
    return subscription;
  }

  // --- event registration ---

  /// Subscribes [handler] to every published event of type [T]. Tracked
  /// for [disposeAll].
  EventSubscription registerEvent<T>(void Function(T event) handler) {
    final subscription = context.events.subscribe<T>(handler);
    _subscriptions.add(subscription);
    return subscription;
  }

  // --- effect / condition registration ---

  /// Registers [factory] as this plugin's [Effect] factory under [key],
  /// so `{"type": key, ...}` in loaded content dispatches to it. Not
  /// tracked for [disposeAll] — `ContentRegistry` has no factory-removal
  /// operation today.
  void registerEffect(
    String key,
    Effect Function(Map<String, dynamic> params) factory,
  ) {
    context.content.registerEffectFactory(key, factory);
  }

  /// Registers [factory] as this plugin's [Condition] factory under
  /// [key]. See [registerEffect].
  void registerCondition(
    String key,
    Condition Function(Map<String, dynamic> params) factory,
  ) {
    context.content.registerConditionFactory(key, factory);
  }

  // --- rule registration ---

  /// Registers [rule] against this context's `RuleEngine`. Tracked for
  /// [disposeAll].
  EventSubscription registerRule(Rule rule) {
    final subscription = context.rules.register(rule);
    _subscriptions.add(subscription);
    return subscription;
  }

  // --- tag registration ---

  /// Records [tag] (with an optional human-readable [description]) as
  /// part of this plugin's own tag vocabulary. Purely a documentation/
  /// introspection aid — Core never interprets tags (`claude.md`'s TAGS
  /// section), and this does not change that.
  void registerTag(String tag, {String description = ''}) {
    _tags[tag] = description;
  }

  /// This plugin's tag vocabulary, as recorded via [registerTag].
  Map<String, String> get tags => Map.unmodifiable(_tags);

  // --- content registration ---

  /// Loads [json] as one content definition. See `ContentRegistry.load`.
  ContentDefinition registerContent(Map<String, dynamic> json) =>
      context.content.load(json);

  /// Loads every entry in [jsonList] as one atomic batch. See
  /// `ContentRegistry.loadAll`.
  List<ContentDefinition> registerContentBatch(
          List<Map<String, dynamic>> jsonList) =>
      context.content.loadAll(jsonList);

  // --- asset registration ---

  /// Loads an asset-shaped content definition: `{...data, 'id': id,
  /// 'type': 'asset'}`. `id`/`type` are applied after spreading [data],
  /// so [data] can never override them. Whatever shape [data] carries
  /// (a `path`, a size, ...) is never interpreted by Core — it surfaces
  /// verbatim on the resulting `ContentDefinition.extra`.
  ContentDefinition registerAsset({
    required String id,
    required Map<String, dynamic> data,
  }) =>
      context.content.load({...data, 'id': id, 'type': 'asset'});

  // --- localization registration ---

  /// Loads a localization-shaped content definition, id `'$locale:$key'`
  /// — `locale`/`key`/`value` are not otherwise interpreted, so they
  /// surface on `ContentDefinition.extra` exactly like any other
  /// unrecognized field.
  ContentDefinition registerLocalization({
    required String locale,
    required String key,
    required String value,
  }) =>
      context.content.load({
        'id': '$locale:$key',
        'type': 'localization',
        'locale': locale,
        'key': key,
        'value': value,
      });

  /// Looks up a string registered via [registerLocalization] for
  /// [locale]/[key]. `null` if no such definition exists, or if a
  /// definition exists at that id but isn't a `'localization'` entry.
  String? localize(String locale, String key) {
    final definition = context.content.find('$locale:$key');
    if (definition == null || definition.type != 'localization') {
      return null;
    }
    return definition.extra['value'] as String?;
  }

  // --- teardown ---

  /// Cancels every subscription tracked by [registerComponentCleanup]/
  /// [registerEvent]/[registerRule], in registration order, then clears
  /// the tracking list. Safe to call more than once.
  void disposeAll() {
    for (final subscription in _subscriptions) {
      subscription.cancel();
    }
    _subscriptions.clear();
  }
}
```

- [ ] **Step 2: Write `plugin_sdk_test.dart`**

```dart
import 'package:build_engine/build_engine.dart';
import 'package:test/test.dart';

PluginContext _newContext() {
  final events = EventBus();
  final entities = EntityRegistry(events);
  final components = ComponentStore();
  final rng = RngService(1);
  return PluginContext(
    entities: entities,
    components: components,
    events: events,
    rng: rng,
    rules: RuleEngine(
      entities: entities,
      components: components,
      events: events,
      rng: rng,
    ),
    queries: QueryEngine(QueryScope(components: components)),
    modifiers: ModifierCollection(),
    content: ContentRegistry(),
  );
}

class _Marker {
  const _Marker(this.value);
  final int value;
}

class _MarkerEvent {
  const _MarkerEvent(this.value);
  final int value;
}

void main() {
  group('registerComponentCleanup', () {
    test('removes the component when the entity is destroyed', () {
      final context = _newContext();
      final sdk = PluginSdk(context);
      sdk.registerComponentCleanup<_Marker>();

      final entity = context.entities.create();
      context.components.add(entity, const _Marker(1));
      expect(context.components.get<_Marker>(entity), isNotNull);

      context.entities.destroy(entity);
      expect(context.components.get<_Marker>(entity), isNull);
    });

    test('is cancelled by disposeAll', () {
      final context = _newContext();
      final sdk = PluginSdk(context);
      sdk.registerComponentCleanup<_Marker>();
      sdk.disposeAll();

      final entity = context.entities.create();
      context.components.add(entity, const _Marker(1));
      context.entities.destroy(entity);
      expect(context.components.get<_Marker>(entity), isNotNull);
    });
  });

  group('registerEvent', () {
    test('fires the handler for published events of the given type', () {
      final context = _newContext();
      final sdk = PluginSdk(context);
      final seen = <int>[];
      sdk.registerEvent<_MarkerEvent>((e) => seen.add(e.value));

      context.events.publish(const _MarkerEvent(7));
      expect(seen, equals([7]));
    });

    test('is cancelled by disposeAll', () {
      final context = _newContext();
      final sdk = PluginSdk(context);
      final seen = <int>[];
      sdk.registerEvent<_MarkerEvent>((e) => seen.add(e.value));
      sdk.disposeAll();

      context.events.publish(const _MarkerEvent(7));
      expect(seen, isEmpty);
    });
  });

  group('registerEffect / registerCondition', () {
    test('registered factories are reachable through content.load', () {
      final context = _newContext();
      final sdk = PluginSdk(context);
      sdk.registerEffect('markerEffect', (p) => const Heal(1));
      sdk.registerCondition(
          'markerCondition', (p) => const RandomChance(1.0));

      final definition = context.content.load({
        'id': 'uses_marker',
        'type': 'test',
        'conditions': [
          {'type': 'markerCondition'},
        ],
        'effects': [
          {'type': 'markerEffect'},
        ],
      });

      expect(definition.conditions.single, isA<RandomChance>());
      expect(definition.effects.single, isA<Heal>());
    });
  });

  group('registerRule', () {
    test('fires through the real RuleEngine', () {
      final context = _newContext();
      final sdk = PluginSdk(context);
      sdk.registerRule(Rule(
        trigger: EntityHealed,
        subjectOf: (e) => (e as EntityHealed).id,
        effects: const [ModifyStat('marker', 1)],
      ));

      final entity = context.entities.create();
      context.events.publish(EntityHealed(entity, 5));

      expect(
        context.components.get<StatComponent>(entity)!.stats['marker'],
        equals(1),
      );
    });

    test('is cancelled by disposeAll', () {
      final context = _newContext();
      final sdk = PluginSdk(context);
      sdk.registerRule(Rule(
        trigger: EntityHealed,
        subjectOf: (e) => (e as EntityHealed).id,
        effects: const [ModifyStat('marker', 1)],
      ));
      sdk.disposeAll();

      final entity = context.entities.create();
      context.events.publish(EntityHealed(entity, 5));

      expect(context.components.get<StatComponent>(entity), isNull);
    });
  });

  group('registerTag', () {
    test('records tags with their description', () {
      final context = _newContext();
      final sdk = PluginSdk(context);
      sdk.registerTag('element:fire', description: 'Fire-aligned.');
      sdk.registerTag('element:water');

      expect(sdk.tags['element:fire'], equals('Fire-aligned.'));
      expect(sdk.tags['element:water'], equals(''));
      expect(sdk.tags, hasLength(2));
    });
  });

  group('registerContent / registerContentBatch', () {
    test('registerContent delegates to content.load', () {
      final context = _newContext();
      final sdk = PluginSdk(context);
      final definition = sdk.registerContent({'id': 'a', 'type': 'skill'});
      expect(context.content.get('a'), same(definition));
    });

    test('registerContentBatch delegates to content.loadAll', () {
      final context = _newContext();
      final sdk = PluginSdk(context);
      final definitions = sdk.registerContentBatch([
        {'id': 'a', 'type': 'skill'},
        {'id': 'b', 'type': 'skill'},
      ]);
      expect(definitions, hasLength(2));
      expect(context.content.get('a'), isNotNull);
      expect(context.content.get('b'), isNotNull);
    });
  });

  group('registerAsset', () {
    test('loads an asset with the given id/type and data in extra', () {
      final context = _newContext();
      final sdk = PluginSdk(context);
      final definition = sdk.registerAsset(
        id: 'fire_icon',
        data: {'path': 'assets/fire.png'},
      );

      expect(definition.id, equals('fire_icon'));
      expect(definition.type, equals('asset'));
      expect(definition.extra['path'], equals('assets/fire.png'));
    });

    test('data cannot override the fixed id/type', () {
      final context = _newContext();
      final sdk = PluginSdk(context);
      final definition = sdk.registerAsset(
        id: 'fire_icon',
        data: {'id': 'hijacked', 'type': 'hijacked'},
      );

      expect(definition.id, equals('fire_icon'));
      expect(definition.type, equals('asset'));
    });
  });

  group('registerLocalization / localize', () {
    test('round-trips a registered string', () {
      final context = _newContext();
      final sdk = PluginSdk(context);
      sdk.registerLocalization(
          locale: 'en', key: 'fireball.name', value: 'Fireball');

      expect(sdk.localize('en', 'fireball.name'), equals('Fireball'));
    });

    test('returns null when not found', () {
      final context = _newContext();
      final sdk = PluginSdk(context);
      expect(sdk.localize('en', 'nonexistent'), isNull);
    });

    test(
        'returns null for an id that exists but is not a localization '
        'entry', () {
      final context = _newContext();
      final sdk = PluginSdk(context);
      sdk.registerContent({'id': 'en:not_localization', 'type': 'skill'});
      expect(sdk.localize('en', 'not_localization'), isNull);
    });
  });

  group('disposeAll', () {
    test('is safe to call twice', () {
      final context = _newContext();
      final sdk = PluginSdk(context);
      sdk.registerEvent<_MarkerEvent>((_) {});
      sdk.disposeAll();
      expect(sdk.disposeAll, returnsNormally);
    });
  });
}
```

- [ ] **Step 3: Wire the export and run**

Add, in this task, to `lib/build_engine.dart`, alphabetically positioned
(after `src/plugin/plugin_manager.dart`, before `src/query/queries.dart`):
```dart
export 'src/plugin/plugin_sdk.dart';
```

Run: `dart test test/plugin_sdk_test.dart`
Expected: every group PASSES.

- [ ] **Step 4: Commit**

```bash
git add lib/src/plugin/plugin_sdk.dart test/plugin_sdk_test.dart lib/build_engine.dart
git commit -m "feat: add PluginSdk - registration helpers over PluginContext"
```

---

### Task 2: `Elements` and `ElementalAffinityComponent`

**Files:**
- Create: `lib/src/plugins/example_elemental/elemental_affinity_component.dart`
- Create: `lib/src/plugins/example_elemental/elements.dart`
- Create: `lib/example_elemental_plugin.dart` (barrel — starts with just these two exports; later tasks add more)
- Test: `test/plugins/example_elemental/elemental_affinity_component_test.dart`
- Test: `test/plugins/example_elemental/elements_test.dart`

**Interfaces:**
- Consumes: `EntityId`, `PluginContext`, `RuleContext`, `AddTag`
  (`package:build_engine/build_engine.dart`) — all pre-existing.
- Produces: `class ElementalAffinityComponent { final Map<String, num> affinities; }`,
  `abstract final class Elements { static const fire; static const water; static const lightning; }`,
  `void attuneToElement(EntityId entity, String element, num affinity, PluginContext context)`.

- [ ] **Step 1: Write `elemental_affinity_component.dart`**

```dart
/// An entity's elemental affinities — how strongly attuned it is to each
/// element it has been attuned to (see `attuneToElement`). Plain state,
/// no gameplay logic, matching every other component in this engine.
class ElementalAffinityComponent {
  const ElementalAffinityComponent(this.affinities);

  /// Element id (see `Elements`) -> affinity level.
  final Map<String, num> affinities;
}
```

- [ ] **Step 2: Write `elements.dart`**

```dart
import 'package:build_engine/build_engine.dart';

import 'elemental_affinity_component.dart';

/// The three elements this example plugin's vertical slice implements.
/// Not components — an element is a marker tag (`element:<id>`) granted
/// by [attuneToElement], mirroring `MartialStyles`/`learnStyle`.
abstract final class Elements {
  static const fire = 'fire';
  static const water = 'water';
  static const lightning = 'lightning';
}

RuleContext _standaloneContext(EntityId subject, PluginContext context) =>
    RuleContext(
      subject: subject,
      triggerEvent: const Object(),
      entities: context.entities,
      components: context.components,
      events: context.events,
      rng: context.rng,
      eventCounts: context.rules.eventCounts,
    );

/// Grants [entity] the `element:<element>` tag and merges [affinity] into
/// its `ElementalAffinityComponent` (creating the component if absent,
/// preserving any other element's existing affinity).
void attuneToElement(
  EntityId entity,
  String element,
  num affinity,
  PluginContext context,
) {
  final existing =
      context.components.get<ElementalAffinityComponent>(entity);
  context.components.add(
    entity,
    ElementalAffinityComponent({
      ...?existing?.affinities,
      element: affinity,
    }),
  );
  AddTag('element:$element').apply(_standaloneContext(entity, context));
}
```

- [ ] **Step 3: Write `lib/example_elemental_plugin.dart`**

```dart
/// Public API for ExampleElementalPlugin — the Plugin SDK's reference
/// plugin. Import this, not `lib/src/...` directly.
library;

export 'src/plugins/example_elemental/elemental_affinity_component.dart';
export 'src/plugins/example_elemental/elements.dart';
```

- [ ] **Step 4: Write `elemental_affinity_component_test.dart`**

```dart
import 'package:build_engine/example_elemental_plugin.dart';
import 'package:test/test.dart';

void main() {
  test('ElementalAffinityComponent stores the given affinities', () {
    const component = ElementalAffinityComponent({'fire': 5, 'water': 2});
    expect(component.affinities, equals({'fire': 5, 'water': 2}));
  });
}
```

- [ ] **Step 5: Write `elements_test.dart`**

```dart
import 'package:build_engine/build_engine.dart';
import 'package:build_engine/example_elemental_plugin.dart';
import 'package:test/test.dart';

PluginContext _newContext() {
  final events = EventBus();
  final entities = EntityRegistry(events);
  final components = ComponentStore();
  final rng = RngService(1);
  return PluginContext(
    entities: entities,
    components: components,
    events: events,
    rng: rng,
    rules: RuleEngine(
      entities: entities,
      components: components,
      events: events,
      rng: rng,
    ),
    queries: QueryEngine(QueryScope(components: components)),
    modifiers: ModifierCollection(),
    content: ContentRegistry(),
  );
}

void main() {
  group('attuneToElement', () {
    test('grants the element:<id> tag', () {
      final context = _newContext();
      final entity = context.entities.create();

      attuneToElement(entity, Elements.fire, 5, context);

      expect(context.components.get<TagSet>(entity)!.tags,
          contains('element:fire'));
    });

    test('sets the affinity level in ElementalAffinityComponent', () {
      final context = _newContext();
      final entity = context.entities.create();

      attuneToElement(entity, Elements.fire, 5, context);

      expect(
        context.components.get<ElementalAffinityComponent>(entity)!
            .affinities['fire'],
        equals(5),
      );
    });

    test('attuning to a second element preserves the first', () {
      final context = _newContext();
      final entity = context.entities.create();

      attuneToElement(entity, Elements.fire, 5, context);
      attuneToElement(entity, Elements.water, 3, context);

      final affinities = context.components
          .get<ElementalAffinityComponent>(entity)!
          .affinities;
      expect(affinities['fire'], equals(5));
      expect(affinities['water'], equals(3));

      final tags = context.components.get<TagSet>(entity)!.tags;
      expect(tags, containsAll(['element:fire', 'element:water']));
    });

    test('re-attuning to the same element overwrites its affinity', () {
      final context = _newContext();
      final entity = context.entities.create();

      attuneToElement(entity, Elements.fire, 5, context);
      attuneToElement(entity, Elements.fire, 9, context);

      expect(
        context.components.get<ElementalAffinityComponent>(entity)!
            .affinities['fire'],
        equals(9),
      );
    });
  });
}
```

- [ ] **Step 6: Run and commit**

Run: `dart test test/plugins/example_elemental/`
Expected: every test PASSES.

```bash
git add lib/src/plugins/example_elemental/elemental_affinity_component.dart \
  lib/src/plugins/example_elemental/elements.dart \
  lib/example_elemental_plugin.dart \
  test/plugins/example_elemental/elemental_affinity_component_test.dart \
  test/plugins/example_elemental/elements_test.dart
git commit -m "feat: add Elements, ElementalAffinityComponent, attuneToElement"
```

---

### Task 3: `HasElementalAffinity` and `ApplyElementalStatus`

**Files:**
- Create: `lib/src/plugins/example_elemental/elemental_conditions.dart`
- Create: `lib/src/plugins/example_elemental/elemental_effects.dart`
- Modify: `lib/example_elemental_plugin.dart`
- Test: `test/plugins/example_elemental/elemental_conditions_test.dart`
- Test: `test/plugins/example_elemental/elemental_effects_test.dart`

**Interfaces:**
- Consumes: `Condition`, `Effect`, `RuleContext`, `ApplyStatus`
  (`package:build_engine/build_engine.dart`); `ElementalAffinityComponent`
  (Task 2, `package:build_engine/example_elemental_plugin.dart`).
- Produces: `class HasElementalAffinity implements Condition`,
  `class ApplyElementalStatus implements Effect`.

- [ ] **Step 1: Write `elemental_conditions.dart`**

```dart
import 'package:build_engine/build_engine.dart';

import 'elemental_affinity_component.dart';

/// Matches when the rule's subject has at least [threshold] affinity for
/// [element] (see `attuneToElement`) — the same shape as core's
/// `ResourceAbove`/`HealthBelow`, just reading this plugin's own
/// component instead of a core one.
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

- [ ] **Step 2: Write `elemental_effects.dart`**

```dart
import 'package:build_engine/build_engine.dart';

/// Applies the status tag associated with [element] — composes core's
/// existing `ApplyStatus` rather than reimplementing status mutation,
/// the same way MartialArts' rules compose `Heal`/`Damage`.
class ApplyElementalStatus implements Effect {
  const ApplyElementalStatus(this.element);

  final String element;

  @override
  void apply(RuleContext context) =>
      ApplyStatus(_statusFor(element)).apply(context);

  static String _statusFor(String element) => switch (element) {
        'fire' => 'status:burning',
        'water' => 'status:soaked',
        'lightning' => 'status:shocked',
        _ => 'status:$element',
      };
}
```

- [ ] **Step 3: Update `lib/example_elemental_plugin.dart`**

```dart
/// Public API for ExampleElementalPlugin — the Plugin SDK's reference
/// plugin. Import this, not `lib/src/...` directly.
library;

export 'src/plugins/example_elemental/elemental_affinity_component.dart';
export 'src/plugins/example_elemental/elemental_conditions.dart';
export 'src/plugins/example_elemental/elemental_effects.dart';
export 'src/plugins/example_elemental/elements.dart';
```

- [ ] **Step 4: Write `elemental_conditions_test.dart`**

```dart
import 'package:build_engine/build_engine.dart';
import 'package:build_engine/example_elemental_plugin.dart';
import 'package:test/test.dart';

PluginContext _newContext() {
  final events = EventBus();
  final entities = EntityRegistry(events);
  final components = ComponentStore();
  final rng = RngService(1);
  return PluginContext(
    entities: entities,
    components: components,
    events: events,
    rng: rng,
    rules: RuleEngine(
      entities: entities,
      components: components,
      events: events,
      rng: rng,
    ),
    queries: QueryEngine(QueryScope(components: components)),
    modifiers: ModifierCollection(),
    content: ContentRegistry(),
  );
}

RuleContext _contextFor(EntityId? subject, PluginContext context) =>
    RuleContext(
      subject: subject,
      triggerEvent: const Object(),
      entities: context.entities,
      components: context.components,
      events: context.events,
      rng: context.rng,
      eventCounts: context.rules.eventCounts,
    );

void main() {
  group('HasElementalAffinity', () {
    test('matches when affinity is at or above the threshold', () {
      final context = _newContext();
      final entity = context.entities.create();
      attuneToElement(entity, Elements.fire, 5, context);

      expect(
        const HasElementalAffinity('fire', 5)
            .evaluate(_contextFor(entity, context)),
        isTrue,
      );
      expect(
        const HasElementalAffinity('fire', 6)
            .evaluate(_contextFor(entity, context)),
        isFalse,
      );
    });

    test('treats a missing component as zero affinity', () {
      final context = _newContext();
      final entity = context.entities.create();

      expect(
        const HasElementalAffinity('fire', 1)
            .evaluate(_contextFor(entity, context)),
        isFalse,
      );
    });

    test('returns false with no subject', () {
      final context = _newContext();
      expect(
        const HasElementalAffinity('fire', 0)
            .evaluate(_contextFor(null, context)),
        isFalse,
      );
    });
  });
}
```

- [ ] **Step 5: Write `elemental_effects_test.dart`**

```dart
import 'package:build_engine/build_engine.dart';
import 'package:build_engine/example_elemental_plugin.dart';
import 'package:test/test.dart';

PluginContext _newContext() {
  final events = EventBus();
  final entities = EntityRegistry(events);
  final components = ComponentStore();
  final rng = RngService(1);
  return PluginContext(
    entities: entities,
    components: components,
    events: events,
    rng: rng,
    rules: RuleEngine(
      entities: entities,
      components: components,
      events: events,
      rng: rng,
    ),
    queries: QueryEngine(QueryScope(components: components)),
    modifiers: ModifierCollection(),
    content: ContentRegistry(),
  );
}

RuleContext _contextFor(EntityId subject, PluginContext context) =>
    RuleContext(
      subject: subject,
      triggerEvent: const Object(),
      entities: context.entities,
      components: context.components,
      events: context.events,
      rng: context.rng,
      eventCounts: context.rules.eventCounts,
    );

void main() {
  group('ApplyElementalStatus', () {
    test('fire applies status:burning', () {
      final context = _newContext();
      final entity = context.entities.create();
      const ApplyElementalStatus('fire').apply(_contextFor(entity, context));
      expect(
        context.components.get<StatusComponent>(entity)!.activeStatuses,
        contains('status:burning'),
      );
    });

    test('water applies status:soaked', () {
      final context = _newContext();
      final entity = context.entities.create();
      const ApplyElementalStatus('water')
          .apply(_contextFor(entity, context));
      expect(
        context.components.get<StatusComponent>(entity)!.activeStatuses,
        contains('status:soaked'),
      );
    });

    test('lightning applies status:shocked', () {
      final context = _newContext();
      final entity = context.entities.create();
      const ApplyElementalStatus('lightning')
          .apply(_contextFor(entity, context));
      expect(
        context.components.get<StatusComponent>(entity)!.activeStatuses,
        contains('status:shocked'),
      );
    });
  });
}
```

- [ ] **Step 6: Run and commit**

Run: `dart test test/plugins/example_elemental/`
Expected: every test PASSES.

```bash
git add lib/src/plugins/example_elemental/elemental_conditions.dart \
  lib/src/plugins/example_elemental/elemental_effects.dart \
  lib/example_elemental_plugin.dart \
  test/plugins/example_elemental/elemental_conditions_test.dart \
  test/plugins/example_elemental/elemental_effects_test.dart
git commit -m "feat: add HasElementalAffinity and ApplyElementalStatus"
```

---

### Task 4: `buildElementalRules`

**Files:**
- Create: `lib/src/plugins/example_elemental/elemental_rules.dart`
- Modify: `lib/example_elemental_plugin.dart`
- Test: `test/plugins/example_elemental/elemental_rules_test.dart`

**Interfaces:**
- Consumes: `Rule`, `HasTag`, `EntityDamaged`
  (`package:build_engine/build_engine.dart`); `ApplyElementalStatus`
  (Task 3, `package:build_engine/example_elemental_plugin.dart`).
- Produces: `List<Rule> buildElementalRules()`.

- [ ] **Step 1: Write `elemental_rules.dart`**

```dart
import 'package:build_engine/build_engine.dart';

import 'elemental_effects.dart';

/// This example plugin's one cross-cutting interaction: "water conducts"
/// — an entity already tagged `status:soaked` that takes damage also
/// gets shocked. Reacts to Core's own `EntityDamaged` event (published
/// by core's `Damage` effect) — needs no Combat dependency at all,
/// unlike MartialArts' `EntityDamaged` rules.
List<Rule> buildElementalRules() => [
      Rule(
        trigger: EntityDamaged,
        subjectOf: (event) => (event as EntityDamaged).id,
        conditions: const [StatusActive('status:soaked')],
        effects: const [ApplyElementalStatus('lightning')],
      ),
    ];
```

- [ ] **Step 2: Update `lib/example_elemental_plugin.dart`**

```dart
/// Public API for ExampleElementalPlugin — the Plugin SDK's reference
/// plugin. Import this, not `lib/src/...` directly.
library;

export 'src/plugins/example_elemental/elemental_affinity_component.dart';
export 'src/plugins/example_elemental/elemental_conditions.dart';
export 'src/plugins/example_elemental/elemental_effects.dart';
export 'src/plugins/example_elemental/elemental_rules.dart';
export 'src/plugins/example_elemental/elements.dart';
```

- [ ] **Step 3: Write `elemental_rules_test.dart`**

```dart
import 'package:build_engine/build_engine.dart';
import 'package:build_engine/example_elemental_plugin.dart';
import 'package:test/test.dart';

PluginContext _newContext() {
  final events = EventBus();
  final entities = EntityRegistry(events);
  final components = ComponentStore();
  final rng = RngService(1);
  return PluginContext(
    entities: entities,
    components: components,
    events: events,
    rng: rng,
    rules: RuleEngine(
      entities: entities,
      components: components,
      events: events,
      rng: rng,
    ),
    queries: QueryEngine(QueryScope(components: components)),
    modifiers: ModifierCollection(),
    content: ContentRegistry(),
  );
}

void main() {
  test('a soaked entity that takes damage also becomes shocked', () {
    final context = _newContext();
    for (final rule in buildElementalRules()) {
      context.rules.register(rule);
    }

    final entity = context.entities.create();
    context.components
        .add(entity, const HealthComponent(current: 100, max: 100));
    context.components.add(entity, StatusComponent({'status:soaked'}));

    context.events.publish(EntityDamaged(entity, 10));

    expect(
      context.components.get<StatusComponent>(entity)!.activeStatuses,
      containsAll(['status:soaked', 'status:shocked']),
    );
  });

  test('an entity that is not soaked is unaffected', () {
    final context = _newContext();
    for (final rule in buildElementalRules()) {
      context.rules.register(rule);
    }

    final entity = context.entities.create();
    context.components
        .add(entity, const HealthComponent(current: 100, max: 100));

    context.events.publish(EntityDamaged(entity, 10));

    expect(context.components.get<StatusComponent>(entity), isNull);
  });
}
```

- [ ] **Step 4: Run and commit**

Run: `dart test test/plugins/example_elemental/`
Expected: every test PASSES.

```bash
git add lib/src/plugins/example_elemental/elemental_rules.dart \
  lib/example_elemental_plugin.dart \
  test/plugins/example_elemental/elemental_rules_test.dart
git commit -m "feat: add buildElementalRules (water conducts lightning)"
```

---

### Task 5: Elemental content definitions

**Files:**
- Create: `lib/src/plugins/example_elemental/elemental_content.dart`
- Modify: `lib/example_elemental_plugin.dart`
- Test: `test/plugins/example_elemental/elemental_content_test.dart`

**Interfaces:**
- Consumes: `PluginSdk`, `ContentField` (Task 1,
  `package:build_engine/build_engine.dart`); `ApplyElementalStatus`,
  `HasElementalAffinity` (Task 3,
  `package:build_engine/example_elemental_plugin.dart`).
- Produces: `const elementalContentDefinitions = <Map<String, dynamic>>[...]`.

- [ ] **Step 1: Write `elemental_content.dart`**

```dart
/// The three elemental spells this example plugin's vertical slice
/// implements, as data — loaded via `PluginSdk.registerContentBatch` in
/// `ExampleElementalPlugin.initialize`. Each mixes a built-in
/// `ContentRegistry` factory (`damage`) with this plugin's own
/// (`applyElementalStatus`, `hasElementalAffinity`), demonstrating the
/// complete data pipeline end to end.
const elementalContentDefinitions = <Map<String, dynamic>>[
  {
    'id': 'fireball',
    'type': 'spell',
    'tags': ['element:fire', 'attack'],
    'components': {
      'cost': {'resource': 'mana', 'amount': 4},
    },
    'conditions': [
      {'type': 'hasElementalAffinity', 'element': 'fire', 'threshold': 1},
    ],
    'effects': [
      {'type': 'damage', 'amount': 12},
      {'type': 'applyElementalStatus', 'element': 'fire'},
    ],
  },
  {
    'id': 'tidal_wave',
    'type': 'spell',
    'tags': ['element:water', 'attack'],
    'components': {
      'cost': {'resource': 'mana', 'amount': 3},
    },
    'conditions': [
      {'type': 'hasElementalAffinity', 'element': 'water', 'threshold': 1},
    ],
    'effects': [
      {'type': 'damage', 'amount': 8},
      {'type': 'applyElementalStatus', 'element': 'water'},
    ],
  },
  {
    'id': 'spark_bolt',
    'type': 'spell',
    'tags': ['element:lightning', 'attack'],
    'components': {
      'cost': {'resource': 'mana', 'amount': 5},
    },
    'conditions': [
      {
        'type': 'hasElementalAffinity',
        'element': 'lightning',
        'threshold': 1,
      },
    ],
    'effects': [
      {'type': 'damage', 'amount': 10},
      {'type': 'applyElementalStatus', 'element': 'lightning'},
    ],
  },
];
```

- [ ] **Step 2: Update `lib/example_elemental_plugin.dart`**

```dart
/// Public API for ExampleElementalPlugin — the Plugin SDK's reference
/// plugin. Import this, not `lib/src/...` directly.
library;

export 'src/plugins/example_elemental/elemental_affinity_component.dart';
export 'src/plugins/example_elemental/elemental_conditions.dart';
export 'src/plugins/example_elemental/elemental_content.dart';
export 'src/plugins/example_elemental/elemental_effects.dart';
export 'src/plugins/example_elemental/elemental_rules.dart';
export 'src/plugins/example_elemental/elements.dart';
```

- [ ] **Step 3: Write `elemental_content_test.dart`**

```dart
import 'package:build_engine/build_engine.dart';
import 'package:build_engine/example_elemental_plugin.dart';
import 'package:test/test.dart';

PluginContext _newContext() {
  final events = EventBus();
  final entities = EntityRegistry(events);
  final components = ComponentStore();
  final rng = RngService(1);
  return PluginContext(
    entities: entities,
    components: components,
    events: events,
    rng: rng,
    rules: RuleEngine(
      entities: entities,
      components: components,
      events: events,
      rng: rng,
    ),
    queries: QueryEngine(QueryScope(components: components)),
    modifiers: ModifierCollection(),
    content: ContentRegistry(),
  );
}

void main() {
  test(
      'all three definitions load atomically with the custom factories '
      'registered', () {
    final context = _newContext();
    final sdk = PluginSdk(context);
    sdk.registerEffect(
      'applyElementalStatus',
      (p) => ApplyElementalStatus(ContentField.requireString(p, 'element')),
    );
    sdk.registerCondition(
      'hasElementalAffinity',
      (p) => HasElementalAffinity(
        ContentField.requireString(p, 'element'),
        ContentField.requireNum(p, 'threshold'),
      ),
    );

    final definitions = sdk.registerContentBatch(elementalContentDefinitions);

    expect(definitions, hasLength(3));
    final fireball = context.content.get('fireball');
    expect(fireball.costEffects.single, isA<ModifyResource>());
    expect(fireball.conditions.single, isA<HasElementalAffinity>());
    expect(fireball.effects, hasLength(2));
    expect(fireball.effects[0], isA<Damage>());
    expect(fireball.effects[1], isA<ApplyElementalStatus>());
  });
}
```

- [ ] **Step 4: Run and commit**

Run: `dart test test/plugins/example_elemental/`
Expected: every test PASSES.

```bash
git add lib/src/plugins/example_elemental/elemental_content.dart \
  lib/example_elemental_plugin.dart \
  test/plugins/example_elemental/elemental_content_test.dart
git commit -m "feat: add elemental content definitions (fireball/tidal_wave/spark_bolt)"
```

---

### Task 6: `ExampleElementalPlugin` and integration test

**Files:**
- Create: `lib/src/plugins/example_elemental/example_elemental_plugin.dart`
- Modify: `lib/example_elemental_plugin.dart`
- Test: `test/plugins/example_elemental/example_elemental_plugin_test.dart`
- Test: `test/integration/example_elemental_end_to_end_test.dart`

**Interfaces:**
- Consumes: `GamePlugin`, `PluginContext`, `PluginSdk`, `PluginManager`
  (`package:build_engine/build_engine.dart`); everything from Tasks 2-5
  (`package:build_engine/example_elemental_plugin.dart`).
- Produces: `class ExampleElementalPlugin extends GamePlugin`.

- [ ] **Step 1: Write `example_elemental_plugin.dart`**

```dart
import 'package:build_engine/build_engine.dart';

import 'elemental_affinity_component.dart';
import 'elemental_conditions.dart';
import 'elemental_content.dart';
import 'elemental_effects.dart';
import 'elemental_rules.dart';

/// The reference plugin for the Plugin SDK: Fire/Water/Lightning, built
/// entirely with `PluginSdk`, depending on nothing but Core — not
/// Combat, not MartialArts. Copy this plugin, not MartialArts, as the
/// starting point for a new content plugin.
class ExampleElementalPlugin extends GamePlugin {
  @override
  String get id => 'example_elemental';

  @override
  String get version => '0.1.0';

  /// Constructed in [initialize]; not `late final` since a plugin can be
  /// `initialize`d again after `unregister` (same reasoning as
  /// `CombatPlugin.system`).
  late PluginSdk sdk;

  @override
  void initialize(PluginContext context) {
    sdk = PluginSdk(context);

    sdk.registerComponentCleanup<ElementalAffinityComponent>();

    sdk.registerEffect(
      'applyElementalStatus',
      (p) => ApplyElementalStatus(ContentField.requireString(p, 'element')),
    );
    sdk.registerCondition(
      'hasElementalAffinity',
      (p) => HasElementalAffinity(
        ContentField.requireString(p, 'element'),
        ContentField.requireNum(p, 'threshold'),
      ),
    );

    sdk.registerTag('element:fire',
        description: 'Fire-aligned entity or content.');
    sdk.registerTag('element:water',
        description: 'Water-aligned entity or content.');
    sdk.registerTag('element:lightning',
        description: 'Lightning-aligned entity or content.');

    for (final rule in buildElementalRules()) {
      sdk.registerRule(rule);
    }

    sdk.registerContentBatch(elementalContentDefinitions);
  }

  /// Mirrors [initialize]: cancels every subscription taken out there —
  /// component cleanup and the "water conducts" rule — so an
  /// unregistered `ExampleElementalPlugin` stops reacting to events
  /// entirely, the same teardown discipline `CombatPlugin`/
  /// `MartialArtsPlugin` already established.
  @override
  void unregister(PluginContext context) {
    sdk.disposeAll();
  }
}
```

- [ ] **Step 2: Update `lib/example_elemental_plugin.dart`**

```dart
/// Public API for ExampleElementalPlugin — the Plugin SDK's reference
/// plugin. Import this, not `lib/src/...` directly.
library;

export 'src/plugins/example_elemental/elemental_affinity_component.dart';
export 'src/plugins/example_elemental/elemental_conditions.dart';
export 'src/plugins/example_elemental/elemental_content.dart';
export 'src/plugins/example_elemental/elemental_effects.dart';
export 'src/plugins/example_elemental/elemental_rules.dart';
export 'src/plugins/example_elemental/elements.dart';
export 'src/plugins/example_elemental/example_elemental_plugin.dart';
```

- [ ] **Step 3: Write `example_elemental_plugin_test.dart`**

```dart
import 'package:build_engine/build_engine.dart';
import 'package:build_engine/example_elemental_plugin.dart';
import 'package:test/test.dart';

PluginContext _newContext() {
  final events = EventBus();
  final entities = EntityRegistry(events);
  final components = ComponentStore();
  final rng = RngService(1);
  return PluginContext(
    entities: entities,
    components: components,
    events: events,
    rng: rng,
    rules: RuleEngine(
      entities: entities,
      components: components,
      events: events,
      rng: rng,
    ),
    queries: QueryEngine(QueryScope(components: components)),
    modifiers: ModifierCollection(),
    content: ContentRegistry(),
  );
}

void main() {
  test('declares no dependencies', () {
    expect(ExampleElementalPlugin().dependencies, isEmpty);
  });

  test('initialize registers the content definitions and the rule', () {
    final context = _newContext();
    final plugin = ExampleElementalPlugin();
    plugin.initialize(context);

    expect(context.content.get('fireball'), isNotNull);
    expect(context.content.get('tidal_wave'), isNotNull);
    expect(context.content.get('spark_bolt'), isNotNull);

    final entity = context.entities.create();
    context.components
        .add(entity, const HealthComponent(current: 10, max: 10));
    context.components.add(entity, StatusComponent({'status:soaked'}));
    context.events.publish(EntityDamaged(entity, 1));
    expect(
      context.components.get<StatusComponent>(entity)!.activeStatuses,
      contains('status:shocked'),
    );
  });

  test('unregister stops the rule and component cleanup from firing', () {
    final context = _newContext();
    final plugin = ExampleElementalPlugin();
    plugin.initialize(context);
    plugin.unregister(context);

    final entity = context.entities.create();
    context.components
        .add(entity, const HealthComponent(current: 10, max: 10));
    context.components.add(entity, StatusComponent({'status:soaked'}));
    context.events.publish(EntityDamaged(entity, 1));
    expect(
      context.components.get<StatusComponent>(entity)!.activeStatuses,
      isNot(contains('status:shocked')),
    );

    attuneToElement(entity, Elements.fire, 1, context);
    context.entities.destroy(entity);
    expect(context.components.get<ElementalAffinityComponent>(entity),
        isNotNull);
  });
}
```

- [ ] **Step 4: Write `test/integration/example_elemental_end_to_end_test.dart`**

```dart
import 'package:build_engine/build_engine.dart';
import 'package:build_engine/example_elemental_plugin.dart';
import 'package:test/test.dart';

void main() {
  test(
      'ExampleElementalPlugin runs standalone (no Combat, no MartialArts) '
      'and is fully removable', () {
    final events = EventBus();
    final entities = EntityRegistry(events);
    final components = ComponentStore();
    final rng = RngService(1);
    final context = PluginContext(
      entities: entities,
      components: components,
      events: events,
      rng: rng,
      rules: RuleEngine(
        entities: entities,
        components: components,
        events: events,
        rng: rng,
      ),
      queries: QueryEngine(QueryScope(components: components)),
      modifiers: ModifierCollection(),
      content: ContentRegistry(),
    );

    final manager = PluginManager();
    manager.register(ExampleElementalPlugin());
    manager.initialize(context);
    manager.start(context);

    final caster = entities.create();
    final target = entities.create();
    attuneToElement(caster, Elements.fire, 1, context);
    components.add(caster, ResourceComponent({'mana': 10}));
    components.add(target, const HealthComponent(current: 100, max: 100));

    RuleContext contextFor(EntityId subject) => RuleContext(
          subject: subject,
          triggerEvent: const Object(),
          entities: entities,
          components: components,
          events: events,
          rng: rng,
          eventCounts: EventCounter(events),
        );

    final fireball = context.content.get('fireball');
    final qualifies =
        fireball.conditions.every((c) => c.evaluate(contextFor(caster)));
    expect(qualifies, isTrue);

    for (final cost in fireball.costEffects) {
      cost.apply(contextFor(caster));
    }
    expect(components.get<ResourceComponent>(caster)!.resources['mana'],
        equals(6));

    for (final effect in fireball.effects) {
      effect.apply(contextFor(target));
    }
    expect(components.get<HealthComponent>(target)!.current, equals(88));
    expect(components.get<StatusComponent>(target)!.activeStatuses,
        contains('status:burning'));

    // "Water conducts": a soaked entity that takes damage also gets
    // shocked, purely through the plugin's own rule.
    final soaked = entities.create();
    components.add(soaked, const HealthComponent(current: 50, max: 50));
    components.add(soaked, StatusComponent({'status:soaked'}));
    events.publish(EntityDamaged(soaked, 5));
    expect(components.get<StatusComponent>(soaked)!.activeStatuses,
        contains('status:shocked'));

    // Removability: after stop/unregister, the rule no longer fires and
    // component cleanup stops too — mirroring MartialArtsPlugin's
    // existing removability test.
    manager.stop(context);
    manager.unregister(context);

    final soakedAfter = entities.create();
    components.add(soakedAfter, const HealthComponent(current: 50, max: 50));
    components.add(soakedAfter, StatusComponent({'status:soaked'}));
    events.publish(EntityDamaged(soakedAfter, 5));
    expect(components.get<StatusComponent>(soakedAfter)!.activeStatuses,
        isNot(contains('status:shocked')));

    entities.destroy(caster);
    expect(components.get<ElementalAffinityComponent>(caster), isNotNull);
  });
}
```

- [ ] **Step 5: Run the whole suite and commit**

Run: `dart test`
Expected: every test in the package PASSES.

```bash
git add lib/src/plugins/example_elemental/example_elemental_plugin.dart \
  lib/example_elemental_plugin.dart \
  test/plugins/example_elemental/example_elemental_plugin_test.dart \
  test/integration/example_elemental_end_to_end_test.dart
git commit -m "feat: add ExampleElementalPlugin; test standalone removability end to end"
```

---

### Task 7: Documentation

**Files:**
- Modify: `PLUGIN_SYSTEM.md`
- Modify: `ARCHITECTURE.md`

- [ ] **Step 1: Fix `PLUGIN_SYSTEM.md`'s stale `PluginContext` block**

Find the existing `## PluginContext` section's code block (currently
missing the `content` field this engine already added in a prior pass)
and replace it and the paragraph below it:

```markdown
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

The only access a plugin's lifecycle methods get to core services.
Exposes exactly the services that exist — no placeholder getters for
services (spatial, resources, save/load) that haven't been built yet.
When those services are built, `PluginContext` grows to expose them.
`content` (a `ContentRegistry`, `claude.md`'s Asset/Data Registry) was
the most recent addition — see `ARCHITECTURE.md`'s Content Registry
section.
```

- [ ] **Step 2: Add a "Plugin SDK" section**

Insert after the "PluginContext" section (before "Dependency
resolution"):

```markdown
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
```

- [ ] **Step 3: Add a "Writing a third-party plugin" section**

Insert after "Adding a plugin" (before "Plugins must not reach into
each other's private implementation"):

```markdown
## Writing a third-party plugin

`ExampleElementalPlugin` (`lib/src/plugins/example_elemental/`,
`lib/example_elemental_plugin.dart`) is the reference: Fire/Water/
Lightning, built entirely with `PluginSdk`, depending on nothing but
Core — not Combat, not MartialArts. Copy it, not `MartialArtsPlugin`, as
your starting point; `MartialArtsPlugin` additionally demonstrates
depending on another plugin (`-> combat`), which most third-party
plugins won't need on day one.

Steps, in the order `ExampleElementalPlugin` follows them:

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
   `ExampleElementalPlugin.initialize`) — and call `sdk.disposeAll()` in
   `unregister`.
7. **Export a barrel** (`lib/my_plugin.dart`) so consumers import your
   plugin the same way they import `combat_plugin.dart`/
   `martial_arts_plugin.dart`/`example_elemental_plugin.dart` — never
   `lib/src/...` directly.

Test the same way every plugin in this engine is tested (see
`claude.md`'s TESTING section): registration, initialization, behavior,
serialization where applicable, dependency, and — if you react to
another plugin's events like MartialArts does — an integration test
proving your plugin is fully removable (see
`test/integration/example_elemental_end_to_end_test.dart` and
`test/integration/martial_arts_end_to_end_test.dart` for the pattern).
```

- [ ] **Step 4: Add an ARCHITECTURE.md entry**

Append after the "Content Registry" section, at the end of the file:

```markdown
## Plugin SDK and ExampleElementalPlugin (`lib/src/plugin/plugin_sdk.dart`, `lib/src/plugins/example_elemental/`)

`PluginSdk` is a convenience façade over `PluginContext`, not a new Core
capability — every method delegates to a service `PluginContext` already
exposed before this pass (`entities`/`components`/`events`/`rules`/
`content`). Its entire value is eliminating the
`List<EventSubscription>` bookkeeping `MartialArtsPlugin` originally had
to manage by hand: `registerComponentCleanup`/`registerEvent`/
`registerRule` all track their `EventSubscription` internally, and
`disposeAll()` cancels every one of them in a plugin's `unregister` —
see `PLUGIN_SYSTEM.md` for the full method table and a step-by-step
walkthrough for third-party developers.

`registerAsset`/`registerLocalization` are sugar over `content` rather
than new services: `claude.md`'s numbered core-service list has one
combined entry, "12. Asset/Data Registry" — `ContentRegistry` (the prior
pass) already is that registry, so "asset" and "localization" are simply
two more opaque `type` values, no different in kind from "skill" or
"item". This does mean neither is undoable via `disposeAll()` —
`ContentRegistry` has no factory-removal or unload operation, a
limitation this pass didn't change, so it's documented rather than
papered over.

`ExampleElementalPlugin` is the SDK's reference implementation:
Fire/Water/Lightning, depending on nothing but Core (`dependencies =>
const []`) — deliberately not Combat, unlike `MartialArtsPlugin`, so a
third-party developer's first example is the simplest one, not one that
also demonstrates cross-plugin dependency. Its "water conducts"
interaction (a `status:soaked` entity that takes damage also becomes
`status:shocked`) reacts to Core's own `EntityDamaged` event exactly the
way MartialArts' Shaolin rule does, proving the same "react to events,
don't intercept effects" pattern holds with zero Combat involvement at
all. Its `ElementalAffinityComponent`/`HasElementalAffinity`/
`ApplyElementalStatus` mirror `MartialLoadoutComponent`/`ResourceAbove`/
composed-`ApplyStatus` in shape, and its three content definitions
(`fireball`/`tidal_wave`/`spark_bolt`) each mix a built-in
`ContentRegistry` factory (`damage`) with two of the plugin's own
(`applyElementalStatus`, `hasElementalAffinity`), loaded atomically via
`sdk.registerContentBatch` — proving last pass's `loadAll` atomicity
composes cleanly with a real plugin's `initialize`.
```

- [ ] **Step 5: Commit**

```bash
git add PLUGIN_SYSTEM.md ARCHITECTURE.md
git commit -m "docs: document PluginSdk and how to write a third-party plugin"
```
