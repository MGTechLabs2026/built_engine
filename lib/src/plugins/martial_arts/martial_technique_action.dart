import 'package:build_engine/build_engine.dart';
import 'package:build_engine/combat_plugin.dart';

import 'martial_styles.dart';
import 'martial_vocabulary.dart';

/// One class for every technique and stance — the same "don't create a
/// new source-code class per content item" principle `AttackAction`
/// already demonstrates. Set [baseDamage]/[damageStat] together for an
/// attack technique (damage resolved through the Modifier Engine,
/// identical mechanism to `AttackAction`); leave both null and set
/// [selfEffects] instead for a stance/utility technique (with `targets:
/// [actor]` at the call site) — never set both kinds on one instance.
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

// --- Boxing ---

MartialTechniqueAction jab({
  required EntityId actor,
  required List<EntityId> targets,
}) =>
    MartialTechniqueAction(
      actor: actor,
      targets: targets,
      tags: const {'martial', 'fist', 'western', 'external'},
      conditions: [HasTag('style:${MartialStyles.boxing}')],
      costEffects: const [ModifyResource(MartialResources.momentum, 8)],
      baseDamage: 6,
      damageStat: 'punch',
    );

MartialTechniqueAction powerCross({
  required EntityId actor,
  required List<EntityId> targets,
}) =>
    MartialTechniqueAction(
      actor: actor,
      targets: targets,
      tags: const {'martial', 'fist', 'western', 'external'},
      conditions: [
        HasTag('style:${MartialStyles.boxing}'),
        const ResourceAbove(MartialResources.momentum, 19),
      ],
      costEffects: const [ModifyResource(MartialResources.momentum, -20)],
      baseDamage: 18,
      damageStat: 'punch',
    );

MartialTechniqueAction guardStance({
  required EntityId actor,
  required List<EntityId> targets,
}) =>
    MartialTechniqueAction(
      actor: actor,
      targets: targets,
      tags: const {'martial', 'fist', 'western'},
      conditions: [HasTag('style:${MartialStyles.boxing}')],
      selfEffects: const [
        AddTag(MartialStances.guard),
        ModifyResource(MartialResources.momentum, 5),
      ],
    );

// --- Shaolin ---

MartialTechniqueAction palmStrike({
  required EntityId actor,
  required List<EntityId> targets,
}) =>
    MartialTechniqueAction(
      actor: actor,
      targets: targets,
      tags: const {'martial', 'palm', 'eastern', 'external'},
      conditions: [
        HasTag('style:${MartialStyles.shaolin}'),
        const ResourceAbove(MartialResources.qi, 2),
      ],
      costEffects: const [ModifyResource(MartialResources.qi, -3)],
      baseDamage: 8,
      damageStat: 'palm',
    );

MartialTechniqueAction blazingPalm({
  required EntityId actor,
  required List<EntityId> targets,
}) =>
    MartialTechniqueAction(
      actor: actor,
      targets: targets,
      tags: const {'martial', 'palm', 'eastern', 'fire', 'qi'},
      conditions: [
        HasTag('style:${MartialStyles.shaolin}'),
        const ResourceAbove(MartialResources.qi, 7),
      ],
      costEffects: const [ModifyResource(MartialResources.qi, -8)],
      baseDamage: 14,
      damageStat: 'palm',
    );

MartialTechniqueAction ironBodyStance({
  required EntityId actor,
  required List<EntityId> targets,
}) =>
    MartialTechniqueAction(
      actor: actor,
      targets: targets,
      tags: const {'martial', 'qi', 'internal', 'eastern'},
      conditions: [
        HasTag('style:${MartialStyles.shaolin}'),
        const ResourceAbove(MartialResources.qi, 4),
      ],
      costEffects: const [ModifyResource(MartialResources.qi, -5)],
      selfEffects: const [AddTag(MartialStances.ironBody)],
    );

// --- Tai Chi ---

MartialTechniqueAction pushHands({
  required EntityId actor,
  required List<EntityId> targets,
}) =>
    MartialTechniqueAction(
      actor: actor,
      targets: targets,
      tags: const {'martial', 'internal', 'eastern', 'qi'},
      conditions: [
        HasTag('style:${MartialStyles.taiChi}'),
        const ResourceAbove(MartialResources.qi, 3),
      ],
      costEffects: const [ModifyResource(MartialResources.qi, -4)],
      baseDamage: 7,
      damageStat: 'internal',
    );

MartialTechniqueAction whirlingPalm({
  required EntityId actor,
  required List<EntityId> targets,
}) =>
    MartialTechniqueAction(
      actor: actor,
      targets: targets,
      tags: const {'martial', 'internal', 'eastern', 'qi', 'yang'},
      conditions: [
        HasTag('style:${MartialStyles.taiChi}'),
        const ResourceAbove(MartialResources.qi, 5),
      ],
      costEffects: const [ModifyResource(MartialResources.qi, -6)],
      baseDamage: 10,
      damageStat: 'internal',
    );

MartialTechniqueAction yieldingStance({
  required EntityId actor,
  required List<EntityId> targets,
}) =>
    MartialTechniqueAction(
      actor: actor,
      targets: targets,
      tags: const {'martial', 'internal', 'eastern', 'qi', 'counter'},
      conditions: [
        HasTag('style:${MartialStyles.taiChi}'),
        const ResourceAbove(MartialResources.qi, 2),
      ],
      costEffects: const [ModifyResource(MartialResources.qi, -3)],
      selfEffects: const [AddTag(MartialStances.taiChi)],
    );
