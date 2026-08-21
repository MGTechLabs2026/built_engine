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
  ///
  /// `T` is whatever type is inferred or declared at the call site — if
  /// [component] is held at a widened static type (e.g. a variable typed
  /// `Object`), it will be keyed under that wider type instead of its
  /// concrete type, and a later `get<ConcreteType>(id)` will return `null`
  /// as if the component were absent, with no error or warning. Pass
  /// [component] at its concrete type, or specify `T` explicitly
  /// (`store.add<ConcreteType>(id, component)`).
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
  ///
  /// Returns an unmodifiable snapshot, not a live view — safe to iterate
  /// while mutating the store (e.g. calling [remove]) in the same loop.
  Iterable<EntityId> entitiesWith<T extends Object>() =>
      List<EntityId>.unmodifiable(_components[T]?.keys ?? const <EntityId>[]);
}
