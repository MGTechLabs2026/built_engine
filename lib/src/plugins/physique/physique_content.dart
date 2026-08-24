import 'package:build_engine/build_engine.dart';

import 'physique_types.dart';

/// The four physique definitions this plugin implements, as data —
/// loaded into `PluginContext.content` via `PluginSdk.registerContentBatch`
/// in `PhysiquePlugin.initialize`, mirroring MartialArts'
/// `martialTechniqueContentDefinitions` and Elemental's
/// `elementalContentDefinitions`.
///
/// `affinities`/`modifiers` are Physique-specific fields `ContentRegistry`
/// doesn't recognize — they surface verbatim on `ContentDefinition.extra`,
/// exactly like `martial_technique_content.dart`'s `baseDamage`/
/// `damageStat`. `modifiers` isn't part of `ContentRegistry`'s vocabulary
/// at all (`Modifier` isn't an `Effect`/`Condition`) —
/// `physiqueDefinitionFromContent` below turns this raw shape into real
/// `Modifier`-producing closures, the same way `martialTechniqueFromDefinition`
/// turns its own `extra` fields into a real `MartialTechniqueAction`.
///
/// Each `modifiers` entry's `condition` is a bare tag name — `'western'`/
/// `'eastern'`, the generic tags MartialArts grants a character via
/// `learnStyle`. Physique never imports MartialArts to know this; it
/// only agrees on the tag *names*.
const physiqueContentDefinitions = <Map<String, dynamic>>[
  {
    'id': 'sturdy',
    'type': 'physique',
    'tags': ['physique', 'defense', 'western_affinity'],
    'affinities': ['defense'],
    'modifiers': [
      {
        'stat': 'defense',
        'operation': 'multiply',
        'value': 1.25,
        'condition': PhysiqueTraditions.western,
      },
      {
        'stat': 'defense',
        'operation': 'multiply',
        'value': 0.85,
        'condition': PhysiqueTraditions.eastern,
      },
    ],
  },
  {
    'id': 'power',
    'type': 'physique',
    'tags': ['physique', 'strength', 'western_affinity'],
    'affinities': ['strength'],
    'modifiers': [
      {
        'stat': 'strength',
        'operation': 'multiply',
        'value': 1.25,
        'condition': PhysiqueTraditions.western,
      },
      {
        'stat': 'strength',
        'operation': 'multiply',
        'value': 0.85,
        'condition': PhysiqueTraditions.eastern,
      },
    ],
  },
  {
    'id': 'burst',
    'type': 'physique',
    'tags': ['physique', 'speed', 'eastern_affinity'],
    'affinities': ['speed'],
    'modifiers': [
      {
        'stat': 'speed',
        'operation': 'multiply',
        'value': 1.25,
        'condition': PhysiqueTraditions.eastern,
      },
      {
        'stat': 'speed',
        'operation': 'multiply',
        'value': 0.85,
        'condition': PhysiqueTraditions.western,
      },
    ],
  },
  {
    'id': 'endurance',
    'type': 'physique',
    'tags': ['physique', 'stamina', 'eastern_affinity'],
    'affinities': ['stamina'],
    'modifiers': [
      {
        'stat': 'stamina',
        'operation': 'multiply',
        'value': 1.25,
        'condition': PhysiqueTraditions.eastern,
      },
      {
        'stat': 'stamina',
        'operation': 'multiply',
        'value': 0.85,
        'condition': PhysiqueTraditions.western,
      },
    ],
  },
];

/// A parsed, runtime-usable physique — [modifiersFor] builds this
/// physique's synergy `Modifier`s for a specific character, read from
/// [physiqueContentDefinitions] via [physiqueDefinitionFromContent].
class PhysiqueDefinition {
  const PhysiqueDefinition({
    required this.id,
    required this.tags,
    required this.primaryAffinity,
    required this.modifiersFor,
  });

  final String id;
  final Set<String> tags;

  /// The stat name this physique's synergy modifiers target —
  /// `'defense'`/`'strength'`/`'speed'`/`'stamina'`, an arbitrary,
  /// caller-chosen string like every other stat name in this engine
  /// (the same convention `damageStat` already follows). Not read by
  /// Core or Combat; whatever future content resolves this stat name
  /// benefits from the synergy for free.
  final String primaryAffinity;

  final List<Modifier> Function(EntityId character) modifiersFor;
}

/// Builds a [PhysiqueDefinition] from a loaded [ContentDefinition].
/// `extra['affinities']` (a one-element list today; the field stays a
/// list for a physique that later needs more than one) supplies
/// [PhysiqueDefinition.primaryAffinity]; `extra['modifiers']` supplies
/// [PhysiqueDefinition.modifiersFor] — each raw entry becomes exactly
/// one conditional `Modifier`, gated on a bare tag name via
/// `HasTagQuery`. No explicit "neutral ×1.00" modifier is registered
/// for either tradition tag — an entity with neither tag simply has no
/// active modifier for this stat, and `ModifierResolver` already treats
/// an empty modifier set as the identity (base value unchanged), which
/// *is* "neutral".
PhysiqueDefinition physiqueDefinitionFromContent(
    ContentDefinition definition) {
  final affinities =
      (definition.extra['affinities'] as List).map((e) => e as String).toList();
  final rawModifiers = (definition.extra['modifiers'] as List)
      .map((e) => (e as Map).map((k, v) => MapEntry(k as String, v)))
      .toList();

  List<Modifier> modifiersFor(EntityId character) => modifiersFromRawList(
        domain: 'physique',
        contentId: definition.id,
        rawModifiers: rawModifiers,
        target: character,
      );

  return PhysiqueDefinition(
    id: definition.id,
    tags: definition.tags,
    primaryAffinity: affinities.first,
    modifiersFor: modifiersFor,
  );
}
