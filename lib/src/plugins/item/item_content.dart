import 'package:build_engine/build_engine.dart';

import 'item_definition.dart';
import 'item_requirement.dart';
import 'item_vocabulary.dart';

/// The 7 combinable base items plus 8 martial-style starting-kit items
/// this plugin implements, as data — loaded into `PluginContext.content`
/// via `PluginSdk.registerContentBatch` in `ItemPlugin.initialize`,
/// mirroring every other content plugin's `*ContentDefinitions`
/// constant. Stats are deliberately simple, not balanced.
/// `requirements.mastery.thresholds` (present only for items with
/// `minimum > 0`) is `ItemPlugin.initialize`'s own input to
/// `MasteryTracker.define` — it is plumbing for reaching the required
/// level, not part of `ItemDefinition`'s own shape (which only needs the
/// subject + minimum to check usability).
///
/// Content Expansion V1 tags every form with `aff:<physique>` (read only
/// by the client reward weighter) and `rarity:<tier>`. Family tags
/// (`fist`/`blade`/`polearm`/`reach`/`thrust`/...) double as the
/// recognised family tags the off-specialty penalty reads.
///
/// The 8 starting-kit items (`polearm`, `chair`, `mask`, `rapier`,
/// `staff`, `fan`, `towel`, `cloth`) are all `minimum: 0` — immediately
/// usable, so a style's opening pair hangs on the Tome with no training
/// gate. Six stay non-combinable (no `maxClass`/`gradeEvolution` — a
/// starter kit never holds a duplicate to combine); V1 gave `polearm`
/// and `rapier` their own combine chains (additive fields, ids unchanged)
/// so a style's starter weapon has somewhere to grow.
/// Which two a style grants is a game-composition concern and lives in
/// the client.
///
/// The 6 originals plus V1's `hand_wraps` each carry a 3-grade Combine chain
/// (`maxClass`/`gradeEvolution`, `docs/superpowers/specs/2026-08-24-item-combine-design.md`):
/// class-capped at 3, it branches at its first grade-up into 2 named
/// grade-2 items, weighted by `TrainingDimensions` tags matching the
/// base item's own `training` weights; each grade-2 item is class-capped
/// at 6 and continues linearly to one terminal grade-3 "masterwork" item,
/// class-capped at 9. The 24 grade items themselves are never part of
/// this starter set a player owns directly — they're reachable only by
/// combining a base item, never placed as starting content.
const itemContentDefinitions = <Map<String, dynamic>>[
  {
    'id': ItemIds.knife,
    'type': ItemCategories.weapon,
    'tags': ['item', 'weapon', 'blade', 'aff:burst', 'rarity:common'],
    'properties': {'attack': 2},
    'training': {'speed': 0.4, 'precision': 0.4, 'control': 0.2},
    'requirements': {
      'mastery': {'subject': 'item:knife', 'minimum': 0},
    },
    'maxClass': 3,
    'gradeEvolution': [
      {'targetId': ItemIds.sharpKnife, 'tags': [TrainingDimensions.precision]},
      {'targetId': ItemIds.fastKnife, 'tags': [TrainingDimensions.speed]},
    ],
  },
  {
    'id': ItemIds.sharpKnife,
    'type': ItemCategories.weapon,
    'tags': ['item', 'weapon', 'blade', 'precision'],
    'properties': {'attack': 3},
    'training': {'precision': 0.6, 'control': 0.4},
    'maxClass': 6,
    'gradeEvolution': [
      {'targetId': ItemIds.masterworkSharpKnife},
    ],
  },
  {
    'id': ItemIds.masterworkSharpKnife,
    'type': ItemCategories.weapon,
    'tags': ['item', 'weapon', 'blade', 'precision'],
    'properties': {'attack': 5},
    'maxClass': 9,
  },
  {
    'id': ItemIds.fastKnife,
    'type': ItemCategories.weapon,
    'tags': ['item', 'weapon', 'blade', 'speed'],
    'properties': {'attack': 3},
    'training': {'speed': 0.6, 'reaction': 0.4},
    'maxClass': 6,
    'gradeEvolution': [
      {'targetId': ItemIds.windcutterKnife},
    ],
  },
  {
    'id': ItemIds.windcutterKnife,
    'type': ItemCategories.weapon,
    'tags': ['item', 'weapon', 'blade', 'speed'],
    'properties': {'attack': 5},
    'maxClass': 9,
  },
  {
    'id': ItemIds.ironSword,
    'type': ItemCategories.weapon,
    'tags': ['item', 'weapon', 'blade', 'aff:power', 'rarity:common'],
    'properties': {'attack': 3},
    'training': {'power': 0.4, 'precision': 0.3, 'control': 0.3},
    'requirements': {
      'mastery': {
        'subject': 'item:iron_sword',
        'minimum': 2,
        'thresholds': [10, 25],
      },
    },
    'maxClass': 3,
    'gradeEvolution': [
      {'targetId': ItemIds.reinforcedIronSword, 'tags': [TrainingDimensions.power]},
      {'targetId': ItemIds.temperedIronSword, 'tags': [TrainingDimensions.precision]},
    ],
  },
  {
    'id': ItemIds.reinforcedIronSword,
    'type': ItemCategories.weapon,
    'tags': ['item', 'weapon', 'blade', 'power'],
    'properties': {'attack': 5},
    'training': {'power': 0.6, 'control': 0.4},
    'maxClass': 6,
    'gradeEvolution': [
      {'targetId': ItemIds.warlordsIronSword},
    ],
  },
  {
    'id': ItemIds.warlordsIronSword,
    'type': ItemCategories.weapon,
    'tags': ['item', 'weapon', 'blade', 'power'],
    'properties': {'attack': 7},
    'maxClass': 9,
  },
  {
    'id': ItemIds.temperedIronSword,
    'type': ItemCategories.weapon,
    'tags': ['item', 'weapon', 'blade', 'precision'],
    'properties': {'attack': 4},
    'training': {'precision': 0.6, 'control': 0.4},
    'maxClass': 6,
    'gradeEvolution': [
      {'targetId': ItemIds.runicIronSword},
    ],
  },
  {
    'id': ItemIds.runicIronSword,
    'type': ItemCategories.weapon,
    'tags': ['item', 'weapon', 'blade', 'precision'],
    'properties': {'attack': 6},
    'maxClass': 9,
  },
  {
    'id': ItemIds.gloves,
    'type': ItemCategories.weapon,
    'tags': ['item', 'weapon', 'fist', 'aff:burst', 'rarity:common'],
    'properties': {'attack': 1},
    'training': {'speed': 0.35, 'reaction': 0.35, 'power': 0.3},
    'requirements': {
      'mastery': {'subject': 'item:gloves', 'minimum': 0},
    },
    'maxClass': 3,
    'gradeEvolution': [
      {'targetId': ItemIds.swiftGloves, 'tags': [TrainingDimensions.speed]},
      {'targetId': ItemIds.ironKnuckleGloves, 'tags': [TrainingDimensions.power]},
    ],
  },
  {
    'id': ItemIds.swiftGloves,
    'type': ItemCategories.weapon,
    'tags': ['item', 'weapon', 'fist', 'speed'],
    'properties': {'attack': 2},
    'training': {'speed': 0.6, 'reaction': 0.4},
    'maxClass': 6,
    'gradeEvolution': [
      {'targetId': ItemIds.lightningGloves},
    ],
  },
  {
    'id': ItemIds.lightningGloves,
    'type': ItemCategories.weapon,
    'tags': ['item', 'weapon', 'fist', 'speed'],
    'properties': {'attack': 3},
    'maxClass': 9,
  },
  {
    'id': ItemIds.ironKnuckleGloves,
    'type': ItemCategories.weapon,
    'tags': ['item', 'weapon', 'fist', 'power'],
    'properties': {'attack': 2},
    'training': {'power': 0.6, 'control': 0.4},
    'maxClass': 6,
    'gradeEvolution': [
      {'targetId': ItemIds.crushingGauntlets},
    ],
  },
  {
    'id': ItemIds.crushingGauntlets,
    'type': ItemCategories.weapon,
    'tags': ['item', 'weapon', 'fist', 'power'],
    'properties': {'attack': 4},
    'maxClass': 9,
  },
  {
    'id': ItemIds.trainingStaff,
    'type': ItemCategories.weapon,
    'tags': ['item', 'weapon', 'staff', 'aff:endurance', 'rarity:common'],
    'properties': {'attack': 2},
    'training': {'control': 0.4, 'precision': 0.3, 'power': 0.3},
    'requirements': {
      'mastery': {
        'subject': 'item:training_staff',
        'minimum': 1,
        'thresholds': [10],
      },
    },
    'maxClass': 3,
    'gradeEvolution': [
      {'targetId': ItemIds.balancedStaff, 'tags': [TrainingDimensions.control]},
      {'targetId': ItemIds.battleStaff, 'tags': [TrainingDimensions.power]},
    ],
  },
  {
    'id': ItemIds.balancedStaff,
    'type': ItemCategories.weapon,
    'tags': ['item', 'weapon', 'staff', 'control'],
    'properties': {'attack': 3},
    'training': {'control': 0.6, 'precision': 0.4},
    'maxClass': 6,
    'gradeEvolution': [
      {'targetId': ItemIds.sagesStaff},
    ],
  },
  {
    'id': ItemIds.sagesStaff,
    'type': ItemCategories.weapon,
    'tags': ['item', 'weapon', 'staff', 'control'],
    'properties': {'attack': 4},
    'maxClass': 9,
  },
  {
    'id': ItemIds.battleStaff,
    'type': ItemCategories.weapon,
    'tags': ['item', 'weapon', 'staff', 'power'],
    'properties': {'attack': 3},
    'training': {'power': 0.6, 'control': 0.4},
    'maxClass': 6,
    'gradeEvolution': [
      {'targetId': ItemIds.warstaffOfTheVanguard},
    ],
  },
  {
    'id': ItemIds.warstaffOfTheVanguard,
    'type': ItemCategories.weapon,
    'tags': ['item', 'weapon', 'staff', 'power'],
    'properties': {'attack': 5},
    'maxClass': 9,
  },
  {
    'id': ItemIds.clothArmor,
    'type': ItemCategories.armor,
    'tags': ['item', 'armor', 'aff:sturdy', 'rarity:common'],
    'properties': {'defense': 2},
    'training': {'consistency': 0.4, 'control': 0.3, 'reaction': 0.3},
    'requirements': {
      'mastery': {
        'subject': 'item:cloth_armor',
        'minimum': 1,
        'thresholds': [8],
      },
    },
    'maxClass': 3,
    'gradeEvolution': [
      {'targetId': ItemIds.paddedClothArmor, 'tags': [TrainingDimensions.consistency]},
      {'targetId': ItemIds.reinforcedClothArmor, 'tags': [TrainingDimensions.control]},
    ],
  },
  {
    'id': ItemIds.paddedClothArmor,
    'type': ItemCategories.armor,
    'tags': ['item', 'armor', 'consistency'],
    'properties': {'defense': 3},
    'training': {'consistency': 0.6, 'reaction': 0.4},
    'maxClass': 6,
    'gradeEvolution': [
      {'targetId': ItemIds.fortifiedClothArmor},
    ],
  },
  {
    'id': ItemIds.fortifiedClothArmor,
    'type': ItemCategories.armor,
    'tags': ['item', 'armor', 'consistency'],
    'properties': {'defense': 4},
    'maxClass': 9,
  },
  {
    'id': ItemIds.reinforcedClothArmor,
    'type': ItemCategories.armor,
    'tags': ['item', 'armor', 'control'],
    'properties': {'defense': 3},
    'training': {'control': 0.6, 'consistency': 0.4},
    'maxClass': 6,
    'gradeEvolution': [
      {'targetId': ItemIds.bastionClothArmor},
    ],
  },
  {
    'id': ItemIds.bastionClothArmor,
    'type': ItemCategories.armor,
    'tags': ['item', 'armor', 'control'],
    'properties': {'defense': 5},
    'maxClass': 9,
  },
  {
    'id': ItemIds.trainingShoes,
    'type': ItemCategories.footwear,
    'tags': ['item', 'footwear', 'aff:burst', 'rarity:common'],
    'properties': {'speed': 1},
    'training': {'speed': 0.5, 'reaction': 0.3, 'consistency': 0.2},
    'requirements': {
      'mastery': {'subject': 'item:training_shoes', 'minimum': 0},
    },
    'maxClass': 3,
    'gradeEvolution': [
      {'targetId': ItemIds.swiftShoes, 'tags': [TrainingDimensions.speed]},
      {'targetId': ItemIds.surefootedShoes, 'tags': [TrainingDimensions.reaction]},
    ],
  },
  {
    'id': ItemIds.swiftShoes,
    'type': ItemCategories.footwear,
    'tags': ['item', 'footwear', 'speed'],
    'properties': {'speed': 2},
    'training': {'speed': 0.7, 'consistency': 0.3},
    'maxClass': 6,
    'gradeEvolution': [
      {'targetId': ItemIds.windwalkerBoots},
    ],
  },
  {
    'id': ItemIds.windwalkerBoots,
    'type': ItemCategories.footwear,
    'tags': ['item', 'footwear', 'speed'],
    'properties': {'speed': 3},
    'maxClass': 9,
  },
  {
    'id': ItemIds.surefootedShoes,
    'type': ItemCategories.footwear,
    'tags': ['item', 'footwear', 'reaction'],
    'properties': {'speed': 2},
    'training': {'reaction': 0.6, 'consistency': 0.4},
    'maxClass': 6,
    'gradeEvolution': [
      {'targetId': ItemIds.steadfastBoots},
    ],
  },
  {
    'id': ItemIds.steadfastBoots,
    'type': ItemCategories.footwear,
    'tags': ['item', 'footwear', 'reaction'],
    'properties': {'speed': 3},
    'maxClass': 9,
  },

  // --- Martial-style starting kits (all immediately usable) ---
  // `polearm` and `rapier` additionally carry a V1 combine chain — still
  // `minimum: 0`, ids unchanged; the `maxClass`/`gradeEvolution` fields
  // are purely additive so a style's starter weapon has somewhere to grow.
  {
    'id': ItemIds.polearm,
    'type': ItemCategories.weapon,
    'tags': ['item', 'weapon', 'polearm', 'reach', 'aff:sturdy', 'rarity:common'],
    'properties': {'attack': 3},
    'training': {'power': 0.4, 'precision': 0.3, 'control': 0.3},
    'requirements': {
      'mastery': {'subject': 'item:polearm', 'minimum': 0},
    },
    'maxClass': 3,
    'gradeEvolution': [
      {'targetId': ItemIds.reachSpear, 'tags': [TrainingDimensions.control]},
      {'targetId': ItemIds.warGlaive, 'tags': [TrainingDimensions.power]},
    ],
  },
  {
    'id': ItemIds.chair,
    'type': ItemCategories.weapon,
    'tags': ['item', 'weapon', 'improvised'],
    'properties': {'attack': 2},
    'training': {'power': 0.4, 'reaction': 0.3, 'control': 0.3},
    'requirements': {
      'mastery': {'subject': 'item:chair', 'minimum': 0},
    },
  },
  {
    'id': ItemIds.mask,
    'type': ItemCategories.armor,
    'tags': ['item', 'armor', 'head'],
    'properties': {'defense': 1},
    'training': {'consistency': 0.4, 'reaction': 0.3, 'control': 0.3},
    'requirements': {
      'mastery': {'subject': 'item:mask', 'minimum': 0},
    },
  },
  {
    'id': ItemIds.rapier,
    'type': ItemCategories.weapon,
    'tags': ['item', 'weapon', 'blade', 'thrust', 'aff:burst', 'rarity:common'],
    'properties': {'attack': 3},
    'training': {'speed': 0.4, 'precision': 0.4, 'reaction': 0.2},
    'requirements': {
      'mastery': {'subject': 'item:rapier', 'minimum': 0},
    },
    'maxClass': 3,
    'gradeEvolution': [
      {'targetId': ItemIds.duelistsRapier, 'tags': [TrainingDimensions.precision]},
      {'targetId': ItemIds.swiftRapier, 'tags': [TrainingDimensions.speed]},
    ],
  },
  {
    'id': ItemIds.staff,
    'type': ItemCategories.weapon,
    'tags': ['item', 'weapon', 'staff'],
    'properties': {'attack': 2},
    'training': {'control': 0.4, 'precision': 0.3, 'power': 0.3},
    'requirements': {
      'mastery': {'subject': 'item:staff', 'minimum': 0},
    },
  },
  {
    'id': ItemIds.fan,
    'type': ItemCategories.weapon,
    'tags': ['item', 'weapon', 'fan'],
    'properties': {'attack': 2},
    'training': {'speed': 0.4, 'precision': 0.3, 'control': 0.3},
    'requirements': {
      'mastery': {'subject': 'item:fan', 'minimum': 0},
    },
  },
  {
    'id': ItemIds.towel,
    'type': ItemCategories.armor,
    'tags': ['item', 'armor', 'cloth', 'grappling'],
    'properties': {'defense': 1},
    'training': {'control': 0.4, 'consistency': 0.3, 'reaction': 0.3},
    'requirements': {
      'mastery': {'subject': 'item:towel', 'minimum': 0},
    },
  },
  {
    'id': ItemIds.cloth,
    'type': ItemCategories.armor,
    'tags': ['item', 'armor', 'cloth'],
    'properties': {'defense': 1},
    'training': {'consistency': 0.4, 'control': 0.3, 'reaction': 0.3},
    'requirements': {
      'mastery': {'subject': 'item:cloth', 'minimum': 0},
    },
  },

  // --- Content Expansion V1: hand_wraps combinable family ---
  // A fist weapon for palm/finger builds (eastern-leaning). `fist` is in
  // most styles' aligned family set, so it stays a safe hybrid pick.
  {
    'id': ItemIds.handWraps,
    'type': ItemCategories.weapon,
    'tags': ['item', 'weapon', 'fist', 'aff:endurance', 'rarity:common'],
    'properties': {'attack': 1},
    'training': {'control': 0.4, 'precision': 0.3, 'power': 0.3},
    'requirements': {
      'mastery': {'subject': 'item:hand_wraps', 'minimum': 0},
    },
    'maxClass': 3,
    'gradeEvolution': [
      {'targetId': ItemIds.focusWraps, 'tags': [TrainingDimensions.precision]},
      {'targetId': ItemIds.weightedWraps, 'tags': [TrainingDimensions.power]},
    ],
  },
  {
    'id': ItemIds.focusWraps,
    'type': ItemCategories.weapon,
    'tags': ['item', 'weapon', 'fist', 'precision', 'aff:endurance', 'rarity:uncommon'],
    'properties': {'attack': 2},
    'training': {'precision': 0.6, 'control': 0.4},
    'maxClass': 6,
    'gradeEvolution': [
      {'targetId': ItemIds.mastersWraps},
    ],
  },
  {
    'id': ItemIds.mastersWraps,
    'type': ItemCategories.weapon,
    'tags': ['item', 'weapon', 'fist', 'precision', 'aff:endurance', 'rarity:rare'],
    'properties': {'attack': 3},
    'maxClass': 9,
  },
  {
    'id': ItemIds.weightedWraps,
    'type': ItemCategories.weapon,
    'tags': ['item', 'weapon', 'fist', 'power', 'aff:power', 'rarity:uncommon'],
    'properties': {'attack': 2},
    'training': {'power': 0.6, 'control': 0.4},
    'maxClass': 6,
    'gradeEvolution': [
      {'targetId': ItemIds.diamondWraps},
    ],
  },
  {
    'id': ItemIds.diamondWraps,
    'type': ItemCategories.weapon,
    'tags': ['item', 'weapon', 'fist', 'power', 'aff:power', 'rarity:rare'],
    'properties': {'attack': 4},
    'maxClass': 9,
  },

  // --- Content Expansion V1: polearm starter combine chain ---
  {
    'id': ItemIds.reachSpear,
    'type': ItemCategories.weapon,
    'tags': ['item', 'weapon', 'polearm', 'reach', 'control', 'aff:sturdy', 'rarity:uncommon'],
    'properties': {'attack': 4},
    'training': {'control': 0.6, 'precision': 0.4},
    'maxClass': 6,
    'gradeEvolution': [
      {'targetId': ItemIds.sentinelSpear},
    ],
  },
  {
    'id': ItemIds.sentinelSpear,
    'type': ItemCategories.weapon,
    'tags': ['item', 'weapon', 'polearm', 'reach', 'control', 'aff:sturdy', 'rarity:rare'],
    'properties': {'attack': 6},
    'maxClass': 9,
  },
  {
    'id': ItemIds.warGlaive,
    'type': ItemCategories.weapon,
    'tags': ['item', 'weapon', 'polearm', 'reach', 'power', 'aff:power', 'rarity:uncommon'],
    'properties': {'attack': 4},
    'training': {'power': 0.6, 'control': 0.4},
    'maxClass': 6,
    'gradeEvolution': [
      {'targetId': ItemIds.vanguardGlaive},
    ],
  },
  {
    'id': ItemIds.vanguardGlaive,
    'type': ItemCategories.weapon,
    'tags': ['item', 'weapon', 'polearm', 'reach', 'power', 'aff:power', 'rarity:rare'],
    'properties': {'attack': 7},
    'maxClass': 9,
  },

  // --- Content Expansion V1: rapier starter combine chain ---
  {
    'id': ItemIds.duelistsRapier,
    'type': ItemCategories.weapon,
    'tags': ['item', 'weapon', 'blade', 'thrust', 'precision', 'aff:burst', 'rarity:uncommon'],
    'properties': {'attack': 4},
    'training': {'precision': 0.6, 'reaction': 0.4},
    'maxClass': 6,
    'gradeEvolution': [
      {'targetId': ItemIds.mastersRapier},
    ],
  },
  {
    'id': ItemIds.mastersRapier,
    'type': ItemCategories.weapon,
    'tags': ['item', 'weapon', 'blade', 'thrust', 'precision', 'aff:burst', 'rarity:rare'],
    'properties': {'attack': 6},
    'maxClass': 9,
  },
  {
    'id': ItemIds.swiftRapier,
    'type': ItemCategories.weapon,
    'tags': ['item', 'weapon', 'blade', 'thrust', 'speed', 'aff:burst', 'rarity:uncommon'],
    'properties': {'attack': 4},
    'training': {'speed': 0.6, 'reaction': 0.4},
    'maxClass': 6,
    'gradeEvolution': [
      {'targetId': ItemIds.windRapier},
    ],
  },
  {
    'id': ItemIds.windRapier,
    'type': ItemCategories.weapon,
    'tags': ['item', 'weapon', 'blade', 'thrust', 'speed', 'aff:burst', 'rarity:rare'],
    'properties': {'attack': 6},
    'maxClass': 9,
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

  final maxClass = definition.extra['maxClass'] as int?;

  final rawGradeEvolution = (definition.extra['gradeEvolution'] as List?) ?? const [];
  final gradeEvolutionCandidates = [
    for (final entry in rawGradeEvolution)
      EvolutionCandidate(
        targetId: (entry as Map)['targetId'] as String,
        tags: {
          for (final tag in (entry['tags'] as List? ?? const [])) tag as String,
        },
      ),
  ];

  final classScalingPercent =
      (definition.extra['classScalingPercent'] as num?) ?? 15;

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
    maxClass: maxClass,
    gradeEvolutionCandidates: gradeEvolutionCandidates,
    classScalingPercent: classScalingPercent,
  );
}

/// Resolves and parses item [id] from [context]'s loaded content in one
/// call — the same convenience `martialItem`/`elementalItem` already
/// provide for their own plugins. Stateless: re-resolves from
/// `context.content` on every call, no caching.
ItemDefinition itemDefinition(String id, PluginContext context) =>
    itemDefinitionFromContent(context.content.get(id));
