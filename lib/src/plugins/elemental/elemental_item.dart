import 'package:build_engine/build_engine.dart';

/// A wearable item or trinket for Elemental — mirrors
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
        condition: HasTagQuery('martial'),
      ),
    ];

/// A fire trinket whose `Modifier` targets the `'punch'` stat — the
/// same, arbitrary, caller-chosen stat name MartialArts' `jab`/
/// `powerCross` already resolve through the Modifier Engine — and is
/// gated on `condition: HasTagQuery('martial')`, so it only activates
/// for an entity another plugin has tagged `'martial'`. This is what
/// makes the cross-plugin synergy (see
/// `test/integration/cross_plugin_synergy_test.dart`) genuinely
/// tag-mediated, not merely a coincidence of two plugins picking the
/// same stat name: it needs zero new Rule/Condition class and zero
/// cross-plugin import, and uses the exact same conditional-`Modifier`
/// pattern `counterstrikeRing` already uses in `martial_item.dart`.
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
