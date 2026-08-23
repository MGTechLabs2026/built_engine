import '../character/character_service.dart';
import '../component/component_store.dart';
import '../content/content_registry.dart';
import '../entity/entity_id.dart';
import '../entity/entity_registry.dart';
import '../event/event_bus.dart';
import '../modifier/modifier_collection.dart';
import '../query/query_engine.dart';
import '../rng/rng_service.dart';
import '../rule/rule_context.dart';
import '../rule/rule_engine.dart';

/// The controlled access every plugin lifecycle method receives. Exposes
/// every core service that exists so far.
class PluginContext {
  PluginContext({
    required this.entities,
    required this.components,
    required this.events,
    required this.rng,
    required this.rules,
    required this.queries,
    required this.modifiers,
    required this.content,
    CharacterService? characters,
  }) : characters = characters ??
            CharacterService(
              entities: entities,
              components: components,
              events: events,
            );

  final EntityRegistry entities;
  final ComponentStore components;
  final EventBus events;
  final RngService rng;
  final RuleEngine rules;
  final QueryEngine queries;
  final ModifierCollection modifiers;
  final ContentRegistry content;
  final CharacterService characters;
}

/// Constructs a standalone [RuleContext] for evaluating a [Condition] or
/// applying an [Effect] outside of an event-triggered [Rule] firing —
/// e.g. granting a tag when an entity equips an item or attunes to
/// something. Before this existed, every plugin that needed one
/// reinvented the same construction by hand (see
/// `ARCHITECTURE_AUDIT.md`'s finding #12).
extension PluginContextRuleContext on PluginContext {
  RuleContext ruleContextFor(EntityId subject, {Object? triggerEvent}) =>
      RuleContext(
        subject: subject,
        triggerEvent: triggerEvent ?? const Object(),
        entities: entities,
        components: components,
        events: events,
        rng: rng,
        eventCounts: rules.eventCounts,
      );
}
