import 'package:build_engine/build_engine.dart';

/// One physical copy of an item an owner possesses — pure runtime state,
/// attached via `ComponentStore` to a freshly created entity per copy
/// (see `ownItem`), exactly like `TomeInstance`'s "two fields, no
/// methods" pattern. Deliberately does NOT store discovered/usable state
/// or a mastery level — `DiscoveryTracker`/`MasteryTracker` (keyed by
/// [owner] + the subject `itemSubject(definitionId)` derives) are the
/// single source of truth for those; duplicating them here would let the
/// copy silently desync from the tracker it's supposed to mirror.
///
/// [itemClass] is the only field `combineItems`
/// (`docs/superpowers/specs/2026-08-24-item-combine-design.md`) mutates
/// in place after a class upgrade; every other field stays as
/// immutable-per-copy as before.
class ItemInstance {
  const ItemInstance({
    required this.definitionId,
    required this.owner,
    this.itemClass = 1,
  });

  final String definitionId;
  final EntityId owner;
  final int itemClass;
}
