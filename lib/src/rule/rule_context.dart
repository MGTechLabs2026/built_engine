import '../component/component_store.dart';
import '../discovery/discovery_tracker.dart';
import '../entity/entity_id.dart';
import '../entity/entity_registry.dart';
import '../event/event_bus.dart';
import '../mastery/mastery_tracker.dart';
import '../progression/progression_engine.dart';
import '../resource/resource_pool.dart';
import '../rng/rng_service.dart';
import 'event_counter.dart';

/// Everything a [Condition] or an effect needs to evaluate/act: the
/// entity this rule concerns itself with (if any), the event that
/// triggered it, and the core services.
class RuleContext {
  /// A [MasteryTracker] built when the caller doesn't supply one is
  /// computed first and shared with [ProgressionEngine]'s own default —
  /// otherwise an unsupplied `progression` would default to a *different*
  /// `MasteryTracker` instance than [mastery] itself, silently splitting
  /// what should be one shared store in two.
  factory RuleContext({
    required EntityId? subject,
    required Object triggerEvent,
    required EntityRegistry entities,
    required ComponentStore components,
    required EventBus events,
    required RngService rng,
    required EventCounter eventCounts,
    ResourcePool? resources,
    MasteryTracker? mastery,
    ProgressionEngine? progression,
    DiscoveryTracker? discovery,
  }) {
    final sharedMastery =
        mastery ?? MasteryTracker(components: components, events: events);
    return RuleContext._(
      subject: subject,
      triggerEvent: triggerEvent,
      entities: entities,
      components: components,
      events: events,
      rng: rng,
      eventCounts: eventCounts,
      resources: resources ?? ResourcePool(components: components, events: events),
      mastery: sharedMastery,
      progression: progression ??
          ProgressionEngine(components: components, events: events, mastery: sharedMastery),
      discovery: discovery ?? DiscoveryTracker(components: components, events: events),
    );
  }

  RuleContext._({
    required this.subject,
    required this.triggerEvent,
    required this.entities,
    required this.components,
    required this.events,
    required this.rng,
    required this.eventCounts,
    required this.resources,
    required this.mastery,
    required this.progression,
    required this.discovery,
  });

  /// The entity this rule's conditions/effects act on, resolved from the
  /// triggering event by the owning rule's `subjectOf`. `null` if the
  /// rule has no subject (e.g. a rule that only checks [EventCount] or
  /// [RandomChance]).
  final EntityId? subject;

  /// The event instance that caused this rule to fire.
  final Object triggerEvent;

  final EntityRegistry entities;
  final ComponentStore components;
  final EventBus events;
  final RngService rng;
  final EventCounter eventCounts;
  final ResourcePool resources;
  final MasteryTracker mastery;
  final ProgressionEngine progression;
  final DiscoveryTracker discovery;
}
