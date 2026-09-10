import 'package:build_engine/build_engine.dart';

import 'affix_mechanic.dart';
import 'affix_types.dart';

/// An affix's immutable, content-derived shape. Built from a loaded
/// `ContentDefinition` of `type: 'affix'` via [affixDefinitionFromContent]
/// — never hand-written. `id` is an opaque `af_*` token; `label` is the
/// only display string and is deterministic from the definition.
class AffixDefinition {
  const AffixDefinition({
    required this.id,
    required this.label,
    required this.category,
    required this.lean,
    required this.mechanic,
  });

  final String id;
  final String label;
  final String category;
  final AffixLean lean;
  final AffixMechanic mechanic;
}

AffixLean _leanFromTags(Set<String> tags) {
  final leanTags = tags.where((t) => t.startsWith('lean:')).toList();
  if (leanTags.isEmpty) {
    throw ContentFieldException('tags', 'missing a lean:* tag');
  }
  if (leanTags.length > 1) {
    throw ContentFieldException('tags', 'multiple lean:* tags');
  }
  return switch (leanTags.single.substring(5)) {
    'neutral' => AffixLean.neutral,
    'force' => AffixLean.force,
    'flow' => AffixLean.flow,
    _ => throw ContentFieldException('tags', 'unknown lean tag: ${leanTags.single}'),
  };
}

AffixDefinition affixDefinitionFromContent(ContentDefinition d) {
  final label = d.extra['label'];
  if (label is! String || label.isEmpty) {
    throw ContentFieldException('label', 'required non-empty string field missing');
  }
  final category = d.extra['category'];
  if (category is! String || !AffixCategories.all.contains(category)) {
    throw ContentFieldException('category', 'must be one of ${AffixCategories.all}');
  }
  final mechanicRaw = d.extra['mechanic'];
  if (mechanicRaw is! Map) {
    throw ContentFieldException('mechanic', 'required object field missing');
  }
  final mechanic = AffixMechanic.fromJson(
    mechanicRaw.map((k, v) => MapEntry(k as String, v)),
  );
  return AffixDefinition(
    id: d.id,
    label: label,
    category: category,
    lean: _leanFromTags(d.tags),
    mechanic: mechanic,
  );
}

/// Resolves and parses affix [id] from [context]'s loaded content in one
/// call — mirrors `itemDefinition` / `consumableDefinition`.
AffixDefinition affixDefinition(String id, PluginContext context) =>
    affixDefinitionFromContent(context.content.get(id));
