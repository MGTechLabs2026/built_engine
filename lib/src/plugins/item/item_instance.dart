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
/// [itemClass] and [statBonuses] are the two fields `combineItems`
/// (`docs/superpowers/specs/2026-08-24-item-combine-design.md`) touches
/// after a class upgrade — the class bumps by one, the surviving copy's
/// [statBonuses] carry over; every other field stays immutable-per-copy.
class ItemInstance {
  const ItemInstance({
    required this.definitionId,
    required this.owner,
    this.itemClass = 1,
    this.statBonuses = const {},
  });

  final String definitionId;
  final EntityId owner;
  final int itemClass;

  /// Flat, per-copy combat-stat bonuses bound to *this* copy — an
  /// affixed reward's prefix/suffix rolls, keyed by the stat they add
  /// to (`'blade'`, `'fist'`, `'item:<id>'`, …). `ItemActionInterpreter`
  /// turns each into a [Modifier] only while the copy is hung on the
  /// Tome, so an unequipped affixed item grants nothing. Two copies of
  /// the same definition/class can carry different bonuses — Combine
  /// still matches on definition + class alone.
  final Map<String, num> statBonuses;
}
