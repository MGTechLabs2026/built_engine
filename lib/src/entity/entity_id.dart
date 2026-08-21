/// A unique identifier for an entity, assigned in creation order by
/// [EntityRegistry.create]. Sequential rather than random so that a run is
/// reproducible from seed + initial state + actions.
class EntityId implements Comparable<EntityId> {
  const EntityId(this.value);

  /// The underlying sequential identifier. Stable across saves/loads.
  final int value;

  @override
  bool operator ==(Object other) => other is EntityId && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  int compareTo(EntityId other) => value.compareTo(other.value);

  @override
  String toString() => 'EntityId($value)';
}
