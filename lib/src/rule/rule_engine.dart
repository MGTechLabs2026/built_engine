import '../component/component_store.dart';
import '../entity/entity_registry.dart';
import '../event/event_bus.dart';
import '../rng/rng_service.dart';
import 'condition.dart';
import 'event_counter.dart';
import 'rule.dart';
import 'rule_context.dart';

/// Registers [Rule]s and dispatches them off the [EventBus]. Deterministic:
/// conditions are evaluated in list order (all must pass), then effects run
/// in list order — no other source of nondeterminism is introduced beyond
/// whatever the injected [RngService] itself produces.
class RuleEngine {
  RuleEngine({
    required EntityRegistry entities,
    required ComponentStore components,
    required EventBus events,
    required RngService rng,
  })  : _entities = entities,
        _components = components,
        _events = events,
        _rng = rng,
        _eventCounts = EventCounter(events);

  final EntityRegistry _entities;
  final ComponentStore _components;
  final EventBus _events;
  final RngService _rng;
  final EventCounter _eventCounts;

  /// Registers [rule], auto-tracking (via `EventCounter.trackType`) the
  /// event type of every [EventCount] condition it uses, then subscribing
  /// to [Rule.trigger] so [rule] fires whenever that event is published.
  void register(Rule rule) {
    for (final condition in rule.conditions) {
      if (condition is EventCount) {
        _eventCounts.trackType(condition.eventType);
      }
    }
    _events.subscribeDynamic(rule.trigger, (event) => _fire(rule, event));
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
    );

    final allConditionsPass =
        rule.conditions.every((condition) => condition.evaluate(context));
    if (!allConditionsPass) return;

    for (final effect in rule.effects) {
      effect.apply(context);
    }
  }
}
