import '../component/component_store.dart';
import '../components/resource_component.dart';
import '../entity/entity_id.dart';
import '../event/event_bus.dart';
import 'resource_definition.dart';
import 'resource_events.dart';
import 'resource_exceptions.dart';
import 'resource_state.dart';

/// The generic Resource Engine — every named-resource operation (get
/// current/maximum, set, add, subtract, clamp, canAfford, consume,
/// restore) for every plugin's resources, all in one place.
///
/// [ResourceComponent] stays pure state (only current values, as before);
/// this service is what gives a resource an upper bound (via [define]) and
/// what applies clamping/eventing consistently. An entity with no
/// registered [ResourceDefinition] for a resource is treated as
/// unbounded above and floored at 0 below — the same permissive-default
/// convention [ResourceAboveQuery]/[ResourceBelowQuery] already use for a
/// missing resource.
///
/// No randomness anywhere in this class — every operation is pure
/// arithmetic and clamping, so resource changes stay deterministic
/// without needing `RngService` at all.
class ResourcePool {
  ResourcePool({required ComponentStore components, required EventBus events})
      : _components = components,
        _events = events;

  final ComponentStore _components;
  final EventBus _events;
  final Map<String, ResourceDefinition> _definitions = {};

  /// Registers (or overwrites) [definition] as the bounds for its
  /// [ResourceDefinition.id].
  void define(ResourceDefinition definition) {
    _definitions[definition.id] = definition;
  }

  /// The registered [ResourceDefinition] for [resource], or `null` if none
  /// has been [define]d.
  ResourceDefinition? definitionOf(String resource) => _definitions[resource];

  /// [id]'s current value for [resource]. Missing [ResourceComponent] or
  /// missing entry reads as `0`.
  num currentOf(EntityId id, String resource) =>
      _components.get<ResourceComponent>(id)?.resources[resource] ?? 0;

  /// The registered maximum for [resource], or `double.infinity` if no
  /// [ResourceDefinition] has been registered.
  num maximumOf(String resource) => _definitions[resource]?.max ?? double.infinity;

  /// The registered minimum for [resource], or `0` if no
  /// [ResourceDefinition] has been registered.
  num minimumOf(String resource) => _definitions[resource]?.min ?? 0;

  /// [id]'s current value and [resource]'s registered maximum, together.
  ResourceState stateOf(EntityId id, String resource) => ResourceState(
        current: currentOf(id, resource),
        max: maximumOf(resource),
      );

  /// Restricts [value] to [resource]'s registered `[min, max]`, without
  /// touching any entity's stored state.
  num clampValue(String resource, num value) =>
      value.clamp(minimumOf(resource), maximumOf(resource));

  /// Sets [id]'s [resource] to [value], clamped to its registered bounds.
  /// Publishes [ResourceChanged] with the actual delta applied — not at
  /// all if clamping leaves the stored value unchanged.
  void set(EntityId id, String resource, num value) {
    final clamped = clampValue(resource, value);
    final current = currentOf(id, resource);
    if (clamped == current) return;
    final existing = _components.get<ResourceComponent>(id);
    final updated = Map<String, num>.of(existing?.resources ?? const <String, num>{});
    updated[resource] = clamped;
    _components.add(id, ResourceComponent(updated));
    _events.publish(ResourceChanged(id, resource, clamped - current, clamped));
  }

  /// Adds [amount] to [id]'s [resource], clamped to its registered maximum.
  void add(EntityId id, String resource, num amount) =>
      set(id, resource, currentOf(id, resource) + amount);

  /// Subtracts [amount] from [id]'s [resource], clamped to its registered
  /// minimum.
  void subtract(EntityId id, String resource, num amount) =>
      add(id, resource, -amount);

  /// Whether [id] currently has at least [amount] of [resource]. Never
  /// mutates, never throws.
  bool canAfford(EntityId id, String resource, num amount) =>
      currentOf(id, resource) >= amount;

  /// Subtracts [amount] from [id]'s [resource]. Throws
  /// [InsufficientResourceException] — without mutating anything — if
  /// [canAfford] would be `false`.
  void consume(EntityId id, String resource, num amount) {
    final available = currentOf(id, resource);
    if (available < amount) {
      throw InsufficientResourceException(
        resource,
        requested: amount,
        available: available,
      );
    }
    subtract(id, resource, amount);
  }

  /// Adds [amount] to [id]'s [resource], clamped to its registered
  /// maximum. Always succeeds.
  void restore(EntityId id, String resource, num amount) =>
      add(id, resource, amount);
}
