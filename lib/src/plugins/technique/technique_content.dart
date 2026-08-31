import 'package:build_engine/build_engine.dart';

import 'technique_definition.dart';
import 'technique_vocabulary.dart';

/// 3 base techniques + their 8 evolved branches, as data — loaded via
/// `PluginSdk.registerContentBatch` in `TechniquePlugin.initialize`.
/// Candidate tags match `TrainingDimensions` constants directly (`speed`/
/// `power`/`reaction`/`precision`) so `EvolutionResolver`'s existing
/// tag-weighted-by-`TrainingProfile` mechanism picks them up with zero
/// new resolver code — exactly the milestone's "high speed -> faster
/// candidates gain weight" example. Evolved branches are terminal
/// (no further `evolution` field) and carry no `requirements` — keeping
/// this plugin's shipped content fully standalone (no MartialArts tag
/// dependency) is what makes the "no Technique -> MartialArts dependency
/// unless content requires it" architecture check trivially true by
/// construction.
/// Content Expansion V1: the three original families (punch / slash /
/// guard) now run `basic → intermediate → advanced → master`, and three
/// new base families (palm / finger / kick) are added. Every form carries
/// an `aff:<physique>` tag (read only by the client reward weighter) and
/// a `rarity:<tier>` tag (`common`/`uncommon`/`rare`/`master`, gating
/// master-rarity loot until later runs). Family tags (`fist`/`blade`/
/// `palm`/`finger`/`kick`/`guard`) double as the recognised family tags
/// the off-specialty penalty reads. Intermediate/advanced forms carry
/// their own `training` weights so a player can steer the next evolution;
/// master forms are terminal and are deliberately single-dimension
/// sidegrades (higher ceiling, no accuracy/multi-hit sweetener) rather
/// than a flat upgrade over their advanced parent.
const techniqueContentDefinitions = <Map<String, dynamic>>[
  // ══ Punch family ═══════════════════════════════════════════════════
  {
    'id': TechniqueIds.basicPunch,
    'type': 'technique',
    'name': 'Basic Punch',
    'tier': EvolutionTiers.basic,
    'tags': ['technique', 'fist', 'aff:burst', 'rarity:common'],
    'properties': {'damage': 6},
    'training': {'speed': 0.3, 'power': 0.2, 'precision': 0.2, 'reaction': 0.3},
    'evolution': [
      {'targetId': TechniqueIds.lightPunch, 'tags': [TrainingDimensions.precision]},
      {'targetId': TechniqueIds.heavyPunch, 'tags': [TrainingDimensions.power]},
      {'targetId': TechniqueIds.fastPunch, 'tags': [TrainingDimensions.speed]},
      {'targetId': TechniqueIds.counterPunch, 'tags': [TrainingDimensions.reaction]},
    ],
  },
  {
    'id': TechniqueIds.lightPunch,
    'type': 'technique',
    'name': 'Light Punch',
    'tier': EvolutionTiers.intermediate,
    'tags': ['technique', 'fist', 'precision', 'aff:burst', 'rarity:uncommon'],
    'properties': {'damage': 5, 'accuracy': 2},
    'training': {'precision': 0.6, 'control': 0.4},
    'evolution': [
      {'targetId': TechniqueIds.preciseJab, 'tags': [TrainingDimensions.precision]},
    ],
  },
  {
    'id': TechniqueIds.heavyPunch,
    'type': 'technique',
    'name': 'Heavy Punch',
    'tier': EvolutionTiers.intermediate,
    'tags': ['technique', 'fist', 'power', 'aff:power', 'rarity:uncommon'],
    'properties': {'damage': 11},
    'training': {'power': 0.7, 'control': 0.3},
    'evolution': [
      {'targetId': TechniqueIds.hammerBlow, 'tags': [TrainingDimensions.power]},
    ],
  },
  {
    'id': TechniqueIds.fastPunch,
    'type': 'technique',
    'name': 'Fast Punch',
    'tier': EvolutionTiers.intermediate,
    'tags': ['technique', 'fist', 'speed', 'aff:burst', 'rarity:uncommon'],
    'properties': {'damage': 5, 'hits': 2},
    'training': {'speed': 0.6, 'reaction': 0.4},
    'evolution': [
      {'targetId': TechniqueIds.flashStrike, 'tags': [TrainingDimensions.speed]},
    ],
  },
  {
    'id': TechniqueIds.counterPunch,
    'type': 'technique',
    'name': 'Counter Punch',
    'tier': EvolutionTiers.intermediate,
    'tags': ['technique', 'fist', 'counter', 'aff:sturdy', 'rarity:uncommon'],
    'properties': {'damage': 7},
    'training': {'reaction': 0.6, 'control': 0.4},
  },
  {
    'id': TechniqueIds.preciseJab,
    'type': 'technique',
    'name': 'Precise Jab',
    'tier': EvolutionTiers.advanced,
    'tags': ['technique', 'fist', 'precision', 'aff:burst', 'rarity:rare'],
    'properties': {'damage': 7, 'accuracy': 3},
    'training': {'precision': 0.7, 'speed': 0.3},
    'evolution': [
      {'targetId': TechniqueIds.lightningJab, 'tags': [TrainingDimensions.precision]},
    ],
  },
  {
    'id': TechniqueIds.lightningJab,
    'type': 'technique',
    'name': 'Lightning Jab',
    'tier': EvolutionTiers.master,
    'tags': ['technique', 'fist', 'precision', 'speed', 'aff:burst', 'rarity:master'],
    'properties': {'damage': 6, 'hits': 2, 'accuracy': 2},
  },
  {
    'id': TechniqueIds.hammerBlow,
    'type': 'technique',
    'name': 'Hammer Blow',
    'tier': EvolutionTiers.advanced,
    'tags': ['technique', 'fist', 'power', 'aff:power', 'rarity:rare'],
    'properties': {'damage': 15},
    'training': {'power': 0.8, 'control': 0.2},
    'evolution': [
      {'targetId': TechniqueIds.mountainBreaker, 'tags': [TrainingDimensions.power]},
    ],
  },
  {
    'id': TechniqueIds.mountainBreaker,
    'type': 'technique',
    'name': 'Mountain Breaker',
    'tier': EvolutionTiers.master,
    'tags': ['technique', 'fist', 'power', 'aff:power', 'rarity:master'],
    'properties': {'damage': 22},
  },
  {
    'id': TechniqueIds.flashStrike,
    'type': 'technique',
    'name': 'Flash Strike',
    'tier': EvolutionTiers.advanced,
    'tags': ['technique', 'fist', 'speed', 'aff:burst', 'rarity:rare'],
    'properties': {'damage': 6, 'hits': 2},
    'training': {'speed': 0.7, 'reaction': 0.3},
    'evolution': [
      {'targetId': TechniqueIds.thunderFlash, 'tags': [TrainingDimensions.speed]},
    ],
  },
  {
    'id': TechniqueIds.thunderFlash,
    'type': 'technique',
    'name': 'Thunder Flash',
    'tier': EvolutionTiers.master,
    'tags': ['technique', 'fist', 'speed', 'reaction', 'aff:burst', 'rarity:master'],
    'properties': {'damage': 5, 'hits': 3},
  },

  // ══ Slash family ═══════════════════════════════════════════════════
  {
    'id': TechniqueIds.basicSlash,
    'type': 'technique',
    'name': 'Basic Slash',
    'tier': EvolutionTiers.basic,
    'tags': ['technique', 'blade', 'aff:power', 'rarity:common'],
    'properties': {'damage': 8},
    'training': {'speed': 0.25, 'power': 0.35, 'precision': 0.25, 'reaction': 0.15},
    'evolution': [
      {'targetId': TechniqueIds.quickSlash, 'tags': [TrainingDimensions.speed]},
      {'targetId': TechniqueIds.heavySlash, 'tags': [TrainingDimensions.power]},
    ],
  },
  {
    'id': TechniqueIds.quickSlash,
    'type': 'technique',
    'name': 'Quick Slash',
    'tier': EvolutionTiers.intermediate,
    'tags': ['technique', 'blade', 'speed', 'aff:burst', 'rarity:uncommon'],
    'properties': {'damage': 6, 'hits': 2},
    'training': {'speed': 0.6, 'precision': 0.4},
    'evolution': [
      {'targetId': TechniqueIds.flashingSlash, 'tags': [TrainingDimensions.speed]},
    ],
  },
  {
    'id': TechniqueIds.heavySlash,
    'type': 'technique',
    'name': 'Heavy Slash',
    'tier': EvolutionTiers.intermediate,
    'tags': ['technique', 'blade', 'power', 'aff:power', 'rarity:uncommon'],
    'properties': {'damage': 15},
    'training': {'power': 0.7, 'control': 0.3},
    'evolution': [
      {'targetId': TechniqueIds.cleavingSlash, 'tags': [TrainingDimensions.power]},
    ],
  },
  {
    'id': TechniqueIds.flashingSlash,
    'type': 'technique',
    'name': 'Flashing Slash',
    'tier': EvolutionTiers.advanced,
    'tags': ['technique', 'blade', 'speed', 'aff:burst', 'rarity:rare'],
    'properties': {'damage': 7, 'hits': 2},
    'training': {'speed': 0.7, 'precision': 0.3},
    'evolution': [
      {'targetId': TechniqueIds.lightningSlash, 'tags': [TrainingDimensions.speed]},
    ],
  },
  {
    'id': TechniqueIds.lightningSlash,
    'type': 'technique',
    'name': 'Lightning Slash',
    'tier': EvolutionTiers.master,
    'tags': ['technique', 'blade', 'speed', 'precision', 'aff:burst', 'rarity:master'],
    'properties': {'damage': 7, 'hits': 3},
  },
  {
    'id': TechniqueIds.cleavingSlash,
    'type': 'technique',
    'name': 'Cleaving Slash',
    'tier': EvolutionTiers.advanced,
    'tags': ['technique', 'blade', 'power', 'aff:power', 'rarity:rare'],
    'properties': {'damage': 20},
    'training': {'power': 0.8, 'control': 0.2},
    'evolution': [
      {'targetId': TechniqueIds.mountainCleave, 'tags': [TrainingDimensions.power]},
    ],
  },
  {
    'id': TechniqueIds.mountainCleave,
    'type': 'technique',
    'name': 'Mountain Cleave',
    'tier': EvolutionTiers.master,
    'tags': ['technique', 'blade', 'power', 'aff:power', 'rarity:master'],
    'properties': {'damage': 28},
  },

  // ══ Guard family ═══════════════════════════════════════════════════
  {
    'id': TechniqueIds.basicGuard,
    'type': 'technique',
    'name': 'Basic Guard',
    'tier': EvolutionTiers.basic,
    'tags': ['technique', 'guard', 'aff:sturdy', 'rarity:common'],
    'properties': {'defense': 4},
    'training': {'reaction': 0.4, 'control': 0.3, 'consistency': 0.3},
    'evolution': [
      {'targetId': TechniqueIds.fastGuard, 'tags': [TrainingDimensions.speed]},
      {'targetId': TechniqueIds.counterGuard, 'tags': [TrainingDimensions.reaction]},
    ],
  },
  {
    'id': TechniqueIds.fastGuard,
    'type': 'technique',
    'name': 'Fast Guard',
    'tier': EvolutionTiers.intermediate,
    'tags': ['technique', 'guard', 'speed', 'aff:burst', 'rarity:uncommon'],
    'properties': {'defense': 3},
    'training': {'speed': 0.5, 'reaction': 0.5},
    'evolution': [
      {'targetId': TechniqueIds.rollingGuard, 'tags': [TrainingDimensions.reaction]},
    ],
  },
  {
    'id': TechniqueIds.counterGuard,
    'type': 'technique',
    'name': 'Counter Guard',
    'tier': EvolutionTiers.intermediate,
    'tags': ['technique', 'guard', 'counter', 'aff:sturdy', 'rarity:uncommon'],
    'properties': {'defense': 5},
    'training': {'reaction': 0.6, 'control': 0.4},
    'evolution': [
      {'targetId': TechniqueIds.turningGuard, 'tags': [TrainingDimensions.reaction]},
    ],
  },
  {
    'id': TechniqueIds.rollingGuard,
    'type': 'technique',
    'name': 'Rolling Guard',
    'tier': EvolutionTiers.advanced,
    'tags': ['technique', 'guard', 'reaction', 'aff:burst', 'rarity:rare'],
    'properties': {'defense': 4},
    'training': {'reaction': 0.7, 'consistency': 0.3},
  },
  {
    'id': TechniqueIds.turningGuard,
    'type': 'technique',
    'name': 'Turning Guard',
    'tier': EvolutionTiers.advanced,
    'tags': ['technique', 'guard', 'counter', 'control', 'aff:sturdy', 'rarity:rare'],
    'properties': {'defense': 6},
    'training': {'reaction': 0.5, 'control': 0.5},
    'evolution': [
      {'targetId': TechniqueIds.stillWaterGuard, 'tags': [TrainingDimensions.control]},
    ],
  },
  {
    'id': TechniqueIds.stillWaterGuard,
    'type': 'technique',
    'name': 'Still Water Guard',
    'tier': EvolutionTiers.master,
    'tags': ['technique', 'guard', 'control', 'aff:endurance', 'rarity:master'],
    'properties': {'defense': 7},
  },

  // ══ Palm family (new) ══════════════════════════════════════════════
  {
    'id': TechniqueIds.basicPalm,
    'type': 'technique',
    'name': 'Basic Palm',
    'tier': EvolutionTiers.basic,
    'tags': ['technique', 'palm', 'aff:endurance', 'rarity:common'],
    'properties': {'damage': 7},
    'training': {'power': 0.3, 'control': 0.3, 'precision': 0.2, 'reaction': 0.2},
    'evolution': [
      {'targetId': TechniqueIds.focusedPalm, 'tags': [TrainingDimensions.precision]},
      {'targetId': TechniqueIds.pushingPalm, 'tags': [TrainingDimensions.control]},
    ],
  },
  {
    'id': TechniqueIds.focusedPalm,
    'type': 'technique',
    'name': 'Focused Palm',
    'tier': EvolutionTiers.intermediate,
    'tags': ['technique', 'palm', 'precision', 'aff:endurance', 'rarity:uncommon'],
    'properties': {'damage': 6, 'accuracy': 3},
    'training': {'precision': 0.6, 'control': 0.4},
    'evolution': [
      {'targetId': TechniqueIds.ironPalm, 'tags': [TrainingDimensions.power]},
    ],
  },
  {
    'id': TechniqueIds.pushingPalm,
    'type': 'technique',
    'name': 'Pushing Palm',
    'tier': EvolutionTiers.intermediate,
    'tags': ['technique', 'palm', 'control', 'aff:endurance', 'rarity:uncommon'],
    'properties': {'damage': 5, 'defense': 2},
    'training': {'control': 0.6, 'reaction': 0.4},
    'evolution': [
      {'targetId': TechniqueIds.stillPalm, 'tags': [TrainingDimensions.control]},
    ],
  },
  {
    'id': TechniqueIds.ironPalm,
    'type': 'technique',
    'name': 'Iron Palm',
    'tier': EvolutionTiers.advanced,
    'tags': ['technique', 'palm', 'power', 'aff:power', 'rarity:rare'],
    'properties': {'damage': 14},
    'training': {'power': 0.6, 'control': 0.4},
    'evolution': [
      {'targetId': TechniqueIds.thunderPalm, 'tags': [TrainingDimensions.power]},
    ],
  },
  {
    'id': TechniqueIds.thunderPalm,
    'type': 'technique',
    'name': 'Thunder Palm',
    'tier': EvolutionTiers.master,
    'tags': ['technique', 'palm', 'power', 'precision', 'aff:power', 'rarity:master'],
    'properties': {'damage': 19},
  },
  {
    'id': TechniqueIds.stillPalm,
    'type': 'technique',
    'name': 'Still Palm',
    'tier': EvolutionTiers.advanced,
    'tags': ['technique', 'palm', 'control', 'aff:endurance', 'rarity:rare'],
    'properties': {'damage': 6, 'defense': 3},
    'training': {'control': 0.7, 'consistency': 0.3},
  },

  // ══ Finger family (new) ════════════════════════════════════════════
  {
    'id': TechniqueIds.basicFinger,
    'type': 'technique',
    'name': 'Basic Finger',
    'tier': EvolutionTiers.basic,
    'tags': ['technique', 'finger', 'aff:burst', 'rarity:common'],
    'properties': {'damage': 5, 'accuracy': 2},
    'training': {'precision': 0.4, 'speed': 0.3, 'reaction': 0.3},
    'evolution': [
      {'targetId': TechniqueIds.fingerStrike, 'tags': [TrainingDimensions.precision]},
      {'targetId': TechniqueIds.needleFinger, 'tags': [TrainingDimensions.speed]},
    ],
  },
  {
    'id': TechniqueIds.fingerStrike,
    'type': 'technique',
    'name': 'Finger Strike',
    'tier': EvolutionTiers.intermediate,
    'tags': ['technique', 'finger', 'precision', 'aff:burst', 'rarity:uncommon'],
    'properties': {'damage': 6, 'accuracy': 3},
    'training': {'precision': 0.6, 'speed': 0.4},
    'evolution': [
      {'targetId': TechniqueIds.piercingFinger, 'tags': [TrainingDimensions.precision]},
    ],
  },
  {
    'id': TechniqueIds.needleFinger,
    'type': 'technique',
    'name': 'Needle Finger',
    'tier': EvolutionTiers.intermediate,
    'tags': ['technique', 'finger', 'speed', 'aff:burst', 'rarity:uncommon'],
    'properties': {'damage': 4, 'hits': 2},
    'training': {'speed': 0.6, 'reaction': 0.4},
  },
  {
    'id': TechniqueIds.piercingFinger,
    'type': 'technique',
    'name': 'Piercing Finger',
    'tier': EvolutionTiers.advanced,
    'tags': ['technique', 'finger', 'precision', 'aff:burst', 'rarity:rare'],
    'properties': {'damage': 8, 'accuracy': 4},
    'training': {'precision': 0.7, 'speed': 0.3},
    'evolution': [
      {'targetId': TechniqueIds.lightningFinger, 'tags': [TrainingDimensions.precision]},
    ],
  },
  {
    'id': TechniqueIds.lightningFinger,
    'type': 'technique',
    'name': 'Lightning Finger',
    'tier': EvolutionTiers.master,
    'tags': ['technique', 'finger', 'precision', 'speed', 'aff:burst', 'rarity:master'],
    'properties': {'damage': 7, 'hits': 2, 'accuracy': 3},
  },

  // ══ Kick family (new) ══════════════════════════════════════════════
  {
    'id': TechniqueIds.basicKick,
    'type': 'technique',
    'name': 'Basic Kick',
    'tier': EvolutionTiers.basic,
    'tags': ['technique', 'kick', 'aff:power', 'rarity:common'],
    'properties': {'damage': 7},
    'training': {'power': 0.3, 'reaction': 0.3, 'speed': 0.2, 'control': 0.2},
    'evolution': [
      {'targetId': TechniqueIds.snapKick, 'tags': [TrainingDimensions.speed]},
      {'targetId': TechniqueIds.thrustKick, 'tags': [TrainingDimensions.power]},
    ],
  },
  {
    'id': TechniqueIds.snapKick,
    'type': 'technique',
    'name': 'Snap Kick',
    'tier': EvolutionTiers.intermediate,
    'tags': ['technique', 'kick', 'speed', 'aff:burst', 'rarity:uncommon'],
    'properties': {'damage': 6, 'hits': 2},
    'training': {'speed': 0.6, 'reaction': 0.4},
    'evolution': [
      {'targetId': TechniqueIds.spinningKick, 'tags': [TrainingDimensions.power]},
    ],
  },
  {
    'id': TechniqueIds.thrustKick,
    'type': 'technique',
    'name': 'Thrust Kick',
    'tier': EvolutionTiers.intermediate,
    'tags': ['technique', 'kick', 'reach', 'power', 'aff:power', 'rarity:uncommon'],
    'properties': {'damage': 12},
    'training': {'power': 0.5, 'control': 0.3, 'precision': 0.2},
    'evolution': [
      {'targetId': TechniqueIds.crescentKick, 'tags': [TrainingDimensions.reaction]},
    ],
  },
  {
    'id': TechniqueIds.spinningKick,
    'type': 'technique',
    'name': 'Spinning Kick',
    'tier': EvolutionTiers.advanced,
    'tags': ['technique', 'kick', 'power', 'aff:power', 'rarity:rare'],
    'properties': {'damage': 16},
    'training': {'power': 0.6, 'control': 0.4},
    'evolution': [
      {'targetId': TechniqueIds.whirlwindKick, 'tags': [TrainingDimensions.power]},
    ],
  },
  {
    'id': TechniqueIds.whirlwindKick,
    'type': 'technique',
    'name': 'Whirlwind Kick',
    'tier': EvolutionTiers.master,
    'tags': ['technique', 'kick', 'power', 'reaction', 'aff:power', 'rarity:master'],
    'properties': {'damage': 13, 'hits': 2},
  },
  {
    'id': TechniqueIds.crescentKick,
    'type': 'technique',
    'name': 'Crescent Kick',
    'tier': EvolutionTiers.advanced,
    'tags': ['technique', 'kick', 'reaction', 'aff:sturdy', 'rarity:rare'],
    'properties': {'damage': 9},
    'training': {'reaction': 0.6, 'control': 0.4},
  },
];

/// Builds a [TechniqueDefinition] from a loaded [ContentDefinition].
/// `extra['name']`/`extra['tier']` supply the two fields `ContentRegistry`
/// doesn't natively parse; `definition.conditions` (native) supplies
/// [TechniqueDefinition.requirements] verbatim; `extra['evolution']`
/// supplies [TechniqueDefinition.evolutionCandidates]; `extra['properties']`
/// supplies properties + [TechniqueDefinition.modifiersFor] (via the
/// shared `modifiersFromProperties`), exactly mirroring
/// `itemDefinitionFromContent`; `extra['training']` supplies
/// [TechniqueDefinition.trainingWeights] — content data, not a
/// hand-written Dart constant (`ARCHITECTURE_AUDIT.md`'s category-7
/// finding).
TechniqueDefinition techniqueDefinitionFromContent(ContentDefinition definition) {
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

  final rawEvolution = (definition.extra['evolution'] as List?) ?? const [];
  final evolutionCandidates = [
    for (final entry in rawEvolution)
      EvolutionCandidate(
        targetId: (entry as Map)['targetId'] as String,
        tags: {
          for (final tag in (entry['tags'] as List? ?? const [])) tag as String,
        },
      ),
  ];

  List<Modifier> modifiersFor(EntityId owner) => modifiersFromProperties(
        domain: 'technique',
        contentId: definition.id,
        properties: properties,
        target: owner,
      );

  return TechniqueDefinition(
    id: definition.id,
    name: definition.extra['name'] as String,
    tier: definition.extra['tier'] as String,
    tags: definition.tags,
    properties: properties,
    requirements: definition.conditions,
    evolutionCandidates: evolutionCandidates,
    trainingWeights: trainingWeights,
    modifiersFor: modifiersFor,
  );
}

/// Resolves and parses technique [id] from [context]'s loaded content —
/// the same convenience `itemDefinition`/`martialItem` already provide.
TechniqueDefinition techniqueDefinition(String id, PluginContext context) =>
    techniqueDefinitionFromContent(context.content.get(id));
