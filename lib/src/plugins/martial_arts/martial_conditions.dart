import 'package:build_engine/build_engine.dart';
import 'package:build_engine/combat_plugin.dart';

/// Matches when the rule's triggering event is an `ActionCompleted` whose
/// `targets` include at least one entity tagged `stance:tai_chi` —
/// regardless of who the attacker is, including a plain core
/// `AttackAction` from an entity with zero martial-arts awareness. Used
/// by the Tai Chi counter/redirect `Rule` (see `martial_arts_rules.dart`).
///
/// Known simplification: `ActionCompleted` publishes whether or not the
/// triggering action's own conditions passed (Combat exposes no "did it
/// land" flag on the event, and adding one would require modifying
/// Combat) — so this matches on any completed action targeting a Tai Chi
/// stance, landed or not.
///
/// `event.actor` is excluded from the target scan, so a self-targeted
/// action (e.g. activating a Tai Chi stance, which targets its own actor)
/// never counters itself. A third party's non-damaging action that
/// targets a Tai Chi-stanced entity (e.g. an ally's heal) still matches —
/// this condition has no way to distinguish "damaging" from "any
/// completed action" without a Combat-side change, same reasoning as the
/// landed-vs-missed simplification above.
class TaiChiCounterCondition implements Condition {
  const TaiChiCounterCondition();

  @override
  bool evaluate(RuleContext context) {
    final event = context.triggerEvent;
    if (event is! ActionCompleted) return false;
    final scope = QueryScope(components: context.components);
    return event.targets.any((target) =>
        target != event.actor &&
        HasTagQuery('stance:tai_chi').matches(target, scope));
  }
}
