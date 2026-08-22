# Spatial/Container System Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add the Spatial/Container Engine to `build_engine`: one generic `Container` class supporting both rectangular grids and arbitrary named slots, `Slot`/`Position`/`SpatialRelation`/`PlacementRule` abstractions, item size + rotation, placement validation, movement, removal, containment, adjacency queries, and self-contained serialization.

**Architecture:** `Container` is a single class with two factory constructors (`.grid`/`.namedSlots`) producing the same underlying structure — a fixed set of `Slot`s, each with a `SlotId` and an optional `Position`. Geometric `SpatialRelation`s operate on `Position` pairs; `distance` is a plain function; `ContainedBy` is `Container.contains`. `PlacementRule` is public/composable (`WithinBounds`, `NoCollision`, plus caller-supplied extras), validated against a minimal `ContainerView` interface to avoid a circular dependency with `Container`. `place`/`move` throw `InvalidPlacementException`; `canPlace` never throws.

**Tech Stack:** Dart (SDK `^3.7.0`), `package:test`.

**Spec:** `docs/superpowers/specs/2026-08-22-spatial-container-system-design.md`

All paths below are relative to the repo root: `/Users/m4maxpro/Projects/Tome:RougelikeGame`.

## Global Constraints

- No martial-arts, magic, combat, cultivation, or other game-specific vocabulary anywhere in this package.
- **No class, file, test, or doc comment anywhere in this module names "Backpack"** (or any of the other future container examples — Tome, Spellbook, Weapon Rack, Equipment Board, Skill Board) as a concrete type. Generic names only: `Container`, `Slot`, `Position`, `SpatialRelation`, `PlacementRule`. Example strings used as test data (e.g. `Container.namedSlots(['head', 'weapon'])`) are fine — those are just string values, not engine types.
- No dedicated Resource Engine service, Scheduler, Asset/Data Registry, or engine-wide Serialization service — out of scope this pass. `Container.toJson`/`fromJson` is this module's own self-contained capability, not an integration point for a future Serialization service.
- Row convention: row 0 is the top; row increases downward.
- `Adjacent` = orthogonal union of `Above`/`Below`/`Left`/`Right` only — never diagonal.
- `distance` is a plain top-level function (Manhattan distance), not a `SpatialRelation`. `ContainedBy` is `Container.contains(EntityId)`, not a `SpatialRelation`.
- No `SpatialRelation` combinators (`and`/`or`/`not`) — not requested, no concrete use case yet.
- `PlacementRule.isSatisfied` takes a `ContainerView` (a minimal `hasSlot`/`itemAt` interface), never the full `Container` class — this is what keeps `placement_rule.dart` free of any dependency on `container.dart`.
- `canPlace` never throws — only `place`/`move` throw `InvalidPlacementException`.
- `move` validates before mutating any state — a rejected move must leave the item at its original position, with zero partial mutation.
- Every task ends with `dart analyze` zero issues and `dart test` passing, before commit.

---

### Task 1: Geometry primitives — Position, ItemSize, Rotation

**Files:**
- Create: `lib/src/spatial/position.dart`
- Test: `test/spatial/position_test.dart`
- Modify: `lib/build_engine.dart`

**Interfaces:**
- Consumes: nothing new.
- Produces: `class Position { const Position(int row, int col); }`; `class ItemSize { const ItemSize(int width, int height); ItemSize rotated(Rotation rotation); }`; `enum Rotation { deg0, deg90, deg180, deg270 }`. Every later task in this plan consumes these.

- [ ] **Step 1: Write the failing tests**

Create `test/spatial/position_test.dart`:
```dart
import 'package:build_engine/build_engine.dart';
import 'package:test/test.dart';

void main() {
  group('Position', () {
    test('two positions with the same row/col are equal', () {
      expect(const Position(1, 2), equals(const Position(1, 2)));
    });

    test('positions with different row or col are not equal', () {
      expect(const Position(1, 2), isNot(equals(const Position(1, 3))));
      expect(const Position(1, 2), isNot(equals(const Position(2, 2))));
    });

    test('equal positions have equal hashCodes', () {
      expect(
        const Position(1, 2).hashCode,
        equals(const Position(1, 2).hashCode),
      );
    });
  });

  group('ItemSize', () {
    test('stores width and height', () {
      const size = ItemSize(2, 3);
      expect(size.width, equals(2));
      expect(size.height, equals(3));
    });

    test('rotated at 0 and 180 degrees keeps the same dimensions', () {
      const size = ItemSize(2, 1);
      expect(size.rotated(Rotation.deg0), equals(const ItemSize(2, 1)));
      expect(size.rotated(Rotation.deg180), equals(const ItemSize(2, 1)));
    });

    test('rotated at 90 and 270 degrees swaps width and height', () {
      const size = ItemSize(2, 1);
      expect(size.rotated(Rotation.deg90), equals(const ItemSize(1, 2)));
      expect(size.rotated(Rotation.deg270), equals(const ItemSize(1, 2)));
    });

    test('equal sizes are equal', () {
      expect(const ItemSize(2, 3), equals(const ItemSize(2, 3)));
    });
  });
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `dart test test/spatial/position_test.dart`
Expected: FAIL — `Error: Undefined class 'Position'`.

- [ ] **Step 3: Implement `Position`, `ItemSize`, `Rotation`**

Create `lib/src/spatial/position.dart`:
```dart
/// A grid coordinate within a `Container`. Row 0 is the top; row increases
/// downward (standard screen/array convention).
class Position {
  const Position(this.row, this.col);

  final int row;
  final int col;

  @override
  bool operator ==(Object other) =>
      other is Position && other.row == row && other.col == col;

  @override
  int get hashCode => Object.hash(row, col);

  @override
  String toString() => 'Position($row, $col)';
}

/// An item's footprint size, in grid cells.
class ItemSize {
  const ItemSize(this.width, this.height);

  final int width;
  final int height;

  /// The effective size after applying [rotation] — width/height swap on
  /// a 90 or 270 degree rotation, unchanged on 0/180. Only the item's
  /// bounding-box dimensions matter here (an axis-aligned rectangle), not
  /// per-cell shape.
  ItemSize rotated(Rotation rotation) {
    switch (rotation) {
      case Rotation.deg0:
      case Rotation.deg180:
        return this;
      case Rotation.deg90:
      case Rotation.deg270:
        return ItemSize(height, width);
    }
  }

  @override
  bool operator ==(Object other) =>
      other is ItemSize && other.width == width && other.height == height;

  @override
  int get hashCode => Object.hash(width, height);

  @override
  String toString() => 'ItemSize($width x $height)';
}

/// How many quarter-turns clockwise an item is rotated.
enum Rotation { deg0, deg90, deg180, deg270 }
```

- [ ] **Step 4: Export it from the barrel file**

Modify `lib/build_engine.dart`, adding the new export line. `spatial` sorts after every existing top-level directory (`rule` < `spatial`, since `r` < `s`), so it becomes the new last line:
```dart
export 'src/rule/rule_engine.dart';
export 'src/spatial/position.dart';
```

- [ ] **Step 5: Run tests to verify they pass, and analyze**

Run:
```bash
dart test test/spatial/position_test.dart
dart analyze
```
Expected: all 7 tests PASS; `dart analyze` reports `No issues found!`.

- [ ] **Step 6: Commit**

```bash
git add lib/src/spatial/position.dart lib/build_engine.dart test/spatial/position_test.dart
git commit -m "feat: add Position, ItemSize, and Rotation"
```

---

### Task 2: SlotId and Slot

**Files:**
- Create: `lib/src/spatial/slot.dart`
- Test: `test/spatial/slot_test.dart`
- Modify: `lib/build_engine.dart`

**Interfaces:**
- Consumes: `Position` (Task 1).
- Produces: `class SlotId { const SlotId(String id); }` with value equality on `id`; `class Slot { const Slot(SlotId id, {Position? position}); }`. `Container` (Task 5) and `PlacementRule` (Task 4) both consume `SlotId`; `Container` consumes `Slot`.

- [ ] **Step 1: Write the failing tests**

Create `test/spatial/slot_test.dart`:
```dart
import 'package:build_engine/build_engine.dart';
import 'package:test/test.dart';

void main() {
  group('SlotId', () {
    test('two ids with the same id are equal', () {
      expect(const SlotId('head'), equals(const SlotId('head')));
    });

    test('ids with different values are not equal', () {
      expect(const SlotId('head'), isNot(equals(const SlotId('weapon'))));
    });

    test('equal ids have equal hashCodes', () {
      expect(const SlotId('x').hashCode, equals(const SlotId('x').hashCode));
    });
  });

  group('Slot', () {
    test('stores its id and position', () {
      const slot = Slot(SlotId('0,0'), position: Position(0, 0));
      expect(slot.id, equals(const SlotId('0,0')));
      expect(slot.position, equals(const Position(0, 0)));
    });

    test('position defaults to null', () {
      const slot = Slot(SlotId('head'));
      expect(slot.position, isNull);
    });
  });
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `dart test test/spatial/slot_test.dart`
Expected: FAIL — `Error: Undefined class 'SlotId'`.

- [ ] **Step 3: Implement `SlotId` and `Slot`**

Create `lib/src/spatial/slot.dart`:
```dart
import 'position.dart';

/// Identifies a single addressable location within a `Container` — the
/// arbitrary "slot ID" a named-slot container is built from (e.g.
/// `SlotId('head')`), or the coordinate-derived ID a grid container
/// assigns each cell (e.g. `SlotId('0,0')`).
class SlotId {
  const SlotId(this.id);

  final String id;

  @override
  bool operator ==(Object other) => other is SlotId && other.id == id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'SlotId($id)';
}

/// One addressable location in a `Container`. [position] is `null` for a
/// non-geometric (named) slot — spatial relations and multi-cell
/// footprints only apply to slots with a [position].
class Slot {
  const Slot(this.id, {this.position});

  final SlotId id;
  final Position? position;
}
```

- [ ] **Step 4: Export it from the barrel file**

Modify `lib/build_engine.dart`, adding the new export line. `slot` sorts after `position` (`p` < `s`):
```dart
export 'src/spatial/position.dart';
export 'src/spatial/slot.dart';
```

- [ ] **Step 5: Run tests to verify they pass, and analyze**

Run:
```bash
dart test test/spatial/slot_test.dart
dart analyze
```
Expected: all 5 tests PASS; `dart analyze` reports `No issues found!`.

- [ ] **Step 6: Commit**

```bash
git add lib/src/spatial/slot.dart lib/build_engine.dart test/spatial/slot_test.dart
git commit -m "feat: add SlotId and Slot"
```

---

### Task 3: SpatialRelation, the 6 concrete relations, and distance

**Files:**
- Create: `lib/src/spatial/spatial_relation.dart`
- Test: `test/spatial/spatial_relation_test.dart`
- Modify: `lib/build_engine.dart`

**Interfaces:**
- Consumes: `Position` (Task 1).
- Produces: `abstract class SpatialRelation { bool holds(Position a, Position b); }`; `Above()`, `Below()`, `Left()`, `Right()`, `Adjacent()`, `SameRow()`, `SameColumn()` (each `implements SpatialRelation`); `int distance(Position a, Position b)`. `Container.relatesTo` (Task 5) consumes `SpatialRelation`.

- [ ] **Step 1: Write the failing tests**

Create `test/spatial/spatial_relation_test.dart`:
```dart
import 'package:build_engine/build_engine.dart';
import 'package:test/test.dart';

void main() {
  group('Above / Below', () {
    test('Above holds when a is exactly one row above b, same column', () {
      expect(
        const Above().holds(const Position(0, 1), const Position(1, 1)),
        isTrue,
      );
    });

    test('Above does not hold in the reverse direction', () {
      expect(
        const Above().holds(const Position(1, 1), const Position(0, 1)),
        isFalse,
      );
    });

    test('Below holds when a is exactly one row below b, same column', () {
      expect(
        const Below().holds(const Position(1, 1), const Position(0, 1)),
        isTrue,
      );
    });

    test('Above(a,b) and Below(b,a) agree', () {
      const a = Position(0, 1);
      const b = Position(1, 1);
      expect(const Above().holds(a, b), equals(const Below().holds(b, a)));
    });
  });

  group('Left / Right', () {
    test('Left holds when a is exactly one column left of b, same row', () {
      expect(
        const Left().holds(const Position(2, 0), const Position(2, 1)),
        isTrue,
      );
    });

    test('Right holds when a is exactly one column right of b, same row',
        () {
      expect(
        const Right().holds(const Position(2, 1), const Position(2, 0)),
        isTrue,
      );
    });

    test('Left(a,b) and Right(b,a) agree', () {
      const a = Position(2, 0);
      const b = Position(2, 1);
      expect(const Left().holds(a, b), equals(const Right().holds(b, a)));
    });
  });

  group('Adjacent', () {
    test('holds for each of the four orthogonal neighbors', () {
      const center = Position(1, 1);
      expect(const Adjacent().holds(const Position(0, 1), center), isTrue);
      expect(const Adjacent().holds(const Position(2, 1), center), isTrue);
      expect(const Adjacent().holds(const Position(1, 0), center), isTrue);
      expect(const Adjacent().holds(const Position(1, 2), center), isTrue);
    });

    test('does not hold for a diagonal neighbor', () {
      expect(
        const Adjacent().holds(const Position(0, 0), const Position(1, 1)),
        isFalse,
      );
    });

    test('is symmetric', () {
      const a = Position(0, 1);
      const b = Position(1, 1);
      expect(
        const Adjacent().holds(a, b),
        equals(const Adjacent().holds(b, a)),
      );
    });

    test('does not hold for the same position', () {
      const a = Position(1, 1);
      expect(const Adjacent().holds(a, a), isFalse);
    });
  });

  group('SameRow / SameColumn', () {
    test('SameRow holds for two positions in the same row', () {
      expect(
        const SameRow().holds(const Position(2, 0), const Position(2, 5)),
        isTrue,
      );
    });

    test('SameRow does not hold for different rows', () {
      expect(
        const SameRow().holds(const Position(2, 0), const Position(3, 0)),
        isFalse,
      );
    });

    test('SameColumn holds for two positions in the same column', () {
      expect(
        const SameColumn().holds(const Position(0, 4), const Position(5, 4)),
        isTrue,
      );
    });

    test('SameColumn does not hold for different columns', () {
      expect(
        const SameColumn().holds(const Position(0, 4), const Position(0, 5)),
        isFalse,
      );
    });
  });

  group('distance', () {
    test('is the Manhattan distance between two positions', () {
      expect(distance(const Position(0, 0), const Position(3, 4)), equals(7));
    });

    test('is zero for the same position', () {
      expect(distance(const Position(2, 2), const Position(2, 2)), equals(0));
    });

    test('matches adjacency: distance 1 means orthogonally adjacent', () {
      const a = Position(1, 1);
      const b = Position(1, 2);
      expect(distance(a, b), equals(1));
      expect(const Adjacent().holds(a, b), isTrue);
    });
  });
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `dart test test/spatial/spatial_relation_test.dart`
Expected: FAIL — `Error: Undefined class 'Above'`.

- [ ] **Step 3: Implement `SpatialRelation` and its concrete relations**

Create `lib/src/spatial/spatial_relation.dart`:
```dart
import 'position.dart';

/// A boolean relation between two positions. Combinators (`and`/`or`/
/// `not`) are deliberately not provided — unlike `Query`, composability
/// wasn't requested here and there's no concrete use case yet.
abstract class SpatialRelation {
  bool holds(Position a, Position b);
}

/// Whether [a] is exactly one row above [b], in the same column. Row 0 is
/// the top; row increases downward.
class Above implements SpatialRelation {
  const Above();

  @override
  bool holds(Position a, Position b) => a.row == b.row - 1 && a.col == b.col;
}

/// Whether [a] is exactly one row below [b], in the same column.
class Below implements SpatialRelation {
  const Below();

  @override
  bool holds(Position a, Position b) => a.row == b.row + 1 && a.col == b.col;
}

/// Whether [a] is exactly one column to the left of [b], in the same row.
class Left implements SpatialRelation {
  const Left();

  @override
  bool holds(Position a, Position b) => a.col == b.col - 1 && a.row == b.row;
}

/// Whether [a] is exactly one column to the right of [b], in the same row.
class Right implements SpatialRelation {
  const Right();

  @override
  bool holds(Position a, Position b) => a.col == b.col + 1 && a.row == b.row;
}

/// Whether [a] and [b] are orthogonally adjacent — one of [Above],
/// [Below], [Left], or [Right] — never diagonal.
class Adjacent implements SpatialRelation {
  const Adjacent();

  @override
  bool holds(Position a, Position b) =>
      const Above().holds(a, b) ||
      const Below().holds(a, b) ||
      const Left().holds(a, b) ||
      const Right().holds(a, b);
}

/// Whether [a] and [b] are in the same row.
class SameRow implements SpatialRelation {
  const SameRow();

  @override
  bool holds(Position a, Position b) => a.row == b.row;
}

/// Whether [a] and [b] are in the same column.
class SameColumn implements SpatialRelation {
  const SameColumn();

  @override
  bool holds(Position a, Position b) => a.col == b.col;
}

/// Manhattan distance between [a] and [b] — not a boolean relation
/// (unlike the seven [SpatialRelation]s above), since it isn't one.
int distance(Position a, Position b) =>
    (a.row - b.row).abs() + (a.col - b.col).abs();
```

- [ ] **Step 4: Export it from the barrel file**

Modify `lib/build_engine.dart`, adding the new export line. `spatial_relation` sorts after `slot` (`sl` < `sp`):
```dart
export 'src/spatial/slot.dart';
export 'src/spatial/spatial_relation.dart';
```

- [ ] **Step 5: Run tests to verify they pass, and analyze**

Run:
```bash
dart test test/spatial/spatial_relation_test.dart
dart analyze
```
Expected: all 15 tests PASS; `dart analyze` reports `No issues found!`.

- [ ] **Step 6: Commit**

```bash
git add lib/src/spatial/spatial_relation.dart lib/build_engine.dart test/spatial/spatial_relation_test.dart
git commit -m "feat: add SpatialRelation, its 6 concrete relations, and distance"
```

---

### Task 4: PlacementRule, ContainerView, and InvalidPlacementException

**Files:**
- Create: `lib/src/spatial/placement_rule.dart`
- Create: `lib/src/spatial/placement_exception.dart`
- Test: `test/spatial/placement_rule_test.dart`
- Test: `test/spatial/placement_exception_test.dart`
- Modify: `lib/build_engine.dart`

**Interfaces:**
- Consumes: `EntityId` (foundation), `SlotId` (Task 2).
- Produces: `abstract class ContainerView { bool hasSlot(SlotId id); EntityId? itemAt(SlotId id); }`; `abstract class PlacementRule { bool isSatisfied(ContainerView container, EntityId item, Set<SlotId> footprint); }`; `WithinBounds()`, `NoCollision()` (each `implements PlacementRule`); `class InvalidPlacementException implements Exception { const InvalidPlacementException(List<String> failedRules); }`. `Container` (Task 5) `implements ContainerView` and consumes `PlacementRule`/`WithinBounds`/`NoCollision`/`InvalidPlacementException` — but **this task's own files have zero dependency on `container.dart`**, which doesn't exist until Task 5. `ContainerView` is defined here specifically so `placement_rule.dart` never needs to import `container.dart` — this is the mechanism that avoids a circular dependency between `Container` and `PlacementRule` (`Container` implements `ContainerView`; `PlacementRule` only ever sees the narrower interface). This is not a forward-reference workaround like earlier passes needed — there is no ordering issue here at all, since this task doesn't reference `Container` in any form.

- [ ] **Step 1: Write the failing tests**

Create `test/spatial/placement_rule_test.dart`:
```dart
import 'package:build_engine/build_engine.dart';
import 'package:test/test.dart';

class _FakeContainer implements ContainerView {
  _FakeContainer(this._slots, this._occupants);

  final Set<SlotId> _slots;
  final Map<SlotId, EntityId> _occupants;

  @override
  bool hasSlot(SlotId id) => _slots.contains(id);

  @override
  EntityId? itemAt(SlotId id) => _occupants[id];
}

void main() {
  group('WithinBounds', () {
    test('is satisfied when every slot in the footprint exists', () {
      final container =
          _FakeContainer({const SlotId('a'), const SlotId('b')}, {});
      expect(
        const WithinBounds().isSatisfied(
          container,
          const EntityId(1),
          {const SlotId('a'), const SlotId('b')},
        ),
        isTrue,
      );
    });

    test('is not satisfied when a slot in the footprint does not exist', () {
      final container = _FakeContainer({const SlotId('a')}, {});
      expect(
        const WithinBounds().isSatisfied(
          container,
          const EntityId(1),
          {const SlotId('a'), const SlotId('missing')},
        ),
        isFalse,
      );
    });
  });

  group('NoCollision', () {
    test('is satisfied when every slot in the footprint is empty', () {
      final container = _FakeContainer({const SlotId('a')}, {});
      expect(
        const NoCollision().isSatisfied(
          container,
          const EntityId(1),
          {const SlotId('a')},
        ),
        isTrue,
      );
    });

    test('is not satisfied when a slot is occupied by a different item', () {
      final container = _FakeContainer(
        {const SlotId('a')},
        {const SlotId('a'): const EntityId(2)},
      );
      expect(
        const NoCollision().isSatisfied(
          container,
          const EntityId(1),
          {const SlotId('a')},
        ),
        isFalse,
      );
    });

    test(
        'is satisfied when a slot is occupied by the item itself '
        '(re-validating a move)', () {
      final container = _FakeContainer(
        {const SlotId('a')},
        {const SlotId('a'): const EntityId(1)},
      );
      expect(
        const NoCollision().isSatisfied(
          container,
          const EntityId(1),
          {const SlotId('a')},
        ),
        isTrue,
      );
    });
  });
}
```

Create `test/spatial/placement_exception_test.dart`:
```dart
import 'package:build_engine/build_engine.dart';
import 'package:test/test.dart';

void main() {
  group('InvalidPlacementException', () {
    test('stores the failed rule names', () {
      const exception =
          InvalidPlacementException(['WithinBounds', 'NoCollision']);
      expect(exception.failedRules, equals(['WithinBounds', 'NoCollision']));
    });

    test('toString names the failed rules', () {
      const exception = InvalidPlacementException(['WithinBounds']);
      expect(exception.toString(), contains('WithinBounds'));
    });
  });
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `dart test test/spatial/placement_rule_test.dart test/spatial/placement_exception_test.dart`
Expected: FAIL — `Error: Undefined class 'ContainerView'`.

- [ ] **Step 3: Implement `PlacementRule`, `ContainerView`, `WithinBounds`, `NoCollision`**

Create `lib/src/spatial/placement_rule.dart`:
```dart
import '../entity/entity_id.dart';
import 'slot.dart';

/// The read-only container access a [PlacementRule] needs to validate a
/// footprint, without depending on the full `Container` class — kept
/// deliberately minimal so this file has no dependency on `container.dart`
/// at all (`Container` implements this interface instead).
abstract class ContainerView {
  bool hasSlot(SlotId id);
  EntityId? itemAt(SlotId id);
}

/// A composable, extensible placement validation check — plugins add
/// content-specific rules ("only weapons in the Weapon Rack") by
/// implementing this directly, no engine change required. `Container`
/// always ANDs [WithinBounds] and [NoCollision] with any extra rules a
/// caller supplies, the same way `Rule.conditions` are ANDed.
abstract class PlacementRule {
  bool isSatisfied(
    ContainerView container,
    EntityId item,
    Set<SlotId> footprint,
  );
}

/// Every slot in the footprint must actually exist in the container. This
/// is also how an unsupported placement (e.g. a multi-cell footprint
/// anchored on a position-less named slot) fails cleanly — the computed
/// footprint contains an id the container doesn't have.
class WithinBounds implements PlacementRule {
  const WithinBounds();

  @override
  bool isSatisfied(
    ContainerView container,
    EntityId item,
    Set<SlotId> footprint,
  ) =>
      footprint.every(container.hasSlot);
}

/// Every slot in the footprint must be either empty or already occupied
/// by [item] itself — so re-validating a move doesn't reject an item
/// against its own current position.
class NoCollision implements PlacementRule {
  const NoCollision();

  @override
  bool isSatisfied(
    ContainerView container,
    EntityId item,
    Set<SlotId> footprint,
  ) =>
      footprint.every((id) {
        final occupant = container.itemAt(id);
        return occupant == null || occupant == item;
      });
}
```

- [ ] **Step 4: Implement `InvalidPlacementException`**

Create `lib/src/spatial/placement_exception.dart`:
```dart
/// Thrown by `Container.place`/`Container.move` when the placement would
/// violate one or more `PlacementRule`s. `canPlace` never throws this —
/// it only returns `bool`.
class InvalidPlacementException implements Exception {
  const InvalidPlacementException(this.failedRules);

  /// The runtime type names of every `PlacementRule` that rejected the
  /// placement.
  final List<String> failedRules;

  @override
  String toString() =>
      'InvalidPlacementException: failed rules: ${failedRules.join(', ')}';
}
```

- [ ] **Step 5: Export both new files from the barrel file**

Modify `lib/build_engine.dart`. Both new files sort BEFORE `position.dart` (`placement_...` < `position`, since `l` < `o` at the first differing character) — and `placement_exception` sorts before `placement_rule` (`e` < `r`):
```dart
export 'src/rule/rule_engine.dart';
export 'src/spatial/placement_exception.dart';
export 'src/spatial/placement_rule.dart';
export 'src/spatial/position.dart';
export 'src/spatial/slot.dart';
export 'src/spatial/spatial_relation.dart';
```

- [ ] **Step 6: Run tests to verify they pass, and analyze**

Run:
```bash
dart test test/spatial/placement_rule_test.dart test/spatial/placement_exception_test.dart
dart analyze
```
Expected: all 5 tests PASS; `dart analyze` reports `No issues found!`.

- [ ] **Step 7: Commit**

```bash
git add lib/src/spatial/placement_rule.dart lib/src/spatial/placement_exception.dart lib/build_engine.dart test/spatial/placement_rule_test.dart test/spatial/placement_exception_test.dart
git commit -m "feat: add PlacementRule, ContainerView, and InvalidPlacementException"
```

---

### Task 5: Container — construction, placement, movement, removal, queries

**Files:**
- Create: `lib/src/spatial/container.dart`
- Test: `test/spatial/container_test.dart`
- Modify: `lib/build_engine.dart`

**Interfaces:**
- Consumes: `EntityId` (foundation); `Position`, `ItemSize`, `Rotation` (Task 1); `SlotId`, `Slot` (Task 2); `SpatialRelation` (Task 3); `ContainerView`, `PlacementRule`, `WithinBounds`, `NoCollision` (Task 4); `InvalidPlacementException` (Task 4).
- Produces: `class Container implements ContainerView`, with `Container(List<Slot> slots)`, `factory Container.grid(int width, int height)`, `factory Container.namedSlots(Iterable<String> ids)`, `hasSlot`, `positionOf`, `itemAt`, `contains`, `canPlace`, `place`, `remove`, `move`, `relatesTo`. Task 6 (serialization) modifies this same file to add `toJson`/`fromJson`. Task 7's integration test and Task 8's docs both consume this class.

This task does **not** implement `toJson`/`fromJson` — that's Task 6, modifying this same file afterward.

- [ ] **Step 1: Write the failing tests**

Create `test/spatial/container_test.dart`:
```dart
import 'package:build_engine/build_engine.dart';
import 'package:test/test.dart';

class _AlwaysReject implements PlacementRule {
  @override
  bool isSatisfied(
    ContainerView container,
    EntityId item,
    Set<SlotId> footprint,
  ) =>
      false;
}

void main() {
  group('Container.grid construction', () {
    test('creates one slot per cell with a position', () {
      final container = Container.grid(2, 2);
      expect(container.hasSlot(const SlotId('0,0')), isTrue);
      expect(container.hasSlot(const SlotId('1,1')), isTrue);
      expect(container.hasSlot(const SlotId('2,0')), isFalse);
    });
  });

  group('Container.namedSlots construction', () {
    test('creates one slot per given id, with no position', () {
      final container = Container.namedSlots(['head', 'weapon']);
      expect(container.hasSlot(const SlotId('head')), isTrue);
      expect(container.hasSlot(const SlotId('weapon')), isTrue);
      expect(container.hasSlot(const SlotId('feet')), isFalse);
    });
  });

  group('placement', () {
    test('places a 1x1 item on a grid container', () {
      final container = Container.grid(3, 3);
      const item = EntityId(1);

      container.place(item, const SlotId('0,0'));

      expect(container.itemAt(const SlotId('0,0')), equals(item));
      expect(container.contains(item), isTrue);
      expect(container.positionOf(item), equals(const Position(0, 0)));
    });

    test('places a multi-cell item, occupying its full footprint', () {
      final container = Container.grid(3, 3);
      const item = EntityId(1);

      container.place(item, const SlotId('0,0'), size: const ItemSize(2, 1));

      expect(container.itemAt(const SlotId('0,0')), equals(item));
      expect(container.itemAt(const SlotId('0,1')), equals(item));
      expect(container.itemAt(const SlotId('1,0')), isNull);
    });

    test('places an item on a named slot', () {
      final container = Container.namedSlots(['head', 'weapon']);
      const item = EntityId(1);

      container.place(item, const SlotId('head'));

      expect(container.itemAt(const SlotId('head')), equals(item));
      expect(container.positionOf(item), isNull);
    });

    test('canPlace returns true without mutating the container', () {
      final container = Container.grid(3, 3);
      const item = EntityId(1);

      expect(container.canPlace(item, const SlotId('0,0')), isTrue);
      expect(container.contains(item), isFalse);
    });

    test('place throws InvalidPlacementException when canPlace would be '
        'false', () {
      final container = Container.grid(1, 1);
      const item = EntityId(1);

      expect(
        () => container.place(
          item,
          const SlotId('0,0'),
          size: const ItemSize(2, 2),
        ),
        throwsA(isA<InvalidPlacementException>()),
      );
    });

    test('an extra PlacementRule can reject a placement canPlace would '
        'otherwise allow', () {
      final container = Container.grid(3, 3);
      const item = EntityId(1);

      expect(
        container.canPlace(
          item,
          const SlotId('0,0'),
          extraRules: [_AlwaysReject()],
        ),
        isFalse,
      );
    });
  });

  group('collision', () {
    test('rejects placing a second item overlapping the first', () {
      final container = Container.grid(3, 3);
      container.place(
        const EntityId(1),
        const SlotId('0,0'),
        size: const ItemSize(2, 1),
      );

      expect(
        container.canPlace(const EntityId(2), const SlotId('0,1')),
        isFalse,
      );
    });

    test('allows placing a second item that does not overlap the first', () {
      final container = Container.grid(3, 3);
      container.place(
        const EntityId(1),
        const SlotId('0,0'),
        size: const ItemSize(2, 1),
      );

      expect(
        container.canPlace(const EntityId(2), const SlotId('1,0')),
        isTrue,
      );
    });
  });

  group('movement', () {
    test('moves an item to a new position', () {
      final container = Container.grid(3, 3);
      const item = EntityId(1);
      container.place(item, const SlotId('0,0'));

      container.move(item, const SlotId('2,2'));

      expect(container.itemAt(const SlotId('0,0')), isNull);
      expect(container.itemAt(const SlotId('2,2')), equals(item));
      expect(container.positionOf(item), equals(const Position(2, 2)));
    });

    test('a rejected move leaves the item at its original position '
        'unchanged', () {
      final container = Container.grid(3, 3);
      const item = EntityId(1);
      const blocker = EntityId(2);
      container.place(item, const SlotId('0,0'));
      container.place(blocker, const SlotId('2,2'));

      expect(
        () => container.move(item, const SlotId('2,2')),
        throwsA(isA<InvalidPlacementException>()),
      );
      expect(container.itemAt(const SlotId('0,0')), equals(item));
      expect(container.positionOf(item), equals(const Position(0, 0)));
    });

    test('moving an item to overlap its own current footprint succeeds', () {
      final container = Container.grid(3, 3);
      const item = EntityId(1);
      container.place(item, const SlotId('0,0'), size: const ItemSize(2, 1));

      container.move(item, const SlotId('0,1'), size: const ItemSize(2, 1));

      expect(container.itemAt(const SlotId('0,1')), equals(item));
      expect(container.itemAt(const SlotId('0,2')), equals(item));
      expect(container.itemAt(const SlotId('0,0')), isNull);
    });
  });

  group('removal', () {
    test('removes an item, freeing every slot it occupied', () {
      final container = Container.grid(3, 3);
      const item = EntityId(1);
      container.place(item, const SlotId('0,0'), size: const ItemSize(2, 1));

      container.remove(item);

      expect(container.itemAt(const SlotId('0,0')), isNull);
      expect(container.itemAt(const SlotId('0,1')), isNull);
      expect(container.contains(item), isFalse);
    });

    test('removing an item not in the container is a no-op', () {
      final container = Container.grid(3, 3);
      expect(() => container.remove(const EntityId(1)), returnsNormally);
    });
  });

  group('adjacency (relatesTo)', () {
    test('relatesTo reports Adjacent between two items in neighboring '
        'cells', () {
      final container = Container.grid(3, 3);
      container.place(const EntityId(1), const SlotId('1,1'));
      container.place(const EntityId(2), const SlotId('1,2'));

      expect(
        container.relatesTo(
          const Adjacent(),
          const EntityId(1),
          const EntityId(2),
        ),
        isTrue,
      );
    });

    test('relatesTo is false when one item has no position', () {
      final container = Container.namedSlots(['head', 'weapon']);
      container.place(const EntityId(1), const SlotId('head'));
      container.place(const EntityId(2), const SlotId('weapon'));

      expect(
        container.relatesTo(
          const Adjacent(),
          const EntityId(1),
          const EntityId(2),
        ),
        isFalse,
      );
    });
  });

  group('rotation', () {
    test('a rotated item occupies the swapped footprint', () {
      final container = Container.grid(3, 3);
      const item = EntityId(1);

      container.place(
        item,
        const SlotId('0,0'),
        size: const ItemSize(2, 1),
        rotation: Rotation.deg90,
      );

      // Effective size after 90 degrees: (1, 2) — 1 column, 2 rows.
      expect(container.itemAt(const SlotId('0,0')), equals(item));
      expect(container.itemAt(const SlotId('1,0')), equals(item));
      expect(container.itemAt(const SlotId('0,1')), isNull);
    });
  });

  group('boundaries', () {
    test('rejects a placement extending past the grid edge', () {
      final container = Container.grid(2, 2);
      expect(
        container.canPlace(
          const EntityId(1),
          const SlotId('1,1'),
          size: const ItemSize(2, 2),
        ),
        isFalse,
      );
    });

    test('rejects an unsupported size on a named (position-less) slot', () {
      final container = Container.namedSlots(['head']);
      expect(
        container.canPlace(
          const EntityId(1),
          const SlotId('head'),
          size: const ItemSize(2, 1),
        ),
        isFalse,
      );
    });

    test('rejects placing on a slot id that does not exist', () {
      final container = Container.grid(2, 2);
      expect(
        container.canPlace(const EntityId(1), const SlotId('9,9')),
        isFalse,
      );
    });
  });
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `dart test test/spatial/container_test.dart`
Expected: FAIL — `Error: Undefined class 'Container'`.

- [ ] **Step 3: Implement `Container`**

Create `lib/src/spatial/container.dart`:
```dart
import '../entity/entity_id.dart';
import 'placement_exception.dart';
import 'placement_rule.dart';
import 'position.dart';
import 'slot.dart';
import 'spatial_relation.dart';

class _Placement {
  const _Placement(this.anchor, this.size, this.rotation, this.footprint);

  final SlotId anchor;
  final ItemSize size;
  final Rotation rotation;
  final Set<SlotId> footprint;
}

/// A generic, content-agnostic collection of addressable [Slot]s that
/// [EntityId] items can be placed into, moved between, and removed from.
/// The engine has no idea what an item "means" — it only tracks where
/// entities are, never what they represent.
///
/// Both a rectangular grid (via [Container.grid]) and an arbitrary set of
/// named slots (via [Container.namedSlots]) are the SAME underlying
/// structure — there is no separate grid/named-slot subclass. This is
/// what makes future containers (a backpack, a tome, a weapon rack, an
/// equipment board) just different factory calls with their own content,
/// with zero container-shape-specific code in this class.
class Container implements ContainerView {
  Container(List<Slot> slots)
      : _slots = {for (final slot in slots) slot.id: slot};

  /// A rectangular grid container: one slot per cell, `SlotId` derived
  /// from its `"row,col"` coordinates, each with a non-null [Position].
  factory Container.grid(int width, int height) {
    final slots = <Slot>[];
    for (var row = 0; row < height; row++) {
      for (var col = 0; col < width; col++) {
        slots.add(Slot(SlotId('$row,$col'), position: Position(row, col)));
      }
    }
    return Container(slots);
  }

  /// A container with an arbitrary, fixed set of named slots, each with
  /// no [Position] — only a 1x1 item at [Rotation.deg0] can ever be
  /// placed on one (see [_footprintFor]).
  factory Container.namedSlots(Iterable<String> ids) =>
      Container([for (final id in ids) Slot(SlotId(id))]);

  final Map<SlotId, Slot> _slots;
  final Map<SlotId, EntityId> _occupants = {};
  final Map<EntityId, _Placement> _placements = {};

  @override
  bool hasSlot(SlotId id) => _slots.containsKey(id);

  /// The [Position] of [item]'s anchor slot, or `null` if [item] isn't in
  /// this container, or its anchor slot has no position.
  Position? positionOf(EntityId item) {
    final placement = _placements[item];
    if (placement == null) return null;
    return _slots[placement.anchor]?.position;
  }

  @override
  EntityId? itemAt(SlotId id) => _occupants[id];

  /// Entity-to-container membership — the `ContainedBy` spatial query.
  bool contains(EntityId item) => _placements.containsKey(item);

  /// Whether [item] could be placed at [anchor] with [size]/[rotation],
  /// checking [WithinBounds], [NoCollision], and every rule in
  /// [extraRules]. Never throws.
  bool canPlace(
    EntityId item,
    SlotId anchor, {
    ItemSize size = const ItemSize(1, 1),
    Rotation rotation = Rotation.deg0,
    List<PlacementRule> extraRules = const [],
  }) {
    final footprint = _footprintFor(anchor, size, rotation);
    if (footprint == null) return false;
    return _allRules(extraRules)
        .every((rule) => rule.isSatisfied(this, item, footprint));
  }

  /// Places [item] at [anchor]. Throws [InvalidPlacementException] if
  /// [canPlace] would return false for the same arguments.
  void place(
    EntityId item,
    SlotId anchor, {
    ItemSize size = const ItemSize(1, 1),
    Rotation rotation = Rotation.deg0,
    List<PlacementRule> extraRules = const [],
  }) {
    final footprint = _footprintFor(anchor, size, rotation);
    final failed = _failedRules(footprint, item, extraRules);
    if (failed.isNotEmpty) {
      throw InvalidPlacementException(failed);
    }
    for (final id in footprint!) {
      _occupants[id] = item;
    }
    _placements[item] = _Placement(anchor, size, rotation, footprint);
  }

  /// Removes [item], freeing every slot it occupied. A no-op if [item]
  /// isn't in this container.
  void remove(EntityId item) {
    final placement = _placements.remove(item);
    if (placement == null) return;
    for (final id in placement.footprint) {
      _occupants.remove(id);
    }
  }

  /// Moves [item] to [newAnchor]. Throws [InvalidPlacementException] if
  /// the new placement would be invalid — [item] is left at its original
  /// position unchanged in that case (atomic, no partial mutation, since
  /// validation runs entirely before any mutation below).
  void move(
    EntityId item,
    SlotId newAnchor, {
    ItemSize size = const ItemSize(1, 1),
    Rotation rotation = Rotation.deg0,
    List<PlacementRule> extraRules = const [],
  }) {
    final current = _placements[item];
    if (current == null) {
      throw const InvalidPlacementException(['NotInContainer']);
    }
    final footprint = _footprintFor(newAnchor, size, rotation);
    final failed = _failedRules(footprint, item, extraRules);
    if (failed.isNotEmpty) {
      throw InvalidPlacementException(failed);
    }
    for (final id in current.footprint) {
      _occupants.remove(id);
    }
    for (final id in footprint!) {
      _occupants[id] = item;
    }
    _placements[item] = _Placement(newAnchor, size, rotation, footprint);
  }

  /// Whether [relation] holds between [a]'s and [b]'s positions. `false`
  /// if either item isn't in this container, or has no position (e.g. a
  /// named slot).
  bool relatesTo(SpatialRelation relation, EntityId a, EntityId b) {
    final posA = positionOf(a);
    final posB = positionOf(b);
    if (posA == null || posB == null) return false;
    return relation.holds(posA, posB);
  }

  /// The footprint [anchor]+[size]+[rotation] would occupy, or `null` if
  /// [anchor] doesn't exist, or is a position-less slot and the requested
  /// size/rotation isn't the trivial 1x1-at-0-degrees case.
  Set<SlotId>? _footprintFor(SlotId anchor, ItemSize size, Rotation rotation) {
    final anchorSlot = _slots[anchor];
    if (anchorSlot == null) return null;
    final anchorPosition = anchorSlot.position;
    if (anchorPosition == null) {
      if (size == const ItemSize(1, 1) && rotation == Rotation.deg0) {
        return {anchor};
      }
      return null;
    }
    final effective = size.rotated(rotation);
    final footprint = <SlotId>{};
    for (var dRow = 0; dRow < effective.height; dRow++) {
      for (var dCol = 0; dCol < effective.width; dCol++) {
        footprint.add(
          SlotId('${anchorPosition.row + dRow},${anchorPosition.col + dCol}'),
        );
      }
    }
    return footprint;
  }

  List<PlacementRule> _allRules(List<PlacementRule> extraRules) => [
        const WithinBounds(),
        const NoCollision(),
        ...extraRules,
      ];

  List<String> _failedRules(
    Set<SlotId>? footprint,
    EntityId item,
    List<PlacementRule> extraRules,
  ) {
    if (footprint == null) return const ['WithinBounds'];
    return [
      for (final rule in _allRules(extraRules))
        if (!rule.isSatisfied(this, item, footprint))
          rule.runtimeType.toString(),
    ];
  }
}
```

- [ ] **Step 4: Export it from the barrel file**

Modify `lib/build_engine.dart`, adding the new export line. `container` sorts before every other `spatial/` file (`c` is the earliest letter among `container`, `placement_exception`, `placement_rule`, `position`, `slot`, `spatial_relation`) — it becomes the new first `spatial/` export:
```dart
export 'src/rule/rule_engine.dart';
export 'src/spatial/container.dart';
export 'src/spatial/placement_exception.dart';
export 'src/spatial/placement_rule.dart';
export 'src/spatial/position.dart';
export 'src/spatial/slot.dart';
export 'src/spatial/spatial_relation.dart';
```

- [ ] **Step 5: Run tests to verify they pass, and analyze**

Run:
```bash
dart test test/spatial/container_test.dart
dart analyze
```
Expected: all 21 tests PASS; `dart analyze` reports `No issues found!`.

- [ ] **Step 6: Commit**

```bash
git add lib/src/spatial/container.dart lib/build_engine.dart test/spatial/container_test.dart
git commit -m "feat: add Container (construction, placement, movement, removal, queries)"
```

---

### Task 6: Container serialization — `toJson`/`fromJson`

**Files:**
- Modify: `lib/src/spatial/container.dart` (adds `toJson`/`fromJson` to the `Container` class from Task 5 — no other file from Task 5 changes)
- Test: `test/spatial/container_serialization_test.dart`

**Interfaces:**
- Consumes: everything from Task 5's `Container` (unchanged), plus `EntityId.value` (foundation), `SlotId.id`, `Rotation.name`/`Rotation.values.byName`.
- Produces: `Container.toJson() → Map<String, dynamic>`, `factory Container.fromJson(Map<String, dynamic> json)`. This is the last change to `container.dart` — Task 7's integration test and Task 8's docs both consume the finished class as-is.

This module's serialization is deliberately self-contained (see spec's "Explicitly Out of Scope") — it does not integrate with any engine-wide Serialization service.

- [ ] **Step 1: Write the failing tests**

Create `test/spatial/container_serialization_test.dart`:
```dart
import 'package:build_engine/build_engine.dart';
import 'package:test/test.dart';

void main() {
  group('Container serialization', () {
    test('round-trips a grid container with a placed item', () {
      final container = Container.grid(3, 3);
      container.place(
        const EntityId(1),
        const SlotId('0,0'),
        size: const ItemSize(2, 1),
      );

      final restored = Container.fromJson(container.toJson());

      expect(restored.itemAt(const SlotId('0,0')), equals(const EntityId(1)));
      expect(restored.itemAt(const SlotId('0,1')), equals(const EntityId(1)));
      expect(restored.contains(const EntityId(1)), isTrue);
      expect(restored.positionOf(const EntityId(1)), equals(const Position(0, 0)));
    });

    test('round-trips a named-slot container with a placed item', () {
      final container = Container.namedSlots(['head', 'weapon']);
      container.place(const EntityId(1), const SlotId('head'));

      final restored = Container.fromJson(container.toJson());

      expect(restored.itemAt(const SlotId('head')), equals(const EntityId(1)));
      expect(restored.hasSlot(const SlotId('weapon')), isTrue);
      expect(restored.itemAt(const SlotId('weapon')), isNull);
    });

    test('round-trips rotation', () {
      final container = Container.grid(3, 3);
      container.place(
        const EntityId(1),
        const SlotId('0,0'),
        size: const ItemSize(2, 1),
        rotation: Rotation.deg90,
      );

      final restored = Container.fromJson(container.toJson());

      expect(restored.itemAt(const SlotId('0,0')), equals(const EntityId(1)));
      expect(restored.itemAt(const SlotId('1,0')), equals(const EntityId(1)));
      expect(restored.itemAt(const SlotId('0,1')), isNull);
    });

    test('round-trips an empty container', () {
      final container = Container.grid(2, 2);

      final restored = Container.fromJson(container.toJson());

      expect(restored.hasSlot(const SlotId('0,0')), isTrue);
      expect(restored.hasSlot(const SlotId('1,1')), isTrue);
      expect(restored.contains(const EntityId(1)), isFalse);
    });
  });
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `dart test test/spatial/container_serialization_test.dart`
Expected: FAIL — `NoSuchMethodError` / `Error: The method 'toJson' isn't defined for the class 'Container'`.

- [ ] **Step 3: Add `toJson`/`fromJson` to `Container`**

Modify `lib/src/spatial/container.dart`. Add these two members to the `Container` class (placed after `relatesTo`, before the private helpers):
```dart
  /// A plain, stable-ID-based structure: every slot's id and position (if
  /// any), and every current placement. Self-contained to this module —
  /// it does not integrate with any engine-wide Serialization service.
  Map<String, dynamic> toJson() {
    return {
      'slots': [
        for (final slot in _slots.values)
          {
            'id': slot.id.id,
            if (slot.position != null)
              'position': {'row': slot.position!.row, 'col': slot.position!.col},
          },
      ],
      'placements': [
        for (final entry in _placements.entries)
          {
            'item': entry.key.value,
            'anchor': entry.value.anchor.id,
            'size': {'width': entry.value.size.width, 'height': entry.value.size.height},
            'rotation': entry.value.rotation.name,
          },
      ],
    };
  }

  /// Reconstructs an equivalent [Container] from [toJson]'s output. Does
  /// not need to know whether the original was built via [Container.grid]
  /// or [Container.namedSlots] — the serialized slot list already
  /// captures the full layout directly.
  factory Container.fromJson(Map<String, dynamic> json) {
    final slots = [
      for (final rawSlot in json['slots'] as List<dynamic>)
        _slotFromJson(rawSlot as Map<String, dynamic>),
    ];
    final container = Container(slots);
    for (final rawPlacement in json['placements'] as List<dynamic>) {
      final placement = rawPlacement as Map<String, dynamic>;
      final size = placement['size'] as Map<String, dynamic>;
      container.place(
        EntityId(placement['item'] as int),
        SlotId(placement['anchor'] as String),
        size: ItemSize(size['width'] as int, size['height'] as int),
        rotation: Rotation.values.byName(placement['rotation'] as String),
      );
    }
    return container;
  }

  static Slot _slotFromJson(Map<String, dynamic> json) {
    final rawPosition = json['position'] as Map<String, dynamic>?;
    return Slot(
      SlotId(json['id'] as String),
      position: rawPosition == null
          ? null
          : Position(rawPosition['row'] as int, rawPosition['col'] as int),
    );
  }
```

- [ ] **Step 4: Run tests to verify they pass, and analyze**

Run:
```bash
dart test test/spatial/container_serialization_test.dart
dart analyze
```
Expected: all 4 tests PASS; `dart analyze` reports `No issues found!`.

- [ ] **Step 5: Commit**

```bash
git add lib/src/spatial/container.dart test/spatial/container_serialization_test.dart
git commit -m "feat: add Container.toJson/fromJson serialization"
```

---

### Task 7: Integration test — grid and named-slot containers through identical machinery

**Files:**
- Test: `test/integration/spatial_container_end_to_end_test.dart`

**Interfaces:**
- Consumes: the complete public surface from Tasks 1-6 (`Container`, `Position`, `ItemSize`, `Rotation`, `SlotId`, `Slot`, `SpatialRelation`/`Adjacent`, `distance`, `PlacementRule`, `InvalidPlacementException`). Produces nothing further — this is the module's final proof of genericity, no other task depends on it.

This test uses example strings like "sword"/"head"/"weapon" purely as test *data* — not engine types or class names — staying compliant with the "do not call this subsystem Backpack" constraint (no engine code names any container shape).

- [ ] **Step 1: Write the test**

Create `test/integration/spatial_container_end_to_end_test.dart`:
```dart
import 'package:build_engine/build_engine.dart';
import 'package:test/test.dart';

void main() {
  test('grid and named-slot containers work through identical machinery', () {
    const sword = EntityId(1);
    const shield = EntityId(2);
    const helmet = EntityId(3);

    // --- Grid-shaped container ---
    final grid = Container.grid(4, 4);

    grid.place(sword, const SlotId('0,0'), size: const ItemSize(2, 1));
    grid.place(shield, const SlotId('0,2'));

    expect(grid.itemAt(const SlotId('0,0')), equals(sword));
    expect(grid.itemAt(const SlotId('0,1')), equals(sword));
    expect(grid.contains(shield), isTrue);

    // Collision: shield's cell can't take a third item.
    expect(grid.canPlace(helmet, const SlotId('0,2')), isFalse);

    // Adjacency: sword's rightmost cell (0,1) is adjacent to shield (0,2).
    expect(grid.relatesTo(const Adjacent(), sword, shield), isTrue);
    expect(distance(grid.positionOf(sword)!, grid.positionOf(shield)!), equals(2));

    // Movement.
    grid.move(sword, const SlotId('2,0'), size: const ItemSize(2, 1));
    expect(grid.itemAt(const SlotId('0,0')), isNull);
    expect(grid.itemAt(const SlotId('2,0')), equals(sword));

    // Removal.
    grid.remove(shield);
    expect(grid.contains(shield), isFalse);
    expect(grid.itemAt(const SlotId('0,2')), isNull);

    // Serialization round-trip.
    final restoredGrid = Container.fromJson(grid.toJson());
    expect(restoredGrid.itemAt(const SlotId('2,0')), equals(sword));
    expect(restoredGrid.itemAt(const SlotId('2,1')), equals(sword));

    // --- Named-slot container: same machinery, no shape-specific code ---
    final board = Container.namedSlots(['head', 'weapon', 'feet']);

    board.place(helmet, const SlotId('head'));
    board.place(sword, const SlotId('weapon'));

    expect(board.itemAt(const SlotId('head')), equals(helmet));
    expect(board.contains(sword), isTrue);

    // A named-slot container has no positions, so relatesTo is always
    // false, not a crash — well-defined, not an error case.
    expect(board.relatesTo(const Adjacent(), helmet, sword), isFalse);

    // The same NoCollision/WithinBounds rules apply: an oversized item
    // (no position to expand into) is rejected exactly like an
    // out-of-bounds grid placement.
    expect(
      board.canPlace(shield, const SlotId('feet'), size: const ItemSize(2, 1)),
      isFalse,
    );

    // Movement and removal work identically.
    board.move(sword, const SlotId('feet'));
    expect(board.itemAt(const SlotId('weapon')), isNull);
    expect(board.itemAt(const SlotId('feet')), equals(sword));

    board.remove(helmet);
    expect(board.contains(helmet), isFalse);

    // Serialization round-trip.
    final restoredBoard = Container.fromJson(board.toJson());
    expect(restoredBoard.itemAt(const SlotId('feet')), equals(sword));
    expect(restoredBoard.hasSlot(const SlotId('head')), isTrue);
    expect(restoredBoard.contains(helmet), isFalse);
  });
}
```

- [ ] **Step 2: Run the test**

Run: `dart test test/integration/spatial_container_end_to_end_test.dart`
Expected: PASS (this test only exercises the already-implemented public API from Tasks 1-6 — it should pass on first run with no implementation changes).

- [ ] **Step 3: Run the full suite and analyze**

Run:
```bash
dart test
dart analyze
```
Expected: every test in the package PASSES; `dart analyze` reports `No issues found!`.

- [ ] **Step 4: Commit**

```bash
git add test/integration/spatial_container_end_to_end_test.dart
git commit -m "test: add grid/named-slot Container integration test"
```

---

### Task 8: Documentation — amend ARCHITECTURE.md

**Files:**
- Modify: `ARCHITECTURE.md`

**Interfaces:**
- Consumes: the finished Spatial/Container Engine from Tasks 1-7 (documents its public surface, does not change it).
- Produces: nothing further — this is the plan's final task.

- [ ] **Step 1: Add the "Spatial/Container Engine" subsection**

Modify `ARCHITECTURE.md`. Insert a new subsection immediately after the existing `### Modifier Engine` subsection (i.e. right before the `## Integrating EntityRegistry and ComponentStore` heading):

```markdown
### Spatial/Container Engine (`lib/src/spatial/`)
`Container` is a single class with two factory constructors, not a
`GridContainer`/`SlotContainer` subclass split: `Container.grid(width,
height)` generates one `Slot` per cell with a derived `SlotId` and a
non-null `Position`; `Container.namedSlots(ids)` generates one `Slot` per
given id with `position: null`. Both are the same underlying structure —
a future Backpack, Tome, Weapon Rack, or Equipment Board plugin is just a
different factory call plus its own content, with zero
container-shape-specific code anywhere in this module.

The 9 requested spatial queries split by their actual mathematical shape
rather than one artificial interface: `Above`/`Below`/`Left`/`Right`/
`Adjacent`/`SameRow`/`SameColumn` are boolean `SpatialRelation`s between
two `Position`s (row 0 is the top; `Adjacent` is orthogonal only, no
diagonals); `distance` is a plain top-level Manhattan-distance function,
not a `SpatialRelation`; `ContainedBy` is entity-container membership —
`Container.contains(EntityId)` — not a relation between two positions.
`Container.relatesTo(relation, a, b)` looks up each item's position and
returns `false` (not a crash) if either item lacks one, so asking about
adjacency on a named-slot container is well-defined.

`ItemSize` + `Rotation` model only an axis-aligned bounding box — a
rotation swaps width/height at 90°/270°, no per-cell/Tetris-style
footprints. Placement validation runs through `PlacementRule`
(`WithinBounds`, `NoCollision`, matching the `Condition`/`Effect`
no-registry pattern), always AND'd with any caller-supplied extra rules —
the plugin extension point for content-specific placement constraints.
`PlacementRule.isSatisfied` takes a minimal `ContainerView` interface
(`hasSlot`/`itemAt`), not the concrete `Container` — this is what lets
`placement_rule.dart` have zero dependency on `container.dart`, avoiding
a circular dependency (`Container implements ContainerView`) rather than
needing any forward-reference workaround. `place`/`move` throw
`InvalidPlacementException` carrying the failing rule(s); `canPlace`
never throws. `move` validates the new placement before clearing the
item's old footprint, so moving an item to overlap its own current
position succeeds correctly, and a rejected move leaves the item
unchanged (atomic — no partial mutation).

`Container.toJson()`/`Container.fromJson()` are a self-contained
capability of this module only — a plain, stable-ID-based structure
(slots + placements) — not an integration point for the engine-wide
Serialization service `claude.md` describes (engine version, RNG state,
etc.), which remains a separate future pass.
```

- [ ] **Step 2: Remove "Spatial/Container Engine" from "What's deliberately not here yet"**

In the same file, find the `## What's deliberately not here yet` section and remove `Spatial/Container Engine, ` from its first sentence, so it reads:

```markdown
## What's deliberately not here yet

A dedicated Resource Engine *service* (this pass added only the
`ResourceComponent` data shape), Scheduler, Asset/Data Registry,
Serialization, and any registry/factory/data-driven rule deserialization
mechanism. Each is a separate future subsystem, to be brainstormed and
planned on its own rather than stubbed out speculatively here.
```

- [ ] **Step 3: Commit**

```bash
git add ARCHITECTURE.md
git commit -m "docs: document the Spatial/Container Engine in ARCHITECTURE.md"
```

---

## Self-Review Notes

**Spec coverage:** Purpose/Core Model → Tasks 1, 5. Geometry Primitives
(`Position`/`ItemSize`/`Rotation`) → Task 1. `SlotId`/`Slot` → Task 2.
Spatial Relations (7 relations + `distance` + `ContainedBy`-is-`contains`)
→ Task 3. `PlacementRule` (`WithinBounds`/`NoCollision`) + `ContainerView`
+ `InvalidPlacementException` → Task 4. `Container`'s full public API
(construction, placement, movement, removal, queries) → Task 5.
Serialization → Task 6. The genericity integration test → Task 7.
Documentation deliverables → Task 8. Every item in "Explicitly Out of
Scope" (engine-wide Serialization, Resource Engine service, Scheduler,
Asset/Data Registry, `SpatialRelation` combinators, actual container
content, `PluginContext.spatial`) has deliberately no task — confirmed
absent from every task above.

**Placeholder scan:** No "TBD"/"TODO"/"implement later" anywhere in
Tasks 1-8. Every code step contains complete, runnable code, not a
description of code. No task references a type/method not defined by an
earlier task in this plan (verified below).

**Type-consistency check:** `SlotId`/`Slot`/`Position`/`ItemSize`/
`Rotation` (Tasks 1-2) are used identically in Tasks 3-8 with no renames.
`ContainerView.hasSlot(SlotId)`/`itemAt(SlotId)` (Task 4) match
`Container`'s own `hasSlot`/`itemAt` signatures exactly (Task 5) — `
Container implements ContainerView` type-checks. `PlacementRule
.isSatisfied(ContainerView, EntityId, Set<SlotId>)` (Task 4) is called
identically from `Container.canPlace`/`_failedRules` (Task 5) — always
passing `this` (a `Container`, satisfying `ContainerView`), never a
concrete `Container` parameter type. `InvalidPlacementException`'s
constructor (Task 4, `List<String> failedRules`) matches every throw
site in Task 5 (`InvalidPlacementException(failed)`,
`InvalidPlacementException(const ['NotInContainer'])`). Task 6's
`toJson`/`fromJson` round-trips exactly the fields `_Placement` (Task 5,
private to `container.dart`) already holds — `anchor`, `size`,
`rotation` — no field renamed or added. Task 7's integration test and
Task 8's docs reference only public members that exist after Task 6
(no reference to a `Container.grid`-only or `.namedSlots`-only method —
confirmed both factories produce the same `Container` type throughout).

**Barrel-ordering double-check:** Final `spatial/` export block, in the
order each task leaves it (Task 1 → 2 → 3 → 4 → 5; Task 6 modifies
`container.dart` in place, no new export; Task 7-8 add no exports):
```dart
export 'src/spatial/container.dart';
export 'src/spatial/placement_exception.dart';
export 'src/spatial/placement_rule.dart';
export 'src/spatial/position.dart';
export 'src/spatial/slot.dart';
export 'src/spatial/spatial_relation.dart';
```
Alphabetical by filename throughout: `container` < `placement_exception`
< `placement_rule` < `position` < `slot` < `spatial_relation` — verified
character-by-character at each ordering decision point in Tasks 1-5
above.
