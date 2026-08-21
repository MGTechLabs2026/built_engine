import '../query/queries.dart';
import '../query/query.dart';
import 'rule_context.dart';

/// A Rule-scoped boolean check. Plugins implement this directly to add
/// their own conditions — no registry required.
abstract class Condition {
  bool evaluate(RuleContext context);
}

QueryScope _scopeOf(RuleContext context) =>
    QueryScope(components: context.components);

/// Matches when the rule's subject has [tag] in its `TagSet`.
class HasTag implements Condition {
  const HasTag(this.tag);

  final String tag;

  @override
  bool evaluate(RuleContext context) {
    final subject = context.subject;
    if (subject == null) return false;
    return HasTagQuery(tag).matches(subject, _scopeOf(context));
  }
}

/// Matches when the rule's subject has a component of type `T`.
class HasComponent<T extends Object> implements Condition {
  const HasComponent();

  @override
  bool evaluate(RuleContext context) {
    final subject = context.subject;
    if (subject == null) return false;
    return HasComponentQuery<T>().matches(subject, _scopeOf(context));
  }
}

/// Matches when the rule's subject's named [resource] is strictly greater
/// than [threshold]. See [ResourceAboveQuery] for the zero-default on a
/// missing resource/component.
class ResourceAbove implements Condition {
  const ResourceAbove(this.resource, this.threshold);

  final String resource;
  final num threshold;

  @override
  bool evaluate(RuleContext context) {
    final subject = context.subject;
    if (subject == null) return false;
    return ResourceAboveQuery(resource, threshold)
        .matches(subject, _scopeOf(context));
  }
}

/// Matches when the rule's subject's named [resource] is strictly less
/// than [threshold]. See [ResourceBelowQuery] for the zero-default.
class ResourceBelow implements Condition {
  const ResourceBelow(this.resource, this.threshold);

  final String resource;
  final num threshold;

  @override
  bool evaluate(RuleContext context) {
    final subject = context.subject;
    if (subject == null) return false;
    return ResourceBelowQuery(resource, threshold)
        .matches(subject, _scopeOf(context));
  }
}

/// Matches when the rule's subject's health is strictly below
/// [threshold]. See [HealthBelowQuery] for why a missing `HealthComponent`
/// never matches.
class HealthBelow implements Condition {
  const HealthBelow(this.threshold);

  final num threshold;

  @override
  bool evaluate(RuleContext context) {
    final subject = context.subject;
    if (subject == null) return false;
    return HealthBelowQuery(threshold).matches(subject, _scopeOf(context));
  }
}

/// Matches when the rule's subject has [status] active.
class StatusActive implements Condition {
  const StatusActive(this.status);

  final String status;

  @override
  bool evaluate(RuleContext context) {
    final subject = context.subject;
    if (subject == null) return false;
    return StatusActiveQuery(status).matches(subject, _scopeOf(context));
  }
}

/// How [EventCount] compares the tracked count against its threshold.
enum CountComparison {
  greaterThan,
  greaterThanOrEqual,
  lessThan,
  lessThanOrEqual,
  equal,
}

/// Matches based on how many times [eventType] has been published since
/// this rule was registered (see `EventCounter` — counting is not
/// retroactive; `RuleEngine` auto-tracks [eventType] when a rule using
/// this condition is registered).
class EventCount implements Condition {
  const EventCount({
    required this.eventType,
    required this.comparison,
    required this.threshold,
  });

  final Type eventType;
  final CountComparison comparison;
  final int threshold;

  @override
  bool evaluate(RuleContext context) {
    final count = context.eventCounts.countOfType(eventType);
    switch (comparison) {
      case CountComparison.greaterThan:
        return count > threshold;
      case CountComparison.greaterThanOrEqual:
        return count >= threshold;
      case CountComparison.lessThan:
        return count < threshold;
      case CountComparison.lessThanOrEqual:
        return count <= threshold;
      case CountComparison.equal:
        return count == threshold;
    }
  }
}

/// Matches with probability [probability] (`0.0`-`1.0`), via the rule
/// engine's injected `RngService` — never `dart:math` directly.
class RandomChance implements Condition {
  const RandomChance(this.probability);

  final double probability;

  @override
  bool evaluate(RuleContext context) => context.rng.chance(probability);
}
