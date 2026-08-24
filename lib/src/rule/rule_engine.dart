import '../component/component_store.dart';
import '../discovery/discovery_tracker.dart';
import '../entity/entity_registry.dart';
import '../event/event_bus.dart';
import '../mastery/mastery_tracker.dart';
import '../progression/progression_engine.dart';
import '../resource/resource_pool.dart';
import '../rng/rng_service.dart';
import 'condition.dart';
import 'core_services.dart';
import 'event_counter.dart';
import 'rule.dart';
import 'rule_context.dart';

/// Registers [Rule]s and dispatches them off the [EventBus]. Deterministic:
/// conditions are evaluated in list order (all must pass), then effects run
/// in list order — no other source of nondeterminism is introduced beyond
/// whatever the injected [RngService] itself produces.
class RuleEngine {
  /// A [MasteryTracker] built when the caller doesn't supply one is
  /// computed first and shared with [ProgressionEngine]'s own default —
  /// see `RuleContext`'s constructor for why this matters.
  factory RuleEngine({
    required EntityRegistry entities,
    required ComponentStore components,
    required EventBus events,
    required RngService rng,
    CoreServices? shared,
    ResourcePool? resources,
    MasteryTracker? mastery,
    ProgressionEngine? progression,
    DiscoveryTracker? discovery,
  }) {
    final sharedMastery = mastery ??
        shared?.mastery ??
        MasteryTracker(components: components, events: events);
    return RuleEngine._(
      entities: entities,
      components: components,
      events: events,
      rng: rng,
      resources: resources ??
          shared?.resources ??
          ResourcePool(components: components, events: events),
      mastery: sharedMastery,
      progression: progression ??
          shared?.progression ??
          ProgressionEngine(components: components, events: events, mastery: sharedMastery),
      discovery: discovery ??
          shared?.discovery ??
          DiscoveryTracker(components: components, events: events),
    );
  }

  RuleEngine._({
    required EntityRegistry entities,
    required ComponentStore components,
    required EventBus events,
    required RngService rng,
    required ResourcePool resources,
    required MasteryTracker mastery,
    required ProgressionEngine progression,
    required DiscoveryTracker discovery,
  })  : _entities = entities,
        _components = components,
        _events = events,
        _rng = rng,
        _resources = resources,
        _mastery = mastery,
        _progression = progression,
        _discovery = discovery,
        _eventCounts = EventCounter(events);

  final EntityRegistry _entities;
  final ComponentStore _components;
  final EventBus _events;
  final RngService _rng;
  final ResourcePool _resources;
  final MasteryTracker _mastery;
  final ProgressionEngine _progression;
  final DiscoveryTracker _discovery;
  final EventCounter _eventCounts;

  /// The shared event counter used by every [EventCount] condition this
  /// engine's rules reference. Exposed so a caller can call
  /// `eventCounts.trackType(SomeEvent)` directly for an `EventCount` nested
  /// inside a composite condition — `register`'s automatic tracking only
  /// scans the top level of a rule's `conditions` list.
  EventCounter get eventCounts => _eventCounts;

  /// Registers [rule], auto-tracking (via `EventCounter.trackType`) the
  /// event type of every [EventCount] condition it uses, then subscribing
  /// to [Rule.trigger] so [rule] fires whenever that event is published.
  /// Returns the [EventSubscription] so a caller can later unsubscribe
  /// (e.g. on plugin stop/unregister).
  EventSubscription register(Rule rule) {
    for (final condition in rule.conditions) {
      if (condition is EventCount) {
        _eventCounts.trackType(condition.eventType);
      }
    }
    return _events.subscribeDynamic(rule.trigger, (event) => _fire(rule, event));
  }

  void _fire(Rule rule, Object event) {
    final subject = rule.subjectOf?.call(event);
    final context = RuleContext(
      subject: subject,
      triggerEvent: event,
      entities: _entities,
      components: _components,
      events: _events,
      rng: _rng,
      eventCounts: _eventCounts,
      resources: _resources,
      mastery: _mastery,
      progression: _progression,
      discovery: _discovery,
    );

    final allConditionsPass =
        rule.conditions.every((condition) => condition.evaluate(context));
    if (!allConditionsPass) return;

    for (final effect in rule.effects) {
      effect.apply(context);
    }
  }
}
