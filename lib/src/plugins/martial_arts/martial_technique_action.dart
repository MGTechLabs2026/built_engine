import 'package:build_engine/build_engine.dart';
import 'package:build_engine/combat_plugin.dart';

/// One class for every technique and stance — the same "don't create a
/// new source-code class per content item" principle `AttackAction`
/// already demonstrates. Set [baseDamage]/[damageStat] together for an
/// attack technique (damage resolved through the Modifier Engine,
/// identical mechanism to `AttackAction`); leave both null and set
/// [selfEffects] instead for a stance/utility technique (with `targets:
/// [actor]` at the call site) — never set both kinds on one instance.
///
/// The 6 techniques and 3 stances themselves are data, loaded via
/// `ContentRegistry` — see `martial_technique_content.dart`'s
/// `martialTechniqueContentDefinitions` and
/// `martialTechniqueFromDefinition`.
class MartialTechniqueAction extends CombatAction {
  const MartialTechniqueAction({
    required this.actor,
    required this.targets,
    required this.tags,
    this.conditions = const [],
    this.costEffects = const [],
    this.baseDamage,
    this.damageStat,
    this.selfEffects = const [],
  });

  @override
  final EntityId actor;
  @override
  final List<EntityId> targets;

  /// This technique's own tags (fist/palm/internal/etc) — content
  /// metadata, not read by any Condition in this plugin.
  final Set<String> tags;

  @override
  final List<Condition> conditions;
  @override
  final List<Effect> costEffects;

  final num? baseDamage;
  final String? damageStat;
  final List<Effect> selfEffects;

  @override
  List<Effect> effectsFor(EntityId target, PluginContext context) {
    if (baseDamage != null) {
      final resolved = const ModifierResolver().resolve(
        baseDamage!,
        context.modifiers.activeModifiersFor(actor, damageStat!, context.components),
      );
      return [Damage(resolved)];
    }
    return selfEffects;
  }
}
