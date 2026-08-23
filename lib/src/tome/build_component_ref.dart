/// An opaque reference to a piece of content a Tome placement represents —
/// an item, a technique, a modifier, a tag, or anything a future plugin
/// invents. Core never interprets [referenceType] or [contentId]; it only
/// carries them through from a Tome placement into an [ActiveBuild] for
/// whatever consumes that snapshot to resolve.
///
/// Also serves directly as the ECS component attached to the placeholder
/// [EntityId] `TomeService.insert` creates for each placement — no
/// redundant wrapper component needed.
class BuildComponentRef {
  const BuildComponentRef({required this.referenceType, required this.contentId});

  final String referenceType;
  final String contentId;
}
