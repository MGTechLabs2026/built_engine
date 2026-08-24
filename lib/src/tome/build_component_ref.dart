import '../entity/entity_id.dart';

/// An opaque reference to a piece of content a Tome placement represents —
/// an item, a technique, a modifier, a tag, or anything a future plugin
/// invents. Core never interprets [referenceType] or [contentId]; it only
/// carries them through from a Tome placement into an [ActiveBuild] for
/// whatever consumes that snapshot to resolve.
///
/// Also serves directly as the ECS component attached to the placeholder
/// [EntityId] `TomeService.insert` creates for each placement — no
/// redundant wrapper component needed.
///
/// [instanceEntityId] is additive, optional data: the entity id of the
/// specific owned copy this placement represents, when the referenced
/// content has per-copy runtime state a consumer needs (e.g. the Item
/// plugin's `ItemInstance.itemClass` for Combine's stat scaling — see
/// `docs/superpowers/specs/2026-08-24-item-combine-design.md`). `null`
/// for every reference type that has no such state (technique, and any
/// item placement made without an owned copy).
class BuildComponentRef {
  const BuildComponentRef({
    required this.referenceType,
    required this.contentId,
    this.instanceEntityId,
  });

  final String referenceType;
  final String contentId;
  final EntityId? instanceEntityId;
}
