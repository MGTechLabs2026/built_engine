import '../entity/entity_id.dart';

/// Published via the owning [EventBus] whenever [ProgressionEngine]
/// actually changes an entity's stored experience for a subject. Not
/// published when a floored add would leave the value unchanged (e.g.
/// subtracting from a subject already at 0).
class ProgressionChanged {
  const ProgressionChanged(this.id, this.subject, this.delta, this.newExperience);

  final EntityId id;
  final String subject;
  final num delta;
  final num newExperience;
}

/// Published once for each tier an [ProgressionEngine.addExperience] or
/// [ProgressionEngine.unlock] call newly reaches — a single large grant
/// that crosses several tier boundaries at once publishes one of these per
/// tier crossed, in ascending order, so no tier-reached reaction is ever
/// skipped.
class ProgressionTierReached {
  const ProgressionTierReached(this.id, this.subject, this.tier);

  final EntityId id;
  final String subject;
  final int tier;
}
