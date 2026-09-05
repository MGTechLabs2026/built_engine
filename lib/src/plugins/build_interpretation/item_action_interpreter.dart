import 'package:build_engine/build_engine.dart';
import 'package:build_engine/combat_plugin.dart';
import 'package:build_engine/item_plugin.dart';

import 'build_action_interpreter.dart';

/// Interprets `item`-typed [ResolvedBuild] components by registering one
/// [Modifier] per distinct stat key on [actor] — items contribute to
/// *how strong* an existing action is (a Knife's `attack` boosting the
/// `'blade'`-tagged stat a technique-derived [AttackAction] already
/// reads via the existing Modifier Engine), not standalone actions of
/// their own. Per the milestone's "do not overbuild weapon mechanics"
/// and "items may modify available actions or action properties."
/// Returns no [CombatAction]s itself — its whole contribution is the
/// side-effecting `context.modifiers.add` call.
///
/// Each item ref (definition + optional [ItemInstance]) is wrapped as an
/// [ItemEffectContributor] to get its [EffectProfile] — scaled `attack`
/// and per-copy stat bonuses both fold into that profile's `supporting`
/// tier (see `ItemEffectContributor`'s own doc comment). Rather than a
/// separate modifier per item and per per-copy bonus (the old two
/// distinct modifier-source prefixes this superseded),
/// [EffectProfileResolver] sums every distinct stat key across
/// [ResolvedBuild.owned]/`.active` item profiles into a single
/// `effectprofile:item:<actorValue>:<stat>` modifier — one path, no
/// parallel system. The source is actor-scoped (mirroring the
/// pre-migration `build:<itemId>:<actorValue>` scoping) so interpreting
/// one actor's build never wipes another actor's item modifiers via
/// `ModifierCollection.removeBySource`.
///
/// [interpret] is idempotent: re-running it for the same [build]/[actor]
/// replaces rather than stacks each stat's modifier (`removeBySource`
/// before `add`), since `ModifierCollection.add` itself has no
/// deduplication.
class ItemActionInterpreter implements BuildActionInterpreter {
  const ItemActionInterpreter();

  @override
  List<CombatAction> interpret({
    required ResolvedBuild build,
    required EntityId actor,
    required List<EntityId> targets,
    required PluginContext context,
  }) {
    EffectProfile profileFor(BuildComponentRef ref) {
      if (ref.referenceType != itemReferenceType) return EffectProfile.empty;
      final definition = context.content.find(ref.contentId);
      if (definition == null) return EffectProfile.empty;
      final item = itemDefinitionFromContent(definition);
      final instance = ref.instanceEntityId == null
          ? null
          : context.components.get<ItemInstance>(ref.instanceEntityId!);
      return ItemEffectContributor(item, instance).effectProfile();
    }

    final ownedItemRefs = [
      for (final r in build.owned)
        if (r.referenceType == itemReferenceType) r,
    ];
    final activeItemRefs = [
      for (final r in build.active)
        if (r.referenceType == itemReferenceType) r,
    ];
    final ownedProfiles = [for (final r in ownedItemRefs) profileFor(r)];
    final activeProfiles = [for (final r in activeItemRefs) profileFor(r)];

    final stats = <String>{
      for (final p in ownedProfiles) ...p.tier(EffectTier.permanent).keys,
      for (final p in ownedProfiles) ...p.tier(EffectTier.supporting).keys,
    };
    const resolver = EffectProfileResolver();
    for (final stat in stats) {
      final value =
          resolver.resolve(owned: ownedProfiles, hung: activeProfiles, stat: stat);
      final source = ModifierSource('effectprofile:item:${actor.value}:$stat');
      context.modifiers.removeBySource(source);
      context.modifiers.add(Modifier(
        source: source,
        target: actor,
        stat: stat,
        operation: ModifierOperation.add,
        value: value,
      ));
    }
    return const [];
  }
}
