import '../component/component_store.dart';
import '../content/content_registry.dart';
import '../entity/entity_registry.dart';
import '../event/event_bus.dart';
import '../modifier/modifier_collection.dart';
import '../query/query_engine.dart';
import '../rng/rng_service.dart';
import '../rule/rule_engine.dart';

/// The controlled access every plugin lifecycle method receives. Exposes
/// every core service that exists so far.
class PluginContext {
  const PluginContext({
    required this.entities,
    required this.components,
    required this.events,
    required this.rng,
    required this.rules,
    required this.queries,
    required this.modifiers,
    required this.content,
  });

  final EntityRegistry entities;
  final ComponentStore components;
  final EventBus events;
  final RngService rng;
  final RuleEngine rules;
  final QueryEngine queries;
  final ModifierCollection modifiers;
  final ContentRegistry content;
}
