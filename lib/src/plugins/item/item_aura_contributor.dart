import 'package:build_engine/build_engine.dart';

import 'item_definition.dart';

/// [ItemDefinition] + the [ContentRegistry] as one [AuraContributor].
/// Resolving `definition.auraRuleIds` into `RuleDefinition`s needs the
/// registry, so the interface is implemented by this thin wrapper, never
/// by `ItemDefinition` (a Core-adjacent value object that must not take a
/// `ContentRegistry` dependency). Mirrors why `ItemEffectContributor`
/// wraps rather than extends — except `EffectContributor` is pure value
/// calculation over item state and needs no registry, whereas this is an
/// id lookup and does. Do not "simplify" the two into one shape.
///
/// The scope-resolution + [AuraRule] assembly is [auraRuleFromRegistry],
/// shared verbatim with `TechniqueAuraContributor` from pure Core.
class ItemAuraContributor implements AuraContributor {
  const ItemAuraContributor(this.definition, this.content);

  final ItemDefinition definition;
  final ContentRegistry content;

  @override
  List<AuraRule> auraRules() => [
        for (final id in definition.auraRuleIds)
          auraRuleFromRegistry(content, id),
      ];
}
