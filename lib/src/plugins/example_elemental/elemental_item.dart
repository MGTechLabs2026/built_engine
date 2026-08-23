import 'package:build_engine/build_engine.dart';

/// A wearable item or trinket for ExampleElemental — mirrors
/// `MartialItemDefinition`/`equipItem`'s exact shape (the second
/// occurrence of an already-proven pattern, not a new one). Deliberately
/// has no item-entity-creation or loadout-tracking — nothing here needs
/// inventory bookkeeping.
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

List<Modifier> _emberCharmModifiers(EntityId wearer) => [
      Modifier(
        source: ModifierSource('item:ember_charm:${wearer.value}'),
        target: wearer,
        stat: 'punch',
        operation: ModifierOperation.add,
        value: 4,
      ),
    ];

/// A fire trinket whose `Modifier` targets the `'punch'` stat — the
/// same, arbitrary, caller-chosen stat name MartialArts' `jab`/
/// `powerCross` already resolve through the Modifier Engine. This is
/// what lets the cross-plugin synergy (see
/// `test/integration/cross_plugin_synergy_test.dart`) work with zero
/// new Rule/Condition code and zero cross-plugin imports: any plugin's
/// Modifier applies to any action reading the same stat name.
const emberCharm = ElementalItemDefinition(
  id: 'ember_charm',
  tags: {'magic', 'fire', 'elemental', 'trinket'},
  modifiersFor: _emberCharmModifiers,
);

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
