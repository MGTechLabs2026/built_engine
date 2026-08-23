import 'package:build_engine/build_engine.dart';

import 'elemental_affinity_component.dart';

/// Matches when the rule's subject has at least [threshold] affinity for
/// [element] (see `attuneToElement`) — the same shape as core's
/// `ResourceAbove`/`HealthBelow`, just reading this plugin's own
/// component instead of a core one.
class HasElementalAffinity implements Condition {
  const HasElementalAffinity(this.element, this.threshold);

  final String element;
  final num threshold;

  @override
  bool evaluate(RuleContext context) {
    final subject = context.subject;
    if (subject == null) return false;
    final affinity =
        context.components.get<ElementalAffinityComponent>(subject);
    return (affinity?.affinities[element] ?? 0) >= threshold;
  }
}
