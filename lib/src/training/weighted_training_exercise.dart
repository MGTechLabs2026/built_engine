import 'training_attempt.dart';
import 'training_exercise.dart';
import 'training_profile.dart';

/// Scales a wrapped exercise's output profile per-dimension by [weights]
/// — the generic primitive that lets "how much each dimension matters for
/// this particular subject" live in content, never hardcoded in the
/// Training Engine itself. A dimension with no entry in [weights] passes
/// through unscaled (multiplied by `1.0`). Just another `TrainingExercise`
/// — composes with any of the 5 concrete exercises, or a future one,
/// without either side knowing about the other.
class WeightedTrainingExercise implements TrainingExercise {
  const WeightedTrainingExercise(this.inner, this.weights);

  final TrainingExercise inner;
  final Map<String, double> weights;

  @override
  TrainingProfile evaluate(List<TrainingAttempt> attempts) {
    final raw = inner.evaluate(attempts);
    return TrainingProfile({
      for (final entry in raw.dimensions.entries)
        entry.key: entry.value * (weights[entry.key] ?? 1.0),
    });
  }
}
