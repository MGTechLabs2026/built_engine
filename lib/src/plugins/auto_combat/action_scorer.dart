import 'package:build_engine/build_engine.dart';
import 'package:build_engine/combat_plugin.dart';

/// Assigns a numeric desirability score to [action] for [actor] — higher
/// is more desirable. Plugins implement this directly (no registry) to
/// bring in their own scoring heuristics; `ScoredActionSelector` picks
/// whichever legal, available action scores highest.
abstract class ActionScorer {
  num score(
    CombatAction action,
    EntityId actor,
    EntityId? preferredTarget,
    PluginContext context,
  );
}

/// The generic default scorer: `action.priority` (a plain, content-defined
/// hint — never martial/weapon-specific) plus a bonus for targeting
/// [preferredTarget], plus — for `AttackAction` specifically, the one
/// concrete `CombatAction` Core/Combat itself ships — its *resolved*
/// damage, run through the exact same `ModifierResolver` +
/// `ModifierCollection.activeModifiersFor` pipeline `AttackAction.effectsFor`
/// itself uses. This is how build synergy (Physique + Martial Style +
/// Technique + Item, all contributing `Modifier`s on the same
/// `damageStat`) changes AutoCombat's choices without this class knowing
/// anything about Physique/MartialArts/Technique/Item: it only reads the
/// existing, already-generic Modifier Engine, exactly the way `claude.md`'s
/// MODIFIER SYSTEM section intends modifiers to be consumed. Checking
/// `action is AttackAction` is a Combat-vocabulary check (Core's own
/// concrete action type), not a domain-vocabulary one — no
/// `if item == sword` anywhere here.
class DefaultActionScorer implements ActionScorer {
  const DefaultActionScorer();

  static const num _preferredTargetBonus = 10;

  @override
  num score(
    CombatAction action,
    EntityId actor,
    EntityId? preferredTarget,
    PluginContext context,
  ) {
    num total = action.priority;
    if (preferredTarget != null && action.targets.contains(preferredTarget)) {
      total += _preferredTargetBonus;
    }
    if (action is AttackAction) {
      total += const ModifierResolver().resolve(
        action.baseDamage,
        context.modifiers.activeModifiersFor(
          action.actor,
          action.damageStat,
          context.components,
        ),
      );
    }
    return total;
  }
}
