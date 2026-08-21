import '../entity/entity_id.dart';

/// Generic per-type storage for entity components, keyed by the component's
/// runtime [Type]. Deliberately has no reference to [EntityRegistry] or
/// `EventBus` — it can be constructed and tested entirely on its own.
///
/// Cleanup of a destroyed entity's components is not automatic: a consumer
/// should subscribe to `EntityDestroyed` and call [remove] for each
/// component type it knows that entity might carry. See `ARCHITECTURE.md`.
class ComponentStore {
  final Map<Type, Map<EntityId, Object>> _components = {};

  /// Stores [component] as entity [id]'s component of type `T`, overwriting
  /// any component of that same type already stored for [id].
  void add<T extends Object>(EntityId id, T component) {
    final byId = _components.putIfAbsent(T, () => <EntityId, Object>{});
    byId[id] = component;
  }

  /// The component of type `T` stored for entity [id], or `null` if entity
  /// [id] has no such component.
  T? get<T extends Object>(EntityId id) {
    final byId = _components[T];
    return byId?[id] as T?;
  }

  /// Whether entity [id] has a component of type `T`.
  bool has<T extends Object>(EntityId id) =>
      _components[T]?.containsKey(id) ?? false;

  /// Removes entity [id]'s component of type `T`, if any. No-op if it has
  /// none.
  void remove<T extends Object>(EntityId id) {
    _components[T]?.remove(id);
  }

  /// Every entity that currently has a component of type `T`.
  Iterable<EntityId> entitiesWith<T extends Object>() =>
      _components[T]?.keys ?? const <EntityId>[];
}
