import 'package:build_engine/build_engine.dart';

import 'martial_loadout_component.dart';

/// A wearable item or trinket. Trinkets are simply items whose behavior
/// comes from a `Rule` reacting to their `equipped:<id>` tag (see
/// `martial_arts_rules.dart`) rather than from [modifiersFor] — one class
/// covers both, matching CLAUDE.md's "don't create a new source-code
/// class for every individual item" guidance. Instances are built from
/// loaded content via `martialItemDefinitionFromContent`/`martialItem`
/// (`martial_item_content.dart`), never hand-written here.
class MartialItemDefinition {
  const MartialItemDefinition({
    required this.id,
    required this.tags,
    this.modifiersFor = _noModifiers,
  });

  final String id;
  final Set<String> tags;
  final List<Modifier> Function(EntityId wearer) modifiersFor;

  static List<Modifier> _noModifiers(EntityId wearer) => const [];
}

/// Creates an entity for [item] (carrying its tags), registers its
/// [MartialItemDefinition.modifiersFor] against [wearer], tags [wearer]
/// `equipped:<item.id>`, and records the new item entity on [wearer]'s
/// `MartialLoadoutComponent` (creating it if absent). Returns the new item
/// entity.
EntityId equipItem(
  MartialItemDefinition item,
  EntityId wearer,
  PluginContext context,
) {
  final itemEntity = context.entities.create();
  context.components.add(itemEntity, TagSet(item.tags));
  for (final modifier in item.modifiersFor(wearer)) {
    context.modifiers.add(modifier);
  }
  AddTag('equipped:${item.id}').apply(context.ruleContextFor(wearer));
  final loadout = context.components.get<MartialLoadoutComponent>(wearer);
  context.components.add(
    wearer,
    MartialLoadoutComponent(
      equippedItems: [...?loadout?.equippedItems, itemEntity],
    ),
  );
  return itemEntity;
}
