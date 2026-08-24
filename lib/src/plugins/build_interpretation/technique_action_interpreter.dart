import 'package:build_engine/build_engine.dart';
import 'package:build_engine/combat_plugin.dart';
import 'package:build_engine/technique_plugin.dart';

import 'build_action_interpreter.dart';
import 'self_effect_action.dart';
import 'weapon_stat_tags.dart';

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
class TechniqueActionInterpreter implements BuildActionInterpreter {
  const TechniqueActionInterpreter();

  @override
  List<CombatAction> interpret({
    required ActiveBuild build,
    required EntityId actor,
    required List<EntityId> targets,
    required PluginContext context,
  }) {
    final actions = <CombatAction>[];
    for (final ref in build.components) {
      if (ref.referenceType != techniqueReferenceType) continue;
      final definition = context.content.find(ref.contentId);
      if (definition == null) continue; // unknown/invalid technique -> no action, not a crash
      final technique = techniqueDefinitionFromContent(definition);
      final action = _actionFor(technique, actor, targets);
      if (action != null) actions.add(action);
    }
    return actions;
  }

  CombatAction? _actionFor(
    TechniqueDefinition technique,
    EntityId actor,
    List<EntityId> targets,
  ) {
    if (technique.tags.contains('guard')) {
      return SelfEffectAction(
        actor: actor,
        selfEffects: [ApplyStatus('status:guard:${technique.id}')],
      );
    }
    final damage = technique.properties['damage'];
    if (damage == null || targets.isEmpty) return null;
    return AttackAction(
      actor: actor,
      targets: targets,
      baseDamage: damage,
      damageStat: _damageStatFor(technique),
    );
  }

  String _damageStatFor(TechniqueDefinition technique) =>
      WeaponStatTags.matchOrFallback(technique.tags, techniqueSubject(technique.id));
}
