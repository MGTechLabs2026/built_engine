import 'package:build_engine/build_engine.dart';
import 'package:build_engine/combat_plugin.dart';
import 'package:build_engine/item_plugin.dart';
import 'package:build_engine/technique_plugin.dart';

import 'build_action_interpreter.dart';
import 'self_effect_action.dart';

/// Translates `technique`-typed [ActiveBuild] components into
/// [CombatAction]s — the plugin-level replacement for
/// `vertical_slice_runner.dart`'s old `_actionFor`/`_damageTable`. Lives
/// here (not in `lib/src/plugins/technique/`) so the Technique plugin's
/// own discovery/learning/mastery lifecycle stays entirely Combat-free;
/// only this bridging interpreter needs both.
///
/// The mapping itself is plain content interpretation, not engine logic:
/// a `'guard'`-tagged technique becomes a defensive [SelfEffectAction]
/// (Basic Guard); anything else with a `properties['damage']` becomes an
/// [AttackAction] (Basic Punch, Basic Slash); a technique with neither
/// produces no action at all — never a crash, never a garbage action.
/// `damageStat` is the technique's own `'fist'`/`'blade'` tag if present,
/// falling back to a per-technique subject string otherwise — the same
/// tag names `ItemActionInterpreter` independently agrees on, so an
/// item's contribution and a technique's damage land on the same stat
/// with zero import between the two plugins.
///
/// When the ref carries a `TechniqueVariant` instance (SP1), the variant's
/// `EffectProfile` `active`-tier `'power'` contribution
/// (`effectProfile().amount(EffectTier.active, 'power')`) is added to the
/// base-family damage, floored at 1; other axes are not mapped to combat
/// in SP1. The variant derives that number from its own `power` axis, but
/// the interpreter no longer reads that field directly — the value flows
/// through the general `EffectProfile`/`EffectTier.active` primitive.
class TechniqueActionInterpreter implements BuildActionInterpreter {
  const TechniqueActionInterpreter();

  @override
  List<CombatAction> interpret({
    required ResolvedBuild build,
    required EntityId actor,
    required List<EntityId> targets,
    required PluginContext context,
  }) {
    final actions = <CombatAction>[];
    for (final ref in build.active) {
      if (ref.referenceType != techniqueReferenceType) continue;
      final definition = context.content.find(ref.contentId);
      if (definition == null) continue; // unknown/invalid technique -> no action, not a crash
      final technique = techniqueDefinitionFromContent(definition);
      final variant = ref.instanceEntityId == null
          ? null
          : context.components.get<TechniqueVariant>(ref.instanceEntityId!);
      final action = _actionFor(technique, actor, targets, ref, variant);
      if (action != null) actions.add(action);
    }
    return actions;
  }

  CombatAction? _actionFor(
    TechniqueDefinition technique,
    EntityId actor,
    List<EntityId> targets,
    BuildComponentRef ref,
    TechniqueVariant? variant,
  ) {
    if (technique.tags.contains('guard')) {
      return SelfEffectAction(
        actor: actor,
        selfEffects: [ApplyStatus('status:guard:${technique.id}')],
        sourceRef: ref,
      );
    }
    final base = technique.properties['damage'];
    if (base == null || targets.isEmpty) return null;
    final power = variant?.effectProfile().amount(EffectTier.active, 'power') ?? 0;
    final folded = base + power;
    final damage = folded < 1 ? 1 : folded;
    return AttackAction(
      actor: actor,
      targets: targets,
      baseDamage: damage,
      damageStat: _damageStatFor(technique),
      sourceRef: ref,
    );
  }

  String _damageStatFor(TechniqueDefinition technique) =>
      WeaponStatTags.matchOrFallback(technique.tags, techniqueSubject(technique.id));
}
