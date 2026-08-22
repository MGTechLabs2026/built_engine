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
