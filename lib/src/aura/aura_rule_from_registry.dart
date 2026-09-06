import '../content/content_registry.dart';
import 'aura_rule.dart';
import 'aura_scope.dart';

/// Looks up [id] in [content], reads its optional `scope` key
/// (`null` or `"self"` → [AuraScope.self]; `"opponent"` →
/// [AuraScope.opponent]; anything else → [ArgumentError]), and pairs the
/// loaded Core `Rule` with it as one [AuraRule] tagged with
/// `sourceRuleId: id`. `content.rule(id)` throws
/// `ContentNotFoundException` for an unknown id — that propagates.
///
/// Shared by `ItemAuraContributor` and `TechniqueAuraContributor`. It
/// lives here, in pure Core, because it touches only [ContentRegistry]
/// and the aura value types — putting it in either plugin would force an
/// Item↔Technique import the architecture guard rejects.
///
/// The asymmetry vs `EffectContributor` is deliberate: `effectProfile()`
/// is pure value calculation over component state and needs no registry,
/// so it lives on the state object; aura resolution is an id lookup and
/// *does* need the registry, so it goes through a composing wrapper that
/// holds one. Do not "simplify" by injecting a `ContentRegistry` into
/// `ItemDefinition` / `TechniqueDefinition` / `TechniqueVariant` — those
/// are Core-adjacent value objects that must stay registry-free.
AuraRule auraRuleFromRegistry(ContentRegistry content, String id) {
  final definition = content.rule(id); // throws ContentNotFoundException if absent
  final rawScope = definition.raw['scope'];
  final AuraScope scope;
  switch (rawScope) {
    case null:
    case 'self':
      scope = AuraScope.self;
    case 'opponent':
      scope = AuraScope.opponent;
    default:
      throw ArgumentError.value(
          rawScope, 'scope', 'aura rule "$id": scope must be "self" or "opponent"');
  }
  return AuraRule(rule: definition.rule, scope: scope, sourceRuleId: id);
}
