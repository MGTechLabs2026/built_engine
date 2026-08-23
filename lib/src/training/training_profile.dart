/// Named constants for the framework's initial generic performance
/// dimensions — plain sports-science/performance-training vocabulary, not
/// martial-arts terminology. Purely a convenience to avoid magic strings;
/// [TrainingProfile.dimensions] is an open string-keyed map, not an enum —
/// any future exercise may introduce dimensions beyond these.
abstract final class TrainingDimensions {
  static const speed = 'speed';
  static const power = 'power';
  static const precision = 'precision';
  static const reaction = 'reaction';
  static const control = 'control';
  static const rhythm = 'rhythm';
  static const accuracy = 'accuracy';
  static const consistency = 'consistency';
}

/// The output of a [TrainingExercise] evaluating a trainee's attempts — a
/// set of generic performance-dimension scores (e.g. `speed: 0.82`). An
/// exercise may populate any subset of dimensions; this is deliberately
/// not a fixed set of fields, so the framework never hardcodes what a
/// specific exercise measures.
class TrainingProfile {
  const TrainingProfile(this.dimensions);

  final Map<String, double> dimensions;
}
