# Build Engine — Spatial/Container System Design

Date: 2026-08-22
Status: Approved

## Purpose

Add the Spatial/Container Engine (`claude.md`'s core service #8) to
`build_engine`: generic `Container`, `Slot`, `Position`, `SpatialRelation`,
and `PlacementRule` abstractions, supporting rectangular grids, arbitrary
named slots, item size, rotation, placement validation, moving/removing
items, containment, and adjacency queries.

No martial-arts, magic, cultivation, or other game-specific content. **No
class, file, test, or doc anywhere in this module names "Backpack"** — the
engine must genuinely support multiple container shapes (grid-based and
named-slot-based) through one generic abstraction, not a Backpack-shaped
abstraction that happens to be reusable. No dedicated Resource Engine
service, Scheduler, Asset/Data Registry, or engine-wide Serialization
service — each remains a separate future pass; this module's own
`toJson`/`fromJson` is a self-contained capability, not an integration with
that future service.

## Core Model: One `Container`, Two Construction Styles

A `Container` is a fixed set of `Slot`s. A `Slot` has an arbitrary `SlotId`
(string-wrapping value type, analogous to `ModifierSource`) and an
*optional* `Position` (grid `(row, col)` coordinates). There is no
`GridContainer`/`SlotContainer` subclass split — both topologies are the
same underlying structure, built via different factory constructors:

- `Container.grid(width, height)` — generates one `Slot` per cell,
  `SlotId` derived from its coordinates, each with a non-null `Position`.
- `Container.namedSlots(Iterable<String> ids)` — generates one `Slot` per
  given id, each with `position: null`.

This is what makes genericity real: a future Backpack, Tome, Weapon Rack,
or Equipment Board plugin is just a different `Container.grid(...)` or
`Container.namedSlots(...)` call plus its own content — zero
container-shape-specific code anywhere in this module.

## Geometry Primitives (`lib/src/spatial/position.dart`)

```dart
class Position {
  const Position(this.row, this.col);
  final int row;
  final int col;
  // == / hashCode by (row, col)
}

class ItemSize {
  const ItemSize(this.width, this.height);
  final int width;
  final int height;
  /// The effective size after applying [rotation] — width/height swap on
  /// a 90° or 270° rotation, unchanged on 0°/180°.
  ItemSize rotated(Rotation rotation);
}

enum Rotation { deg0, deg90, deg180, deg270 }
```

This is a deliberate simplification: only the item's bounding-box
width/height matters for footprint computation (an axis-aligned
rectangle), not per-cell shape (no Tetris-style irregular footprints).
0°/180° produce the same footprint as each other; 90°/270° produce the
same (swapped) footprint as each other.

## `SlotId` and `Slot` (`lib/src/spatial/slot.dart`)

```dart
class SlotId {
  const SlotId(this.id);
  final String id;
  // == / hashCode by id
}

class Slot {
  const Slot(this.id, {this.position});
  final SlotId id;
  final Position? position;  // null for a non-geometric (named) slot
}
```

## Spatial Relations (`lib/src/spatial/spatial_relation.dart`)

The 9 requested queries split by their actual shape — not forced into one
interface artificially:

- **Boolean relations between two `Position`s** — `Adjacent`, `Above`,
  `Below`, `Left`, `Right`, `SameRow`, `SameColumn` — all implement:
  ```dart
  abstract class SpatialRelation {
    bool holds(Position a, Position b);
  }
  ```
  Row convention: row 0 is the top, increasing row goes down (standard
  screen/array convention). `Above(a, b)` means `a` is exactly one row
  above `b`, same column (`a.row == b.row - 1 && a.col == b.col`);
  `Below`/`Left`/`Right` mirror this directionally. `Adjacent(a, b)` =
  `Above(a,b) || Below(a,b) || Left(a,b) || Right(a,b)` — orthogonal only,
  no diagonals (this is exactly why Above/Below/Left/Right are separately
  listed rather than folded into one "adjacent" concept). `SameRow`/
  `SameColumn` compare the respective coordinate only, with no exclusion
  for `a == b` (trivially true, not special-cased).
- **`Distance`** is not boolean — a plain top-level function computing
  Manhattan distance (`(a.row - b.row).abs() + (a.col - b.col).abs()`),
  consistent with orthogonal adjacency meaning distance 1.
- **`ContainedBy`** is not about two positions — it's entity-to-container
  membership, so it's `Container.contains(EntityId item)`, not a
  `SpatialRelation` instance.

Querying a relation between two **items** (not raw positions) goes through
`Container.relatesTo(SpatialRelation relation, EntityId a, EntityId b)` —
looks up each item's anchor position, returns `false` if either has none
(e.g. asking whether two named-slot items are "Adjacent" is well-defined
as always false, not a crash or exception).

No combinators (`and`/`or`/`not`) on `SpatialRelation` — unlike `Query`,
composability wasn't requested for spatial relations and there's no
concrete use case yet; adding it would be speculative.

## `PlacementRule` (`lib/src/spatial/placement_rule.dart`)

Composable and extensible, matching the established `Condition`/`Effect`
pattern:

```dart
abstract class PlacementRule {
  bool isSatisfied(Container container, EntityId item, Set<SlotId> footprint);
}

class WithinBounds implements PlacementRule { const WithinBounds(); ... }
class NoCollision implements PlacementRule { const NoCollision(); ... }
```

`WithinBounds` checks every `SlotId` in the footprint actually exists in
the container (this is also how an unsupported placement — e.g. a
multi-cell footprint anchored on a position-less named slot — fails
cleanly: the footprint computation for such a case can't produce valid
additional cells, so at least one computed id won't exist in the
container, and `WithinBounds` rejects it). `NoCollision` checks every
slot in the footprint is either empty or already occupied by `item`
itself (so re-validating a move doesn't reject an item against its own
current position).

`Container.canPlace`/`place`/`move` always AND these two built-ins with
any extra `PlacementRule`s a caller supplies — the plugin extension
point for content-specific rules ("only weapons in the Weapon Rack") with
zero engine changes required.

## `Container` (`lib/src/spatial/container.dart`)

```dart
class Container {
  Container(List<Slot> slots);
  factory Container.grid(int width, int height);
  factory Container.namedSlots(Iterable<String> ids);

  bool hasSlot(SlotId id);
  Position? positionOf(EntityId item);
  EntityId? itemAt(SlotId id);
  bool contains(EntityId item);

  bool canPlace(
    EntityId item,
    SlotId anchor, {
    ItemSize size = const ItemSize(1, 1),
    Rotation rotation = Rotation.deg0,
    List<PlacementRule> extraRules = const [],
  });

  /// Throws [InvalidPlacementException] if [canPlace] would return false.
  void place(
    EntityId item,
    SlotId anchor, {
    ItemSize size = const ItemSize(1, 1),
    Rotation rotation = Rotation.deg0,
    List<PlacementRule> extraRules = const [],
  });

  void remove(EntityId item);

  /// Throws [InvalidPlacementException] if the new placement would be
  /// invalid; leaves the item at its original position unchanged in that
  /// case (atomic — no partial mutation).
  void move(
    EntityId item,
    SlotId newAnchor, {
    ItemSize size = const ItemSize(1, 1),
    Rotation rotation = Rotation.deg0,
    List<PlacementRule> extraRules = const [],
  });

  bool relatesTo(SpatialRelation relation, EntityId a, EntityId b);

  Map<String, dynamic> toJson();
  factory Container.fromJson(Map<String, dynamic> json);
}
```

Footprint computation: given an anchor `SlotId`'s `Position` and the
effective size after rotation, the occupied cells are
`(anchor.row .. anchor.row + effectiveHeight - 1, anchor.col ..
anchor.col + effectiveWidth - 1)`, translated to `SlotId`s via the same
`"$row,$col"` convention `Container.grid` uses internally. If the anchor
slot has no `Position` (a named slot), only a footprint of exactly the
anchor's own `SlotId` is valid (i.e. `size == ItemSize(1,1)` and
`rotation == Rotation.deg0`) — anything else produces a footprint
containing an id that doesn't exist in the container, which
`WithinBounds` then correctly rejects.

`InvalidPlacementException` (`lib/src/spatial/placement_exception.dart`)
carries the failing rule(s) for a clear error message — thrown by
`place`/`move`, never by `canPlace` (which only returns `bool`).

## Serialization

`Container.toJson()` produces a plain, stable-ID-based structure: every
slot's `id` and `position` (if any), and every current placement (`item`
as `EntityId.value`, `anchor` slot id, `size`, `rotation`).
`Container.fromJson(json)` reconstructs an equivalent `Container` from
scratch — it does not need to know whether the original was built via
`.grid(...)` or `.namedSlots(...)`, since the serialized form already
captures the full slot layout directly. This is a self-contained
capability of this module only — it does not touch, wire into, or
anticipate the engine-wide Serialization service `claude.md` describes
(engine version, plugin versions, RNG state, etc.), which remains a
separate future pass.

## Testing

Unit tests for: geometry primitives (`Position` equality, `ItemSize`
rotation swapping correctly for all 4 rotation values); `SlotId`/`Slot`
value semantics; each `SpatialRelation` in isolation (including the
non-symmetry of directional relations and the symmetry of `Adjacent`) and
the `Distance` function; `PlacementRule`s in isolation (`WithinBounds`,
`NoCollision`, including the "colliding with self during a move" case);
`Container` covering every requested category — **placement** (grid and
named-slot, single and multi-cell), **collision** (overlapping footprints
rejected, non-overlapping accepted), **movement** (successful move
relocates the item, a rejected move leaves the item at its original
position unchanged), **removal** (frees all of an item's occupied slots),
**adjacency** (`relatesTo` across all 7 relations, and the
no-position case), **rotation** (a 2×1 item at 90° occupies the 1×2
footprint, not the 2×1 one), **boundaries** (placement rejected past grid
edges, and on a named slot with an unsupported size/rotation), and
**serialization** (round-trip: build a container, place several items,
serialize, deserialize, verify identical `itemAt`/`positionOf`/`contains`
results). One integration test constructing both a grid-shaped container
and a named-slot-shaped container side by side, proving the same
`Container`/`PlacementRule`/`SpatialRelation` machinery works identically
for both without any container-shape-specific code — the concrete proof
of genericity this module exists to deliver.

## Documentation Deliverables

Amend `ARCHITECTURE.md`: add a `### Spatial/Container Engine` subsection
under "Services implemented so far"; remove "Spatial/Container Engine"
from "What's deliberately not here yet".

## Explicitly Out of Scope

The engine-wide Serialization service (engine/plugin versions, RNG state,
etc.) — this module's `toJson`/`fromJson` is self-contained, not an
integration point for that future service. A dedicated Resource Engine
service, Scheduler, Asset/Data Registry. `SpatialRelation` combinators
(`and`/`or`/`not`) — not requested, no concrete use case yet. Any actual
container content (Backpack, Tome, Spellbook, Weapon Rack, Equipment
Board, Skill Board) — those are future plugins built on top of this
generic module, not part of it. Extending `PluginContext` to expose
`spatial` — a future pass, following the same pattern as the Query/Rule/
Effect and Modifier modules before it.
