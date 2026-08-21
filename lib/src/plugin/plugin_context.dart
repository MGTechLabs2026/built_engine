import '../component/component_store.dart';
import '../entity/entity_registry.dart';
import '../event/event_bus.dart';

/// The controlled access every plugin lifecycle method receives. Exposes
/// only the core services that exist so far — no placeholder getters for
/// services (rules, effects, modifiers, ...) that aren't built yet.
class PluginContext {
  const PluginContext({
    required this.entities,
    required this.components,
    required this.events,
  });

  final EntityRegistry entities;
  final ComponentStore components;
  final EventBus events;
}
