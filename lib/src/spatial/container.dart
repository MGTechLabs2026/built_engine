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
