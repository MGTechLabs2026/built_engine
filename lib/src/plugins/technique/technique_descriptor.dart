import 'package:build_engine/build_engine.dart';

/// A thematic modifier a technique variant can carry. Content data,
/// loaded via `ContentRegistry` like `TechniqueDefinition` already is.
/// [axes] maps one or more axis keys (the open string set in
/// `technique_descriptor_content.dart` — `power` / `speed` / `endurance`
/// / `precision` at launch) to signed magnitudes: one `bear` can be
/// `{power: 6, speed: -1}` (rule 1). [tags] are free thematic tags for
/// SP0b matching.
class TechniqueDescriptor {
  const TechniqueDescriptor({
    required this.id,
    required this.axes,
    this.tags = const {},
  });

  final String id;
  final Map<String, num> axes;
  final Set<String> tags;
}

/// Thrown by [techniqueDescriptor] when no loaded content with [id] is a
/// descriptor (no `axes` field).
class UnknownTechniqueDescriptorException implements Exception {
  const UnknownTechniqueDescriptorException(this.id);
  final String id;
  @override
  String toString() => 'Unknown technique descriptor: $id';
}

/// Builds a [TechniqueDescriptor] from an already-parsed [ContentDefinition]
/// — mirrors `techniqueDefinitionFromContent`.
TechniqueDescriptor techniqueDescriptorFromContent(ContentDefinition definition) {
  final rawAxes = definition.extra['axes'] as Map;
  return TechniqueDescriptor(
    id: definition.id,
    axes: {
      for (final entry in rawAxes.entries)
        entry.key as String: entry.value as num,
    },
    tags: definition.tags,
  );
}

/// Resolves descriptor [id] from [context]'s loaded content — the same
/// convenience `techniqueDefinition` provides. Throws
/// [UnknownTechniqueDescriptorException] if [id] is absent or not a
/// descriptor.
TechniqueDescriptor techniqueDescriptor(String id, PluginContext context) {
  final definition = context.content.find(id);
  if (definition == null || definition.extra['axes'] == null) {
    throw UnknownTechniqueDescriptorException(id);
  }
  return techniqueDescriptorFromContent(definition);
}
