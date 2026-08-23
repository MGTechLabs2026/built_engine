import '../character/character_service.dart';
import '../component/component_store.dart';
import '../content/content_registry.dart';
import '../discovery/discovery_tracker.dart';
import '../entity/entity_id.dart';
import '../entity/entity_registry.dart';
import '../event/event_bus.dart';
import '../mastery/mastery_tracker.dart';
import '../modifier/modifier_collection.dart';
import '../progression/progression_engine.dart';
import '../query/query_engine.dart';
import '../resource/resource_pool.dart';
import '../rng/rng_service.dart';
import '../rule/rule_context.dart';
import '../rule/rule_engine.dart';
import '../tome/tome_service.dart';

/// The controlled access every plugin lifecycle method receives. Exposes
/// every core service that exists so far.
class PluginContext {
  /// A [MasteryTracker] built when the caller doesn't supply one is
  /// computed first and shared with [ProgressionEngine]'s own default —
  /// see `RuleContext`'s constructor for why this matters. Note this only
  /// keeps *this context's own* `mastery`/`progression` consistent with
  /// each other — if [rules] (an already-constructed [RuleEngine]) was
  /// built with its own unsupplied defaults too, it ends up with a
  /// *different* pair of instances unless the caller passes the same ones
  /// to both constructors (see the bootstrap example in
  /// `ARCHITECTURE.md`).
  factory PluginContext({
    required EntityRegistry entities,
    required ComponentStore components,
    required EventBus events,
    required RngService rng,
    required RuleEngine rules,
    required QueryEngine queries,
    required ModifierCollection modifiers,
    required ContentRegistry content,
    CharacterService? characters,
    ResourcePool? resources,
    MasteryTracker? mastery,
    ProgressionEngine? progression,
    DiscoveryTracker? discovery,
    TomeService? tome,
  }) {
    final sharedMastery =
        mastery ?? MasteryTracker(components: components, events: events);
    return PluginContext._(
      entities: entities,
      components: components,
      events: events,
      rng: rng,
      rules: rules,
      queries: queries,
      modifiers: modifiers,
      content: content,
      characters: characters ??
          CharacterService(entities: entities, components: components, events: events),
      resources: resources ?? ResourcePool(components: components, events: events),
      mastery: sharedMastery,
      progression: progression ??
          ProgressionEngine(components: components, events: events, mastery: sharedMastery),
      discovery: discovery ?? DiscoveryTracker(components: components, events: events),
      tome: tome ?? TomeService(entities: entities, components: components),
    );
  }

  PluginContext._({
    required this.entities,
    required this.components,
    required this.events,
    required this.rng,
    required this.rules,
    required this.queries,
    required this.modifiers,
    required this.content,
    required this.characters,
    required this.resources,
    required this.mastery,
    required this.progression,
    required this.discovery,
    required this.tome,
  });

  final EntityRegistry entities;
  final ComponentStore components;
  final EventBus events;
  final RngService rng;
  final RuleEngine rules;
  final QueryEngine queries;
  final ModifierCollection modifiers;
  final ContentRegistry content;
  final CharacterService characters;
  final ResourcePool resources;
  final MasteryTracker mastery;
  final ProgressionEngine progression;
  final DiscoveryTracker discovery;
  final TomeService tome;
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
        resources: resources,
        mastery: mastery,
        progression: progression,
        discovery: discovery,
      );
}
