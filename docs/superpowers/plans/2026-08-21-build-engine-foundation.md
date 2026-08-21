# Build Engine Foundation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Bootstrap the Build Engine repository with the core foundation only — EntityId, EntityRegistry, ComponentStore, EventBus, and the plugin system (GamePlugin interface, PluginContext, PluginManager with dependency resolution) — with full test coverage, clean analysis, and architecture docs.

**Architecture:** A single pure-Dart package `build_engine` (no Flutter dependency, so the engine stays usable headless). Each service is a small, independently-testable class with no hidden coupling to its siblings — EntityRegistry and ComponentStore in particular do not reference each other directly; integration between them is documented as an event-subscription pattern, not hardcoded.

**Tech Stack:** Dart (SDK `^3.7.0`), `package:test`, `package:lints` recommended ruleset, `dart pub`/`dart test`/`dart analyze`. No Flutter, no build_runner/codegen.

**Spec:** `docs/superpowers/specs/2026-08-21-build-engine-foundation-design.md`

All paths below are relative to the repo root: `/Users/m4maxpro/Projects/Tome:RougelikeGame`.

## Global Constraints

- No martial-arts, magic, combat, or other game-specific vocabulary anywhere in this package (per `CLAUDE.md`'s core/plugin contract).
- No Rule Engine, Effect Engine, Modifier Engine, Query Engine, Spatial/Container Engine, Resource Engine, Scheduler, RNG Service, Asset/Data Registry, or Serialization — out of scope this pass.
- Pure Dart package, no Flutter SDK dependency.
- `sdk: ^3.7.0` in `pubspec.yaml`.
- Gameplay/lifecycle randomness is not introduced in this pass at all (no RNG service exists yet) — do not add any use of `dart:math`'s `Random()` anywhere in this package.
- EntityId allocation is a monotonically increasing `int`, never a random UUID (determinism requirement from the spec).
- `EntityRegistry` and `ComponentStore` must not import or reference each other.
- Every task must end with `dart analyze` reporting zero issues and `dart test` passing, before committing.

---

### Task 1: Project scaffolding

**Files:**
- Create: `pubspec.yaml`
- Create: `analysis_options.yaml`
- Create: `.gitignore`
- Create: `lib/build_engine.dart`

**Interfaces:**
- Consumes: nothing (first task).
- Produces: a `dart pub get`-able, `dart analyze`-clean package skeleton that every later task adds files under `lib/src/` and exports from `lib/build_engine.dart`.

- [ ] **Step 1: Initialize git**

Run:
```bash
cd "/Users/m4maxpro/Projects/Tome:RougelikeGame"
git init
git status
```
Expected: `Initialized empty Git repository in /Users/m4maxpro/Projects/Tome:RougelikeGame/.git/`, and `git rev-parse --show-toplevel` now prints `/Users/m4maxpro/Projects/Tome:RougelikeGame` (confirm this — it must **not** print `/Users/m4maxpro`).

- [ ] **Step 2: Create `pubspec.yaml`**

```yaml
name: build_engine
description: >-
  A modular, data-driven game engine core. Provides generic verbs (entities,
  components, events, plugins) only; game-specific content lives in plugins,
  never in this package.
version: 0.1.0
publish_to: none

environment:
  sdk: ^3.7.0

dev_dependencies:
  lints: ^5.0.0
  test: ^1.25.0
```

- [ ] **Step 3: Create `analysis_options.yaml`**

```yaml
include: package:lints/recommended.yaml

analyzer:
  language:
    strict-casts: true
    strict-inference: true
    strict-raw-types: true
```

- [ ] **Step 4: Create `.gitignore`**

```
.dart_tool/
.packages
build/
pubspec.lock
doc/api/
```

- [ ] **Step 5: Create `lib/build_engine.dart`**

```dart
/// Build Engine — a modular, data-driven game engine core.
///
/// The core provides generic verbs (entities, components, events, plugins);
/// game-specific content belongs in plugins, not here.
library;
```

- [ ] **Step 6: Fetch dependencies and verify the skeleton is clean**

Run:
```bash
dart pub get
dart analyze
```
Expected: `dart pub get` succeeds (`Got dependencies!`); `dart analyze` reports `No issues found!`.

- [ ] **Step 7: Commit**

```bash
git add pubspec.yaml analysis_options.yaml .gitignore lib/build_engine.dart
git commit -m "chore: scaffold build_engine package"
```

---

### Task 2: EntityId

**Files:**
- Create: `lib/src/entity/entity_id.dart`
- Test: `test/entity_id_test.dart`
- Modify: `lib/build_engine.dart`

**Interfaces:**
- Consumes: nothing.
- Produces: `class EntityId implements Comparable<EntityId>` with `const EntityId(int value)` constructor, a public `final int value` field, `==`, `hashCode`, `compareTo`, `toString`. Every later task that needs an entity identifier uses this type.

- [ ] **Step 1: Write the failing test**

Create `test/entity_id_test.dart`:

```dart
import 'package:build_engine/build_engine.dart';
import 'package:test/test.dart';

void main() {
  group('EntityId', () {
    test('two ids with the same value are equal', () {
      expect(const EntityId(1), equals(const EntityId(1)));
    });

    test('ids with different values are not equal', () {
      expect(const EntityId(1), isNot(equals(const EntityId(2))));
    });

    test('equal ids have equal hashCodes', () {
      expect(const EntityId(7).hashCode, equals(const EntityId(7).hashCode));
    });

    test('compareTo orders by value', () {
      expect(const EntityId(1).compareTo(const EntityId(2)), lessThan(0));
      expect(const EntityId(2).compareTo(const EntityId(1)), greaterThan(0));
      expect(const EntityId(2).compareTo(const EntityId(2)), equals(0));
    });

    test('exposes its underlying value', () {
      expect(const EntityId(42).value, equals(42));
    });

    test('toString is human-readable', () {
      expect(const EntityId(3).toString(), contains('3'));
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `dart test test/entity_id_test.dart`
Expected: FAIL — `Error: Undefined class 'EntityId'` (or similar), because `EntityId` and the `build_engine` export don't exist yet.

- [ ] **Step 3: Implement `EntityId`**

Create `lib/src/entity/entity_id.dart`:

```dart
/// A unique identifier for an entity, assigned in creation order by
/// [EntityRegistry.create]. Sequential rather than random so that a run is
/// reproducible from seed + initial state + actions.
class EntityId implements Comparable<EntityId> {
  const EntityId(this.value);

  /// The underlying sequential identifier. Stable across saves/loads.
  final int value;

  @override
  bool operator ==(Object other) => other is EntityId && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  int compareTo(EntityId other) => value.compareTo(other.value);

  @override
  String toString() => 'EntityId($value)';
}
```

- [ ] **Step 4: Export it from the barrel file**

Modify `lib/build_engine.dart`:

```dart
/// Build Engine — a modular, data-driven game engine core.
///
/// The core provides generic verbs (entities, components, events, plugins);
/// game-specific content belongs in plugins, not here.
library;

export 'src/entity/entity_id.dart';
```

- [ ] **Step 5: Run test to verify it passes, and analyze**

Run:
```bash
dart test test/entity_id_test.dart
dart analyze
```
Expected: all tests PASS; `dart analyze` reports `No issues found!`.

- [ ] **Step 6: Commit**

```bash
git add lib/src/entity/entity_id.dart lib/build_engine.dart test/entity_id_test.dart
git commit -m "feat: add EntityId value type"
```

---

### Task 3: EventBus

**Files:**
- Create: `lib/src/event/event_bus.dart`
- Test: `test/event_bus_test.dart`
- Modify: `lib/build_engine.dart`

**Interfaces:**
- Consumes: nothing.
- Produces: `class EventBus` with `EventSubscription subscribe<T>(void Function(T event) handler)` and `void publish<T>(T event)`; `class EventSubscription` with `void cancel()`. `EntityRegistry` (Task 4) and `PluginContext` (Task 7) both hold an `EventBus` instance.

- [ ] **Step 1: Write the failing test**

Create `test/event_bus_test.dart`:

```dart
import 'package:build_engine/build_engine.dart';
import 'package:test/test.dart';

class _Ping {
  const _Ping(this.n);
  final int n;
}

class _Pong {
  const _Pong(this.n);
  final int n;
}

void main() {
  group('EventBus', () {
    test('a subscriber receives a published event of its type', () {
      final bus = EventBus();
      final received = <int>[];

      bus.subscribe<_Ping>((event) => received.add(event.n));
      bus.publish(const _Ping(1));

      expect(received, equals([1]));
    });

    test('multiple subscribers to the same type all receive the event', () {
      final bus = EventBus();
      final receivedA = <int>[];
      final receivedB = <int>[];

      bus.subscribe<_Ping>((event) => receivedA.add(event.n));
      bus.subscribe<_Ping>((event) => receivedB.add(event.n));
      bus.publish(const _Ping(5));

      expect(receivedA, equals([5]));
      expect(receivedB, equals([5]));
    });

    test('a subscriber never receives events of a different type', () {
      final bus = EventBus();
      final pings = <int>[];
      final pongs = <int>[];

      bus.subscribe<_Ping>((event) => pings.add(event.n));
      bus.subscribe<_Pong>((event) => pongs.add(event.n));

      bus.publish(const _Ping(1));
      bus.publish(const _Pong(2));

      expect(pings, equals([1]));
      expect(pongs, equals([2]));
    });

    test('publishing with no subscribers does not throw', () {
      final bus = EventBus();
      expect(() => bus.publish(const _Ping(1)), returnsNormally);
    });

    test('a cancelled subscription stops receiving events', () {
      final bus = EventBus();
      final received = <int>[];

      final subscription = bus.subscribe<_Ping>((event) => received.add(event.n));
      subscription.cancel();
      bus.publish(const _Ping(1));

      expect(received, isEmpty);
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `dart test test/event_bus_test.dart`
Expected: FAIL — `Error: Undefined class 'EventBus'`.

- [ ] **Step 3: Implement `EventBus`**

Create `lib/src/event/event_bus.dart`:

```dart
/// A handle to a single [EventBus.subscribe] registration. Call [cancel] to
/// stop receiving events on this subscription.
class EventSubscription {
  EventSubscription._(this._cancel);

  final void Function() _cancel;

  /// Stops this subscription's handler from being called for future events.
  void cancel() => _cancel();
}

/// A typed publish/subscribe event bus. Dispatch is by exact runtime type of
/// the published event — a handler registered via `subscribe<Foo>` is only
/// ever called for events whose runtime type is exactly `Foo`.
///
/// When subscribing, give the handler an explicitly-typed parameter (e.g.
/// `bus.subscribe((FooEvent e) => ...)`) or pass the type argument
/// explicitly (`bus.subscribe<FooEvent>(...)`) — an untyped closure parameter
/// infers as `dynamic` and will not match published events correctly.
class EventBus {
  final Map<Type, List<Function>> _handlers = {};

  /// Registers [handler] to be called for every event published with
  /// [publish] whose runtime type is exactly `T`. Returns a subscription
  /// that can be [EventSubscription.cancel]ed.
  EventSubscription subscribe<T>(void Function(T event) handler) {
    final handlers = _handlers.putIfAbsent(T, () => <Function>[]);
    handlers.add(handler);
    return EventSubscription._(() => handlers.remove(handler));
  }

  /// Dispatches [event] to every handler subscribed for its exact runtime
  /// type. No-op if there are no such subscribers.
  void publish<T>(T event) {
    final handlers = _handlers[event.runtimeType];
    if (handlers == null) return;
    for (final handler in List<Function>.from(handlers)) {
      (handler as void Function(T))(event);
    }
  }
}
```

- [ ] **Step 4: Export it from the barrel file**

Modify `lib/build_engine.dart`, adding the new export line:

```dart
export 'src/entity/entity_id.dart';
export 'src/event/event_bus.dart';
```

- [ ] **Step 5: Run test to verify it passes, and analyze**

Run:
```bash
dart test test/event_bus_test.dart
dart analyze
```
Expected: all tests PASS; `dart analyze` reports `No issues found!`.

- [ ] **Step 6: Commit**

```bash
git add lib/src/event/event_bus.dart lib/build_engine.dart test/event_bus_test.dart
git commit -m "feat: add EventBus"
```

---

### Task 4: EntityRegistry

**Files:**
- Create: `lib/src/entity/entity_registry.dart`
- Test: `test/entity_registry_test.dart`
- Modify: `lib/build_engine.dart`

**Interfaces:**
- Consumes: `EntityId` (Task 2), `EventBus` (Task 3) — specifically `EventBus.subscribe<T>()` and `EventBus.publish<T>()`.
- Produces: `class EntityCreated { final EntityId id; }`, `class EntityDestroyed { final EntityId id; }`, `class EntityRegistry` with constructor `EntityRegistry(EventBus events)` and methods `EntityId create()`, `void destroy(EntityId id)`, `bool isAlive(EntityId id)`, `Iterable<EntityId> get all`. `PluginContext` (Task 7) holds an `EntityRegistry` instance.

- [ ] **Step 1: Write the failing test**

Create `test/entity_registry_test.dart`:

```dart
import 'package:build_engine/build_engine.dart';
import 'package:test/test.dart';

void main() {
  group('EntityRegistry', () {
    test('create returns unique sequential ids', () {
      final registry = EntityRegistry(EventBus());

      final first = registry.create();
      final second = registry.create();
      final third = registry.create();

      expect(first, isNot(equals(second)));
      expect(second, isNot(equals(third)));
      expect(second.value, equals(first.value + 1));
      expect(third.value, equals(second.value + 1));
    });

    test('a created entity is alive', () {
      final registry = EntityRegistry(EventBus());
      final id = registry.create();

      expect(registry.isAlive(id), isTrue);
    });

    test('a destroyed entity is no longer alive', () {
      final registry = EntityRegistry(EventBus());
      final id = registry.create();

      registry.destroy(id);

      expect(registry.isAlive(id), isFalse);
    });

    test('destroying an unknown entity throws StateError', () {
      final registry = EntityRegistry(EventBus());

      expect(() => registry.destroy(const EntityId(999)), throwsStateError);
    });

    test('destroying an already-destroyed entity throws StateError', () {
      final registry = EntityRegistry(EventBus());
      final id = registry.create();
      registry.destroy(id);

      expect(() => registry.destroy(id), throwsStateError);
    });

    test('all returns exactly the currently-alive entities', () {
      final registry = EntityRegistry(EventBus());
      final a = registry.create();
      final b = registry.create();
      registry.destroy(a);
      final c = registry.create();

      expect(registry.all.toSet(), equals({b, c}));
    });

    test('create publishes EntityCreated with the new id', () {
      final events = EventBus();
      final registry = EntityRegistry(events);
      final received = <EntityId>[];
      events.subscribe<EntityCreated>((event) => received.add(event.id));

      final id = registry.create();

      expect(received, equals([id]));
    });

    test('destroy publishes EntityDestroyed with the destroyed id', () {
      final events = EventBus();
      final registry = EntityRegistry(events);
      final received = <EntityId>[];
      events.subscribe<EntityDestroyed>((event) => received.add(event.id));

      final id = registry.create();
      registry.destroy(id);

      expect(received, equals([id]));
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `dart test test/entity_registry_test.dart`
Expected: FAIL — `Error: Undefined class 'EntityRegistry'`.

- [ ] **Step 3: Implement `EntityRegistry`**

Create `lib/src/entity/entity_registry.dart`:

```dart
import 'entity_id.dart';
import '../event/event_bus.dart';

/// Published via the registry's [EventBus] whenever [EntityRegistry.create]
/// allocates a new entity.
class EntityCreated {
  const EntityCreated(this.id);
  final EntityId id;
}

/// Published via the registry's [EventBus] whenever [EntityRegistry.destroy]
/// removes an entity.
class EntityDestroyed {
  const EntityDestroyed(this.id);
  final EntityId id;
}

/// Tracks which [EntityId]s currently exist. Allocation is sequential
/// (see [EntityId]). Deliberately has no knowledge of components — cleanup
/// of an entity's components on destroy is the caller's responsibility via
/// an [EntityDestroyed] subscription, not something this class does itself.
class EntityRegistry {
  EntityRegistry(this._events);

  final EventBus _events;
  int _nextValue = 1;
  final Set<EntityId> _alive = {};

  /// Allocates and returns a new, currently-alive [EntityId]. Publishes
  /// [EntityCreated].
  EntityId create() {
    final id = EntityId(_nextValue);
    _nextValue += 1;
    _alive.add(id);
    _events.publish(EntityCreated(id));
    return id;
  }

  /// Marks [id] as no longer alive. Publishes [EntityDestroyed].
  ///
  /// Throws [StateError] if [id] is unknown or already destroyed.
  void destroy(EntityId id) {
    if (!_alive.remove(id)) {
      throw StateError(
        'Cannot destroy unknown or already-destroyed entity: $id',
      );
    }
    _events.publish(EntityDestroyed(id));
  }

  /// Whether [id] currently exists.
  bool isAlive(EntityId id) => _alive.contains(id);

  /// Every currently-alive entity.
  Iterable<EntityId> get all => _alive;
}
```

- [ ] **Step 4: Export it from the barrel file**

Modify `lib/build_engine.dart`, adding the new export line (alongside the existing two):

```dart
export 'src/entity/entity_id.dart';
export 'src/entity/entity_registry.dart';
export 'src/event/event_bus.dart';
```

- [ ] **Step 5: Run test to verify it passes, and analyze**

Run:
```bash
dart test test/entity_registry_test.dart
dart analyze
```
Expected: all tests PASS; `dart analyze` reports `No issues found!`.

- [ ] **Step 6: Commit**

```bash
git add lib/src/entity/entity_registry.dart lib/build_engine.dart test/entity_registry_test.dart
git commit -m "feat: add EntityRegistry"
```

---

### Task 5: ComponentStore

**Files:**
- Create: `lib/src/component/component_store.dart`
- Test: `test/component_store_test.dart`
- Modify: `lib/build_engine.dart`

**Interfaces:**
- Consumes: `EntityId` (Task 2) only — no reference to `EntityRegistry` or `EventBus`.
- Produces: `class ComponentStore` with `void add<T extends Object>(EntityId id, T component)`, `T? get<T extends Object>(EntityId id)`, `bool has<T extends Object>(EntityId id)`, `void remove<T extends Object>(EntityId id)`, `Iterable<EntityId> entitiesWith<T extends Object>()`. `PluginContext` (Task 7) holds a `ComponentStore` instance.

- [ ] **Step 1: Write the failing test**

Create `test/component_store_test.dart`:

```dart
import 'package:build_engine/build_engine.dart';
import 'package:test/test.dart';

class _Position {
  const _Position(this.x, this.y);
  final int x;
  final int y;
}

class _Health {
  const _Health(this.hp);
  final int hp;
}

void main() {
  group('ComponentStore', () {
    test('a component can be added and retrieved', () {
      final store = ComponentStore();
      const id = EntityId(1);

      store.add(id, const _Position(3, 4));

      final position = store.get<_Position>(id);
      expect(position, isNotNull);
      expect(position!.x, equals(3));
      expect(position.y, equals(4));
    });

    test('get returns null when the entity has no such component', () {
      final store = ComponentStore();
      expect(store.get<_Position>(const EntityId(1)), isNull);
    });

    test('has reflects presence and absence', () {
      final store = ComponentStore();
      const id = EntityId(1);

      expect(store.has<_Position>(id), isFalse);
      store.add(id, const _Position(0, 0));
      expect(store.has<_Position>(id), isTrue);
    });

    test('remove clears only the given component type for that entity', () {
      final store = ComponentStore();
      const id = EntityId(1);
      store.add(id, const _Position(1, 1));
      store.add(id, const _Health(10));

      store.remove<_Position>(id);

      expect(store.has<_Position>(id), isFalse);
      expect(store.has<_Health>(id), isTrue);
    });

    test('different component types on the same entity do not collide', () {
      final store = ComponentStore();
      const id = EntityId(1);

      store.add(id, const _Position(2, 2));
      store.add(id, const _Health(50));

      expect(store.get<_Position>(id)!.x, equals(2));
      expect(store.get<_Health>(id)!.hp, equals(50));
    });

    test('entitiesWith returns exactly the entities carrying that component',
        () {
      final store = ComponentStore();
      const a = EntityId(1);
      const b = EntityId(2);
      const c = EntityId(3);

      store.add(a, const _Position(0, 0));
      store.add(b, const _Position(0, 0));
      store.add(c, const _Health(1));

      expect(store.entitiesWith<_Position>().toSet(), equals({a, b}));
      expect(store.entitiesWith<_Health>().toSet(), equals({c}));
    });

    test('entitiesWith returns empty for a component type never added', () {
      final store = ComponentStore();
      expect(store.entitiesWith<_Position>(), isEmpty);
    });

    test('re-adding a component for the same entity overwrites it', () {
      final store = ComponentStore();
      const id = EntityId(1);

      store.add(id, const _Position(1, 1));
      store.add(id, const _Position(2, 2));

      expect(store.get<_Position>(id)!.x, equals(2));
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `dart test test/component_store_test.dart`
Expected: FAIL — `Error: Undefined class 'ComponentStore'`.

- [ ] **Step 3: Implement `ComponentStore`**

Create `lib/src/component/component_store.dart`:

```dart
import '../entity/entity_id.dart';

/// Generic per-type storage for entity components, keyed by the component's
/// runtime [Type]. Deliberately has no reference to [EntityRegistry] or
/// `EventBus` — it can be constructed and tested entirely on its own.
///
/// Cleanup of a destroyed entity's components is not automatic: a consumer
/// should subscribe to `EntityDestroyed` and call [remove] for each
/// component type it knows that entity might carry. See `ARCHITECTURE.md`.
class ComponentStore {
  final Map<Type, Map<EntityId, Object>> _components = {};

  /// Stores [component] as entity [id]'s component of type `T`, overwriting
  /// any component of that same type already stored for [id].
  void add<T extends Object>(EntityId id, T component) {
    final byId = _components.putIfAbsent(T, () => <EntityId, Object>{});
    byId[id] = component;
  }

  /// The component of type `T` stored for entity [id], or `null` if entity
  /// [id] has no such component.
  T? get<T extends Object>(EntityId id) {
    final byId = _components[T];
    return byId?[id] as T?;
  }

  /// Whether entity [id] has a component of type `T`.
  bool has<T extends Object>(EntityId id) =>
      _components[T]?.containsKey(id) ?? false;

  /// Removes entity [id]'s component of type `T`, if any. No-op if it has
  /// none.
  void remove<T extends Object>(EntityId id) {
    _components[T]?.remove(id);
  }

  /// Every entity that currently has a component of type `T`.
  Iterable<EntityId> entitiesWith<T extends Object>() =>
      _components[T]?.keys ?? const <EntityId>[];
}
```

- [ ] **Step 4: Export it from the barrel file**

Modify `lib/build_engine.dart`, adding the new export line:

```dart
export 'src/component/component_store.dart';
export 'src/entity/entity_id.dart';
export 'src/entity/entity_registry.dart';
export 'src/event/event_bus.dart';
```

- [ ] **Step 5: Run test to verify it passes, and analyze**

Run:
```bash
dart test test/component_store_test.dart
dart analyze
```
Expected: all tests PASS; `dart analyze` reports `No issues found!`.

- [ ] **Step 6: Commit**

```bash
git add lib/src/component/component_store.dart lib/build_engine.dart test/component_store_test.dart
git commit -m "feat: add ComponentStore"
```

---

### Task 6: GamePlugin interface and plugin exceptions

**Files:**
- Create: `lib/src/plugin/game_plugin.dart`
- Create: `lib/src/plugin/plugin_exceptions.dart`
- Test: `test/plugin_exceptions_test.dart`
- Modify: `lib/build_engine.dart`

**Interfaces:**
- Consumes: `PluginContext` (Task 7 — see note below on ordering).
- Produces: `abstract class GamePlugin { String get id; String get version; List<String> get dependencies; void register(PluginContext); void initialize(PluginContext); void start(PluginContext); void stop(PluginContext); void unregister(PluginContext); }`; `abstract class PluginSystemException implements Exception`, `class DuplicatePluginException`, `class MissingPluginDependencyException`, `class CyclicPluginDependencyException`. `PluginManager` (Task 8) uses all of these.

**Note on ordering:** `GamePlugin`'s lifecycle methods take a `PluginContext`, but `PluginContext` (Task 7) is defined after this task. Dart resolves this fine as a forward reference within the same package (no circular *package* dependency — `game_plugin.dart` will `import 'plugin_context.dart'`, and `plugin_context.dart` does not import `game_plugin.dart`), but you create `plugin_context.dart` in Task 7. To keep this task compiling on its own, write `game_plugin.dart`'s import for `plugin_context.dart` now; the file it points to is created in Task 7, and this task's own test (`plugin_exceptions_test.dart`) only exercises the exception classes, not `GamePlugin` itself, so it does not require `PluginContext` to exist yet. `dart analyze` in this task's Step 4 will report `game_plugin.dart` as unable to find `plugin_context.dart` — that's expected and resolved by Task 7; do not run `dart analyze` against `game_plugin.dart` as a blocking check in this task, only against the exceptions file and the test.

- [ ] **Step 1: Write the failing test (exceptions only)**

Create `test/plugin_exceptions_test.dart`:

```dart
import 'package:build_engine/build_engine.dart';
import 'package:test/test.dart';

void main() {
  group('plugin exceptions', () {
    test('DuplicatePluginException message names the plugin', () {
      final exception = DuplicatePluginException('combat');
      expect(exception, isA<PluginSystemException>());
      expect(exception.toString(), contains('combat'));
    });

    test('MissingPluginDependencyException names both plugins', () {
      final exception =
          MissingPluginDependencyException('combat', 'container');
      expect(exception.toString(), contains('combat'));
      expect(exception.toString(), contains('container'));
    });

    test('CyclicPluginDependencyException names every plugin in the cycle',
        () {
      final exception =
          CyclicPluginDependencyException(['a', 'b', 'a']);
      expect(exception.toString(), contains('a'));
      expect(exception.toString(), contains('b'));
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `dart test test/plugin_exceptions_test.dart`
Expected: FAIL — `Error: Undefined class 'DuplicatePluginException'`.

- [ ] **Step 3: Implement the exceptions**

Create `lib/src/plugin/plugin_exceptions.dart`:

```dart
/// Base type for every exception thrown by the plugin system.
abstract class PluginSystemException implements Exception {
  const PluginSystemException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Thrown by [PluginManager.register] when a plugin with the same [id] is
/// already registered.
class DuplicatePluginException extends PluginSystemException {
  DuplicatePluginException(String pluginId)
      : super('Plugin already registered: $pluginId');
}

/// Thrown by [PluginManager.resolveLoadOrder] when a plugin declares a
/// dependency on a plugin id that was never registered.
class MissingPluginDependencyException extends PluginSystemException {
  MissingPluginDependencyException(String pluginId, String missingDependencyId)
      : super(
          'Plugin "$pluginId" depends on unknown plugin '
          '"$missingDependencyId"',
        );
}

/// Thrown by [PluginManager.resolveLoadOrder] when plugin dependencies form
/// a cycle. [cycle] lists the plugin ids in the cycle, in order, with the
/// first id repeated at the end to show where it closes.
class CyclicPluginDependencyException extends PluginSystemException {
  CyclicPluginDependencyException(List<String> cycle)
      : super('Cyclic plugin dependency detected: ${cycle.join(' -> ')}');
}
```

- [ ] **Step 4: Implement the `GamePlugin` interface**

Create `lib/src/plugin/game_plugin.dart`:

```dart
import 'plugin_context.dart';

/// The contract every plugin implements. Core services never depend on any
/// concrete `GamePlugin` — this is the only shape core code knows about.
///
/// [dependencies] and every lifecycle method default to a no-op / empty list
/// so a plugin only needs to override what it actually uses. [id] and
/// [version] have no sensible default and must be overridden.
abstract class GamePlugin {
  /// A stable, globally-unique identifier for this plugin, e.g. `"combat"`.
  String get id;

  /// This plugin's own version string, e.g. `"1.0.0"`.
  String get version;

  /// The ids of plugins that must be registered, initialized, and started
  /// before this one. See `PluginManager.resolveLoadOrder`.
  List<String> get dependencies => const [];

  /// Called first, in dependency order, for every registered plugin before
  /// any plugin's [initialize] runs.
  void register(PluginContext context) {}

  /// Called after every plugin has [register]ed, in dependency order.
  void initialize(PluginContext context) {}

  /// Called after every plugin has [initialize]d, in dependency order.
  void start(PluginContext context) {}

  /// Called in reverse dependency order when the plugin set is torn down.
  void stop(PluginContext context) {}

  /// Called in reverse dependency order, after every plugin has [stop]ped.
  void unregister(PluginContext context) {}
}
```

- [ ] **Step 5: Export the exceptions from the barrel file**

Modify `lib/build_engine.dart` — add only the exceptions export for now (the plugin export is added once `plugin_context.dart` exists in Task 7, otherwise the barrel file itself fails to resolve):

```dart
export 'src/component/component_store.dart';
export 'src/entity/entity_id.dart';
export 'src/entity/entity_registry.dart';
export 'src/event/event_bus.dart';
export 'src/plugin/plugin_exceptions.dart';
```

- [ ] **Step 6: Run the exceptions test to verify it passes**

Run: `dart test test/plugin_exceptions_test.dart`
Expected: all tests PASS. (Do not run `dart analyze` across the whole package yet — `game_plugin.dart` importing the not-yet-created `plugin_context.dart` will report an error until Task 7. Running `dart analyze lib/src/plugin/plugin_exceptions.dart test/plugin_exceptions_test.dart` instead should show `No issues found!`.)

- [ ] **Step 7: Commit**

```bash
git add lib/src/plugin/game_plugin.dart lib/src/plugin/plugin_exceptions.dart lib/build_engine.dart test/plugin_exceptions_test.dart
git commit -m "feat: add GamePlugin interface and plugin exceptions"
```

---

### Task 7: PluginContext

**Files:**
- Create: `lib/src/plugin/plugin_context.dart`
- Modify: `lib/build_engine.dart`

**Interfaces:**
- Consumes: `EntityRegistry` (Task 4), `ComponentStore` (Task 5), `EventBus` (Task 3).
- Produces: `class PluginContext` with `const PluginContext({required EntityRegistry entities, required ComponentStore components, required EventBus events})` and public final fields `entities`, `components`, `events`. `PluginManager` (Task 8) and every `GamePlugin` lifecycle method (Task 6) take a `PluginContext`.

This task has no new tests of its own — `PluginContext` is a plain data holder with no logic to unit-test in isolation; it's exercised by Task 8's `plugin_manager_test.dart` and Task 9's integration test.

- [ ] **Step 1: Implement `PluginContext`**

Create `lib/src/plugin/plugin_context.dart`:

```dart
import '../component/component_store.dart';
import '../entity/entity_registry.dart';
import '../event/event_bus.dart';

/// The controlled access every plugin lifecycle method receives. Exposes
/// only the core services that exist so far — no placeholder getters for
/// services (rules, effects, modifiers, ...) that aren't built yet.
class PluginContext {
  const PluginContext({
    required this.entities,
    required this.components,
    required this.events,
  });

  final EntityRegistry entities;
  final ComponentStore components;
  final EventBus events;
}
```

- [ ] **Step 2: Export it from the barrel file**

Modify `lib/build_engine.dart`, adding both remaining plugin exports now that `plugin_context.dart` exists:

```dart
export 'src/component/component_store.dart';
export 'src/entity/entity_id.dart';
export 'src/entity/entity_registry.dart';
export 'src/event/event_bus.dart';
export 'src/plugin/game_plugin.dart';
export 'src/plugin/plugin_context.dart';
export 'src/plugin/plugin_exceptions.dart';
```

- [ ] **Step 3: Run the full test suite and analyze**

Run:
```bash
dart test
dart analyze
```
Expected: every test from Tasks 1–7 PASSes; `dart analyze` reports `No issues found!` (this is the first point `game_plugin.dart`'s import of `plugin_context.dart` resolves, so this step also confirms Task 6's deferred analyze check now passes).

- [ ] **Step 4: Commit**

```bash
git add lib/src/plugin/plugin_context.dart lib/build_engine.dart
git commit -m "feat: add PluginContext"
```

---

### Task 8: PluginManager

**Files:**
- Create: `lib/src/plugin/plugin_manager.dart`
- Test: `test/plugin_manager_test.dart`
- Modify: `lib/build_engine.dart`

**Interfaces:**
- Consumes: `GamePlugin` (Task 6), `PluginContext` (Task 7), `DuplicatePluginException`/`MissingPluginDependencyException`/`CyclicPluginDependencyException` (Task 6).
- Produces: `class PluginManager` with `void register(GamePlugin plugin)`, `List<String> resolveLoadOrder()`, `void initialize(PluginContext context)`, `void start(PluginContext context)`, `void stop(PluginContext context)`, `void unregister(PluginContext context)`. Task 9's integration test uses all of these.

- [ ] **Step 1: Write the failing test**

Create `test/plugin_manager_test.dart`:

```dart
import 'package:build_engine/build_engine.dart';
import 'package:test/test.dart';

class _RecordingPlugin extends GamePlugin {
  _RecordingPlugin(
    this.id,
    this._log, {
    this.dependencies = const <String>[],
  });

  @override
  final String id;

  @override
  String get version => '1.0.0';

  @override
  final List<String> dependencies;

  final List<String> _log;

  @override
  void register(PluginContext context) => _log.add('$id.register');

  @override
  void initialize(PluginContext context) => _log.add('$id.initialize');

  @override
  void start(PluginContext context) => _log.add('$id.start');

  @override
  void stop(PluginContext context) => _log.add('$id.stop');

  @override
  void unregister(PluginContext context) => _log.add('$id.unregister');
}

PluginContext _newContext() {
  final events = EventBus();
  return PluginContext(
    entities: EntityRegistry(events),
    components: ComponentStore(),
    events: events,
  );
}

void main() {
  group('PluginManager registration', () {
    test('two plugins with distinct ids both register', () {
      final manager = PluginManager();
      final log = <String>[];

      manager.register(_RecordingPlugin('a', log));
      manager.register(_RecordingPlugin('b', log));

      expect(manager.resolveLoadOrder().toSet(), equals({'a', 'b'}));
    });

    test('registering a duplicate id throws DuplicatePluginException', () {
      final manager = PluginManager();
      final log = <String>[];
      manager.register(_RecordingPlugin('a', log));

      expect(
        () => manager.register(_RecordingPlugin('a', log)),
        throwsA(isA<DuplicatePluginException>()),
      );
    });
  });

  group('PluginManager.resolveLoadOrder', () {
    test('a plugin with no dependencies resolves trivially', () {
      final manager = PluginManager();
      manager.register(_RecordingPlugin('a', <String>[]));

      expect(manager.resolveLoadOrder(), equals(['a']));
    });

    test('dependencies are ordered before their dependents', () {
      final manager = PluginManager();
      final log = <String>[];
      manager.register(_RecordingPlugin('a', log));
      manager.register(_RecordingPlugin('b', log, dependencies: ['a']));
      manager.register(_RecordingPlugin('c', log, dependencies: ['b']));

      final order = manager.resolveLoadOrder();

      expect(order.indexOf('a'), lessThan(order.indexOf('b')));
      expect(order.indexOf('b'), lessThan(order.indexOf('c')));
    });

    test('a dependency on an unregistered plugin throws '
        'MissingPluginDependencyException', () {
      final manager = PluginManager();
      manager.register(
        _RecordingPlugin('a', <String>[], dependencies: ['ghost']),
      );

      expect(
        () => manager.resolveLoadOrder(),
        throwsA(isA<MissingPluginDependencyException>()),
      );
    });

    test('a two-plugin cycle throws CyclicPluginDependencyException', () {
      final manager = PluginManager();
      manager.register(
        _RecordingPlugin('a', <String>[], dependencies: ['b']),
      );
      manager.register(
        _RecordingPlugin('b', <String>[], dependencies: ['a']),
      );

      expect(
        () => manager.resolveLoadOrder(),
        throwsA(isA<CyclicPluginDependencyException>()),
      );
    });
  });

  group('PluginManager lifecycle ordering', () {
    test('initialize registers every plugin before initializing any',
        () {
      final manager = PluginManager();
      final log = <String>[];
      manager.register(_RecordingPlugin('a', log));
      manager.register(_RecordingPlugin('b', log, dependencies: ['a']));

      manager.initialize(_newContext());

      expect(
        log,
        equals(['a.register', 'b.register', 'a.initialize', 'b.initialize']),
      );
    });

    test('start runs in dependency order after initialize', () {
      final manager = PluginManager();
      final log = <String>[];
      manager.register(_RecordingPlugin('a', log));
      manager.register(_RecordingPlugin('b', log, dependencies: ['a']));
      final context = _newContext();

      manager.initialize(context);
      log.clear();
      manager.start(context);

      expect(log, equals(['a.start', 'b.start']));
    });

    test('stop runs in reverse dependency order', () {
      final manager = PluginManager();
      final log = <String>[];
      manager.register(_RecordingPlugin('a', log));
      manager.register(_RecordingPlugin('b', log, dependencies: ['a']));
      final context = _newContext();
      manager.initialize(context);
      manager.start(context);
      log.clear();

      manager.stop(context);

      expect(log, equals(['b.stop', 'a.stop']));
    });

    test('unregister runs in reverse dependency order after stop', () {
      final manager = PluginManager();
      final log = <String>[];
      manager.register(_RecordingPlugin('a', log));
      manager.register(_RecordingPlugin('b', log, dependencies: ['a']));
      final context = _newContext();
      manager.initialize(context);
      manager.start(context);
      manager.stop(context);
      log.clear();

      manager.unregister(context);

      expect(log, equals(['b.unregister', 'a.unregister']));
    });

    test('initialize, start, stop, and unregister all succeed with zero '
        'plugins registered', () {
      final manager = PluginManager();
      final context = _newContext();

      expect(() => manager.initialize(context), returnsNormally);
      expect(() => manager.start(context), returnsNormally);
      expect(() => manager.stop(context), returnsNormally);
      expect(() => manager.unregister(context), returnsNormally);
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `dart test test/plugin_manager_test.dart`
Expected: FAIL — `Error: Undefined class 'PluginManager'`.

- [ ] **Step 3: Implement `PluginManager`**

Create `lib/src/plugin/plugin_manager.dart`:

```dart
import 'game_plugin.dart';
import 'plugin_context.dart';
import 'plugin_exceptions.dart';

/// Registers [GamePlugin]s, resolves their dependency order, and drives
/// their lifecycle (register → initialize → start, then stop → unregister
/// in reverse) in that resolved order.
class PluginManager {
  final Map<String, GamePlugin> _plugins = {};
  List<String>? _loadOrder;

  /// Adds [plugin] to the registry. Does not call any lifecycle method.
  ///
  /// Throws [DuplicatePluginException] if a plugin with the same [GamePlugin.id]
  /// is already registered.
  void register(GamePlugin plugin) {
    if (_plugins.containsKey(plugin.id)) {
      throw DuplicatePluginException(plugin.id);
    }
    _plugins[plugin.id] = plugin;
    _loadOrder = null;
  }

  /// Returns every registered plugin's id, topologically sorted so each
  /// plugin's dependencies precede it. Deterministic for a fixed
  /// registration order. The result is cached until the next [register].
  ///
  /// Throws [MissingPluginDependencyException] if a plugin depends on an id
  /// that was never registered, or [CyclicPluginDependencyException] if
  /// dependencies form a cycle.
  List<String> resolveLoadOrder() {
    final cachedOrder = _loadOrder;
    if (cachedOrder != null) return cachedOrder;

    final visited = <String>{};
    final visiting = <String>{};
    final order = <String>[];

    void visit(String pluginId, List<String> path) {
      if (visited.contains(pluginId)) return;
      if (visiting.contains(pluginId)) {
        throw CyclicPluginDependencyException([...path, pluginId]);
      }
      final plugin = _plugins[pluginId];
      if (plugin == null) {
        throw MissingPluginDependencyException(path.last, pluginId);
      }
      visiting.add(pluginId);
      for (final dependencyId in plugin.dependencies) {
        visit(dependencyId, [...path, pluginId]);
      }
      visiting.remove(pluginId);
      visited.add(pluginId);
      order.add(pluginId);
    }

    for (final pluginId in _plugins.keys) {
      visit(pluginId, const []);
    }

    _loadOrder = order;
    return order;
  }

  /// Calls [GamePlugin.register] on every plugin in dependency order, then
  /// [GamePlugin.initialize] on every plugin in dependency order.
  void initialize(PluginContext context) {
    final order = resolveLoadOrder();
    for (final pluginId in order) {
      _plugins[pluginId]!.register(context);
    }
    for (final pluginId in order) {
      _plugins[pluginId]!.initialize(context);
    }
  }

  /// Calls [GamePlugin.start] on every plugin in dependency order.
  void start(PluginContext context) {
    for (final pluginId in resolveLoadOrder()) {
      _plugins[pluginId]!.start(context);
    }
  }

  /// Calls [GamePlugin.stop] on every plugin in reverse dependency order.
  void stop(PluginContext context) {
    for (final pluginId in resolveLoadOrder().reversed) {
      _plugins[pluginId]!.stop(context);
    }
  }

  /// Calls [GamePlugin.unregister] on every plugin in reverse dependency
  /// order, then clears the registry.
  void unregister(PluginContext context) {
    for (final pluginId in resolveLoadOrder().reversed) {
      _plugins[pluginId]!.unregister(context);
    }
    _plugins.clear();
    _loadOrder = null;
  }
}
```

- [ ] **Step 4: Export it from the barrel file**

Modify `lib/build_engine.dart`, adding the new export line:

```dart
export 'src/component/component_store.dart';
export 'src/entity/entity_id.dart';
export 'src/entity/entity_registry.dart';
export 'src/event/event_bus.dart';
export 'src/plugin/game_plugin.dart';
export 'src/plugin/plugin_context.dart';
export 'src/plugin/plugin_exceptions.dart';
export 'src/plugin/plugin_manager.dart';
```

- [ ] **Step 5: Run test to verify it passes, and analyze**

Run:
```bash
dart test test/plugin_manager_test.dart
dart analyze
```
Expected: all tests PASS; `dart analyze` reports `No issues found!`.

- [ ] **Step 6: Commit**

```bash
git add lib/src/plugin/plugin_manager.dart lib/build_engine.dart test/plugin_manager_test.dart
git commit -m "feat: add PluginManager with dependency resolution"
```

---

### Task 9: Integration test — core boots with and without plugins

**Files:**
- Create: `test/integration/core_boots_without_plugins_test.dart`

**Interfaces:**
- Consumes: everything from Tasks 2–8 (`EntityId`, `EntityRegistry`, `ComponentStore`, `EventBus`, `GamePlugin`, `PluginContext`, `PluginManager`).
- Produces: nothing new — this is a verification-only task covering two items from `CLAUDE.md`'s testing list that are in scope this pass: "Core can run without content plugins" and "Plugins can be loaded/unloaded".

- [ ] **Step 1: Write the integration test**

Create `test/integration/core_boots_without_plugins_test.dart`:

```dart
import 'package:build_engine/build_engine.dart';
import 'package:test/test.dart';

class _MarkerComponent {
  const _MarkerComponent(this.label);
  final String label;
}

class _EntityCreatingPlugin extends GamePlugin {
  _EntityCreatingPlugin(this.id, {this.dependencies = const <String>[]});

  @override
  final String id;

  @override
  String get version => '1.0.0';

  @override
  final List<String> dependencies;

  EntityId? createdEntity;

  @override
  void initialize(PluginContext context) {
    final entity = context.entities.create();
    context.components.add(entity, _MarkerComponent(id));
    createdEntity = entity;
  }

  @override
  void unregister(PluginContext context) {
    final entity = createdEntity;
    if (entity != null && context.entities.isAlive(entity)) {
      context.components.remove<_MarkerComponent>(entity);
      context.entities.destroy(entity);
    }
  }
}

void main() {
  group('core without any plugins', () {
    test('full lifecycle succeeds with zero plugins registered', () {
      final events = EventBus();
      final context = PluginContext(
        entities: EntityRegistry(events),
        components: ComponentStore(),
        events: events,
      );
      final manager = PluginManager();

      manager.initialize(context);
      manager.start(context);
      manager.stop(context);
      manager.unregister(context);

      expect(context.entities.all, isEmpty);
    });

    test('entity/component/event services work with no plugins involved',
        () {
      final events = EventBus();
      final registry = EntityRegistry(events);
      final components = ComponentStore();
      final createdIds = <EntityId>[];
      events.subscribe<EntityCreated>((event) => createdIds.add(event.id));

      final entity = registry.create();
      components.add(entity, const _MarkerComponent('standalone'));

      expect(createdIds, equals([entity]));
      expect(components.get<_MarkerComponent>(entity)!.label,
          equals('standalone'));
    });
  });

  group('core with dependent plugins', () {
    test('plugins load and unload in dependency order end-to-end', () {
      final events = EventBus();
      final context = PluginContext(
        entities: EntityRegistry(events),
        components: ComponentStore(),
        events: events,
      );
      final manager = PluginManager();
      final base = _EntityCreatingPlugin('base');
      final dependent =
          _EntityCreatingPlugin('dependent', dependencies: ['base']);
      manager.register(dependent);
      manager.register(base);

      manager.initialize(context);
      manager.start(context);

      expect(base.createdEntity, isNotNull);
      expect(dependent.createdEntity, isNotNull);
      expect(context.entities.isAlive(base.createdEntity!), isTrue);
      expect(context.entities.isAlive(dependent.createdEntity!), isTrue);
      expect(context.components.get<_MarkerComponent>(base.createdEntity!)!.label,
          equals('base'));

      manager.stop(context);
      manager.unregister(context);

      expect(context.entities.isAlive(base.createdEntity!), isFalse);
      expect(context.entities.isAlive(dependent.createdEntity!), isFalse);
      expect(context.entities.all, isEmpty);
    });
  });
}
```

- [ ] **Step 2: Run it and confirm it passes on the first try**

Run: `dart test test/integration/core_boots_without_plugins_test.dart`
Expected: all tests PASS. (No implementation step needed here — every service under test was already implemented in Tasks 2–8. If anything fails, that's a bug in an earlier task; stop and fix the earlier task's implementation, don't patch around it here.)

- [ ] **Step 3: Run the whole suite and analyze**

Run:
```bash
dart test
dart analyze
```
Expected: every test across the whole package PASSes; `dart analyze` reports `No issues found!`.

- [ ] **Step 4: Commit**

```bash
git add test/integration/core_boots_without_plugins_test.dart
git commit -m "test: add core/plugin-system integration coverage"
```

---

### Task 10: Architecture documentation

**Files:**
- Create: `ARCHITECTURE.md`
- Create: `PLUGIN_SYSTEM.md`

**Interfaces:**
- Consumes: the finished implementation from Tasks 1–9 (this task only documents it).
- Produces: nothing new in `lib/` — this is the plan's final task.

- [ ] **Step 1: Write `ARCHITECTURE.md`**

Create `ARCHITECTURE.md`:

```markdown
# Build Engine — Architecture

This document describes the engine foundation implemented so far. See
`CLAUDE.md` for the full architecture contract this engine follows, and
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
calls. No service in this pass uses `dart:math`'s `Random()` or any other
non-deterministic source — there is no RNG service yet; one will be added,
injectable rather than global, when gameplay systems that need randomness
are built.

## What's deliberately not here yet

Rule Engine, Effect Engine, Modifier Engine, Query Engine, Spatial/Container
Engine, Resource Engine, Scheduler, RNG Service, Asset/Data Registry,
Serialization. Each is a separate future subsystem, to be brainstormed and
planned on its own rather than stubbed out speculatively here.
```

- [ ] **Step 2: Write `PLUGIN_SYSTEM.md`**

Create `PLUGIN_SYSTEM.md`:

```markdown
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
  exception lists every plugin id in the cycle, in order.

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
```

- [ ] **Step 3: Final full verification**

Run:
```bash
dart pub get
dart test
dart analyze
```
Expected: `dart pub get` succeeds; every test in the package PASSes; `dart analyze` reports `No issues found!`.

- [ ] **Step 4: Commit**

```bash
git add ARCHITECTURE.md PLUGIN_SYSTEM.md
git commit -m "docs: add ARCHITECTURE.md and PLUGIN_SYSTEM.md"
```

---

## Self-Review Notes

- **Spec coverage:** every component in the spec (EntityId, EntityRegistry,
  ComponentStore, EventBus, GamePlugin, PluginContext, PluginManager,
  exceptions, both docs, git init, tooling) maps to a task above. The two
  testing items the spec marked in-scope ("core runs without content
  plugins", "plugins can load/unload") are both covered in Task 9.
- **Type consistency checked:** `EntityId`, `EntityRegistry`,
  `ComponentStore`, `EventBus`/`EventSubscription`, `GamePlugin`,
  `PluginContext`, `PluginManager`, and the three plugin exceptions use the
  same method names, parameter types, and return types everywhere they
  appear across Tasks 2–9.
- **Known ordering wrinkle (Task 6):** `GamePlugin` references
  `PluginContext` before `PluginContext` is defined (Task 7). This is
  called out explicitly in Task 6 with an exact explanation of why it's
  safe and what to expect from `dart analyze` at that point, rather than
  silently glossing over it.
