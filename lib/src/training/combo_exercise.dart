import 'training_attempt.dart';
import 'training_exercise.dart';
import 'training_profile.dart';
import 'training_statistics.dart';

/// A sequence exercise: how many of `length` numerically-coded steps
/// (`'expected_0'`/`'actual_0'`, `'expected_1'`/`'actual_1'`, ...) matched,
/// and how closely `'actualDurationMs'` matched `'expectedDurationMs'` —
/// generic across any "perform this sequence" mechanic (a martial combo,
/// a magic incantation sequence, an alchemy step order, a crafting
/// recipe sequence). Step codes are opaque numbers the caller assigns;
/// this exercise never interprets what a code means.
///
/// `accuracy`: fraction of steps that matched, per attempt, averaged.
/// `rhythm`: how closely the whole sequence's overall pacing matched the
/// expected duration.
/// `consistency`: `1.0` minus how much per-attempt `accuracy` varies.
/// `execution`: `accuracy * rhythm` per attempt, averaged — a holistic
/// "how clean was the whole performance" signal distinct from either
/// factor alone.
class ComboExercise implements TrainingExercise {
  const ComboExercise();

  @override
  TrainingProfile evaluate(List<TrainingAttempt> attempts) {
    if (attempts.isEmpty) return const TrainingProfile({});

    final accuracyScores = <double>[];
    final rhythmScores = <double>[];
    final executionScores = <double>[];
    for (final attempt in attempts) {
      final length = attempt.measurements['length']!.round();
      var matches = 0;
      for (var i = 0; i < length; i++) {
        if (attempt.measurements['expected_$i'] == attempt.measurements['actual_$i']) {
          matches++;
        }
      }
      final accuracy = length == 0 ? 0.0 : matches / length;

      final expectedDuration = attempt.measurements['expectedDurationMs']!;
      final actualDuration = attempt.measurements['actualDurationMs']!;
      final rhythm =
          (1 - (actualDuration - expectedDuration).abs() / expectedDuration).clamp(0.0, 1.0);

      accuracyScores.add(accuracy);
      rhythmScores.add(rhythm);
      executionScores.add(accuracy * rhythm);
    }

    return TrainingProfile({
      TrainingDimensions.accuracy: TrainingStatistics.average(accuracyScores),
      TrainingDimensions.rhythm: TrainingStatistics.average(rhythmScores),
      TrainingDimensions.consistency:
          1 - TrainingStatistics.standardDeviation(accuracyScores).clamp(0.0, 1.0),
      TrainingDimensions.execution: TrainingStatistics.average(executionScores),
    });
  }
}
