# Query / Condition / Rule / Effect Engine Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add the Query Engine, Condition system, Rule Engine, and Effect Engine to `build_engine`, plus the minimal supporting data (tags/health/resources/stats/status components, an injectable RNG, an event counter) they need to be meaningful — all generic, none of it game-specific.

**Architecture:** Five new immutable component types stored via the existing `ComponentStore`; a `Query`/`QueryScope`/`QueryEngine` layer for composable single-entity predicates and bulk entity search; a `Condition` interface (six entity-scoped conditions wrapping `Query`, two standalone: `EventCount`, `RandomChance`); an `Effect` interface (eleven concrete effects); a `Rule`/`RuleEngine` that dispatches on a runtime `Type` via one new additive `EventBus.subscribeDynamic` method, builds a `RuleContext`, and runs conditions (AND) then effects (in order) deterministically.

**Tech Stack:** Dart (SDK `^3.7.0`), `package:test`, `dart:math`'s `Random` (only inside `RngService`).

**Spec:** `docs/superpowers/specs/2026-08-21-query-rule-effect-engine-design.md`

All paths below are relative to the repo root: `/Users/m4maxpro/Projects/Tome:RougelikeGame`.

## Global Constraints

- No martial-arts, magic, combat, cultivation, or other game-specific vocabulary anywhere in this package.
- No Modifier Engine, Spatial/Container Engine, dedicated Resource Engine service, Scheduler, Asset/Data Registry, Serialization, or any registry/factory/data-driven rule deserialization mechanism — out of scope this pass.
- `dart:math`'s `Random` may appear **only** inside `lib/src/rng/rng_service.dart` — nowhere else in this package.
- Every new component type (`TagSet`, `HealthComponent`, `ResourceComponent`, `StatComponent`, `StatusComponent`) is immutable: `final` fields, internal collections wrapped in `Set.unmodifiable`/`Map.unmodifiable`.
- `ResourceAboveQuery`/condition: strictly greater than (`>`). `ResourceBelowQuery`/condition and `HealthBelowQuery`/condition: strictly less than (`<`).
- A missing `ResourceComponent`, or a missing entry in its `resources` map, is treated as `0` for `ResourceAbove`/`ResourceBelow`. A missing `HealthComponent` makes `HealthBelow` **not** match (asymmetric with Resource's zero-default — intentional, documented at the point of implementation).
- Every entity-scoped `Condition`/subject-scoped `Effect` no-ops (`Condition` returns `false`; `Effect` returns without acting) when `RuleContext.subject` is `null`.
- Every task ends with `dart analyze` zero issues and `dart test` passing, before commit.

---

### Task 1: Supporting components

**Files:**
- Create: `lib/src/components/tag_set.dart`
- Create: `lib/src/components/health_component.dart`
- Create: `lib/src/components/resource_component.dart`
- Create: `lib/src/components/stat_component.dart`
- Create: `lib/src/components/status_component.dart`
- Test: `test/components/tag_set_test.dart`
- Test: `test/components/health_component_test.dart`
- Test: `test/components/resource_component_test.dart`
- Test: `test/components/stat_component_test.dart`
- Test: `test/components/status_component_test.dart`
- Modify: `lib/build_engine.dart`

**Interfaces:**
- Consumes: nothing new (plain data classes).
- Produces: `TagSet(Set<String> tags)` → `.tags` (`Set<String>`, unmodifiable); `HealthComponent({required num current, required num max})` → `.current`, `.max`; `ResourceComponent(Map<String, num> resources)` → `.resources` (unmodifiable); `StatComponent(Map<String, num> stats)` → `.stats` (unmodifiable); `StatusComponent(Set<String> activeStatuses)` → `.activeStatuses` (unmodifiable). Every later task in this plan stores/reads these via `ComponentStore`.

- [ ] **Step 1: Write the failing tests**

Create `test/components/tag_set_test.dart`:
```dart
import 'package:build_engine/build_engine.dart';
import 'package:test/test.dart';

void main() {
  group('TagSet', () {
    test('stores the given tags', () {
      final tagSet = TagSet({'fire', 'dragon'});
      expect(tagSet.tags, equals({'fire', 'dragon'}));
    });

    test('tags set is unmodifiable', () {
      final tagSet = TagSet({'fire'});
      expect(() => tagSet.tags.add('ice'), throwsUnsupportedError);
    });
  });
}
```

Create `test/components/health_component_test.dart`:
```dart
import 'package:build_engine/build_engine.dart';
import 'package:test/test.dart';

void main() {
  group('HealthComponent', () {
    test('stores current and max', () {
      const health = HealthComponent(current: 80, max: 100);
      expect(health.current, equals(80));
      expect(health.max, equals(100));
    });
  });
}
```

Create `test/components/resource_component_test.dart`:
```dart
import 'package:build_engine/build_engine.dart';
import 'package:test/test.dart';

void main() {
  group('ResourceComponent', () {
    test('stores named resources', () {
      final resources = ResourceComponent({'stamina': 50});
      expect(resources.resources['stamina'], equals(50));
    });

    test('resources map is unmodifiable', () {
      final resources = ResourceComponent({'stamina': 50});
      expect(() => resources.resources['stamina'] = 10, throwsUnsupportedError);
    });
  });
}
```

Create `test/components/stat_component_test.dart`:
```dart
import 'package:build_engine/build_engine.dart';
import 'package:test/test.dart';

void main() {
  group('StatComponent', () {
    test('stores named stats', () {
      final stats = StatComponent({'strength': 12});
      expect(stats.stats['strength'], equals(12));
    });

    test('stats map is unmodifiable', () {
      final stats = StatComponent({'strength': 12});
      expect(() => stats.stats['strength'] = 1, throwsUnsupportedError);
    });
  });
}
```

Create `test/components/status_component_test.dart`:
```dart
import 'package:build_engine/build_engine.dart';
import 'package:test/test.dart';

void main() {
  group('StatusComponent', () {
    test('stores active statuses', () {
      final status = StatusComponent({'burning'});
      expect(status.activeStatuses, equals({'burning'}));
    });

    test('activeStatuses set is unmodifiable', () {
      final status = StatusComponent({'burning'});
      expect(() => status.activeStatuses.add('frozen'), throwsUnsupportedError);
    });
  });
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `dart test test/components/`
Expected: FAIL — `Error: Undefined class 'TagSet'` (and similarly for each of the other four).

- [ ] **Step 3: Implement the five components**

Create `lib/src/components/tag_set.dart`:
```dart
/// An entity's tags — a generic, engine-agnostic label set. The engine
/// never interprets tag values; it only stores and matches them.
class TagSet {
  TagSet(Set<String> tags) : tags = Set.unmodifiable(tags);

  final Set<String> tags;
}
```

Create `lib/src/components/health_component.dart`:
```dart
/// An entity's health pool. Effects that mutate [current] ([Damage],
/// [Heal]) keep it within `[0, max]` — this component itself stores
/// whatever values it's given without enforcing that.
class HealthComponent {
  const HealthComponent({required this.current, required this.max});

  final num current;
  final num max;
}
```

Create `lib/src/components/resource_component.dart`:
```dart
/// An entity's named numeric resource pools (e.g. a content plugin's own
/// "stamina" or "focus"). The engine never hardcodes a resource name.
class ResourceComponent {
  ResourceComponent(Map<String, num> resources)
      : resources = Map.unmodifiable(resources);

  final Map<String, num> resources;
}
```

Create `lib/src/components/stat_component.dart`:
```dart
/// An entity's named numeric stats/attributes, stored as raw values.
///
/// This is a stopgap: `claude.md`'s Modifier System says derived stats
/// should be `base + modifiers`, computed by a future Modifier Engine.
/// Until that exists, [ModifyStat] mutates the raw value stored here
/// directly. Expect this component's role to change once Modifier Engine
/// lands.
class StatComponent {
  StatComponent(Map<String, num> stats) : stats = Map.unmodifiable(stats);

  final Map<String, num> stats;
}
```

Create `lib/src/components/status_component.dart`:
```dart
/// An entity's currently-active status-effect names. No duration or
/// stacking is modeled here — that belongs to a future Scheduler/Modifier
/// pass; this is a plain set of "is this status currently active" flags.
class StatusComponent {
  StatusComponent(Set<String> activeStatuses)
      : activeStatuses = Set.unmodifiable(activeStatuses);

  final Set<String> activeStatuses;
}
```

- [ ] **Step 4: Export all five from the barrel file**

Modify `lib/build_engine.dart` — insert the five new export lines alphabetically after `src/component/component_store.dart` and before `src/entity/entity_id.dart` (matching the file's existing alphabetical convention):
```dart
export 'src/component/component_store.dart';
export 'src/components/health_component.dart';
export 'src/components/resource_component.dart';
export 'src/components/stat_component.dart';
export 'src/components/status_component.dart';
export 'src/components/tag_set.dart';
export 'src/entity/entity_id.dart';
export 'src/entity/entity_registry.dart';
export 'src/event/event_bus.dart';
export 'src/plugin/game_plugin.dart';
export 'src/plugin/plugin_context.dart';
export 'src/plugin/plugin_exceptions.dart';
export 'src/plugin/plugin_manager.dart';
```

- [ ] **Step 5: Run tests to verify they pass, and analyze**

Run:
```bash
dart test test/components/
dart analyze
```
Expected: all 10 tests PASS; `dart analyze` reports `No issues found!`.

- [ ] **Step 6: Commit**

```bash
git add lib/src/components/ lib/build_engine.dart test/components/
git commit -m "feat: add TagSet, HealthComponent, ResourceComponent, StatComponent, StatusComponent"
```

---

### Task 2: EventBus.subscribeDynamic

**Files:**
- Modify: `lib/src/event/event_bus.dart`
- Modify: `test/event_bus_test.dart`

**Interfaces:**
- Consumes: the existing `EventBus`/`EventSubscription` internals (the `Map<Type, List<void Function(Object?)>> _handlers` field introduced by the foundation pass's Task-3 fix).
- Produces: `EventSubscription subscribeDynamic(Type type, void Function(Object event) handler)`. Task 4 (`EventCounter`) and Task 8 (`RuleEngine`) both call this.

- [ ] **Step 1: Read the current file, then write the failing tests**

Read `lib/src/event/event_bus.dart` and `test/event_bus_test.dart` first to confirm their exact current content (both already exist from the foundation pass) — this task only *adds* to them, it does not replace them.

Add these three tests to `test/event_bus_test.dart`, inside the existing `group('EventBus', ...)` block, reusing the file's existing `_Ping`/`_Pong` fixture classes:
```dart
test('subscribeDynamic dispatches by a Type known only at runtime', () {
  final bus = EventBus();
  final received = <int>[];
  bus.subscribeDynamic(_Ping, (event) => received.add((event as _Ping).n));

  bus.publish(const _Ping(7));

  expect(received, equals([7]));
});

test('subscribeDynamic subscription can be cancelled', () {
  final bus = EventBus();
  final received = <int>[];
  final subscription =
      bus.subscribeDynamic(_Ping, (event) => received.add((event as _Ping).n));

  subscription.cancel();
  bus.publish(const _Ping(1));

  expect(received, isEmpty);
});

test('subscribeDynamic does not receive events of a different type', () {
  final bus = EventBus();
  final pings = <int>[];
  bus.subscribeDynamic(_Ping, (event) => pings.add((event as _Ping).n));

  bus.publish(const _Pong(1));

  expect(pings, isEmpty);
});
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `dart test test/event_bus_test.dart`
Expected: FAIL — `Error: The method 'subscribeDynamic' isn't defined for the class 'EventBus'`.

- [ ] **Step 3: Add `subscribeDynamic`**

Modify `lib/src/event/event_bus.dart` — add this method to the `EventBus` class (alongside the existing `subscribe`/`publish`; do not change either of those):
```dart
  /// Like [subscribe], but for callers that only know the event type at
  /// runtime (e.g. a rule engine dispatching on a [Type] value read from
  /// data rather than known at compile time). [handler] receives the
  /// event as `Object`.
  EventSubscription subscribeDynamic(
    Type type,
    void Function(Object event) handler,
  ) {
    final handlers = _handlers.putIfAbsent(type, () => <void Function(Object?)>[]);
    void wrapped(Object? event) => handler(event!);
    handlers.add(wrapped);
    return EventSubscription._(() => handlers.remove(wrapped));
  }
```

- [ ] **Step 4: Run tests to verify they pass, and analyze**

Run:
```bash
dart test test/event_bus_test.dart
dart analyze
```
Expected: all tests PASS (the 3 new ones plus every existing `EventBus` test unchanged and still green); `dart analyze` reports `No issues found!`.

- [ ] **Step 5: Commit**

```bash
git add lib/src/event/event_bus.dart test/event_bus_test.dart
git commit -m "feat: add EventBus.subscribeDynamic for runtime-Type dispatch"
```

---

### Task 3: RngService

**Files:**
- Create: `lib/src/rng/rng_service.dart`
- Test: `test/rng/rng_service_test.dart`
- Modify: `lib/build_engine.dart`

**Interfaces:**
- Consumes: `dart:math`'s `Random` (the only file in this package permitted to import it).
- Produces: `RngService(int seed)` with `double nextDouble()`, `int nextInt(int max)`, `bool chance(double probability)`. Task 6 (`RandomChance` condition) and Task 8 (`RuleEngine`/`RuleContext`) consume this.

- [ ] **Step 1: Write the failing tests**

Create `test/rng/rng_service_test.dart`:
```dart
import 'package:build_engine/build_engine.dart';
import 'package:test/test.dart';

void main() {
  group('RngService', () {
    test('the same seed produces the same sequence of doubles', () {
      final a = RngService(42);
      final b = RngService(42);

      final valuesA = List.generate(5, (_) => a.nextDouble());
      final valuesB = List.generate(5, (_) => b.nextDouble());

      expect(valuesA, equals(valuesB));
    });

    test('different seeds produce different first values', () {
      final a = RngService(1);
      final b = RngService(2);

      expect(a.nextDouble(), isNot(equals(b.nextDouble())));
    });

    test('nextInt stays within [0, max)', () {
      final rng = RngService(1);

      for (var i = 0; i < 100; i++) {
        final value = rng.nextInt(10);
        expect(value, greaterThanOrEqualTo(0));
        expect(value, lessThan(10));
      }
    });

    test('chance(0.0) is always false', () {
      final rng = RngService(1);

      for (var i = 0; i < 20; i++) {
        expect(rng.chance(0.0), isFalse);
      }
    });

    test('chance(1.0) is always true', () {
      final rng = RngService(1);

      for (var i = 0; i < 20; i++) {
        expect(rng.chance(1.0), isTrue);
      }
    });
  });
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `dart test test/rng/rng_service_test.dart`
Expected: FAIL — `Error: Undefined class 'RngService'`.

- [ ] **Step 3: Implement `RngService`**

Create `lib/src/rng/rng_service.dart`:
```dart
import 'dart:math';

/// The sole sanctioned source of randomness in this package. Gameplay
/// systems (conditions, effects, rules) must never call `dart:math`'s
/// `Random` directly — everything goes through an injected [RngService]
/// instance, so a run is reproducible from its seed.
class RngService {
  RngService(int seed) : _random = Random(seed);

  final Random _random;

  /// A pseudo-random double in `[0.0, 1.0)`.
  double nextDouble() => _random.nextDouble();

  /// A pseudo-random integer in `[0, max)`.
  int nextInt(int max) => _random.nextInt(max);

  /// Whether a random draw falls within [probability] (`0.0`-`1.0`).
  /// `probability <= 0.0` never returns true; `probability >= 1.0` always
  /// does.
  bool chance(double probability) => _random.nextDouble() < probability;
}
```

- [ ] **Step 4: Export it from the barrel file**

Modify `lib/build_engine.dart`, adding the new export line alphabetically after the `plugin/` exports and before nothing else follows currently, so it becomes the new last line:
```dart
export 'src/component/component_store.dart';
export 'src/components/health_component.dart';
export 'src/components/resource_component.dart';
export 'src/components/stat_component.dart';
export 'src/components/status_component.dart';
export 'src/components/tag_set.dart';
export 'src/entity/entity_id.dart';
export 'src/entity/entity_registry.dart';
export 'src/event/event_bus.dart';
export 'src/plugin/game_plugin.dart';
export 'src/plugin/plugin_context.dart';
export 'src/plugin/plugin_exceptions.dart';
export 'src/plugin/plugin_manager.dart';
export 'src/rng/rng_service.dart';
```

- [ ] **Step 5: Run tests to verify they pass, and analyze**

Run:
```bash
dart test test/rng/rng_service_test.dart
dart analyze
```
Expected: all 5 tests PASS; `dart analyze` reports `No issues found!`.

- [ ] **Step 6: Commit**

```bash
git add lib/src/rng/rng_service.dart lib/build_engine.dart test/rng/rng_service_test.dart
git commit -m "feat: add RngService"
```

---

### Task 4: EventCounter

**Files:**
- Create: `lib/src/rule/event_counter.dart`
- Test: `test/rule/event_counter_test.dart`
- Modify: `lib/build_engine.dart`

**Interfaces:**
- Consumes: `EventBus.subscribeDynamic` (Task 2).
- Produces: `EventCounter(EventBus events)` with `void trackType(Type type)`, `int countOfType(Type type)`. Task 6's `EventCount` condition and Task 8's `RuleEngine` both consume this.

- [ ] **Step 1: Write the failing tests**

Create `test/rule/event_counter_test.dart`:
```dart
import 'package:build_engine/build_engine.dart';
import 'package:test/test.dart';

class _Ping {
  const _Ping();
}

class _Pong {
  const _Pong();
}

void main() {
  group('EventCounter', () {
    test('counts occurrences of a tracked event type', () {
      final events = EventBus();
      final counter = EventCounter(events);
      counter.trackType(_Ping);

      events.publish(const _Ping());
      events.publish(const _Ping());

      expect(counter.countOfType(_Ping), equals(2));
    });

    test('does not count a type that was never tracked', () {
      final events = EventBus();
      final counter = EventCounter(events);

      events.publish(const _Ping());

      expect(counter.countOfType(_Ping), equals(0));
    });

    test('tracking one type does not count a different type', () {
      final events = EventBus();
      final counter = EventCounter(events);
      counter.trackType(_Ping);

      events.publish(const _Pong());

      expect(counter.countOfType(_Ping), equals(0));
      expect(counter.countOfType(_Pong), equals(0));
    });

    test('counting starts from zero, not retroactively', () {
      final events = EventBus();
      final counter = EventCounter(events);

      events.publish(const _Ping());
      counter.trackType(_Ping);
      events.publish(const _Ping());

      expect(counter.countOfType(_Ping), equals(1));
    });

    test('calling trackType twice does not reset the count', () {
      final events = EventBus();
      final counter = EventCounter(events);
      counter.trackType(_Ping);
      events.publish(const _Ping());
      counter.trackType(_Ping);

      expect(counter.countOfType(_Ping), equals(1));
    });
  });
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `dart test test/rule/event_counter_test.dart`
Expected: FAIL — `Error: Undefined class 'EventCounter'`.

- [ ] **Step 3: Implement `EventCounter`**

Create `lib/src/rule/event_counter.dart`:
```dart
import '../event/event_bus.dart';

/// Tallies how many times specific event types have been published.
/// Counting for a type only begins once [trackType] is called for it —
/// there is no retroactive counting.
class EventCounter {
  EventCounter(this._events);

  final EventBus _events;
  final Map<Type, int> _counts = {};

  /// Starts counting occurrences of [type]. A no-op if already tracking
  /// [type].
  void trackType(Type type) {
    if (_counts.containsKey(type)) return;
    _counts[type] = 0;
    _events.subscribeDynamic(
      type,
      (_) => _counts[type] = (_counts[type] ?? 0) + 1,
    );
  }

  /// How many times [type] has been published since [trackType] was
  /// called for it. `0` if [type] was never tracked.
  int countOfType(Type type) => _counts[type] ?? 0;
}
```

- [ ] **Step 4: Export it from the barrel file**

Modify `lib/build_engine.dart`, adding the new export line alphabetically — `rng` sorts before `rule` (`n` < `u`), so it goes after `rng_service.dart`:
```dart
export 'src/plugin/plugin_manager.dart';
export 'src/rng/rng_service.dart';
```
becomes:
```dart
export 'src/plugin/plugin_manager.dart';
export 'src/rng/rng_service.dart';
export 'src/rule/event_counter.dart';
```

- [ ] **Step 5: Run tests to verify they pass, and analyze**

Run:
```bash
dart test test/rule/event_counter_test.dart
dart analyze
```
Expected: all 5 tests PASS; `dart analyze` reports `No issues found!`.

- [ ] **Step 6: Commit**

```bash
git add lib/src/rule/event_counter.dart lib/build_engine.dart test/rule/event_counter_test.dart
git commit -m "feat: add EventCounter"
```

---

### Task 5: Query Engine

**Files:**
- Create: `lib/src/query/query.dart`
- Create: `lib/src/query/queries.dart`
- Create: `lib/src/query/query_engine.dart`
- Test: `test/query/query_test.dart`
- Test: `test/query/query_engine_test.dart`
- Modify: `lib/build_engine.dart`

**Interfaces:**
- Consumes: `EntityId` (foundation), `ComponentStore` (foundation), `TagSet`/`HealthComponent`/`ResourceComponent`/`StatusComponent` (Task 1).
- Produces: `class QueryScope { ComponentStore components; }`; `abstract class Query { bool matches(EntityId, QueryScope); Query and(Query); Query or(Query); Query not(); }`; `AndQuery(List<Query>)`, `OrQuery(List<Query>)`, `NotQuery(Query)`; `HasComponentQuery<T extends Object>()`, `HasTagQuery(String)`, `ResourceAboveQuery(String, num)`, `ResourceBelowQuery(String, num)`, `HealthBelowQuery(num)`, `StatusActiveQuery(String)`; `class QueryEngine { const QueryEngine(QueryScope); Iterable<EntityId> evaluate(Iterable<EntityId>, Query); }`. Task 6 (Condition system) wraps every concrete query above.

- [ ] **Step 1: Write the failing tests**

Create `test/query/query_test.dart`:
```dart
import 'package:build_engine/build_engine.dart';
import 'package:test/test.dart';

class _Marker {
  const _Marker();
}

void main() {
  group('Query combinators', () {
    test('AndQuery matches only when every query matches', () {
      final components = ComponentStore();
      const id = EntityId(1);
      components.add(id, TagSet({'fire'}));
      final scope = QueryScope(components: components);

      final query = AndQuery([HasTagQuery('fire'), HasComponentQuery<TagSet>()]);

      expect(query.matches(id, scope), isTrue);
    });

    test('AndQuery fails when any query fails', () {
      final components = ComponentStore();
      const id = EntityId(1);
      components.add(id, TagSet({'fire'}));
      final scope = QueryScope(components: components);

      final query = AndQuery([HasTagQuery('fire'), HasTagQuery('ice')]);

      expect(query.matches(id, scope), isFalse);
    });

    test('OrQuery matches when any query matches', () {
      final components = ComponentStore();
      const id = EntityId(1);
      components.add(id, TagSet({'fire'}));
      final scope = QueryScope(components: components);

      final query = OrQuery([HasTagQuery('ice'), HasTagQuery('fire')]);

      expect(query.matches(id, scope), isTrue);
    });

    test('NotQuery inverts its wrapped query', () {
      final components = ComponentStore();
      const id = EntityId(1);
      final scope = QueryScope(components: components);

      final query = NotQuery(HasTagQuery('fire'));

      expect(query.matches(id, scope), isTrue);
    });

    test('Query.and/.or/.not fluent methods build the same combinators', () {
      final components = ComponentStore();
      const id = EntityId(1);
      components.add(id, TagSet({'fire', 'dragon'}));
      final scope = QueryScope(components: components);

      expect(
        HasTagQuery('fire').and(HasTagQuery('dragon')).matches(id, scope),
        isTrue,
      );
      expect(
        HasTagQuery('ice').or(HasTagQuery('fire')).matches(id, scope),
        isTrue,
      );
      expect(HasTagQuery('ice').not().matches(id, scope), isTrue);
    });
  });

  group('HasComponentQuery', () {
    test('matches when the entity has the component', () {
      final components = ComponentStore();
      const id = EntityId(1);
      components.add(id, const _Marker());
      final scope = QueryScope(components: components);

      expect(const HasComponentQuery<_Marker>().matches(id, scope), isTrue);
    });

    test('does not match when the entity lacks the component', () {
      final components = ComponentStore();
      const id = EntityId(1);
      final scope = QueryScope(components: components);

      expect(const HasComponentQuery<_Marker>().matches(id, scope), isFalse);
    });
  });

  group('HasTagQuery', () {
    test('matches when the tag is present', () {
      final components = ComponentStore();
      const id = EntityId(1);
      components.add(id, TagSet({'fire'}));
      final scope = QueryScope(components: components);

      expect(HasTagQuery('fire').matches(id, scope), isTrue);
    });

    test('does not match when the entity has no TagSet at all', () {
      final components = ComponentStore();
      const id = EntityId(1);
      final scope = QueryScope(components: components);

      expect(HasTagQuery('fire').matches(id, scope), isFalse);
    });
  });

  group('ResourceAboveQuery / ResourceBelowQuery', () {
    test('above matches strictly greater than the threshold', () {
      final components = ComponentStore();
      const id = EntityId(1);
      components.add(id, ResourceComponent({'stamina': 50}));
      final scope = QueryScope(components: components);

      expect(ResourceAboveQuery('stamina', 40).matches(id, scope), isTrue);
      expect(ResourceAboveQuery('stamina', 50).matches(id, scope), isFalse);
    });

    test('below matches strictly less than the threshold', () {
      final components = ComponentStore();
      const id = EntityId(1);
      components.add(id, ResourceComponent({'stamina': 50}));
      final scope = QueryScope(components: components);

      expect(ResourceBelowQuery('stamina', 60).matches(id, scope), isTrue);
      expect(ResourceBelowQuery('stamina', 50).matches(id, scope), isFalse);
    });

    test('a missing resource, or a missing ResourceComponent, is treated as zero', () {
      final components = ComponentStore();
      const withComponent = EntityId(1);
      const withoutComponent = EntityId(2);
      components.add(withComponent, ResourceComponent({}));
      final scope = QueryScope(components: components);

      expect(
        ResourceBelowQuery('stamina', 1).matches(withComponent, scope),
        isTrue,
      );
      expect(
        ResourceBelowQuery('stamina', 1).matches(withoutComponent, scope),
        isTrue,
      );
      expect(
        ResourceAboveQuery('stamina', -1).matches(withoutComponent, scope),
        isTrue,
      );
    });
  });

  group('HealthBelowQuery', () {
    test('matches strictly below the threshold', () {
      final components = ComponentStore();
      const id = EntityId(1);
      components.add(id, const HealthComponent(current: 30, max: 100));
      final scope = QueryScope(components: components);

      expect(const HealthBelowQuery(50).matches(id, scope), isTrue);
      expect(const HealthBelowQuery(30).matches(id, scope), isFalse);
    });

    test('an entity with no HealthComponent never matches', () {
      final components = ComponentStore();
      const id = EntityId(1);
      final scope = QueryScope(components: components);

      expect(const HealthBelowQuery(9999).matches(id, scope), isFalse);
    });
  });

  group('StatusActiveQuery', () {
    test('matches when the status is active', () {
      final components = ComponentStore();
      const id = EntityId(1);
      components.add(id, StatusComponent({'burning'}));
      final scope = QueryScope(components: components);

      expect(StatusActiveQuery('burning').matches(id, scope), isTrue);
    });

    test('does not match when the entity has no StatusComponent', () {
      final components = ComponentStore();
      const id = EntityId(1);
      final scope = QueryScope(components: components);

      expect(StatusActiveQuery('burning').matches(id, scope), isFalse);
    });
  });
}
```

Create `test/query/query_engine_test.dart`:
```dart
import 'package:build_engine/build_engine.dart';
import 'package:test/test.dart';

void main() {
  group('QueryEngine', () {
    test('evaluate returns only candidates matching the query', () {
      final components = ComponentStore();
      const a = EntityId(1);
      const b = EntityId(2);
      const c = EntityId(3);
      components.add(a, TagSet({'enemy'}));
      components.add(b, TagSet({'enemy'}));
      components.add(c, TagSet({'ally'}));
      final engine = QueryEngine(QueryScope(components: components));

      final matches = engine.evaluate([a, b, c], HasTagQuery('enemy'));

      expect(matches.toSet(), equals({a, b}));
    });

    test('evaluate returns empty when nothing matches', () {
      final components = ComponentStore();
      const a = EntityId(1);
      final engine = QueryEngine(QueryScope(components: components));

      final matches = engine.evaluate([a], HasTagQuery('enemy'));

      expect(matches, isEmpty);
    });

    test('evaluate composes with combinators for multi-criteria queries', () {
      final components = ComponentStore();
      const a = EntityId(1);
      const b = EntityId(2);
      components.add(a, TagSet({'enemy'}));
      components.add(a, const HealthComponent(current: 10, max: 100));
      components.add(b, TagSet({'enemy'}));
      components.add(b, const HealthComponent(current: 90, max: 100));
      final engine = QueryEngine(QueryScope(components: components));

      final query = HasTagQuery('enemy').and(const HealthBelowQuery(50));
      final matches = engine.evaluate([a, b], query);

      expect(matches.toSet(), equals({a}));
    });
  });
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `dart test test/query/`
Expected: FAIL — `Error: Undefined class 'QueryScope'` (and similarly for the other undefined names).

- [ ] **Step 3: Implement `Query`, `QueryScope`, and the combinators**

Create `lib/src/query/query.dart`:
```dart
import '../component/component_store.dart';
import '../entity/entity_id.dart';

/// The read-only data a [Query] evaluates against.
class QueryScope {
  const QueryScope({required this.components});

  final ComponentStore components;
}

/// A composable predicate over a single entity. Independently useful on
/// its own via [QueryEngine] — "find every entity matching some
/// combination of tags/components/resources" — with no Rule Engine
/// involvement required.
abstract class Query {
  bool matches(EntityId id, QueryScope scope);

  /// A query that matches only when both this and [other] match.
  Query and(Query other) => AndQuery([this, other]);

  /// A query that matches when either this or [other] matches.
  Query or(Query other) => OrQuery([this, other]);

  /// A query that matches exactly when this query does not.
  Query not() => NotQuery(this);
}

/// Matches when every query in [queries] matches.
class AndQuery implements Query {
  const AndQuery(this.queries);

  final List<Query> queries;

  @override
  bool matches(EntityId id, QueryScope scope) =>
      queries.every((query) => query.matches(id, scope));
}

/// Matches when any query in [queries] matches.
class OrQuery implements Query {
  const OrQuery(this.queries);

  final List<Query> queries;

  @override
  bool matches(EntityId id, QueryScope scope) =>
      queries.any((query) => query.matches(id, scope));
}

/// Matches exactly when [query] does not.
class NotQuery implements Query {
  const NotQuery(this.query);

  final Query query;

  @override
  bool matches(EntityId id, QueryScope scope) => !query.matches(id, scope);
}
```

Create `lib/src/query/queries.dart`:
```dart
import '../components/health_component.dart';
import '../components/resource_component.dart';
import '../components/status_component.dart';
import '../components/tag_set.dart';
import '../entity/entity_id.dart';
import 'query.dart';

/// Matches an entity that has a component of type `T`.
class HasComponentQuery<T extends Object> implements Query {
  const HasComponentQuery();

  @override
  bool matches(EntityId id, QueryScope scope) => scope.components.has<T>(id);
}

/// Matches an entity whose [TagSet] contains [tag].
class HasTagQuery implements Query {
  const HasTagQuery(this.tag);

  final String tag;

  @override
  bool matches(EntityId id, QueryScope scope) =>
      scope.components.get<TagSet>(id)?.tags.contains(tag) ?? false;
}

/// Matches an entity whose named [resource] is strictly greater than
/// [threshold]. An entity with no [ResourceComponent], or no entry for
/// [resource], is treated as if that resource were `0`.
class ResourceAboveQuery implements Query {
  const ResourceAboveQuery(this.resource, this.threshold);

  final String resource;
  final num threshold;

  @override
  bool matches(EntityId id, QueryScope scope) =>
      (scope.components.get<ResourceComponent>(id)?.resources[resource] ??
          0) >
      threshold;
}

/// Matches an entity whose named [resource] is strictly less than
/// [threshold]. Same zero-default as [ResourceAboveQuery].
class ResourceBelowQuery implements Query {
  const ResourceBelowQuery(this.resource, this.threshold);

  final String resource;
  final num threshold;

  @override
  bool matches(EntityId id, QueryScope scope) =>
      (scope.components.get<ResourceComponent>(id)?.resources[resource] ??
          0) <
      threshold;
}

/// Matches an entity whose [HealthComponent.current] is strictly less
/// than [threshold] (an absolute value, not a percentage of `max`). An
/// entity with no [HealthComponent] never matches — unlike
/// [ResourceBelowQuery]'s zero-default, "no health system at all" is
/// deliberately not the same as "health is low".
class HealthBelowQuery implements Query {
  const HealthBelowQuery(this.threshold);

  final num threshold;

  @override
  bool matches(EntityId id, QueryScope scope) {
    final health = scope.components.get<HealthComponent>(id);
    if (health == null) return false;
    return health.current < threshold;
  }
}

/// Matches an entity whose [StatusComponent] has [status] active.
class StatusActiveQuery implements Query {
  const StatusActiveQuery(this.status);

  final String status;

  @override
  bool matches(EntityId id, QueryScope scope) =>
      scope.components
          .get<StatusComponent>(id)
          ?.activeStatuses
          .contains(status) ??
      false;
}
```

Create `lib/src/query/query_engine.dart`:
```dart
import '../entity/entity_id.dart';
import 'query.dart';

/// Evaluates a [Query] against a set of candidate entities, independent of
/// any particular source of candidates (typically `EntityRegistry.all`).
class QueryEngine {
  const QueryEngine(this.scope);

  final QueryScope scope;

  /// Every entity in [candidates] that [query] matches.
  Iterable<EntityId> evaluate(Iterable<EntityId> candidates, Query query) =>
      candidates.where((id) => query.matches(id, scope));
}
```

- [ ] **Step 4: Export all three from the barrel file**

Modify `lib/build_engine.dart`, adding three new export lines alphabetically (after `plugin/plugin_manager.dart`, before `rng/rng_service.dart` — `query` sorts before `rng`):
```dart
export 'src/plugin/plugin_manager.dart';
export 'src/query/queries.dart';
export 'src/query/query.dart';
export 'src/query/query_engine.dart';
export 'src/rng/rng_service.dart';
export 'src/rule/event_counter.dart';
```

- [ ] **Step 5: Run tests to verify they pass, and analyze**

Run:
```bash
dart test test/query/
dart analyze
```
Expected: all tests PASS; `dart analyze` reports `No issues found!`.

- [ ] **Step 6: Commit**

```bash
git add lib/src/query/ lib/build_engine.dart test/query/
git commit -m "feat: add Query Engine"
```

---

### Task 6: RuleContext and the Condition system

**Files:**
- Create: `lib/src/rule/rule_context.dart`
- Create: `lib/src/rule/condition.dart`
- Test: `test/rule/condition_test.dart`
- Modify: `lib/build_engine.dart`

**Interfaces:**
- Consumes: `EntityId`, `EntityRegistry`, `ComponentStore`, `EventBus` (foundation); `RngService` (Task 3); `EventCounter` (Task 4); `Query`/`QueryScope`/every concrete query (Task 5).
- Produces: `class RuleContext { EntityId? subject; Object triggerEvent; EntityRegistry entities; ComponentStore components; EventBus events; RngService rng; EventCounter eventCounts; }`; `abstract class Condition { bool evaluate(RuleContext); }`; `HasTag(String)`, `HasComponent<T extends Object>()`, `ResourceAbove(String, num)`, `ResourceBelow(String, num)`, `HealthBelow(num)`, `StatusActive(String)`, `enum CountComparison`, `EventCount({required Type eventType, required CountComparison comparison, required int threshold})`, `RandomChance(double)`. Task 7 (Effect system) and Task 8 (`Rule`/`RuleEngine`) both consume `RuleContext`; Task 8 also consumes `EventCount` directly (to auto-track its `eventType`).

- [ ] **Step 1: Write the failing tests**

Create `test/rule/condition_test.dart`:
```dart
import 'package:build_engine/build_engine.dart';
import 'package:test/test.dart';

class _TestEvent {
  const _TestEvent();
}

RuleContext _contextFor({
  EntityId? subject,
  ComponentStore? components,
  RngService? rng,
}) {
  final eventBus = EventBus();
  return RuleContext(
    subject: subject,
    triggerEvent: const Object(),
    entities: EntityRegistry(eventBus),
    components: components ?? ComponentStore(),
    events: eventBus,
    rng: rng ?? RngService(1),
    eventCounts: EventCounter(eventBus),
  );
}

void main() {
  group('HasTag', () {
    test('matches when the subject has the tag', () {
      final components = ComponentStore();
      const subject = EntityId(1);
      components.add(subject, TagSet({'fire'}));

      expect(
        HasTag('fire')
            .evaluate(_contextFor(subject: subject, components: components)),
        isTrue,
      );
    });

    test('does not match with no subject', () {
      expect(HasTag('fire').evaluate(_contextFor(subject: null)), isFalse);
    });
  });

  group('HasComponent', () {
    test('matches when the subject has the component', () {
      final components = ComponentStore();
      const subject = EntityId(1);
      components.add(subject, const HealthComponent(current: 1, max: 1));

      expect(
        const HasComponent<HealthComponent>().evaluate(
          _contextFor(subject: subject, components: components),
        ),
        isTrue,
      );
    });

    test('does not match with no subject', () {
      expect(
        const HasComponent<HealthComponent>().evaluate(
          _contextFor(subject: null),
        ),
        isFalse,
      );
    });
  });

  group('ResourceAbove / ResourceBelow', () {
    test('respect the strict comparisons', () {
      final components = ComponentStore();
      const subject = EntityId(1);
      components.add(subject, ResourceComponent({'stamina': 50}));
      final context = _contextFor(subject: subject, components: components);

      expect(ResourceAbove('stamina', 40).evaluate(context), isTrue);
      expect(ResourceAbove('stamina', 50).evaluate(context), isFalse);
      expect(ResourceBelow('stamina', 60).evaluate(context), isTrue);
      expect(ResourceBelow('stamina', 50).evaluate(context), isFalse);
    });
  });

  group('HealthBelow', () {
    test('matches strictly below the threshold', () {
      final components = ComponentStore();
      const subject = EntityId(1);
      components.add(subject, const HealthComponent(current: 20, max: 100));

      expect(
        HealthBelow(50)
            .evaluate(_contextFor(subject: subject, components: components)),
        isTrue,
      );
    });

    test('does not match with no subject', () {
      expect(HealthBelow(9999).evaluate(_contextFor(subject: null)), isFalse);
    });
  });

  group('StatusActive', () {
    test('matches when the status is active', () {
      final components = ComponentStore();
      const subject = EntityId(1);
      components.add(subject, StatusComponent({'burning'}));

      expect(
        StatusActive('burning').evaluate(
          _contextFor(subject: subject, components: components),
        ),
        isTrue,
      );
    });
  });

  group('EventCount', () {
    test('every comparison direction behaves correctly', () {
      final events = EventBus();
      final counter = EventCounter(events);
      counter.trackType(_TestEvent);
      events.publish(const _TestEvent());
      final context = RuleContext(
        subject: null,
        triggerEvent: const Object(),
        entities: EntityRegistry(events),
        components: ComponentStore(),
        events: events,
        rng: RngService(1),
        eventCounts: counter,
      );

      expect(
        const EventCount(
          eventType: _TestEvent,
          comparison: CountComparison.greaterThan,
          threshold: 0,
        ).evaluate(context),
        isTrue,
      );
      expect(
        const EventCount(
          eventType: _TestEvent,
          comparison: CountComparison.greaterThanOrEqual,
          threshold: 1,
        ).evaluate(context),
        isTrue,
      );
      expect(
        const EventCount(
          eventType: _TestEvent,
          comparison: CountComparison.lessThan,
          threshold: 2,
        ).evaluate(context),
        isTrue,
      );
      expect(
        const EventCount(
          eventType: _TestEvent,
          comparison: CountComparison.lessThanOrEqual,
          threshold: 1,
        ).evaluate(context),
        isTrue,
      );
      expect(
        const EventCount(
          eventType: _TestEvent,
          comparison: CountComparison.equal,
          threshold: 1,
        ).evaluate(context),
        isTrue,
      );
    });

    test('an untracked event type reports zero', () {
      final events = EventBus();
      final context = RuleContext(
        subject: null,
        triggerEvent: const Object(),
        entities: EntityRegistry(events),
        components: ComponentStore(),
        events: events,
        rng: RngService(1),
        eventCounts: EventCounter(events),
      );

      expect(
        const EventCount(
          eventType: _TestEvent,
          comparison: CountComparison.equal,
          threshold: 0,
        ).evaluate(context),
        isTrue,
      );
    });
  });

  group('RandomChance', () {
    test('chance(0.0) never matches', () {
      final context = _contextFor(subject: null, rng: RngService(1));
      for (var i = 0; i < 20; i++) {
        expect(RandomChance(0.0).evaluate(context), isFalse);
      }
    });

    test('chance(1.0) always matches', () {
      final context = _contextFor(subject: null, rng: RngService(1));
      for (var i = 0; i < 20; i++) {
        expect(RandomChance(1.0).evaluate(context), isTrue);
      }
    });
  });
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `dart test test/rule/condition_test.dart`
Expected: FAIL — `Error: Undefined class 'RuleContext'`.

- [ ] **Step 3: Implement `RuleContext`**

Create `lib/src/rule/rule_context.dart`:
```dart
import '../component/component_store.dart';
import '../entity/entity_id.dart';
import '../entity/entity_registry.dart';
import '../event/event_bus.dart';
import '../rng/rng_service.dart';
import 'event_counter.dart';

/// Everything a [Condition] or an effect needs to evaluate/act: the
/// entity this rule concerns itself with (if any), the event that
/// triggered it, and the core services.
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

  /// The entity this rule's conditions/effects act on, resolved from the
  /// triggering event by the owning rule's `subjectOf`. `null` if the
  /// rule has no subject (e.g. a rule that only checks [EventCount] or
  /// [RandomChance]).
  final EntityId? subject;

  /// The event instance that caused this rule to fire.
  final Object triggerEvent;

  final EntityRegistry entities;
  final ComponentStore components;
  final EventBus events;
  final RngService rng;
  final EventCounter eventCounts;
}
```

- [ ] **Step 4: Implement the `Condition` interface and every concrete condition**

Create `lib/src/rule/condition.dart`:
```dart
import '../query/queries.dart';
import '../query/query.dart';
import 'rule_context.dart';

/// A Rule-scoped boolean check. Plugins implement this directly to add
/// their own conditions — no registry required.
abstract class Condition {
  bool evaluate(RuleContext context);
}

QueryScope _scopeOf(RuleContext context) =>
    QueryScope(components: context.components);

/// Matches when the rule's subject has [tag] in its `TagSet`.
class HasTag implements Condition {
  const HasTag(this.tag);

  final String tag;

  @override
  bool evaluate(RuleContext context) {
    final subject = context.subject;
    if (subject == null) return false;
    return HasTagQuery(tag).matches(subject, _scopeOf(context));
  }
}

/// Matches when the rule's subject has a component of type `T`.
class HasComponent<T extends Object> implements Condition {
  const HasComponent();

  @override
  bool evaluate(RuleContext context) {
    final subject = context.subject;
    if (subject == null) return false;
    return HasComponentQuery<T>().matches(subject, _scopeOf(context));
  }
}

/// Matches when the rule's subject's named [resource] is strictly greater
/// than [threshold]. See [ResourceAboveQuery] for the zero-default on a
/// missing resource/component.
class ResourceAbove implements Condition {
  const ResourceAbove(this.resource, this.threshold);

  final String resource;
  final num threshold;

  @override
  bool evaluate(RuleContext context) {
    final subject = context.subject;
    if (subject == null) return false;
    return ResourceAboveQuery(resource, threshold)
        .matches(subject, _scopeOf(context));
  }
}

/// Matches when the rule's subject's named [resource] is strictly less
/// than [threshold]. See [ResourceBelowQuery] for the zero-default.
class ResourceBelow implements Condition {
  const ResourceBelow(this.resource, this.threshold);

  final String resource;
  final num threshold;

  @override
  bool evaluate(RuleContext context) {
    final subject = context.subject;
    if (subject == null) return false;
    return ResourceBelowQuery(resource, threshold)
        .matches(subject, _scopeOf(context));
  }
}

/// Matches when the rule's subject's health is strictly below
/// [threshold]. See [HealthBelowQuery] for why a missing `HealthComponent`
/// never matches.
class HealthBelow implements Condition {
  const HealthBelow(this.threshold);

  final num threshold;

  @override
  bool evaluate(RuleContext context) {
    final subject = context.subject;
    if (subject == null) return false;
    return HealthBelowQuery(threshold).matches(subject, _scopeOf(context));
  }
}

/// Matches when the rule's subject has [status] active.
class StatusActive implements Condition {
  const StatusActive(this.status);

  final String status;

  @override
  bool evaluate(RuleContext context) {
    final subject = context.subject;
    if (subject == null) return false;
    return StatusActiveQuery(status).matches(subject, _scopeOf(context));
  }
}

/// How [EventCount] compares the tracked count against its threshold.
enum CountComparison {
  greaterThan,
  greaterThanOrEqual,
  lessThan,
  lessThanOrEqual,
  equal,
}

/// Matches based on how many times [eventType] has been published since
/// this rule was registered (see `EventCounter` — counting is not
/// retroactive; `RuleEngine` auto-tracks [eventType] when a rule using
/// this condition is registered).
class EventCount implements Condition {
  const EventCount({
    required this.eventType,
    required this.comparison,
    required this.threshold,
  });

  final Type eventType;
  final CountComparison comparison;
  final int threshold;

  @override
  bool evaluate(RuleContext context) {
    final count = context.eventCounts.countOfType(eventType);
    switch (comparison) {
      case CountComparison.greaterThan:
        return count > threshold;
      case CountComparison.greaterThanOrEqual:
        return count >= threshold;
      case CountComparison.lessThan:
        return count < threshold;
      case CountComparison.lessThanOrEqual:
        return count <= threshold;
      case CountComparison.equal:
        return count == threshold;
    }
  }
}

/// Matches with probability [probability] (`0.0`-`1.0`), via the rule
/// engine's injected `RngService` — never `dart:math` directly.
class RandomChance implements Condition {
  const RandomChance(this.probability);

  final double probability;

  @override
  bool evaluate(RuleContext context) => context.rng.chance(probability);
}
```

- [ ] **Step 5: Export both new files from the barrel file**

Modify `lib/build_engine.dart`, adding two new export lines alphabetically (after `query/query_engine.dart`, before `rng/rng_service.dart` — `rule/condition.dart` and `rule/rule_context.dart` both sort after `rng`):
```dart
export 'src/query/query_engine.dart';
export 'src/rng/rng_service.dart';
export 'src/rule/condition.dart';
export 'src/rule/event_counter.dart';
export 'src/rule/rule_context.dart';
```

- [ ] **Step 6: Run tests to verify they pass, and analyze**

Run:
```bash
dart test test/rule/condition_test.dart
dart analyze
```
Expected: all tests PASS; `dart analyze` reports `No issues found!`.

- [ ] **Step 7: Commit**

```bash
git add lib/src/rule/rule_context.dart lib/src/rule/condition.dart lib/build_engine.dart test/rule/condition_test.dart
git commit -m "feat: add RuleContext and the Condition system"
```

---

### Task 7: Effect system and effect events

**Files:**
- Create: `lib/src/rule/effect_events.dart`
- Create: `lib/src/rule/effect.dart`
- Test: `test/rule/effect_test.dart`
- Modify: `lib/build_engine.dart`

**Interfaces:**
- Consumes: `RuleContext` (Task 6); `HealthComponent`, `ResourceComponent`, `StatComponent`, `StatusComponent`, `TagSet` (Task 1); `EntityRegistry`, `EventBus` (foundation).
- Produces: `class EntityDamaged { EntityId id; num amount; }`, `class EntityHealed { EntityId id; num amount; }`, `class EntityKilled { EntityId id; }`; `abstract class Effect { void apply(RuleContext); }`; `Damage(num)`, `Heal(num)`, `ModifyStat(String, num)`, `ModifyResource(String, num)`, `ApplyStatus(String)`, `RemoveStatus(String)`, `AddTag(String)`, `RemoveTag(String)`, `CreateEntity({Set<String> tags})`, `DestroyEntity()`, `TransformEntity(Set<String>)`. Task 9's integration test exercises these directly; Task 8's `RuleEngine` runs whichever effects a `Rule` lists.

- [ ] **Step 1: Write the failing tests**

Create `test/rule/effect_test.dart`:
```dart
import 'package:build_engine/build_engine.dart';
import 'package:test/test.dart';

class _Harness {
  _Harness()
      : events = EventBus(),
        components = ComponentStore() {
    entities = EntityRegistry(events);
  }

  final EventBus events;
  final ComponentStore components;
  late final EntityRegistry entities;

  RuleContext contextFor(EntityId? subject) => RuleContext(
        subject: subject,
        triggerEvent: const Object(),
        entities: entities,
        components: components,
        events: events,
        rng: RngService(1),
        eventCounts: EventCounter(events),
      );
}

void main() {
  group('Damage', () {
    test('reduces health and publishes EntityDamaged', () {
      final harness = _Harness();
      final subject = harness.entities.create();
      harness.components
          .add(subject, const HealthComponent(current: 100, max: 100));
      final damaged = <EntityId>[];
      harness.events.subscribe<EntityDamaged>((e) => damaged.add(e.id));

      const Damage(30).apply(harness.contextFor(subject));

      expect(
        harness.components.get<HealthComponent>(subject)!.current,
        equals(70),
      );
      expect(damaged, equals([subject]));
    });

    test('clamps at 0 and publishes EntityKilled', () {
      final harness = _Harness();
      final subject = harness.entities.create();
      harness.components
          .add(subject, const HealthComponent(current: 10, max: 100));
      final killed = <EntityId>[];
      harness.events.subscribe<EntityKilled>((e) => killed.add(e.id));

      const Damage(50).apply(harness.contextFor(subject));

      expect(
        harness.components.get<HealthComponent>(subject)!.current,
        equals(0),
      );
      expect(killed, equals([subject]));
    });

    test('does not destroy the entity on death', () {
      final harness = _Harness();
      final subject = harness.entities.create();
      harness.components
          .add(subject, const HealthComponent(current: 10, max: 100));

      const Damage(50).apply(harness.contextFor(subject));

      expect(harness.entities.isAlive(subject), isTrue);
    });

    test('no-ops with no subject', () {
      final harness = _Harness();
      expect(
        () => const Damage(10).apply(harness.contextFor(null)),
        returnsNormally,
      );
    });

    test('no-ops when the subject has no HealthComponent', () {
      final harness = _Harness();
      final subject = harness.entities.create();

      expect(
        () => const Damage(10).apply(harness.contextFor(subject)),
        returnsNormally,
      );
      expect(harness.components.has<HealthComponent>(subject), isFalse);
    });
  });

  group('Heal', () {
    test('increases health and publishes EntityHealed, clamped to max', () {
      final harness = _Harness();
      final subject = harness.entities.create();
      harness.components
          .add(subject, const HealthComponent(current: 90, max: 100));
      final healed = <EntityId>[];
      harness.events.subscribe<EntityHealed>((e) => healed.add(e.id));

      const Heal(30).apply(harness.contextFor(subject));

      expect(
        harness.components.get<HealthComponent>(subject)!.current,
        equals(100),
      );
      expect(healed, equals([subject]));
    });
  });

  group('ModifyStat', () {
    test('adds delta to an existing stat', () {
      final harness = _Harness();
      final subject = harness.entities.create();
      harness.components.add(subject, StatComponent({'strength': 10}));

      const ModifyStat('strength', 5).apply(harness.contextFor(subject));

      expect(
        harness.components.get<StatComponent>(subject)!.stats['strength'],
        equals(15),
      );
    });

    test('treats a missing stat/component as zero', () {
      final harness = _Harness();
      final subject = harness.entities.create();

      const ModifyStat('strength', 5).apply(harness.contextFor(subject));

      expect(
        harness.components.get<StatComponent>(subject)!.stats['strength'],
        equals(5),
      );
    });
  });

  group('ModifyResource', () {
    test('adds delta to an existing resource', () {
      final harness = _Harness();
      final subject = harness.entities.create();
      harness.components.add(subject, ResourceComponent({'stamina': 20}));

      const ModifyResource('stamina', -5).apply(harness.contextFor(subject));

      expect(
        harness.components.get<ResourceComponent>(subject)!.resources['stamina'],
        equals(15),
      );
    });
  });

  group('ApplyStatus / RemoveStatus', () {
    test('ApplyStatus adds a status, creating the component if absent', () {
      final harness = _Harness();
      final subject = harness.entities.create();

      const ApplyStatus('burning').apply(harness.contextFor(subject));

      expect(
        harness.components.get<StatusComponent>(subject)!.activeStatuses,
        contains('burning'),
      );
    });

    test('RemoveStatus removes an active status', () {
      final harness = _Harness();
      final subject = harness.entities.create();
      harness.components.add(subject, StatusComponent({'burning', 'stunned'}));

      const RemoveStatus('burning').apply(harness.contextFor(subject));

      expect(
        harness.components.get<StatusComponent>(subject)!.activeStatuses,
        equals({'stunned'}),
      );
    });

    test('RemoveStatus no-ops when the subject has no StatusComponent', () {
      final harness = _Harness();
      final subject = harness.entities.create();

      expect(
        () => const RemoveStatus('burning').apply(harness.contextFor(subject)),
        returnsNormally,
      );
      expect(harness.components.has<StatusComponent>(subject), isFalse);
    });
  });

  group('AddTag / RemoveTag', () {
    test('AddTag adds a tag, creating the component if absent', () {
      final harness = _Harness();
      final subject = harness.entities.create();

      const AddTag('fire').apply(harness.contextFor(subject));

      expect(harness.components.get<TagSet>(subject)!.tags, contains('fire'));
    });

    test('RemoveTag removes a tag', () {
      final harness = _Harness();
      final subject = harness.entities.create();
      harness.components.add(subject, TagSet({'fire', 'dragon'}));

      const RemoveTag('fire').apply(harness.contextFor(subject));

      expect(harness.components.get<TagSet>(subject)!.tags, equals({'dragon'}));
    });
  });

  group('CreateEntity', () {
    test('creates a new entity distinct from the subject', () {
      final harness = _Harness();
      final subject = harness.entities.create();

      const CreateEntity().apply(harness.contextFor(subject));

      expect(harness.entities.all.length, equals(2));
    });

    test('attaches a TagSet when tags are given', () {
      final harness = _Harness();

      const CreateEntity(tags: {'loot'}).apply(harness.contextFor(null));

      final created = harness.entities.all.single;
      expect(harness.components.get<TagSet>(created)!.tags, equals({'loot'}));
    });

    test('attaches no TagSet when tags are empty', () {
      final harness = _Harness();

      const CreateEntity().apply(harness.contextFor(null));

      final created = harness.entities.all.single;
      expect(harness.components.has<TagSet>(created), isFalse);
    });
  });

  group('DestroyEntity', () {
    test('destroys the subject', () {
      final harness = _Harness();
      final subject = harness.entities.create();

      const DestroyEntity().apply(harness.contextFor(subject));

      expect(harness.entities.isAlive(subject), isFalse);
    });

    test('no-ops on an already-destroyed subject rather than throwing', () {
      final harness = _Harness();
      final subject = harness.entities.create();
      harness.entities.destroy(subject);

      expect(
        () => const DestroyEntity().apply(harness.contextFor(subject)),
        returnsNormally,
      );
    });
  });

  group('TransformEntity', () {
    test('replaces the entire TagSet', () {
      final harness = _Harness();
      final subject = harness.entities.create();
      harness.components.add(subject, TagSet({'unidentified'}));

      const TransformEntity({'identified', 'potion'})
          .apply(harness.contextFor(subject));

      expect(
        harness.components.get<TagSet>(subject)!.tags,
        equals({'identified', 'potion'}),
      );
    });
  });
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `dart test test/rule/effect_test.dart`
Expected: FAIL — `Error: Undefined class 'Damage'` (and similarly for the other undefined names).

- [ ] **Step 3: Implement the effect events**

Create `lib/src/rule/effect_events.dart`:
```dart
import '../entity/entity_id.dart';

/// Published by [Damage] whenever it reduces an entity's health.
class EntityDamaged {
  const EntityDamaged(this.id, this.amount);

  final EntityId id;
  final num amount;
}

/// Published by [Heal] whenever it increases an entity's health.
class EntityHealed {
  const EntityHealed(this.id, this.amount);

  final EntityId id;
  final num amount;
}

/// Published by [Damage] when an entity's health reaches exactly 0.
class EntityKilled {
  const EntityKilled(this.id);

  final EntityId id;
}
```

- [ ] **Step 4: Implement the `Effect` interface and every concrete effect**

Create `lib/src/rule/effect.dart`:
```dart
import '../components/health_component.dart';
import '../components/resource_component.dart';
import '../components/stat_component.dart';
import '../components/status_component.dart';
import '../components/tag_set.dart';
import 'effect_events.dart';
import 'rule_context.dart';

/// A Rule-scoped state mutation. Plugins implement this directly to add
/// their own effects — no registry required.
abstract class Effect {
  void apply(RuleContext context);
}

/// Reduces the subject's health by [amount], clamped to `[0, max]`.
/// Publishes [EntityDamaged], and additionally [EntityKilled] if health
/// reaches exactly 0. Does not destroy the entity — that stays a policy
/// decision for whoever reacts to [EntityKilled]. No-ops if the subject
/// has no [HealthComponent].
class Damage implements Effect {
  const Damage(this.amount);

  final num amount;

  @override
  void apply(RuleContext context) {
    final subject = context.subject;
    if (subject == null) return;
    final health = context.components.get<HealthComponent>(subject);
    if (health == null) return;
    final newCurrent = (health.current - amount).clamp(0, health.max);
    context.components.add(
      subject,
      HealthComponent(current: newCurrent, max: health.max),
    );
    context.events.publish(EntityDamaged(subject, amount));
    if (newCurrent == 0) {
      context.events.publish(EntityKilled(subject));
    }
  }
}

/// Increases the subject's health by [amount], clamped to `[0, max]`.
/// Publishes [EntityHealed]. No-ops if the subject has no
/// [HealthComponent].
class Heal implements Effect {
  const Heal(this.amount);

  final num amount;

  @override
  void apply(RuleContext context) {
    final subject = context.subject;
    if (subject == null) return;
    final health = context.components.get<HealthComponent>(subject);
    if (health == null) return;
    final newCurrent = (health.current + amount).clamp(0, health.max);
    context.components.add(
      subject,
      HealthComponent(current: newCurrent, max: health.max),
    );
    context.events.publish(EntityHealed(subject, amount));
  }
}

/// Adds [delta] to the subject's named [stat], treating a missing
/// [StatComponent] or missing entry as `0`.
///
/// Stopgap: mutates the raw value directly. See `StatComponent`'s doc
/// comment — this will change once Modifier Engine lands.
class ModifyStat implements Effect {
  const ModifyStat(this.stat, this.delta);

  final String stat;
  final num delta;

  @override
  void apply(RuleContext context) {
    final subject = context.subject;
    if (subject == null) return;
    final existing = context.components.get<StatComponent>(subject);
    final stats = Map<String, num>.of(existing?.stats ?? const <String, num>{});
    stats[stat] = (stats[stat] ?? 0) + delta;
    context.components.add(subject, StatComponent(stats));
  }
}

/// Adds [delta] to the subject's named [resource], treating a missing
/// [ResourceComponent] or missing entry as `0`.
class ModifyResource implements Effect {
  const ModifyResource(this.resource, this.delta);

  final String resource;
  final num delta;

  @override
  void apply(RuleContext context) {
    final subject = context.subject;
    if (subject == null) return;
    final existing = context.components.get<ResourceComponent>(subject);
    final resources = Map<String, num>.of(existing?.resources ?? const <String, num>{});
    resources[resource] = (resources[resource] ?? 0) + delta;
    context.components.add(subject, ResourceComponent(resources));
  }
}

/// Adds [status] to the subject's active statuses, creating the
/// [StatusComponent] if the subject doesn't have one yet.
class ApplyStatus implements Effect {
  const ApplyStatus(this.status);

  final String status;

  @override
  void apply(RuleContext context) {
    final subject = context.subject;
    if (subject == null) return;
    final existing = context.components.get<StatusComponent>(subject);
    final statuses = Set<String>.of(existing?.activeStatuses ?? const <String>{});
    statuses.add(status);
    context.components.add(subject, StatusComponent(statuses));
  }
}

/// Removes [status] from the subject's active statuses. A no-op if the
/// subject has no [StatusComponent].
class RemoveStatus implements Effect {
  const RemoveStatus(this.status);

  final String status;

  @override
  void apply(RuleContext context) {
    final subject = context.subject;
    if (subject == null) return;
    final existing = context.components.get<StatusComponent>(subject);
    if (existing == null) return;
    final statuses = Set<String>.of(existing.activeStatuses);
    statuses.remove(status);
    context.components.add(subject, StatusComponent(statuses));
  }
}

/// Adds [tag] to the subject's [TagSet], creating it if the subject
/// doesn't have one yet.
class AddTag implements Effect {
  const AddTag(this.tag);

  final String tag;

  @override
  void apply(RuleContext context) {
    final subject = context.subject;
    if (subject == null) return;
    final existing = context.components.get<TagSet>(subject);
    final tags = Set<String>.of(existing?.tags ?? const <String>{});
    tags.add(tag);
    context.components.add(subject, TagSet(tags));
  }
}

/// Removes [tag] from the subject's [TagSet]. A no-op if the subject has
/// no [TagSet].
class RemoveTag implements Effect {
  const RemoveTag(this.tag);

  final String tag;

  @override
  void apply(RuleContext context) {
    final subject = context.subject;
    if (subject == null) return;
    final existing = context.components.get<TagSet>(subject);
    if (existing == null) return;
    final tags = Set<String>.of(existing.tags);
    tags.remove(tag);
    context.components.add(subject, TagSet(tags));
  }
}

/// Creates a new entity (not the rule's subject) and, if [tags] is
/// non-empty, attaches a [TagSet]. Further initialization happens by
/// reacting to the `EntityCreated` event `EntityRegistry.create` already
/// publishes — no arbitrary component-initialization hook here.
class CreateEntity implements Effect {
  const CreateEntity({this.tags = const <String>{}});

  final Set<String> tags;

  @override
  void apply(RuleContext context) {
    final entity = context.entities.create();
    if (tags.isNotEmpty) {
      context.components.add(entity, TagSet(tags));
    }
  }
}

/// Destroys the rule's subject. Component cleanup stays the caller's job
/// via the `EntityDestroyed` subscription pattern documented in
/// `ARCHITECTURE.md` — this effect doesn't special-case it. A no-op if
/// the subject is already destroyed (rather than throwing), since two
/// rules reacting to different events could both target the same
/// subject for destruction.
class DestroyEntity implements Effect {
  const DestroyEntity();

  @override
  void apply(RuleContext context) {
    final subject = context.subject;
    if (subject == null) return;
    if (!context.entities.isAlive(subject)) return;
    context.entities.destroy(subject);
  }
}

/// Replaces the subject's entire [TagSet] with [newTags] — a wholesale
/// identity swap, distinct from [AddTag]/[RemoveTag]'s single-tag
/// increments.
class TransformEntity implements Effect {
  const TransformEntity(this.newTags);

  final Set<String> newTags;

  @override
  void apply(RuleContext context) {
    final subject = context.subject;
    if (subject == null) return;
    context.components.add(subject, TagSet(newTags));
  }
}
```

- [ ] **Step 5: Export both new files from the barrel file**

Modify `lib/build_engine.dart`, adding two new export lines alphabetically (`rule/effect.dart` and `rule/effect_events.dart` sort before `rule/event_counter.dart`):
```dart
export 'src/rule/condition.dart';
export 'src/rule/effect.dart';
export 'src/rule/effect_events.dart';
export 'src/rule/event_counter.dart';
export 'src/rule/rule_context.dart';
```

- [ ] **Step 6: Run tests to verify they pass, and analyze**

Run:
```bash
dart test test/rule/effect_test.dart
dart analyze
```
Expected: all tests PASS; `dart analyze` reports `No issues found!`.

- [ ] **Step 7: Commit**

```bash
git add lib/src/rule/effect.dart lib/src/rule/effect_events.dart lib/build_engine.dart test/rule/effect_test.dart
git commit -m "feat: add Effect system and effect events"
```

---

### Task 8: Rule and RuleEngine

**Files:**
- Create: `lib/src/rule/rule.dart`
- Create: `lib/src/rule/rule_engine.dart`
- Test: `test/rule/rule_engine_test.dart`
- Modify: `lib/build_engine.dart`

**Interfaces:**
- Consumes: `Condition`/`EventCount` (Task 6), `Effect` (Task 7), `RuleContext` (Task 6), `EntityRegistry`/`ComponentStore`/`EventBus.subscribeDynamic` (foundation + Task 2), `RngService` (Task 3), `EventCounter` (Task 4).
- Produces: `class Rule { Type trigger; EntityId? Function(Object)? subjectOf; List<Condition> conditions; List<Effect> effects; }`; `class RuleEngine { RuleEngine({required EntityRegistry entities, required ComponentStore components, required EventBus events, required RngService rng}); void register(Rule rule); }`. Task 9's integration test drives this end-to-end.

Each `Rule` gets its **own** `EventBus.subscribeDynamic` subscription in `register` — multiple rules sharing the same `trigger` just means multiple independent subscriptions (EventBus already supports multiple subscribers per type), so `RuleEngine` needs no trigger-deduplication bookkeeping.

- [ ] **Step 1: Write the failing tests**

Create `test/rule/rule_engine_test.dart`:
```dart
import 'package:build_engine/build_engine.dart';
import 'package:test/test.dart';

class _Trigger {
  const _Trigger(this.actor);
  final EntityId actor;
}

class _OtherEvent {
  const _OtherEvent();
}

class _RecordingEffect implements Effect {
  const _RecordingEffect(this.onApply);

  final void Function() onApply;

  @override
  void apply(RuleContext context) => onApply();
}

RuleEngine _newEngine({
  required EntityRegistry entities,
  required ComponentStore components,
  required EventBus events,
  int seed = 1,
}) =>
    RuleEngine(
      entities: entities,
      components: components,
      events: events,
      rng: RngService(seed),
    );

num _runRandomRule({required int seed}) {
  final events = EventBus();
  final components = ComponentStore();
  final entities = EntityRegistry(events);
  final actor = entities.create();
  components.add(actor, const HealthComponent(current: 100, max: 100));
  final engine = RuleEngine(
    entities: entities,
    components: components,
    events: events,
    rng: RngService(seed),
  );

  engine.register(Rule(
    trigger: _Trigger,
    subjectOf: (event) => (event as _Trigger).actor,
    conditions: [const RandomChance(0.5)],
    effects: [const Damage(10)],
  ));

  for (var i = 0; i < 10; i++) {
    events.publish(_Trigger(actor));
  }

  return components.get<HealthComponent>(actor)!.current;
}

void main() {
  group('RuleEngine', () {
    test('a registered rule fires when its trigger is published', () {
      final events = EventBus();
      final components = ComponentStore();
      final entities = EntityRegistry(events);
      final actor = entities.create();
      components.add(actor, const HealthComponent(current: 100, max: 100));
      final engine =
          _newEngine(entities: entities, components: components, events: events);

      engine.register(Rule(
        trigger: _Trigger,
        subjectOf: (event) => (event as _Trigger).actor,
        effects: [const Damage(10)],
      ));

      events.publish(_Trigger(actor));

      expect(components.get<HealthComponent>(actor)!.current, equals(90));
    });

    test('a rule does not fire for a different event type', () {
      final events = EventBus();
      final components = ComponentStore();
      final entities = EntityRegistry(events);
      final actor = entities.create();
      components.add(actor, const HealthComponent(current: 100, max: 100));
      final engine =
          _newEngine(entities: entities, components: components, events: events);

      engine.register(Rule(
        trigger: _Trigger,
        subjectOf: (event) => (event as _Trigger).actor,
        effects: [const Damage(10)],
      ));

      events.publish(const _OtherEvent());

      expect(components.get<HealthComponent>(actor)!.current, equals(100));
    });

    test('all conditions must pass (AND) for effects to run', () {
      final events = EventBus();
      final components = ComponentStore();
      final entities = EntityRegistry(events);
      final actor = entities.create();
      components.add(actor, TagSet({'fire'}));
      components.add(actor, const HealthComponent(current: 100, max: 100));
      final engine =
          _newEngine(entities: entities, components: components, events: events);

      engine.register(Rule(
        trigger: _Trigger,
        subjectOf: (event) => (event as _Trigger).actor,
        conditions: [HasTag('fire'), HasTag('ice')],
        effects: [const Damage(10)],
      ));

      events.publish(_Trigger(actor));

      expect(components.get<HealthComponent>(actor)!.current, equals(100));
    });

    test('effects run in list order', () {
      final events = EventBus();
      final components = ComponentStore();
      final entities = EntityRegistry(events);
      final actor = entities.create();
      components.add(actor, const HealthComponent(current: 100, max: 100));
      final engine =
          _newEngine(entities: entities, components: components, events: events);

      engine.register(Rule(
        trigger: _Trigger,
        subjectOf: (event) => (event as _Trigger).actor,
        effects: [const Damage(50), const Heal(10)],
      ));

      events.publish(_Trigger(actor));

      expect(components.get<HealthComponent>(actor)!.current, equals(60));
    });

    test('an entity-scoped condition never passes with no resolvable subject',
        () {
      final events = EventBus();
      final components = ComponentStore();
      final entities = EntityRegistry(events);
      final engine =
          _newEngine(entities: entities, components: components, events: events);
      var fired = false;

      engine.register(Rule(
        trigger: _OtherEvent,
        conditions: [HasTag('fire')],
        effects: [_RecordingEffect(() => fired = true)],
      ));

      events.publish(const _OtherEvent());

      expect(fired, isFalse);
    });

    test('EventCount is auto-tracked from rule registration, not retroactively',
        () {
      final events = EventBus();
      final components = ComponentStore();
      final entities = EntityRegistry(events);
      final actor = entities.create();
      components.add(actor, const HealthComponent(current: 100, max: 100));
      final engine =
          _newEngine(entities: entities, components: components, events: events);

      events.publish(const _OtherEvent());
      engine.register(Rule(
        trigger: _Trigger,
        subjectOf: (event) => (event as _Trigger).actor,
        conditions: [
          const EventCount(
            eventType: _OtherEvent,
            comparison: CountComparison.equal,
            threshold: 1,
          ),
        ],
        effects: [const Damage(10)],
      ));
      events.publish(const _OtherEvent());

      events.publish(_Trigger(actor));

      expect(components.get<HealthComponent>(actor)!.current, equals(90));
    });

    test('the same seed and the same registration/publish order produce the '
        'same outcome', () {
      final resultA = _runRandomRule(seed: 42);
      final resultB = _runRandomRule(seed: 42);

      expect(resultA, equals(resultB));
    });
  });
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `dart test test/rule/rule_engine_test.dart`
Expected: FAIL — `Error: Undefined class 'Rule'`.

- [ ] **Step 3: Implement `Rule`**

Create `lib/src/rule/rule.dart`:
```dart
import '../entity/entity_id.dart';
import 'condition.dart';
import 'effect.dart';

/// A generic `WHEN trigger IF conditions THEN effects` rule, composed
/// entirely from reusable [Condition]/[Effect] building blocks — no
/// content-specific logic lives in this class or in `RuleEngine`.
class Rule {
  const Rule({
    required this.trigger,
    this.subjectOf,
    this.conditions = const [],
    required this.effects,
  });

  /// The event [Type] this rule listens for.
  final Type trigger;

  /// Resolves the entity this rule's conditions/effects act on from the
  /// triggering event instance. `null` (the default) for rules with no
  /// subject (e.g. one that only checks [EventCount]/[RandomChance]).
  final EntityId? Function(Object event)? subjectOf;

  /// Every condition must pass (AND) for [effects] to run.
  final List<Condition> conditions;

  /// Run in list order, only if every condition passes.
  final List<Effect> effects;
}
```

- [ ] **Step 4: Implement `RuleEngine`**

Create `lib/src/rule/rule_engine.dart`:
```dart
import '../component/component_store.dart';
import '../entity/entity_registry.dart';
import '../event/event_bus.dart';
import '../rng/rng_service.dart';
import 'condition.dart';
import 'event_counter.dart';
import 'rule.dart';
import 'rule_context.dart';

/// Registers [Rule]s and dispatches them off the [EventBus]. Deterministic:
/// conditions are evaluated in list order (all must pass), then effects run
/// in list order — no other source of nondeterminism is introduced beyond
/// whatever the injected [RngService] itself produces.
class RuleEngine {
  RuleEngine({
    required EntityRegistry entities,
    required ComponentStore components,
    required EventBus events,
    required RngService rng,
  })  : _entities = entities,
        _components = components,
        _events = events,
        _rng = rng,
        _eventCounts = EventCounter(events);

  final EntityRegistry _entities;
  final ComponentStore _components;
  final EventBus _events;
  final RngService _rng;
  final EventCounter _eventCounts;

  /// Registers [rule], auto-tracking (via `EventCounter.trackType`) the
  /// event type of every [EventCount] condition it uses, then subscribing
  /// to [Rule.trigger] so [rule] fires whenever that event is published.
  void register(Rule rule) {
    for (final condition in rule.conditions) {
      if (condition is EventCount) {
        _eventCounts.trackType(condition.eventType);
      }
    }
    _events.subscribeDynamic(rule.trigger, (event) => _fire(rule, event));
  }

  void _fire(Rule rule, Object event) {
    final subject = rule.subjectOf?.call(event);
    final context = RuleContext(
      subject: subject,
      triggerEvent: event,
      entities: _entities,
      components: _components,
      events: _events,
      rng: _rng,
      eventCounts: _eventCounts,
    );

    final allConditionsPass =
        rule.conditions.every((condition) => condition.evaluate(context));
    if (!allConditionsPass) return;

    for (final effect in rule.effects) {
      effect.apply(context);
    }
  }
}
```

- [ ] **Step 5: Export both new files from the barrel file**

Modify `lib/build_engine.dart`, adding two new export lines. Watch the
ordering carefully: `rule/rule.dart` sorts **before** `rule/rule_context.dart`
(`.` sorts before `_` in `rule.dart` vs `rule_context.dart`), and
`rule/rule_engine.dart` sorts after it:
```dart
export 'src/rule/event_counter.dart';
export 'src/rule/rule.dart';
export 'src/rule/rule_context.dart';
export 'src/rule/rule_engine.dart';
```

- [ ] **Step 6: Run tests to verify they pass, and analyze**

Run:
```bash
dart test test/rule/rule_engine_test.dart
dart analyze
```
Expected: all tests PASS; `dart analyze` reports `No issues found!`.

- [ ] **Step 7: Commit**

```bash
git add lib/src/rule/rule.dart lib/src/rule/rule_engine.dart lib/build_engine.dart test/rule/rule_engine_test.dart
git commit -m "feat: add Rule and RuleEngine"
```

---

### Task 9: Integration test — Event → Rule → Condition → Effect → State change

**Files:**
- Create: `test/integration/rule_engine_end_to_end_test.dart`

**Interfaces:**
- Consumes: everything from Tasks 1–8.
- Produces: nothing new — verification-only, proving the exact chain requested: a real event publish triggers a real rule, whose real conditions gate real effects, which produce a real, observable state change — using actual services throughout, no fakes.

- [ ] **Step 1: Write the integration test**

Create `test/integration/rule_engine_end_to_end_test.dart`:
```dart
import 'package:build_engine/build_engine.dart';
import 'package:test/test.dart';

class _SkillUsed {
  const _SkillUsed(this.actor);
  final EntityId actor;
}

void main() {
  test('Event -> Rule -> Condition -> Effect -> State change, end to end',
      () {
    final events = EventBus();
    final components = ComponentStore();
    final entities = EntityRegistry(events);
    final ruleEngine = RuleEngine(
      entities: entities,
      components: components,
      events: events,
      rng: RngService(1),
    );

    final actor = entities.create();
    components.add(actor, TagSet({'fire', 'dragon'}));
    components.add(actor, const HealthComponent(current: 100, max: 100));

    final damaged = <EntityId>[];
    events.subscribe<EntityDamaged>((event) => damaged.add(event.id));

    ruleEngine.register(Rule(
      trigger: _SkillUsed,
      subjectOf: (event) => (event as _SkillUsed).actor,
      conditions: [HasTag('fire'), HasTag('dragon')],
      effects: [const Damage(10)],
    ));

    events.publish(_SkillUsed(actor));

    expect(components.get<HealthComponent>(actor)!.current, equals(90));
    expect(damaged, equals([actor]));
  });

  test('a rule whose conditions fail leaves state unchanged', () {
    final events = EventBus();
    final components = ComponentStore();
    final entities = EntityRegistry(events);
    final ruleEngine = RuleEngine(
      entities: entities,
      components: components,
      events: events,
      rng: RngService(1),
    );

    final actor = entities.create();
    components.add(actor, TagSet({'ice'}));
    components.add(actor, const HealthComponent(current: 100, max: 100));

    ruleEngine.register(Rule(
      trigger: _SkillUsed,
      subjectOf: (event) => (event as _SkillUsed).actor,
      conditions: [HasTag('fire')],
      effects: [const Damage(10)],
    ));

    events.publish(_SkillUsed(actor));

    expect(components.get<HealthComponent>(actor)!.current, equals(100));
  });

  test('Query Engine finds entities independent of any rule', () {
    final components = ComponentStore();
    const a = EntityId(1);
    const b = EntityId(2);
    components.add(a, TagSet({'enemy'}));
    components.add(a, const HealthComponent(current: 20, max: 100));
    components.add(b, TagSet({'enemy'}));
    components.add(b, const HealthComponent(current: 90, max: 100));
    final engine = QueryEngine(QueryScope(components: components));

    final lowHealthEnemies = engine.evaluate(
      [a, b],
      HasTagQuery('enemy').and(const HealthBelowQuery(50)),
    );

    expect(lowHealthEnemies.toSet(), equals({a}));
  });
}
```

- [ ] **Step 2: Run it and confirm it passes on the first try**

Run: `dart test test/integration/rule_engine_end_to_end_test.dart`
Expected: all 3 tests PASS. (No implementation step needed — every service under test was already implemented in Tasks 1–8. If anything fails, that's a bug in an earlier task; stop and fix the earlier task's implementation, don't patch around it here.)

- [ ] **Step 3: Run the whole suite and analyze**

Run:
```bash
dart test
dart analyze
```
Expected: every test across the whole package PASSes; `dart analyze` reports `No issues found!`.

- [ ] **Step 4: Commit**

```bash
git add test/integration/rule_engine_end_to_end_test.dart
git commit -m "test: add Query/Rule/Condition/Effect end-to-end integration coverage"
```

---

### Task 10: Documentation

**Files:**
- Modify: `ARCHITECTURE.md`

**Interfaces:**
- Consumes: the finished implementation from Tasks 1–9 (this task only documents it).
- Produces: nothing new in `lib/` — this is the plan's final task.

- [ ] **Step 1: Amend `ARCHITECTURE.md`**

Read the current `ARCHITECTURE.md` first to get its exact present content
(it already has a "Plugin system" subsection under "Services implemented
so far" from the foundation pass's own final-review fix wave — leave that
subsection and everything else already there untouched). Make these two
changes:

1. Add five new subsections under "## Services implemented so far", after
   the existing "### Plugin system" subsection:

```markdown
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

### Query / Condition / Rule / Effect Engine (`lib/src/rule/`)
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
beyond whatever `RngService` itself produces. See `PLUGIN_SYSTEM.md`'s
sibling note on how plugins register their own conditions/effects — there
is no registry: the interfaces are simply public, the same way
`GamePlugin` already is.
```

2. In the existing "## What's deliberately not here yet" section, replace
   the current line so it no longer lists services this pass built:

```markdown
Modifier Engine (proper `base + modifiers` stat derivation — `ModifyStat`
is a deliberate stopgap pending it), Spatial/Container Engine, a
dedicated Resource Engine *service* (this pass added only the
`ResourceComponent` data shape), Scheduler, Asset/Data Registry,
Serialization, and any registry/factory/data-driven rule deserialization
mechanism. Each is a separate future subsystem, to be brainstormed and
planned on its own rather than stubbed out speculatively here.
```

- [ ] **Step 2: Final full verification**

Run:
```bash
dart pub get
dart test
dart analyze
```
Expected: `dart pub get` succeeds; every test in the package PASSes; `dart analyze` reports `No issues found!`.

- [ ] **Step 3: Commit**

```bash
git add ARCHITECTURE.md
git commit -m "docs: describe the Query/Condition/Rule/Effect Engine in ARCHITECTURE.md"
```

---

## Self-Review Notes

- **Spec coverage:** every piece of the spec (5 components, `EventBus.subscribeDynamic`,
  `RngService`, `EventCounter`, `Query`/combinators/6 concrete queries/`QueryEngine`,
  `RuleContext`, `Condition`/8 concrete conditions, `Effect`/11 concrete effects
  plus 3 new events, `Rule`/`RuleEngine`, the requested integration proof, and
  the doc update) maps to a task above.
- **Type consistency checked:** `RuleContext`'s field names (`subject`,
  `triggerEvent`, `entities`, `components`, `events`, `rng`, `eventCounts`)
  are used identically across Tasks 6, 7, 8, and 9. Every condition/effect
  constructor signature used in Task 8's and Task 9's tests matches exactly
  what Tasks 6/7 define. `EventBus.subscribeDynamic`'s signature (Task 2) is
  used identically by `EventCounter` (Task 4) and `RuleEngine` (Task 8).
- **Barrel-file ordering:** double-check alphabetical export ordering when
  executing each task's Step 4/5 — several tasks touch adjacent lines (e.g.
  `rule/rule.dart` sorts *before* `rule/rule_context.dart` because `.` sorts
  before `_`, which is easy to get backwards). Getting this wrong doesn't
  break anything functionally (Dart doesn't care about export order), only
  the documented "alphabetical convention" — a task reviewer should flag a
  slip but it isn't a correctness bug.
- **Determinism:** verified by construction — `Rule.conditions`/`.effects`
  are evaluated/run in list order (no unordered `Set`/`Map` iteration in the
  hot path), and `RngService` is the sole randomness source, seeded and
  injected. Task 8's own test asserts same-seed-same-outcome directly.

