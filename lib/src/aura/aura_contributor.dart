import 'aura_rule.dart';

/// A component type that can declare rules which are live only while the
/// component is in `ResolvedBuild.active`. The "implement the interface,
/// no registry" pattern `EffectContributor` / `Condition` / `Effect` /
/// `CombatAction` already use.
///
/// Parameterless, mirroring `EffectContributor.effectProfile()`. Owner /
/// opponent identity is injected later by `AuraBinder._wire`, so every
/// [Rule] returned here stays identity-free and serializable.
///
/// **Implemented by a composing wrapper** (`ItemAuraContributor`,
/// `TechniqueAuraContributor`) that holds a `ContentRegistry` — NOT by
/// `ItemDefinition` / `TechniqueVariant` themselves. Resolving a
/// component's `auras` id list into `RuleDefinition`s needs the registry,
/// and a Core-adjacent value object must not take a `ContentRegistry`
/// dependency. Contrast `EffectContributor`: pure value calculation over
/// component state, so it can live on the state object. Do not
/// "simplify" this asymmetry away.
abstract interface class AuraContributor {
  List<AuraRule> auraRules();
}
