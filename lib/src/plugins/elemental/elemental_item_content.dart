import 'package:build_engine/build_engine.dart';

import 'elemental_item.dart';
import 'elemental_vocabulary.dart';

/// Elemental's one item, as data — loaded into `PluginContext.content`
/// via `PluginSdk.registerContentBatch` in `ElementalPlugin.initialize`,
/// mirroring `martialItemContentDefinitions` (the MartialArts
/// counterpart in `martial_item_content.dart`), the same pattern
/// applied to Elemental.
const elementalItemContentDefinitions = <Map<String, dynamic>>[
  {
    'id': ElementalItemIds.emberCharm,
    'type': 'elemental_item',
    'tags': ['magic', 'fire', 'elemental', 'trinket'],
    'modifiers': [
      {
        'stat': 'punch',
        'operation': 'add',
        'value': 4,
        'condition': 'martial',
      },
    ],
  },
];

/// Builds an [ElementalItemDefinition] from a loaded [ContentDefinition].
/// See `martialItemDefinitionFromContent` (the MartialArts counterpart
/// in `martial_item_content.dart`) for the full parsing rationale —
/// this is the identical pattern, independently applied here (Elemental
/// never imports MartialArts).
ElementalItemDefinition elementalItemDefinitionFromContent(
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

  return ElementalItemDefinition(
    id: definition.id,
    tags: definition.tags,
    modifiersFor: modifiersFor,
  );
}

/// Resolves and parses item [id] from [context]'s loaded content in one
/// call — the replacement for the old bare `const emberCharm` identifier
/// everywhere it was previously referenced. Stateless: re-resolves from
/// `context.content` on every call, no caching.
ElementalItemDefinition elementalItem(String id, PluginContext context) =>
    elementalItemDefinitionFromContent(context.content.get(id));

ModifierOperation _operationFor(String name) => switch (name) {
      'add' => ModifierOperation.add,
      'multiply' => ModifierOperation.multiply,
      'override' => ModifierOperation.override,
      'min' => ModifierOperation.min,
      'max' => ModifierOperation.max,
      _ => throw ArgumentError('unknown modifier operation: $name'),
    };
