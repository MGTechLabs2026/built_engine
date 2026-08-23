import '../entity/entity_id.dart';

/// Published via the owning [EventBus] whenever [MasteryTracker] actually
/// changes an owner's stored progress for a subject. Not published when a
/// floored increase would leave the value unchanged.
class MasteryChanged {
  const MasteryChanged(this.owner, this.subject, this.delta, this.newProgress);

  final EntityId owner;
  final String subject;
  final num delta;
  final num newProgress;
}

/// Published once for each level a [MasteryTracker.increase] call newly
/// reaches — a single large grant that crosses several level boundaries at
/// once publishes one of these per level crossed, in ascending order.
class MasteryLevelReached {
  const MasteryLevelReached(this.owner, this.subject, this.level);

  final EntityId owner;
  final String subject;
  final int level;
}
