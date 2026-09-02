import 'package:build_engine/build_engine.dart';
import 'package:build_engine/combat_plugin.dart';

/// A generic self-targeted [CombatAction]: applies [selfEffects] to
/// [actor] alone, no damage — the "defensive action" shape the milestone
/// asks for (e.g. Basic Guard), and equally usable by any future
/// self-buff/stance-style technique from any content domain. Mirrors
/// exactly what `MartialTechniqueAction`'s stance branch already does
/// (`selfEffects` when `baseDamage` is null) but generically, with no
/// martial vocabulary and no dependency on MartialArts — a second,
/// independent implementation of `CombatAction`, alongside `AttackAction`,
/// added without touching either existing file.
class SelfEffectAction extends CombatAction {
  const SelfEffectAction({
    required this.actor,
    this.conditions = const [],
    this.costEffects = const [],
    this.selfEffects = const [],
    this.sourceRef,
  });

  @override
  final EntityId actor;

  @override
  List<EntityId> get targets => [actor];

  @override
  final List<Condition> conditions;

  @override
  final List<Effect> costEffects;

  final List<Effect> selfEffects;

  @override
  final BuildComponentRef? sourceRef;

  @override
  List<Effect> effectsFor(EntityId target, PluginContext context) => selfEffects;
}
