import '../component/component_store.dart';
import '../entity/entity_id.dart';
import '../entity/entity_registry.dart';
import '../event/event_bus.dart';
import '../rng/rng_service.dart';
import 'event_counter.dart';

/// Everything a [Condition] or an effect needs to evaluate/act: the
/// entity this rule concerns itself with (if any), the event that
/// triggered it, and the core services.
class RuleContext {
  const RuleContext({
    required this.subject,
    required this.triggerEvent,
    required this.entities,
    required this.components,
    required this.events,
    required this.rng,
    required this.eventCounts,
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
}
