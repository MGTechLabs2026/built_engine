import '../entity/entity_id.dart';

/// Published via the owning [EventBus] whenever [DiscoveryTracker.discover]
/// (or [DiscoveryTracker.unlock] auto-promoting through `discovered`)
/// actually moves a subject from `unknown` to `discovered` for an entity.
class SubjectDiscovered {
  const SubjectDiscovered(this.id, this.subject);

  final EntityId id;
  final String subject;
}

/// Published via the owning [EventBus] whenever [DiscoveryTracker.unlock]
/// actually moves a subject to `unlocked` for an entity.
class SubjectUnlocked {
  const SubjectUnlocked(this.id, this.subject);

  final EntityId id;
  final String subject;
}
