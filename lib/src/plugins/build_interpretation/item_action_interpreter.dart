import 'package:build_engine/build_engine.dart';
import 'package:build_engine/combat_plugin.dart';
import 'package:build_engine/item_plugin.dart';

import 'build_action_interpreter.dart';
import 'weapon_stat_tags.dart';

/// Interprets `item`-typed [ActiveBuild] components by registering their
/// content-defined `attack` property as a [Modifier] on [actor] — items
/// contribute to *how strong* an existing action is (a Knife's `attack`
/// boosting the `'blade'`-tagged stat a technique-derived [AttackAction]
/// already reads via the existing Modifier Engine), not standalone
/// actions of their own. Per the milestone's "do not overbuild weapon
/// mechanics" and "items may modify available actions or action
/// properties." Returns no [CombatAction]s itself — its whole
/// contribution is the side-effecting `context.modifiers.add` call.
///
/// Shares the `'fist'`/`'blade'` tag vocabulary with
/// `TechniqueActionInterpreter`'s `damageStat` convention purely by
/// agreeing on the same strings — the same "shared vocabulary, not
/// shared import" pattern `PLUGIN_SYSTEM.md`'s Physique/MartialArts
/// example already established; this file never imports the Technique
/// plugin.
///
/// [interpret] is idempotent: re-running it for the same [build]/[actor]
/// replaces rather than stacks each item's modifier (`removeBySource`
/// before `add`), since `ModifierCollection.add` itself has no
/// deduplication.
class ItemActionInterpreter implements BuildActionInterpreter {
  const ItemActionInterpreter();

  @override
  List<CombatAction> interpret({
    required ActiveBuild build,
    required EntityId actor,
    required List<EntityId> targets,
    required PluginContext context,
  }) {
    for (final ref in build.components) {
      if (ref.referenceType != itemReferenceType) continue;
      final definition = context.content.find(ref.contentId);
      if (definition == null) continue; // unknown/invalid item -> no modifier, not a crash
      final item = itemDefinitionFromContent(definition);
      final itemClass = ref.instanceEntityId == null
          ? 1
          : context.components.get<ItemInstance>(ref.instanceEntityId!)?.itemClass ?? 1;
      final attack = item.scaledProperties(itemClass)['attack'];
      if (attack == null) continue;

      final source = ModifierSource('build:${item.id}:${actor.value}');
      context.modifiers.removeBySource(source);
      context.modifiers.add(Modifier(
        source: source,
        target: actor,
        stat: _statFor(item),
        operation: ModifierOperation.add,
        value: attack,
      ));
    }
    return const [];
  }

  String _statFor(ItemDefinition item) =>
      WeaponStatTags.matchOrFallback(item.tags, 'item:${item.id}');
}
