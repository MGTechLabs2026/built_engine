import 'package:build_engine/build_engine.dart';
import 'package:build_engine/combat_plugin.dart';

import 'action_scorer.dart';

/// `DefaultActionScorer` plus consumable-shaped intent, read from the
/// action's own Core effect types (SP3 §5.6) — the same category as the
/// base scorer's `action is AttackAction` check, no domain vocabulary:
///
/// - each `Heal` effect adds `missingHealthWeight * (1 - actorHpFraction)`
///   — near-worthless at full HP, top value near death;
/// - each `ApplyStatus` effect adds a flat `buffBonus` (an early-use buff).
///
/// Offensive consumables are `AttackAction` and are already scored by
/// resolved damage in the composed base. `GrantModifier` matches neither
/// branch (priority-gated). Applies to ANY heal/buff action, not only
/// consumables (a healing guard technique gets smarter too).
class ConsumableAwareActionScorer implements ActionScorer {
  const ConsumableAwareActionScorer({
    this.base = const DefaultActionScorer(),
    this.missingHealthWeight = 40,
    this.buffBonus = 6,
  });

  final ActionScorer base;
  final num missingHealthWeight;
  final num buffBonus;

  @override
  num score(
    CombatAction action,
    EntityId actor,
    EntityId? preferredTarget,
    PluginContext context,
  ) {
    var total = base.score(action, actor, preferredTarget, context);
    final hp = context.components.get<HealthComponent>(actor);
    final missing = (hp == null || hp.max <= 0)
        ? 0.0
        : (1 - hp.current / hp.max).clamp(0.0, 1.0);
    for (final effect in action.effectsFor(action.actor, context)) {
      if (effect is Heal) total += missingHealthWeight * missing;
      if (effect is ApplyStatus) total += buffBonus;
    }
    return total;
  }
}
