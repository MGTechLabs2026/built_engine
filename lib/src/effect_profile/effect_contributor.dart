import 'effect_profile.dart';

/// A component type that can declare tiered numeric effects. Implemented
/// directly by a plugin's own definition/instance type — the "implement
/// the interface, no registry" pattern already used by `Condition`,
/// `Effect`, `CombatAction`, `TrainingExercise`.
abstract interface class EffectContributor {
  /// This component's contributions. The implementer folds in whatever
  /// of its own domain state matters (item class/grade/affixes,
  /// technique axis profile, etc.). Core never sees that state, only the
  /// returned profile.
  EffectProfile effectProfile();
}
