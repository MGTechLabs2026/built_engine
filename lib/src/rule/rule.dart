import '../entity/entity_id.dart';
import 'condition.dart';
import 'effect.dart';

/// A generic `WHEN trigger IF conditions THEN effects` rule, composed
/// entirely from reusable [Condition]/[Effect] building blocks — no
/// content-specific logic lives in this class or in `RuleEngine`.
class Rule {
  const Rule({
    required this.trigger,
    this.subjectOf,
    this.conditions = const [],
    required this.effects,
  });

  /// The event [Type] this rule listens for.
  final Type trigger;

  /// Resolves the entity this rule's conditions/effects act on from the
  /// triggering event instance. `null` (the default) for rules with no
  /// subject (e.g. one that only checks [EventCount]/[RandomChance]).
  final EntityId? Function(Object event)? subjectOf;

  /// Every condition must pass (AND) for [effects] to run.
  final List<Condition> conditions;

  /// Run in list order, only if every condition passes.
  final List<Effect> effects;
}
