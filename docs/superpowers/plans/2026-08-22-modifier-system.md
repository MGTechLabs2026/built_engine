# Modifier System Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add the Modifier Engine to `build_engine`: `Modifier`, `ModifierSource`, `ModifierCollection`, `ModifierResolver`, a deterministic `base → ADD → MULTIPLY → OVERRIDE → MIN → MAX → final` calculation pipeline, priority-within-group ordering, temporary (duration-based) modifiers, and conditional modifiers reusing the existing `Query` system.

**Architecture:** `Modifier` is a plain immutable value carrying `source`/`target`/`stat`/`operation`/`value`/`priority`/`duration`/`condition`. `ModifierCollection` is a single global repository (not per-entity) supporting `add`, `removeBySource`, `activeModifiersFor` (filters by target+stat+expiry+condition), and `tick()` (the only temporary-modifier mechanism — no Scheduler). `ModifierResolver` is a pure function with no storage dependency, implementing the fixed pipeline with its own manual stable sort for deterministic priority-tie-breaking.

**Tech Stack:** Dart (SDK `^3.7.0`), `package:test`, `dart:math`'s `min`/`max` (pure functions, not `Random` — no determinism concern).

**Spec:** `docs/superpowers/specs/2026-08-22-modifier-system-design.md`

All paths below are relative to the repo root: `/Users/m4maxpro/Projects/Tome:RougelikeGame`.

## Global Constraints

- No martial-arts, magic, combat, cultivation, or other game-specific vocabulary anywhere in this package.
- No Spatial/Container Engine, dedicated Resource Engine service, Scheduler, Asset/Data Registry, Serialization, or any registry/factory/data-driven modifier deserialization — out of scope this pass.
- Do NOT rewire `ModifyStat`/`ModifyResource` effects to use `ModifierCollection` — that's a separate future decision, not this pass's job.
- Do NOT extend `PluginContext` to expose `modifiers` — also a future pass.
- `Modifier`'s `condition` field is typed `Query?` (reusing `lib/src/query/query.dart`) — do not invent a new predicate interface.
- `ModifierResolver`'s macro pipeline order (`ADD → MULTIPLY → OVERRIDE → MIN → MAX`) is always fixed regardless of `priority`; `priority` only orders modifiers within their own operation group.
- Determinism: no sequence-number field on `Modifier`. Ties break by position in the input iterable, via an explicit manual stable sort in `ModifierResolver` (never rely on `List.sort`'s stability).
- Every task ends with `dart analyze` zero issues and `dart test` passing, before commit.

---

### Task 1: Modifier data shapes

**Files:**
- Create: `lib/src/modifier/modifier_source.dart`
- Create: `lib/src/modifier/modifier.dart`
- Test: `test/modifier/modifier_test.dart`
- Modify: `lib/build_engine.dart`

**Interfaces:**
- Consumes: `EntityId` (foundation), `Query` (`lib/src/query/query.dart`).
- Produces: `class ModifierSource { const ModifierSource(String id); }` with value equality on `id`; `enum ModifierOperation { add, multiply, override, min, max }`; `class Modifier { const Modifier({required ModifierSource source, required EntityId target, required String stat, required ModifierOperation operation, required num value, int priority = 0, int? duration, Query? condition}); }`. Task 2 (`ModifierResolver`) and Task 3 (`ModifierCollection`) both consume `Modifier`/`ModifierSource`/`ModifierOperation`.

- [ ] **Step 1: Write the failing tests**

Create `test/modifier/modifier_test.dart`:
```dart
import 'package:build_engine/build_engine.dart';
import 'package:test/test.dart';

void main() {
  group('ModifierSource', () {
    test('two sources with the same id are equal', () {
      expect(const ModifierSource('item_a'), equals(const ModifierSource('item_a')));
    });

    test('sources with different ids are not equal', () {
      expect(
        const ModifierSource('item_a'),
        isNot(equals(const ModifierSource('item_b'))),
      );
    });

    test('equal sources have equal hashCodes', () {
      expect(
        const ModifierSource('x').hashCode,
        equals(const ModifierSource('x').hashCode),
      );
    });
  });

  group('Modifier', () {
    test('stores all its fields', () {
      const modifier = Modifier(
        source: ModifierSource('item_a'),
        target: EntityId(1),
        stat: 'damage',
        operation: ModifierOperation.add,
        value: 5,
        priority: 2,
        duration: 3,
      );

      expect(modifier.source, equals(const ModifierSource('item_a')));
      expect(modifier.target, equals(const EntityId(1)));
      expect(modifier.stat, equals('damage'));
      expect(modifier.operation, equals(ModifierOperation.add));
      expect(modifier.value, equals(5));
      expect(modifier.priority, equals(2));
      expect(modifier.duration, equals(3));
      expect(modifier.condition, isNull);
    });

    test('priority defaults to 0 and duration/condition default to null', () {
      const modifier = Modifier(
        source: ModifierSource('item_a'),
        target: EntityId(1),
        stat: 'damage',
        operation: ModifierOperation.add,
        value: 5,
      );

      expect(modifier.priority, equals(0));
      expect(modifier.duration, isNull);
      expect(modifier.condition, isNull);
    });
  });
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `dart test test/modifier/modifier_test.dart`
Expected: FAIL — `Error: Undefined class 'ModifierSource'`.

- [ ] **Step 3: Implement `ModifierSource`**

Create `lib/src/modifier/modifier_source.dart`:
```dart
/// Identifies where a [Modifier] came from, for later bulk removal via
/// `ModifierCollection.removeBySource`. Not tied to `EntityId` — a source
/// can be an item's data id, a rule's identifier, a plugin name, or any
/// other stable string key a caller chooses.
class ModifierSource {
  const ModifierSource(this.id);

  final String id;

  @override
  bool operator ==(Object other) => other is ModifierSource && other.id == id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'ModifierSource($id)';
}
```

- [ ] **Step 4: Implement `ModifierOperation` and `Modifier`**

Create `lib/src/modifier/modifier.dart`:
```dart
import '../entity/entity_id.dart';
import '../query/query.dart';
import 'modifier_source.dart';

/// How a [Modifier] combines with a stat's base value. See
/// `ModifierResolver` for the full calculation pipeline and how each
/// operation behaves.
enum ModifierOperation { add, multiply, override, min, max }

/// A single stat adjustment. Fields match claude.md's MODIFIER SYSTEM
/// section: source, target, stat, operation, value, priority, duration,
/// condition.
class Modifier {
  const Modifier({
    required this.source,
    required this.target,
    required this.stat,
    required this.operation,
    required this.value,
    this.priority = 0,
    this.duration,
    this.condition,
  });

  final ModifierSource source;
  final EntityId target;

  /// An arbitrary, engine-agnostic string key — e.g. "damage", "armor",
  /// "qi". The engine never interprets this value.
  final String stat;

  final ModifierOperation operation;
  final num value;

  /// Orders this modifier relative to others of the SAME [operation] only
  /// — it does not affect which operation group runs first; that order
  /// (add, then multiply, then override, then min, then max) is always
  /// fixed. See `ModifierResolver`.
  final int priority;

  /// Remaining lifetime in `ModifierCollection.tick()` calls. `null` means
  /// permanent. Set once at construction — `ModifierCollection` tracks the
  /// actual countdown separately, since this field stays immutable.
  final int? duration;

  /// If non-null, this modifier only applies while [condition] matches its
  /// [target] — re-evaluated every time it's queried, not cached.
  final Query? condition;
}
```

- [ ] **Step 5: Export both new files from the barrel file**

Modify `lib/build_engine.dart`, adding two new export lines alphabetically. `modifier` sorts after `event` (`e` < `m`) and before `plugin` (`m` < `p`); `modifier.dart` sorts before `modifier_source.dart` (`.` < `_`):
```dart
export 'src/event/event_bus.dart';
export 'src/modifier/modifier.dart';
export 'src/modifier/modifier_source.dart';
export 'src/plugin/game_plugin.dart';
```

- [ ] **Step 6: Run tests to verify they pass, and analyze**

Run:
```bash
dart test test/modifier/modifier_test.dart
dart analyze
```
Expected: all 5 tests PASS; `dart analyze` reports `No issues found!`.

- [ ] **Step 7: Commit**

```bash
git add lib/src/modifier/modifier_source.dart lib/src/modifier/modifier.dart lib/build_engine.dart test/modifier/modifier_test.dart
git commit -m "feat: add ModifierSource, ModifierOperation, and Modifier"
```

---

### Task 2: ModifierResolver

**Files:**
- Create: `lib/src/modifier/modifier_resolver.dart`
- Test: `test/modifier/modifier_resolver_test.dart`
- Modify: `lib/build_engine.dart`

**Interfaces:**
- Consumes: `Modifier`, `ModifierOperation`, `ModifierSource` (Task 1).
- Produces: `class ModifierResolver { const ModifierResolver(); num resolve(num base, Iterable<Modifier> modifiers); }`. Task 3's integration test and Task 4's integration test both consume this.

- [ ] **Step 1: Write the failing tests**

Create `test/modifier/modifier_resolver_test.dart`:
```dart
import 'package:build_engine/build_engine.dart';
import 'package:test/test.dart';

const _source = ModifierSource('test');
const _target = EntityId(1);

Modifier _mod({
  required ModifierOperation operation,
  required num value,
  int priority = 0,
}) =>
    Modifier(
      source: _source,
      target: _target,
      stat: 'stat',
      operation: operation,
      value: value,
      priority: priority,
    );

void main() {
  group('ModifierResolver', () {
    const resolver = ModifierResolver();

    test('with no modifiers, returns the base value unchanged', () {
      expect(resolver.resolve(10, []), equals(10));
    });

    test('ADD modifiers sum together', () {
      final result = resolver.resolve(10, [
        _mod(operation: ModifierOperation.add, value: 5),
        _mod(operation: ModifierOperation.add, value: 3),
      ]);
      expect(result, equals(18));
    });

    test('MULTIPLY modifiers stack as sequential factors', () {
      final result = resolver.resolve(10, [
        _mod(operation: ModifierOperation.multiply, value: 2),
        _mod(operation: ModifierOperation.multiply, value: 1.5),
      ]);
      expect(result, equals(30));
    });

    test('OVERRIDE: the highest-priority modifier wins', () {
      final result = resolver.resolve(10, [
        _mod(operation: ModifierOperation.override, value: 100, priority: 1),
        _mod(operation: ModifierOperation.override, value: 200, priority: 5),
        _mod(operation: ModifierOperation.override, value: 50, priority: 2),
      ]);
      expect(result, equals(200));
    });

    test(
        'MIN modifiers act as a ceiling, tightest wins regardless of order',
        () {
      final result = resolver.resolve(100, [
        _mod(operation: ModifierOperation.min, value: 50, priority: 5),
        _mod(operation: ModifierOperation.min, value: 30, priority: 1),
      ]);
      expect(result, equals(30));
    });

    test(
        'MAX modifiers act as a floor, loosest (highest) wins regardless of '
        'order', () {
      final result = resolver.resolve(10, [
        _mod(operation: ModifierOperation.max, value: 20, priority: 5),
        _mod(operation: ModifierOperation.max, value: 50, priority: 1),
      ]);
      expect(result, equals(50));
    });

    test(
        'the full pipeline runs ADD, then MULTIPLY, then OVERRIDE, then MIN, '
        'then MAX', () {
      // base 10 -> +5 = 15 -> *2 = 30 -> override to 40 -> min(40,35)=35 -> max(35,38)=38
      final result = resolver.resolve(10, [
        _mod(operation: ModifierOperation.add, value: 5),
        _mod(operation: ModifierOperation.multiply, value: 2),
        _mod(operation: ModifierOperation.override, value: 40),
        _mod(operation: ModifierOperation.min, value: 35),
        _mod(operation: ModifierOperation.max, value: 38),
      ]);
      expect(result, equals(38));
    });

    test('priority orders modifiers within an operation group', () {
      final result = resolver.resolve(0, [
        _mod(operation: ModifierOperation.override, value: 1, priority: 10),
        _mod(operation: ModifierOperation.override, value: 2, priority: 1),
      ]);
      // priority 1 applies first (value=1), then priority 10 applies (value=2)
      expect(result, equals(2));
    });

    test('equal-priority modifiers break ties by input order, deterministically',
        () {
      final orderingA = resolver.resolve(0, [
        _mod(operation: ModifierOperation.override, value: 1, priority: 0),
        _mod(operation: ModifierOperation.override, value: 2, priority: 0),
      ]);
      final orderingB = resolver.resolve(0, [
        _mod(operation: ModifierOperation.override, value: 2, priority: 0),
        _mod(operation: ModifierOperation.override, value: 1, priority: 0),
      ]);
      // In each case, the SECOND modifier in the input list wins (applied last).
      expect(orderingA, equals(2));
      expect(orderingB, equals(1));
    });

    test('resolving the same modifiers twice produces the same result', () {
      final modifiers = [
        _mod(operation: ModifierOperation.add, value: 5, priority: 2),
        _mod(operation: ModifierOperation.multiply, value: 1.5, priority: 1),
      ];
      final resultA = resolver.resolve(10, modifiers);
      final resultB = resolver.resolve(10, modifiers);
      expect(resultA, equals(resultB));
    });
  });
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `dart test test/modifier/modifier_resolver_test.dart`
Expected: FAIL — `Error: Undefined class 'ModifierResolver'`.

- [ ] **Step 3: Implement `ModifierResolver`**

Create `lib/src/modifier/modifier_resolver.dart`:
```dart
import 'dart:math' as math;

import 'modifier.dart';

/// Computes a stat's derived value from a base value plus a set of
/// modifiers, via a fixed, deterministic pipeline:
///
/// ```
/// base -> ADD (sum) -> MULTIPLY (product) -> OVERRIDE (highest priority
/// wins) -> MIN (ceiling) -> MAX (floor) -> final value
/// ```
///
/// This macro order is always fixed regardless of any modifier's
/// [Modifier.priority] — priority only orders modifiers within their own
/// operation group. Ties (equal priority, same operation) break by each
/// modifier's position in the `modifiers` iterable passed in — callers
/// (typically `ModifierCollection.activeModifiersFor`) are responsible for
/// providing a stable, meaningful order.
class ModifierResolver {
  const ModifierResolver();

  /// Applies every modifier in [modifiers] to [base], following the fixed
  /// pipeline above. Does not filter by target/stat/condition/expiry —
  /// callers pass in an already-filtered set (see `ModifierCollection`).
  num resolve(num base, Iterable<Modifier> modifiers) {
    final all = modifiers.toList(growable: false);
    var value = base;

    for (final modifier
        in _stableSortByPriority(all.where((m) => m.operation == ModifierOperation.add))) {
      value += modifier.value;
    }

    for (final modifier in _stableSortByPriority(
        all.where((m) => m.operation == ModifierOperation.multiply))) {
      value *= modifier.value;
    }

    for (final modifier in _stableSortByPriority(
        all.where((m) => m.operation == ModifierOperation.override))) {
      value = modifier.value;
    }

    for (final modifier
        in _stableSortByPriority(all.where((m) => m.operation == ModifierOperation.min))) {
      value = math.min(value, modifier.value);
    }

    for (final modifier
        in _stableSortByPriority(all.where((m) => m.operation == ModifierOperation.max))) {
      value = math.max(value, modifier.value);
    }

    return value;
  }

  /// Sorts by ascending [Modifier.priority], breaking ties by each
  /// modifier's original position in [modifiers] — a manual stable sort,
  /// since `List.sort` does not guarantee stability.
  List<Modifier> _stableSortByPriority(Iterable<Modifier> modifiers) {
    final indexed = modifiers.toList(growable: false).asMap().entries.toList();
    indexed.sort((a, b) {
      final priorityCompare = a.value.priority.compareTo(b.value.priority);
      if (priorityCompare != 0) return priorityCompare;
      return a.key.compareTo(b.key);
    });
    return indexed.map((entry) => entry.value).toList(growable: false);
  }
}
```

- [ ] **Step 4: Export it from the barrel file**

Modify `lib/build_engine.dart`, adding the new export line alphabetically (`modifier_resolver.dart` sorts after `modifier_source.dart`? Check: "modifier_resolver" vs "modifier_source" — common prefix "modifier_"; then 'r' vs 's' — 'r' < 's', so `modifier_resolver.dart` sorts BEFORE `modifier_source.dart`):
```dart
export 'src/modifier/modifier.dart';
export 'src/modifier/modifier_resolver.dart';
export 'src/modifier/modifier_source.dart';
```

- [ ] **Step 5: Run tests to verify they pass, and analyze**

Run:
```bash
dart test test/modifier/modifier_resolver_test.dart
dart analyze
```
Expected: all 10 tests PASS; `dart analyze` reports `No issues found!`.

- [ ] **Step 6: Commit**

```bash
git add lib/src/modifier/modifier_resolver.dart lib/build_engine.dart test/modifier/modifier_resolver_test.dart
git commit -m "feat: add ModifierResolver"
```

---

### Task 3: ModifierCollection

**Files:**
- Create: `lib/src/modifier/modifier_collection.dart`
- Test: `test/modifier/modifier_collection_test.dart`
- Modify: `lib/build_engine.dart`

**Interfaces:**
- Consumes: `Modifier`, `ModifierSource` (Task 1); `EntityId`, `ComponentStore` (foundation); `Query`, `QueryScope` (`lib/src/query/query.dart`); `HasTagQuery`, `TagSet` (existing, for the conditional-modifier test).
- Produces: `class ModifierCollection { void add(Modifier); void removeBySource(ModifierSource); Iterable<Modifier> activeModifiersFor(EntityId, String, ComponentStore); void tick(); }`. Task 4's integration test consumes this alongside `ModifierResolver`.

- [ ] **Step 1: Write the failing tests**

Create `test/modifier/modifier_collection_test.dart`:
```dart
import 'package:build_engine/build_engine.dart';
import 'package:test/test.dart';

void main() {
  group('ModifierCollection', () {
    test('activeModifiersFor returns modifiers matching target and stat', () {
      final collection = ModifierCollection();
      const source = ModifierSource('item_a');
      const target = EntityId(1);
      const other = EntityId(2);
      collection.add(Modifier(
        source: source,
        target: target,
        stat: 'damage',
        operation: ModifierOperation.add,
        value: 5,
      ));
      collection.add(Modifier(
        source: source,
        target: other,
        stat: 'damage',
        operation: ModifierOperation.add,
        value: 5,
      ));
      collection.add(Modifier(
        source: source,
        target: target,
        stat: 'armor',
        operation: ModifierOperation.add,
        value: 5,
      ));

      final active =
          collection.activeModifiersFor(target, 'damage', ComponentStore());

      expect(active.length, equals(1));
      expect(active.single.target, equals(target));
      expect(active.single.stat, equals('damage'));
    });

    test('stacking: multiple modifiers on the same target+stat are all returned',
        () {
      final collection = ModifierCollection();
      const target = EntityId(1);
      collection.add(Modifier(
        source: const ModifierSource('a'),
        target: target,
        stat: 'damage',
        operation: ModifierOperation.add,
        value: 5,
      ));
      collection.add(Modifier(
        source: const ModifierSource('b'),
        target: target,
        stat: 'damage',
        operation: ModifierOperation.add,
        value: 3,
      ));

      final active =
          collection.activeModifiersFor(target, 'damage', ComponentStore());

      expect(active.length, equals(2));
    });

    test('removeBySource removes only modifiers from that source', () {
      final collection = ModifierCollection();
      const target = EntityId(1);
      const sourceA = ModifierSource('a');
      const sourceB = ModifierSource('b');
      collection.add(Modifier(
        source: sourceA,
        target: target,
        stat: 'damage',
        operation: ModifierOperation.add,
        value: 5,
      ));
      collection.add(Modifier(
        source: sourceB,
        target: target,
        stat: 'damage',
        operation: ModifierOperation.add,
        value: 3,
      ));

      collection.removeBySource(sourceA);
      final active =
          collection.activeModifiersFor(target, 'damage', ComponentStore());

      expect(active.length, equals(1));
      expect(active.single.source, equals(sourceB));
    });

    test('tick decrements duration and expires modifiers that reach zero', () {
      final collection = ModifierCollection();
      const target = EntityId(1);
      collection.add(Modifier(
        source: const ModifierSource('temp'),
        target: target,
        stat: 'damage',
        operation: ModifierOperation.add,
        value: 5,
        duration: 2,
      ));

      expect(
        collection.activeModifiersFor(target, 'damage', ComponentStore()).length,
        equals(1),
      );

      collection.tick();
      expect(
        collection.activeModifiersFor(target, 'damage', ComponentStore()).length,
        equals(1),
      );

      collection.tick();
      expect(
        collection.activeModifiersFor(target, 'damage', ComponentStore()).length,
        equals(0),
      );
    });

    test('tick does not affect permanent (duration: null) modifiers', () {
      final collection = ModifierCollection();
      const target = EntityId(1);
      collection.add(Modifier(
        source: const ModifierSource('permanent'),
        target: target,
        stat: 'damage',
        operation: ModifierOperation.add,
        value: 5,
      ));

      for (var i = 0; i < 10; i++) {
        collection.tick();
      }

      expect(
        collection.activeModifiersFor(target, 'damage', ComponentStore()).length,
        equals(1),
      );
    });

    test('conditional modifiers: only active when their condition matches', () {
      final collection = ModifierCollection();
      const target = EntityId(1);
      final components = ComponentStore();
      collection.add(Modifier(
        source: const ModifierSource('conditional'),
        target: target,
        stat: 'damage',
        operation: ModifierOperation.add,
        value: 10,
        condition: HasTagQuery('enraged'),
      ));

      expect(
        collection.activeModifiersFor(target, 'damage', components).length,
        equals(0),
      );

      components.add(target, TagSet({'enraged'}));

      expect(
        collection.activeModifiersFor(target, 'damage', components).length,
        equals(1),
      );
    });

    test('activeModifiersFor returns modifiers in registration order', () {
      final collection = ModifierCollection();
      const target = EntityId(1);
      final first = Modifier(
        source: const ModifierSource('first'),
        target: target,
        stat: 'damage',
        operation: ModifierOperation.override,
        value: 1,
      );
      final second = Modifier(
        source: const ModifierSource('second'),
        target: target,
        stat: 'damage',
        operation: ModifierOperation.override,
        value: 2,
      );
      collection.add(first);
      collection.add(second);

      final active =
          collection.activeModifiersFor(target, 'damage', ComponentStore()).toList();

      expect(active, equals([first, second]));
    });
  });
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `dart test test/modifier/modifier_collection_test.dart`
Expected: FAIL — `Error: Undefined class 'ModifierCollection'`.

- [ ] **Step 3: Implement `ModifierCollection`**

Create `lib/src/modifier/modifier_collection.dart`:
```dart
import '../component/component_store.dart';
import '../entity/entity_id.dart';
import '../query/query.dart';
import 'modifier.dart';
import 'modifier_source.dart';

class _ModifierEntry {
  _ModifierEntry(this.modifier) : remainingDuration = modifier.duration;

  final Modifier modifier;
  int? remainingDuration;
}

/// The repository of all registered [Modifier]s, across every entity and
/// stat. Not per-entity — [Modifier] already carries its own `target`.
class ModifierCollection {
  final List<_ModifierEntry> _entries = [];

  /// Registers [modifier]. Its `duration` (if any) starts counting down
  /// from the next [tick] call.
  void add(Modifier modifier) {
    _entries.add(_ModifierEntry(modifier));
  }

  /// Removes every modifier whose `source` equals [source].
  void removeBySource(ModifierSource source) {
    _entries.removeWhere((entry) => entry.modifier.source == source);
  }

  /// Modifiers currently applicable to [target]'s [stat]: matching
  /// target+stat, not yet expired, and whose `condition` (if any) currently
  /// matches via [components]. Returned in registration order — the order
  /// `ModifierResolver` relies on for deterministic tie-breaking.
  Iterable<Modifier> activeModifiersFor(
    EntityId target,
    String stat,
    ComponentStore components,
  ) {
    final scope = QueryScope(components: components);
    return _entries
        .where((entry) {
          final modifier = entry.modifier;
          if (modifier.target != target || modifier.stat != stat) {
            return false;
          }
          final remaining = entry.remainingDuration;
          if (remaining != null && remaining <= 0) {
            return false;
          }
          final condition = modifier.condition;
          if (condition != null && !condition.matches(target, scope)) {
            return false;
          }
          return true;
        })
        .map((entry) => entry.modifier);
  }

  /// Decrements every timed modifier's remaining duration by 1, removing
  /// any that reach 0. Permanent modifiers (`duration == null`) are
  /// untouched. The only mechanism for expiring temporary modifiers — no
  /// Scheduler, no event; a future Scheduler pass calls this, and for now
  /// callers (including tests) call it directly.
  void tick() {
    for (final entry in _entries) {
      final remaining = entry.remainingDuration;
      if (remaining != null) {
        entry.remainingDuration = remaining - 1;
      }
    }
    _entries.removeWhere((entry) {
      final remaining = entry.remainingDuration;
      return remaining != null && remaining <= 0;
    });
  }
}
```

- [ ] **Step 4: Export it from the barrel file**

Modify `lib/build_engine.dart`, adding the new export line alphabetically. `modifier.dart` sorts first (`.` < `_`), then `modifier_collection.dart` (its `c` sorts before the `r` in `modifier_resolver.dart`), then `modifier_resolver.dart`, then `modifier_source.dart`:
```dart
export 'src/modifier/modifier.dart';
export 'src/modifier/modifier_collection.dart';
export 'src/modifier/modifier_resolver.dart';
export 'src/modifier/modifier_source.dart';
```

- [ ] **Step 5: Run tests to verify they pass, and analyze**

Run:
```bash
dart test test/modifier/modifier_collection_test.dart
dart analyze
```
Expected: all 7 tests PASS; `dart analyze` reports `No issues found!`.

- [ ] **Step 6: Commit**

```bash
git add lib/src/modifier/modifier_collection.dart lib/build_engine.dart test/modifier/modifier_collection_test.dart
git commit -m "feat: add ModifierCollection"
```

---

### Task 4: Integration test — ModifierCollection + ModifierResolver end to end

**Files:**
- Create: `test/integration/modifier_system_end_to_end_test.dart`

**Interfaces:**
- Consumes: `ModifierCollection`, `ModifierResolver`, `Modifier`, `ModifierSource`, `ModifierOperation` (Tasks 1–3); `EntityId`, `ComponentStore`, `TagSet`, `HasTagQuery` (existing).
- Produces: nothing new — verification-only, proving stacking, conditional activation, temporary expiry, and removal-by-source all compose correctly together with real (non-fake) services.

- [ ] **Step 1: Write the integration test**

Create `test/integration/modifier_system_end_to_end_test.dart`:
```dart
import 'package:build_engine/build_engine.dart';
import 'package:test/test.dart';

void main() {
  test(
      'ModifierCollection + ModifierResolver: stacking, conditional, and '
      'temporary modifiers resolve correctly end to end', () {
    final collection = ModifierCollection();
    const resolver = ModifierResolver();
    final components = ComponentStore();
    const target = EntityId(1);

    // Permanent flat bonus from equipment.
    collection.add(Modifier(
      source: const ModifierSource('item_sword'),
      target: target,
      stat: 'damage',
      operation: ModifierOperation.add,
      value: 5,
    ));

    // Conditional multiplier, only active while enraged.
    collection.add(Modifier(
      source: const ModifierSource('status_enraged'),
      target: target,
      stat: 'damage',
      operation: ModifierOperation.multiply,
      value: 2,
      condition: HasTagQuery('enraged'),
    ));

    // A temporary buff that expires after 1 tick.
    collection.add(Modifier(
      source: const ModifierSource('buff_adrenaline'),
      target: target,
      stat: 'damage',
      operation: ModifierOperation.add,
      value: 3,
      duration: 1,
    ));

    num currentDamage() => resolver.resolve(
          10,
          collection.activeModifiersFor(target, 'damage', components),
        );

    // Not enraged yet: base 10 + item 5 + buff 3 = 18 (multiplier inactive).
    expect(currentDamage(), equals(18));

    // Become enraged: (10 + 5 + 3) * 2 = 36.
    components.add(target, TagSet({'enraged'}));
    expect(currentDamage(), equals(36));

    // Tick past the buff's duration: (10 + 5) * 2 = 30.
    collection.tick();
    expect(currentDamage(), equals(30));

    // Remove the equipment bonus by source: 10 * 2 = 20.
    collection.removeBySource(const ModifierSource('item_sword'));
    expect(currentDamage(), equals(20));
  });
}
```

- [ ] **Step 2: Run it and confirm it passes on the first try**

Run: `dart test test/integration/modifier_system_end_to_end_test.dart`
Expected: the test PASSes. (No implementation step needed — every service under test was already implemented in Tasks 1–3. If it fails, that's a bug in an earlier task; stop and fix the earlier task's implementation, don't patch around it here.)

- [ ] **Step 3: Run the whole suite and analyze**

Run:
```bash
dart test
dart analyze
```
Expected: every test across the whole package PASSes; `dart analyze` reports `No issues found!`.

- [ ] **Step 4: Commit**

```bash
git add test/integration/modifier_system_end_to_end_test.dart
git commit -m "test: add Modifier System end-to-end integration coverage"
```

---

### Task 5: Documentation

**Files:**
- Modify: `ARCHITECTURE.md`

**Interfaces:**
- Consumes: the finished implementation from Tasks 1–4 (this task only documents it).
- Produces: nothing new in `lib/` — this is the plan's final task.

- [ ] **Step 1: Amend `ARCHITECTURE.md`**

Read the current `ARCHITECTURE.md` first to confirm its exact present content — leave every existing section untouched except the two edits below.

1. Add a new subsection under "## Services implemented so far", immediately after the existing "### Condition / Rule / Effect Engine" subsection:

```markdown
### Modifier Engine (`lib/src/modifier/`)
`Modifier` (`source`, `target`, `stat`, `operation`, `value`, `priority`,
`duration`, `condition` — matching claude.md's MODIFIER SYSTEM field list
exactly) is a plain immutable value; `ModifierSource` is a small string-id
wrapper used for bulk removal, not tied to `EntityId`. `ModifierCollection`
is the single repository of every registered modifier across every entity
and stat (not per-entity) — `add`, `removeBySource`, and
`activeModifiersFor(target, stat, components)` (filtering by target+stat,
expiry, and `condition`, in registration order). `condition` reuses the
existing `Query` system rather than a new predicate type, since a
conditional modifier is a continuous "is this entity in state X" check, not
an event-triggered `Rule` condition. `tick()` is the only mechanism for
temporary modifiers — decrements durations, drops expired ones; no
Scheduler exists yet, so callers invoke it directly.

`ModifierResolver` is a pure function (`resolve(base, modifiers)`) with no
storage dependency, implementing a fixed, documented pipeline:

```
base -> ADD (sum) -> MULTIPLY (product) -> OVERRIDE (highest priority wins)
     -> MIN (ceiling) -> MAX (floor) -> final value
```

`priority` only orders modifiers within their own operation group — it
never changes this macro order. MIN/MAX stacking is order-independent
(`math.min`/`math.max` are associative); only the MIN-before-MAX group
ordering is a fixed, documented convention (relevant only for
contradictory content where a ceiling is below a floor). Ties within a
group (equal priority) break by each modifier's position in the input
iterable — `ModifierResolver` runs its own explicit stable sort rather
than relying on `List.sort`'s unspecified stability, and
`ModifierCollection` naturally hands back modifiers in registration
order, so the whole pipeline is deterministic without any extra
sequence-number field on `Modifier` itself.

`StatComponent`'s "stopgap" status (see above) is unchanged by this pass:
the Modifier Engine now exists, but rewiring the already-shipped
`ModifyStat` effect to route through it is a deliberate, separate design
decision for a future pass, not a mechanical follow-on to this one.
```

2. In "## What's deliberately not here yet", remove "Modifier Engine (proper
   `base + modifiers` stat derivation — `ModifyStat` is a deliberate
   stopgap pending it)," from the list (it's built now), keeping every
   other item in that list exactly as it is.

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
git commit -m "docs: describe the Modifier Engine in ARCHITECTURE.md"
```

---

## Self-Review Notes

- **Spec coverage:** every piece of the spec (`ModifierSource`, `Modifier`,
  `ModifierOperation`, `ModifierResolver`'s full pipeline, `ModifierCollection`'s
  storage/removal/filtering/tick, the integration test, the doc update) maps
  to a task above. All six requested test categories (stacking, removal,
  priority, duration, conditional modifiers, deterministic ordering) are
  covered: stacking (Task 2's ADD/MULTIPLY tests, Task 3's stacking test),
  removal (Task 3's `removeBySource` test), priority (Task 2's
  priority-ordering and tie-break tests), duration (Task 3's `tick` tests),
  conditional modifiers (Task 3's condition test, Task 4's integration
  test), deterministic ordering (Task 2's "same input twice" test and
  tie-break test, Task 3's registration-order test).
- **Type consistency checked:** `Modifier`'s field names (`source`, `target`,
  `stat`, `operation`, `value`, `priority`, `duration`, `condition`) are used
  identically across Tasks 1–4. `ModifierCollection.activeModifiersFor`'s
  signature matches exactly what Task 2's `ModifierResolver.resolve` expects
  as its second argument (`Iterable<Modifier>`) and what Task 4's
  integration test calls.
- **Barrel-file ordering:** four new files under `lib/src/modifier/` — watch
  the ordering carefully per each task's Step 4/5, matching the pattern
  already established in the previous module's plan (`.` sorts before `_`).
- **Determinism:** verified by construction in `ModifierResolver` (manual
  stable sort, no reliance on `List.sort`'s unspecified stability) and in
  `ModifierCollection` (insertion-ordered `List`, `.where()` never reorders).
  `dart:math`'s `min`/`max` are pure, deterministic functions — using them
  outside `rng_service.dart` does not violate the earlier "Random only in
  rng_service.dart" constraint, which was specifically about `Random`.
