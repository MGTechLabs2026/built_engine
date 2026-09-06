import 'package:build_engine/build_engine.dart';

import 'technique_definition.dart';

/// [TechniqueDefinition] + the [ContentRegistry] as one [AuraContributor]
/// — the exact analogue of `ItemAuraContributor`, reading `auraRuleIds`
/// off the base technique definition. `TechniqueVariant` keeps
/// implementing `EffectContributor` directly (no registry needed there),
/// but not `AuraContributor`: aura resolution needs the registry, so it
/// goes through this wrapper. See `AuraContributor`'s own doc comment.
///
/// The scope-resolution + [AuraRule] assembly is [auraRuleFromRegistry],
/// shared verbatim with `ItemAuraContributor` from pure Core — so this
/// file never imports the Item plugin.
class TechniqueAuraContributor implements AuraContributor {
  const TechniqueAuraContributor(this.definition, this.content);

  final TechniqueDefinition definition;
  final ContentRegistry content;

  @override
  List<AuraRule> auraRules() => [
        for (final id in definition.auraRuleIds)
          auraRuleFromRegistry(content, id),
      ];
}
