import 'package:build_engine/build_engine.dart';

import 'item_definition.dart';
import 'item_requirement.dart';
import 'item_vocabulary.dart';

/// The 6 starter items this plugin implements, as data — loaded into
/// `PluginContext.content` via `PluginSdk.registerContentBatch` in
/// `ItemPlugin.initialize`, mirroring every other content plugin's
/// `*ContentDefinitions` constant. Stats are deliberately simple, not
/// balanced. `requirements.mastery.thresholds` (present only for items
/// with `minimum > 0`) is `ItemPlugin.initialize`'s own input to
/// `MasteryTracker.define` — it is plumbing for reaching the required
/// level, not part of `ItemDefinition`'s own shape (which only needs the
/// subject + minimum to check usability).
const itemContentDefinitions = <Map<String, dynamic>>[
  {
    'id': ItemIds.knife,
    'type': ItemCategories.weapon,
    'tags': ['item', 'weapon', 'blade'],
    'properties': {'attack': 2},
    'training': {'speed': 0.4, 'precision': 0.4, 'control': 0.2},
    'requirements': {
      'mastery': {'subject': 'item:knife', 'minimum': 0},
    },
  },
  {
    'id': ItemIds.ironSword,
    'type': ItemCategories.weapon,
    'tags': ['item', 'weapon', 'blade'],
    'properties': {'attack': 3},
    'training': {'power': 0.4, 'precision': 0.3, 'control': 0.3},
    'requirements': {
      'mastery': {
        'subject': 'item:iron_sword',
        'minimum': 2,
        'thresholds': [10, 25],
      },
    },
  },
  {
    'id': ItemIds.gloves,
    'type': ItemCategories.weapon,
    'tags': ['item', 'weapon', 'fist'],
    'properties': {'attack': 1},
    'training': {'speed': 0.35, 'reaction': 0.35, 'power': 0.3},
    'requirements': {
      'mastery': {'subject': 'item:gloves', 'minimum': 0},
    },
  },
  {
    'id': ItemIds.trainingStaff,
    'type': ItemCategories.weapon,
    'tags': ['item', 'weapon', 'staff'],
    'properties': {'attack': 2},
    'requirements': {
      'mastery': {
        'subject': 'item:training_staff',
        'minimum': 1,
        'thresholds': [10],
      },
    },
  },
  {
    'id': ItemIds.clothArmor,
    'type': ItemCategories.armor,
    'tags': ['item', 'armor'],
    'properties': {'defense': 2},
    'requirements': {
      'mastery': {
        'subject': 'item:cloth_armor',
        'minimum': 1,
        'thresholds': [8],
      },
    },
  },
  {
    'id': ItemIds.trainingShoes,
    'type': ItemCategories.footwear,
    'tags': ['item', 'footwear'],
    'properties': {'speed': 1},
    'requirements': {
      'mastery': {'subject': 'item:training_shoes', 'minimum': 0},
    },
  },
];

/// Builds an [ItemDefinition] from a loaded [ContentDefinition].
/// `extra['properties']` supplies [ItemDefinition.properties] and
/// [ItemDefinition.modifiersFor] (one unconditional `add` `Modifier` per
/// property, via the shared `modifiersFromProperties`);
/// `extra['requirements']['mastery']` supplies [ItemDefinition.requirement],
/// if present; `extra['training']` supplies
/// [ItemDefinition.trainingWeights] — content data, not a hand-written
/// Dart constant (`ARCHITECTURE_AUDIT.md`'s category-7 finding).
ItemDefinition itemDefinitionFromContent(ContentDefinition definition) {
  final rawProperties =
      (definition.extra['properties'] as Map?) ?? const <String, dynamic>{};
  final properties = <String, num>{
    for (final entry in rawProperties.entries)
      entry.key as String: entry.value as num,
  };

  final rawTraining =
      (definition.extra['training'] as Map?) ?? const <String, dynamic>{};
  final trainingWeights = <String, double>{
    for (final entry in rawTraining.entries)
      entry.key as String: (entry.value as num).toDouble(),
  };

  final masteryRaw =
      (definition.extra['requirements'] as Map?)?['mastery'] as Map?;
  final requirement = masteryRaw == null
      ? null
      : ItemRequirement(
          masterySubject: masteryRaw['subject'] as String,
          minimumLevel: masteryRaw['minimum'] as int,
        );

  List<Modifier> modifiersFor(EntityId owner) => modifiersFromProperties(
        domain: 'item',
        contentId: definition.id,
        properties: properties,
        target: owner,
      );

  return ItemDefinition(
    id: definition.id,
    category: definition.type,
    tags: definition.tags,
    properties: properties,
    requirement: requirement,
    trainingWeights: trainingWeights,
    modifiersFor: modifiersFor,
  );
}

/// Resolves and parses item [id] from [context]'s loaded content in one
/// call — the same convenience `martialItem`/`elementalItem` already
/// provide for their own plugins. Stateless: re-resolves from
/// `context.content` on every call, no caching.
ItemDefinition itemDefinition(String id, PluginContext context) =>
    itemDefinitionFromContent(context.content.get(id));
