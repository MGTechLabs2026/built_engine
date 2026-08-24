import 'package:build_engine/build_engine.dart';
import 'package:build_engine/combat_plugin.dart';

import 'action_scorer.dart';
import 'action_selector.dart';
import 'scored_action_selector.dart';
import 'target_selector.dart';

/// Bundles a [TargetSelector] and an [ActionSelector] into the strategy
/// `AutoCombatController` consults each turn. Swapping either half changes
/// AutoCombat's behavior without touching the controller itself.
class CombatPolicy {
  const CombatPolicy({required this.targetSelector, required this.actionSelector});

  /// The original, deliberately simple policy: choose a legal action,
  /// choose a target, nothing more sophisticated.
  const CombatPolicy.simple()
      : targetSelector = const FirstLivingParticipantTargetSelector(),
        actionSelector = const FirstMatchingActionSelector();

  /// The scoring policy: enumerate legal actions, remove unavailable ones
  /// (conditions/resource affordability), score the rest (priority +
  /// Modifier-Engine-aware effectiveness by default, via [scorer]),
  /// select the highest score, break ties deterministically by list
  /// order. See `ScoredActionSelector`/`DefaultActionScorer`.
  CombatPolicy.scored({
    this.targetSelector = const FirstLivingParticipantTargetSelector(),
    ActionScorer scorer = const DefaultActionScorer(),
  }) : actionSelector = ScoredActionSelector(scorer: scorer);

  final TargetSelector targetSelector;
  final ActionSelector actionSelector;

  /// `null` if [legalActions] is empty — nothing to decide.
  CombatAction? decideNextAction(
    EntityId actor,
    List<CombatAction> legalActions,
    List<EntityId> otherLivingParticipants,
    PluginContext context,
  ) {
    if (legalActions.isEmpty) return null;
    final preferredTarget = targetSelector.selectTarget(actor, otherLivingParticipants);
    return actionSelector.selectAction(actor, legalActions, preferredTarget, context);
  }
}
