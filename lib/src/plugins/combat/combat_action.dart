import 'package:build_engine/build_engine.dart';

/// A generic combat action: what an actor can do to zero or more targets
/// on their turn. Plugins compose their own actions by implementing this
/// directly — the same "no registry required" pattern `Condition`/`Effect`
/// already use in core.
abstract class CombatAction {
  const CombatAction();

  /// The entity performing this action.
  EntityId get actor;

  /// The entities this action affects. A plain list, not a resolver
  /// strategy — whoever builds the action (AI, UI, a future plugin)
  /// decides who's targeted.
  List<EntityId> get targets;

  /// Checked against [actor] before anything else applies. Every
  /// condition must pass (AND) for [costEffects]/[effectsFor] to run.
  List<Condition> get conditions => const [];

  /// Applied once to [actor] if [conditions] all pass.
  List<Effect> get costEffects => const [];

  /// Applied once for each entry in [targets] if [conditions] all pass.
  /// [context] is the owning `PluginContext` — passed in at call time
  /// (rather than resolved once at construction) so an action can read
  /// execution-time state, e.g. Modifier Engine-derived values, exactly
  /// when it runs.
  List<Effect> effectsFor(EntityId target, PluginContext context);
}

/// A generic "deal damage to targets" action — no martial-arts/magic/
/// weapon vocabulary. [baseDamage] is resolved through the Modifier
/// Engine against [actor]'s [damageStat] before being applied via the
/// existing core `Damage` effect, so a future plugin can affect Combat's
/// damage purely by registering a `Modifier`, with zero Combat-side
/// knowledge that plugin exists.
class AttackAction extends CombatAction {
  const AttackAction({
    required this.actor,
    required this.targets,
    required this.baseDamage,
    required this.damageStat,
    this.conditions = const [],
    this.costEffects = const [],
  });

  @override
  final EntityId actor;
  @override
  final List<EntityId> targets;

  /// The un-modified damage value; see [effectsFor] for how modifiers
  /// adjust it.
  final num baseDamage;

  /// The `Modifier.stat` key this action reads on [actor] — an arbitrary,
  /// caller-chosen string. Combat never interprets its value.
  final String damageStat;

  @override
  final List<Condition> conditions;
  @override
  final List<Effect> costEffects;

  @override
  List<Effect> effectsFor(EntityId target, PluginContext context) {
    final resolved = const ModifierResolver().resolve(
      baseDamage,
      context.modifiers.activeModifiersFor(
        actor,
        damageStat,
        context.components,
      ),
    );
    return [Damage(resolved)];
  }
}
