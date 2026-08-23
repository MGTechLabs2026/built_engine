import 'package:build_engine/build_engine.dart';

import 'martial_loadout_component.dart';

/// A wearable item or trinket. Trinkets are simply items whose behavior
/// comes from a `Rule` reacting to their `equipped:<id>` tag (see
/// `martial_arts_rules.dart`) rather than from [modifiersFor] — one class
/// covers both, matching CLAUDE.md's "don't create a new source-code
/// class for every individual item" guidance.
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

RuleContext _standaloneContext(EntityId subject, PluginContext context) =>
    RuleContext(
      subject: subject,
      triggerEvent: const Object(),
      entities: context.entities,
      components: context.components,
      events: context.events,
      rng: context.rng,
      eventCounts: context.rules.eventCounts,
    );

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
  final ctx = _standaloneContext(wearer, context);
  AddTag('equipped:${item.id}').apply(ctx);
  final loadout = context.components.get<MartialLoadoutComponent>(wearer);
  context.components.add(
    wearer,
    MartialLoadoutComponent(
      equippedItems: [...?loadout?.equippedItems, itemEntity],
    ),
  );
  return itemEntity;
}

List<Modifier> _brassKnucklesModifiers(EntityId wearer) => [
      Modifier(
        source: ModifierSource('item:brass_knuckles:${wearer.value}'),
        target: wearer,
        stat: 'punch',
        operation: ModifierOperation.add,
        value: 6,
      ),
    ];

const brassKnuckles = MartialItemDefinition(
  id: 'brass_knuckles',
  tags: {'martial', 'fist', 'western'},
  modifiersFor: _brassKnucklesModifiers,
);

List<Modifier> _ironPalmWrapsModifiers(EntityId wearer) => [
      Modifier(
        source: ModifierSource('item:iron_palm_wraps:${wearer.value}'),
        target: wearer,
        stat: 'palm',
        operation: ModifierOperation.add,
        value: 6,
      ),
    ];

const ironPalmWraps = MartialItemDefinition(
  id: 'iron_palm_wraps',
  tags: {'martial', 'palm', 'eastern'},
  modifiersFor: _ironPalmWrapsModifiers,
);

List<Modifier> _taiChiSilkSashModifiers(EntityId wearer) => [
      Modifier(
        source: ModifierSource('item:tai_chi_silk_sash:${wearer.value}'),
        target: wearer,
        stat: 'internal',
        operation: ModifierOperation.add,
        value: 5,
      ),
    ];

const taiChiSilkSash = MartialItemDefinition(
  id: 'tai_chi_silk_sash',
  tags: {'martial', 'internal', 'eastern', 'qi'},
  modifiersFor: _taiChiSilkSashModifiers,
);

List<Modifier> _sparringGlovesModifiers(EntityId wearer) => [
      Modifier(
        source: ModifierSource('item:sparring_gloves:${wearer.value}'),
        target: wearer,
        stat: 'punch',
        operation: ModifierOperation.add,
        value: 3,
      ),
    ];

const sparringGloves = MartialItemDefinition(
  id: 'sparring_gloves',
  tags: {'martial', 'fist', 'western'},
  modifiersFor: _sparringGlovesModifiers,
);

List<Modifier> _weightedVestModifiers(EntityId wearer) => [
      Modifier(
        source: ModifierSource('item:weighted_vest:${wearer.value}'),
        target: wearer,
        stat: 'punch',
        operation: ModifierOperation.multiply,
        value: 1.1,
      ),
    ];

const weightedVest = MartialItemDefinition(
  id: 'weighted_vest',
  tags: {'martial', 'fist', 'western', 'external'},
  modifiersFor: _weightedVestModifiers,
);

const martialItems = [
  brassKnuckles,
  ironPalmWraps,
  taiChiSilkSash,
  sparringGloves,
  weightedVest,
];

const momentumTrinket = MartialItemDefinition(
  id: 'momentum_trinket',
  tags: {'martial', 'western'},
);

const qiPendant = MartialItemDefinition(
  id: 'qi_pendant',
  tags: {'martial', 'qi', 'eastern'},
);

List<Modifier> _counterstrikeRingModifiers(EntityId wearer) => [
      Modifier(
        source: ModifierSource('item:counterstrike_ring:${wearer.value}'),
        target: wearer,
        stat: 'internal',
        operation: ModifierOperation.add,
        value: 3,
        condition: HasTagQuery('stance:tai_chi'),
      ),
    ];

const counterstrikeRing = MartialItemDefinition(
  id: 'counterstrike_ring',
  tags: {'martial', 'eastern', 'counter'},
  modifiersFor: _counterstrikeRingModifiers,
);

const martialTrinkets = [momentumTrinket, qiPendant, counterstrikeRing];
