import 'dart:math' as math;

/// Pure numeric helpers shared by every concrete `TrainingExercise` —
/// namespaced under one class (the same convention `ContentField` uses)
/// so the package's public surface doesn't gain generic top-level names
/// like `average`. Extracted once, rather than duplicated across
/// `TimingExercise`/`PrecisionExercise`/`ReactionExercise`/
/// `PowerExercise`/`ComboExercise`, all five of which need the same
/// "how consistent were these scores" computation.
class TrainingStatistics {
  const TrainingStatistics._();

  /// The arithmetic mean of [values]; `0.0` for an empty list.
  static double average(List<double> values) {
    if (values.isEmpty) return 0.0;
    return values.reduce((a, b) => a + b) / values.length;
  }

  /// The population standard deviation of [values]; `0.0` for fewer than
  /// 2 values (nothing to vary against).
  static double standardDeviation(List<double> values) {
    if (values.length < 2) return 0.0;
    final mean = average(values);
    final variance = average([for (final v in values) (v - mean) * (v - mean)]);
    return math.sqrt(variance);
  }
}
