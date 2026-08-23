import 'package:build_engine/build_engine.dart';

import 'martial_item.dart';
import 'martial_vocabulary.dart';

/// The 5 items + 3 trinkets this plugin implements, as data — loaded
/// into `PluginContext.content` via `PluginSdk.registerContentBatch` in
/// `MartialArtsPlugin.initialize`, mirroring
/// `martialTechniqueContentDefinitions` and
/// `physiqueContentDefinitions`.
///
/// `modifiers` isn't part of `ContentRegistry`'s native vocabulary
/// (`Modifier` isn't an `Effect`/`Condition`) — it lands verbatim on
/// `ContentDefinition.extra`, exactly like
/// `physique_content.dart`'s `modifiers` field.
/// `physiqueDefinitionFromContent` always required a `'condition'` key
/// (every physique's modifiers are tag-gated); items are less uniform —
/// most have an unconditional modifier (no `'condition'` key at all),
/// and two trinkets (`momentum_trinket`/`qi_pendant`) have no static
/// modifiers whatsoever (their behavior comes entirely from the
/// `equipped:<id>` tag `equipItem` grants, read by
/// `martial_arts_rules.dart`'s passive-regen rules) — so both
/// `'condition'` and a non-empty `'modifiers'` list are optional here.
const martialItemContentDefinitions = <Map<String, dynamic>>[
  {
    'id': MartialItemIds.brassKnuckles,
    'type': 'martial_item',
    'tags': ['martial', 'fist', MartialTraditions.western],
    'modifiers': [
      {'stat': 'punch', 'operation': 'add', 'value': 6},
    ],
  },
  {
    'id': MartialItemIds.ironPalmWraps,
    'type': 'martial_item',
    'tags': ['martial', 'palm', MartialTraditions.eastern],
    'modifiers': [
      {'stat': 'palm', 'operation': 'add', 'value': 6},
    ],
  },
  {
    'id': MartialItemIds.taiChiSilkSash,
    'type': 'martial_item',
    'tags': ['martial', 'internal', MartialTraditions.eastern, 'qi'],
    'modifiers': [
      {'stat': 'internal', 'operation': 'add', 'value': 5},
    ],
  },
  {
    'id': MartialItemIds.sparringGloves,
    'type': 'martial_item',
    'tags': ['martial', 'fist', MartialTraditions.western],
    'modifiers': [
      {'stat': 'punch', 'operation': 'add', 'value': 3},
    ],
  },
  {
    'id': MartialItemIds.weightedVest,
    'type': 'martial_item',
    'tags': ['martial', 'fist', MartialTraditions.western, 'external'],
    'modifiers': [
      {'stat': 'punch', 'operation': 'multiply', 'value': 1.1},
    ],
  },
  {
    'id': MartialItemIds.momentumTrinket,
    'type': 'martial_trinket',
    'tags': ['martial', MartialTraditions.western],
    'modifiers': <Map<String, dynamic>>[],
  },
  {
    'id': MartialItemIds.qiPendant,
    'type': 'martial_trinket',
    'tags': ['martial', 'qi', MartialTraditions.eastern],
    'modifiers': <Map<String, dynamic>>[],
  },
  {
    'id': MartialItemIds.counterstrikeRing,
    'type': 'martial_trinket',
    'tags': ['martial', MartialTraditions.eastern, 'counter'],
    'modifiers': [
      {
        'stat': 'internal',
        'operation': 'add',
        'value': 3,
        'condition': MartialStances.taiChi,
      },
    ],
  },
];

/// Builds a [MartialItemDefinition] from a loaded [ContentDefinition].
/// `extra['modifiers']` supplies [MartialItemDefinition.modifiersFor] —
/// each raw entry becomes one `Modifier`, unconditional unless the entry
/// has a `'condition'` key (in which case it's gated via `HasTagQuery`).
/// An empty `extra['modifiers']` list produces a `modifiersFor` that
/// always returns `const []` — the same behavior
/// `MartialItemDefinition`'s own `_noModifiers` default already
/// provides for a definition with no `modifiersFor` at all.
MartialItemDefinition martialItemDefinitionFromContent(
    ContentDefinition definition) {
  final rawModifiers = (definition.extra['modifiers'] as List? ?? const [])
      .map((e) => (e as Map).map((k, v) => MapEntry(k as String, v)))
      .toList();

  List<Modifier> modifiersFor(EntityId wearer) => [
        for (var i = 0; i < rawModifiers.length; i++)
          Modifier(
            source:
                ModifierSource('item:${definition.id}:$i:${wearer.value}'),
            target: wearer,
            stat: rawModifiers[i]['stat'] as String,
            operation: _operationFor(rawModifiers[i]['operation'] as String),
            value: rawModifiers[i]['value'] as num,
            condition: rawModifiers[i].containsKey('condition')
                ? HasTagQuery(rawModifiers[i]['condition'] as String)
                : null,
          ),
      ];

  return MartialItemDefinition(
    id: definition.id,
    tags: definition.tags,
    modifiersFor: modifiersFor,
  );
}

/// Resolves and parses item [id] from [context]'s loaded content in one
/// call — the replacement for the old bare `const` item identifiers
/// (`brassKnuckles`, etc.) everywhere they were previously referenced.
/// Stateless: re-resolves from `context.content` on every call, no
/// caching.
MartialItemDefinition martialItem(String id, PluginContext context) =>
    martialItemDefinitionFromContent(context.content.get(id));

ModifierOperation _operationFor(String name) => switch (name) {
      'add' => ModifierOperation.add,
      'multiply' => ModifierOperation.multiply,
      'override' => ModifierOperation.override,
      'min' => ModifierOperation.min,
      'max' => ModifierOperation.max,
      _ => throw ArgumentError('unknown modifier operation: $name'),
    };
