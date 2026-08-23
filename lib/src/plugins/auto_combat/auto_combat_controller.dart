import 'package:build_engine/build_engine.dart';
import 'package:build_engine/combat_plugin.dart';

import 'combat_policy.dart';

/// Decides *what action to perform* each turn of a battle already running
/// through the existing, untouched `CombatSystem` — a separate layer, not
/// an expansion of `CombatSystem` itself. Knows nothing about any specific
/// content ("Sword"/"Boxing"/"Punch"/"Magic") — only `EntityId`,
/// `CombatAction`, `CombatantComponent`, and `HealthComponent`, all
/// already-generic Combat/Core vocabulary.
///
/// [availableActions] is one flat pool spanning every participant in
/// [battle] (not resupplied per turn) — each turn, `step()` filters it to
/// the *legal* subset for whoever's turn it currently is: the action's
/// `actor` must match, and every one of its `targets` must currently be
/// alive (checked via `HealthBelowQuery`, the exact query `CombatSystem`
/// itself already uses for living-participant checks — no new legality
/// machinery). [policy] then picks one of those legal actions to execute.
class AutoCombatController {
  AutoCombatController({
    required this.context,
    required this.combatSystem,
    required this.battle,
    required this.availableActions,
    this.policy = const CombatPolicy.simple(),
  });

  final PluginContext context;
  final CombatSystem combatSystem;
  final EntityId battle;
  final List<CombatAction> availableActions;
  final CombatPolicy policy;

  /// Whether [battle] is still active.
  bool get isActive => context.components.get<CombatStateComponent>(battle)?.active ?? false;

  /// Runs one turn: picks a legal action for whoever's turn it is (via
  /// [policy]) and executes it through [combatSystem]. Returns `false` —
  /// without executing anything — if the battle isn't active, or no legal
  /// action exists for the current actor; never throws for either case.
  bool step() {
    final state = context.components.get<CombatStateComponent>(battle);
    if (state == null || !state.active) return false;

    final actor = state.participants[state.currentTurnIndex];
    final living = context.queries
        .evaluate(state.participants, HealthBelowQuery(1).not())
        .toSet();
    final legalActions = [
      for (final action in availableActions)
        if (action.actor == actor &&
            action.targets.isNotEmpty &&
            action.targets.every(living.contains))
          action,
    ];
    final otherLivingParticipants = [
      for (final id in state.participants)
        if (id != actor && living.contains(id)) id,
    ];

    final chosen = policy.decideNextAction(actor, legalActions, otherLivingParticipants);
    if (chosen == null) return false;

    combatSystem.executeAction(battle, chosen);
    return true;
  }

  /// Runs [step] repeatedly until the battle ends or no legal action can
  /// be found for the current actor. [maxSteps] is a safety stop against
  /// a misconfigured battle that can never end — not expected to matter
  /// in a normal run.
  void runUntilBattleEnds({int maxSteps = 10000}) {
    var steps = 0;
    while (isActive && steps < maxSteps) {
      if (!step()) break;
      steps += 1;
    }
  }
}
