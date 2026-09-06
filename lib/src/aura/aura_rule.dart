import '../rule/rule.dart';
import 'aura_scope.dart';

/// One aura: an unmodified Core [Rule] body (trigger + conditions +
/// effects, straight from the `ContentRegistry.loadRule` DSL) plus the
/// single piece of aura-specific metadata the binder needs to scope it.
///
/// [rule] is never mutated. [sourceRuleId] is the `RuleDefinition` id it
/// came from — for diagnostics / logging ONLY. It is **never** a sort
/// key: aura firing order is fixed by interpreter-list order ->
/// `build.active` order -> a component's `auraRuleIds` order ->
/// `EventBus` subscription order, and nothing re-orders `AuraRule`s.
class AuraRule {
  const AuraRule({
    required this.rule,
    required this.scope,
    required this.sourceRuleId,
  });

  final Rule rule;
  final AuraScope scope;
  final String sourceRuleId;
}
