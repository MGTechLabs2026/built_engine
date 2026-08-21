/// Build Engine — a modular, data-driven game engine core.
///
/// The core provides generic verbs (entities, components, events, plugins);
/// game-specific content belongs in plugins, not here.
library;

export 'src/component/component_store.dart';
export 'src/components/health_component.dart';
export 'src/components/resource_component.dart';
export 'src/components/stat_component.dart';
export 'src/components/status_component.dart';
export 'src/components/tag_set.dart';
export 'src/entity/entity_id.dart';
export 'src/entity/entity_registry.dart';
export 'src/event/event_bus.dart';
export 'src/plugin/game_plugin.dart';
export 'src/plugin/plugin_context.dart';
export 'src/plugin/plugin_exceptions.dart';
export 'src/plugin/plugin_manager.dart';
export 'src/rng/rng_service.dart';
