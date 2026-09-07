import 'package:build_engine/build_engine.dart';
import 'package:build_engine/combat_plugin.dart';
import 'package:build_engine/consumable_plugin.dart';

import 'build_action_interpreter.dart';
import 'self_effect_action.dart';

/// Translates `consumable`-typed [ResolvedBuild] components into
/// [CombatAction]s. Lives here (not in `lib/src/plugins/consumable/`) so
/// the Consumable plugin's own content/resource lifecycle stays
/// Combat-free — only this bridging interpreter needs both, exactly like
/// `Item`/`Technique`.
///
/// One action per hung consumable ref, mapped 1:1 from its
/// `ConsumableEffectSpec` (SP3 §5.2). Every action carries
/// `costEffects: [ConsumeResource(consumable:<id>, 1)]` (the per-fight
/// charge — `ConsumableBinder` grants the pool, `ScoredActionSelector`
/// filters when it is empty), a matching
/// `conditions: [ResourceAbove(consumable:<id>, 0)]` gate, the content
/// `priority`, and `sourceRef`. An `attack` consumable with no `targets`
/// yields no action, mirroring `TechniqueActionInterpreter`.
///
/// The `ResourceAbove` condition is not redundant with the cost:
/// `ScoredActionSelector` falls back to the full legal-action set when
/// *every* action is unaffordable (`available.isEmpty`), and
/// `CombatSystem.executeAction` gates costs **and** effects on
/// `action.conditions` only. Without the condition, a consumable that is
/// the player's sole legal action would be force-executed for free once
/// its pool hits `0` (SP3 C1 regression). With it, that forced path
/// no-ops the effect too, and the harness's fallback strike (see
/// `CombatStage`) keeps the player able to act.
class ConsumableActionInterpreter implements BuildActionInterpreter {
  const ConsumableActionInterpreter();

  @override
  List<CombatAction> interpret({
    required ResolvedBuild build,
    required EntityId actor,
    required List<EntityId> targets,
    required PluginContext context,
  }) {
    final actions = <CombatAction>[];
    for (final ref in build.active) {
      if (ref.referenceType != consumableReferenceType) continue;
      final definition = context.content.find(ref.contentId);
      if (definition == null) continue;
      final consumable = consumableDefinitionFromContent(definition);
      final action = _actionFor(consumable, actor, targets, ref);
      if (action != null) actions.add(action);
    }
    return actions;
  }

  @override
  List<AuraRule> auraRules({
    required ResolvedBuild build,
    required PluginContext context,
  }) =>
      const [];

  CombatAction? _actionFor(
    ConsumableDefinition c,
    EntityId actor,
    List<EntityId> targets,
    BuildComponentRef ref,
  ) {
    final resource = consumableChargeResource(c.id);
    final cost = [ConsumeResource(resource, 1)];
    final gate = <Condition>[ResourceAbove(resource, 0)];
    switch (c.effect) {
      case ConsumableHeal(:final amount):
        return SelfEffectAction(
          actor: actor,
          selfEffects: [Heal(amount)],
          conditions: gate,
          costEffects: cost,
          priority: c.priority,
          sourceRef: ref,
        );
      case ConsumableAttack(:final damage, :final stat):
        if (targets.isEmpty) return null;
        return AttackAction(
          actor: actor,
          targets: targets,
          baseDamage: damage,
          damageStat: stat,
          conditions: gate,
          costEffects: cost,
          priority: c.priority,
          sourceRef: ref,
        );
      case ConsumableGrantModifier(:final stat, :final operation, :final value):
        return SelfEffectAction(
          actor: actor,
          selfEffects: [
            GrantModifier(stat, operation, value, sourceKey: 'consumable:${c.id}'),
          ],
          conditions: gate,
          costEffects: cost,
          priority: c.priority,
          sourceRef: ref,
        );
      case ConsumableRemoveAllStatuses():
        return SelfEffectAction(
          actor: actor,
          selfEffects: const [RemoveAllStatuses()],
          conditions: gate,
          costEffects: cost,
          priority: c.priority,
          sourceRef: ref,
        );
    }
  }
}
