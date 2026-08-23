import '../component/component_store.dart';
import '../entity/entity_id.dart';
import '../entity/entity_registry.dart';
import '../event/event_bus.dart';
import 'character_component.dart';
import 'character_events.dart';

/// Creates and tears down the generic "character" identity for a run.
///
/// A character is an ordinary entity that happens to carry a
/// [CharacterComponent] — nothing about it is sealed or special. Future
/// plugins (Physique, resources, item mastery, learned techniques, Tome,
/// progression, combat state, ...) attach their own components onto the
/// same [EntityId]; this service knows nothing about any of them.
///
/// Constructed once alongside [EntityRegistry]/[ComponentStore]/[EventBus]
/// (see `PluginContext`) — its constructor subscribes to [EntityDestroyed]
/// for the lifetime of the app, so [CharacterComponent] cleanup is automatic
/// rather than pushed onto every caller, unlike the general [ComponentStore]
/// cleanup convention documented in `ARCHITECTURE.md` (which applies when a
/// component's owner isn't a single dedicated Core service like this one).
class CharacterService {
  CharacterService({
    required EntityRegistry entities,
    required ComponentStore components,
    required EventBus events,
  })  : _entities = entities,
        _components = components,
        _events = events {
    _events.subscribe<EntityDestroyed>(_onEntityDestroyed);
  }

  final EntityRegistry _entities;
  final ComponentStore _components;
  final EventBus _events;

  /// Allocates a new entity (deterministic — [EntityRegistry.create] is
  /// sequential, no randomness involved), attaches a [CharacterComponent],
  /// publishes [CharacterCreated], and returns the new [EntityId].
  EntityId create() {
    final id = _entities.create();
    _components.add(id, const CharacterComponent());
    _events.publish(CharacterCreated(id));
    return id;
  }

  void _onEntityDestroyed(EntityDestroyed event) {
    _components.remove<CharacterComponent>(event.id);
  }
}
