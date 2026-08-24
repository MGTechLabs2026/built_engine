import 'dart:math' as math;

import 'training_attempt.dart';
import 'training_exercise.dart';
import 'training_profile.dart';
import 'training_statistics.dart';

/// A spatial-accuracy exercise: how close `('actionX','actionY')` lands
/// to `('targetX','targetY')`, within a `'tolerance'` radius — generic
/// across any "hit this spot" mechanic (a martial strike zone, an
/// alchemy pour target, a crafting tap point).
///
/// `accuracy`: average closeness to the target (`1.0` at dead center,
/// `0.0` at or beyond `tolerance`).
/// `precision`: how tightly attempts group together (low variance in
/// distance-from-target) — distinct from `accuracy`: a trainee can group
/// tightly (high precision) while consistently missing the true target
/// (low accuracy), or vice versa.
/// `control`: the fraction of attempts that landed within `tolerance` at
/// all (a hit-rate, distinct from the continuous `accuracy` score).
class PrecisionExercise implements TrainingExercise {
  const PrecisionExercise();

  @override
  TrainingProfile evaluate(List<TrainingAttempt> attempts) {
    if (attempts.isEmpty) return const TrainingProfile({});

    final distances = <double>[];
    final accuracyScores = <double>[];
    final hits = <double>[];
    for (final attempt in attempts) {
      final dx = attempt.measurements['actionX']! - attempt.measurements['targetX']!;
      final dy = attempt.measurements['actionY']! - attempt.measurements['targetY']!;
      final distance = math.sqrt(dx * dx + dy * dy);
      final tolerance = attempt.measurements['tolerance']!;

      distances.add(distance);
      accuracyScores.add((1 - distance / tolerance).clamp(0.0, 1.0));
      hits.add(distance <= tolerance ? 1.0 : 0.0);
    }
    final tolerance = attempts.first.measurements['tolerance']!;

    return TrainingProfile({
      TrainingDimensions.accuracy: TrainingStatistics.average(accuracyScores),
      TrainingDimensions.precision:
          1 - (TrainingStatistics.standardDeviation(distances) / tolerance).clamp(0.0, 1.0),
      TrainingDimensions.control: TrainingStatistics.average(hits),
    });
  }
}
