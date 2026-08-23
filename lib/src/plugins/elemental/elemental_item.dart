import 'package:build_engine/build_engine.dart';

/// A wearable item or trinket for Elemental — mirrors
/// `MartialItemDefinition`/`equipItem`'s exact shape (the second
/// occurrence of an already-proven pattern, not a new one). Deliberately
/// has no item-entity-creation or loadout-tracking — nothing here needs
/// inventory bookkeeping. Instances are built from loaded content via
/// `elementalItemDefinitionFromContent`/`elementalItem`
/// (`elemental_item_content.dart`), never hand-written here.
class ElementalItemDefinition {
  const ElementalItemDefinition({
    required this.id,
    required this.tags,
    this.modifiersFor = _noModifiers,
  });

  final String id;
  final Set<String> tags;
  final List<Modifier> Function(EntityId wearer) modifiersFor;

  static List<Modifier> _noModifiers(EntityId wearer) => const [];
}

/// Registers [item]'s modifiers against [wearer] and tags [wearer]
/// `equipped:<item.id>`.
void equipElementalItem(
  ElementalItemDefinition item,
  EntityId wearer,
  PluginContext context,
) {
  for (final modifier in item.modifiersFor(wearer)) {
    context.modifiers.add(modifier);
  }
  AddTag('equipped:${item.id}').apply(context.ruleContextFor(wearer));
}
