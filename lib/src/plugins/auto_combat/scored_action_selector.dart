import 'package:build_engine/build_engine.dart';
import 'package:build_engine/combat_plugin.dart';

import 'action_scorer.dart';
import 'action_selector.dart';

/// The 5-step scoring policy the milestone asks for, built entirely on
/// [ActionScorer] plus existing Core machinery:
///
/// 1. `legalActions` is already step 1 (enumerate legal actions) —
///    `AutoCombatController.step()`'s job, unchanged.
/// 2. [_isAvailable] removes actions whose `conditions` wouldn't currently
///    pass (evaluated via the same `PluginContext.ruleContextFor` every
///    other `Condition` consumer already uses) or whose `costEffects`
///    include a `ConsumeResource` the actor can't currently afford
///    (checked via the existing `ResourcePool.canAfford` — no new
///    resource machinery).
/// 3–4. Every remaining action is scored via [scorer]; the highest wins.
/// 5. Ties resolve deterministically: only a *strictly* higher score
///    replaces the current best, so the earliest-listed action among
///    equal scores is kept — a pure function of [legalActions]' own
///    order, no hidden randomness.
///
/// If every legal action is unavailable, falls back to scoring the full
/// legal set anyway — `CombatSystem.executeAction` already no-ops an
/// action's costs/effects when its conditions fail (documented on
/// `executeAction` itself), so this never produces an illegal call; it
/// simply "spends" a turn attempting the best-scored action.
class ScoredActionSelector implements ActionSelector {
  const ScoredActionSelector({this.scorer = const DefaultActionScorer()});

  final ActionScorer scorer;

  @override
  CombatAction selectAction(
    EntityId actor,
    List<CombatAction> legalActions,
    EntityId? preferredTarget,
    PluginContext context,
  ) {
    final available = [
      for (final action in legalActions)
        if (_isAvailable(action, context)) action,
    ];
    final pool = available.isEmpty ? legalActions : available;

    var best = pool.first;
    var bestScore = scorer.score(best, actor, preferredTarget, context);
    for (final action in pool.skip(1)) {
      final candidateScore = scorer.score(action, actor, preferredTarget, context);
      if (candidateScore > bestScore) {
        best = action;
        bestScore = candidateScore;
      }
    }
    return best;
  }

  bool _isAvailable(CombatAction action, PluginContext context) {
    final ruleContext = context.ruleContextFor(action.actor, triggerEvent: action);
    if (!action.conditions.every((condition) => condition.evaluate(ruleContext))) {
      return false;
    }
    for (final effect in action.costEffects) {
      if (effect is ConsumeResource &&
          !context.resources.canAfford(action.actor, effect.resource, effect.amount)) {
        return false;
      }
    }
    return true;
  }
}
