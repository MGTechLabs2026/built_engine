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
/// The actual `Modifier` construction is shared with
/// `martialItemDefinitionFromContent`/`physiqueDefinitionFromContent` via
/// the generic `modifiersFromRawList` (Core) — Elemental still never
/// imports MartialArts; both independently call the same Core helper.
ElementalItemDefinition elementalItemDefinitionFromContent(
    ContentDefinition definition) {
  final rawModifiers = (definition.extra['modifiers'] as List? ?? const [])
      .map((e) => (e as Map).map((k, v) => MapEntry(k as String, v)))
      .toList();

  List<Modifier> modifiersFor(EntityId wearer) => modifiersFromRawList(
        domain: 'item',
        contentId: definition.id,
        rawModifiers: rawModifiers,
        target: wearer,
      );

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
