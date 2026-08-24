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
const techniqueContentDefinitions = <Map<String, dynamic>>[
  {
    'id': TechniqueIds.basicPunch,
    'type': 'technique',
    'name': 'Basic Punch',
    'tier': EvolutionTiers.basic,
    'tags': ['technique', 'fist'],
    'properties': {'damage': 6},
    'evolution': [
      {'targetId': TechniqueIds.lightPunch, 'tags': [TrainingDimensions.precision]},
      {'targetId': TechniqueIds.heavyPunch, 'tags': [TrainingDimensions.power]},
      {'targetId': TechniqueIds.fastPunch, 'tags': [TrainingDimensions.speed]},
      {'targetId': TechniqueIds.counterPunch, 'tags': [TrainingDimensions.reaction]},
    ],
  },
  {
    'id': TechniqueIds.basicSlash,
    'type': 'technique',
    'name': 'Basic Slash',
    'tier': EvolutionTiers.basic,
    'tags': ['technique', 'blade'],
    'properties': {'damage': 8},
    'evolution': [
      {'targetId': TechniqueIds.quickSlash, 'tags': [TrainingDimensions.speed]},
      {'targetId': TechniqueIds.heavySlash, 'tags': [TrainingDimensions.power]},
    ],
  },
  {
    'id': TechniqueIds.basicGuard,
    'type': 'technique',
    'name': 'Basic Guard',
    'tier': EvolutionTiers.basic,
    'tags': ['technique', 'guard'],
    'properties': {'defense': 4},
    'evolution': [
      {'targetId': TechniqueIds.fastGuard, 'tags': [TrainingDimensions.speed]},
      {'targetId': TechniqueIds.counterGuard, 'tags': [TrainingDimensions.reaction]},
    ],
  },
  {
    'id': TechniqueIds.lightPunch,
    'type': 'technique',
    'name': 'Light Punch',
    'tier': EvolutionTiers.intermediate,
    'tags': ['technique', 'fist', 'precision'],
    'properties': {'damage': 5, 'accuracy': 2},
  },
  {
    'id': TechniqueIds.heavyPunch,
    'type': 'technique',
    'name': 'Heavy Punch',
    'tier': EvolutionTiers.intermediate,
    'tags': ['technique', 'fist', 'power'],
    'properties': {'damage': 11},
  },
  {
    'id': TechniqueIds.fastPunch,
    'type': 'technique',
    'name': 'Fast Punch',
    'tier': EvolutionTiers.intermediate,
    'tags': ['technique', 'fist', 'speed'],
    'properties': {'damage': 5, 'hits': 2},
  },
  {
    'id': TechniqueIds.counterPunch,
    'type': 'technique',
    'name': 'Counter Punch',
    'tier': EvolutionTiers.intermediate,
    'tags': ['technique', 'fist', 'counter'],
    'properties': {'damage': 7},
  },
  {
    'id': TechniqueIds.quickSlash,
    'type': 'technique',
    'name': 'Quick Slash',
    'tier': EvolutionTiers.intermediate,
    'tags': ['technique', 'blade', 'speed'],
    'properties': {'damage': 6, 'hits': 2},
  },
  {
    'id': TechniqueIds.heavySlash,
    'type': 'technique',
    'name': 'Heavy Slash',
    'tier': EvolutionTiers.intermediate,
    'tags': ['technique', 'blade', 'power'],
    'properties': {'damage': 15},
  },
  {
    'id': TechniqueIds.fastGuard,
    'type': 'technique',
    'name': 'Fast Guard',
    'tier': EvolutionTiers.intermediate,
    'tags': ['technique', 'guard', 'speed'],
    'properties': {'defense': 3},
  },
  {
    'id': TechniqueIds.counterGuard,
    'type': 'technique',
    'name': 'Counter Guard',
    'tier': EvolutionTiers.intermediate,
    'tags': ['technique', 'guard', 'counter'],
    'properties': {'defense': 5},
  },
];

/// Builds a [TechniqueDefinition] from a loaded [ContentDefinition].
/// `extra['name']`/`extra['tier']` supply the two fields `ContentRegistry`
/// doesn't natively parse; `definition.conditions` (native) supplies
/// [TechniqueDefinition.requirements] verbatim; `extra['evolution']`
/// supplies [TechniqueDefinition.evolutionCandidates]; `extra['properties']`
/// supplies properties + [TechniqueDefinition.modifiersFor], exactly
/// mirroring `itemDefinitionFromContent`.
TechniqueDefinition techniqueDefinitionFromContent(ContentDefinition definition) {
  final rawProperties =
      (definition.extra['properties'] as Map?) ?? const <String, dynamic>{};
  final properties = <String, num>{
    for (final entry in rawProperties.entries)
      entry.key as String: entry.value as num,
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

  List<Modifier> modifiersFor(EntityId owner) => [
        for (final entry in properties.entries)
          Modifier(
            source: ModifierSource(
                'technique:${definition.id}:${entry.key}:${owner.value}'),
            target: owner,
            stat: entry.key,
            operation: ModifierOperation.add,
            value: entry.value,
          ),
      ];

  return TechniqueDefinition(
    id: definition.id,
    name: definition.extra['name'] as String,
    tier: definition.extra['tier'] as String,
    tags: definition.tags,
    properties: properties,
    requirements: definition.conditions,
    evolutionCandidates: evolutionCandidates,
    modifiersFor: modifiersFor,
  );
}

/// Resolves and parses technique [id] from [context]'s loaded content —
/// the same convenience `itemDefinition`/`martialItem` already provide.
TechniqueDefinition techniqueDefinition(String id, PluginContext context) =>
    techniqueDefinitionFromContent(context.content.get(id));
