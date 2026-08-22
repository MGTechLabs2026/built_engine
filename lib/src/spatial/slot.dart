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
