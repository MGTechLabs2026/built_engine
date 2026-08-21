import 'entity_id.dart';
import '../event/event_bus.dart';

/// Published via the registry's [EventBus] whenever [EntityRegistry.create]
/// allocates a new entity.
class EntityCreated {
  const EntityCreated(this.id);
  final EntityId id;
}

/// Published via the registry's [EventBus] whenever [EntityRegistry.destroy]
/// removes an entity.
class EntityDestroyed {
  const EntityDestroyed(this.id);
  final EntityId id;
}

/// Tracks which [EntityId]s currently exist. Allocation is sequential
/// (see [EntityId]). Deliberately has no knowledge of components — cleanup
/// of an entity's components on destroy is the caller's responsibility via
/// an [EntityDestroyed] subscription, not something this class does itself.
class EntityRegistry {
  EntityRegistry(this._events);

  final EventBus _events;
  int _nextValue = 1;
  final Set<EntityId> _alive = {};

  /// Allocates and returns a new, currently-alive [EntityId]. Publishes
  /// [EntityCreated].
  EntityId create() {
    final id = EntityId(_nextValue);
    _nextValue += 1;
    _alive.add(id);
    _events.publish(EntityCreated(id));
    return id;
  }

  /// Marks [id] as no longer alive. Publishes [EntityDestroyed].
  ///
  /// Throws [StateError] if [id] is unknown or already destroyed.
  void destroy(EntityId id) {
    if (!_alive.remove(id)) {
      throw StateError(
        'Cannot destroy unknown or already-destroyed entity: $id',
      );
    }
    _events.publish(EntityDestroyed(id));
  }

  /// Whether [id] currently exists.
  bool isAlive(EntityId id) => _alive.contains(id);

  /// Every currently-alive entity.
  Iterable<EntityId> get all => _alive;
}
