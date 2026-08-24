import 'training_attempt.dart';
import 'training_exercise.dart';
import 'training_profile.dart';
import 'training_statistics.dart';

/// A charge-and-release exercise: how much `'charge'` (0.0–1.0) was built
/// up and how close `'releaseTimestamp'` lands to
/// `'optimalReleaseTimestamp'` (within `'releaseWindow'`) — generic across
/// any "build up then release" mechanic (a martial haymaker, a magic
/// spell charge, an alchemy heat build-up).
///
/// `power`: average charge level reached.
/// `timing`: closeness of release to the optimal moment.
/// `control`: `1.0` minus how much `charge` varies attempt-to-attempt —
/// steady effort control, distinct from raw `power` output.
class PowerExercise implements TrainingExercise {
  const PowerExercise();

  @override
  TrainingProfile evaluate(List<TrainingAttempt> attempts) {
    if (attempts.isEmpty) return const TrainingProfile({});

    final charges = <double>[];
    final timingScores = <double>[];
    for (final attempt in attempts) {
      final charge = attempt.measurements['charge']!.clamp(0.0, 1.0);
      final release = attempt.measurements['releaseTimestamp']!;
      final optimal = attempt.measurements['optimalReleaseTimestamp']!;
      final window = attempt.measurements['releaseWindow']!;

      charges.add(charge);
      timingScores.add((1 - (release - optimal).abs() / window).clamp(0.0, 1.0));
    }

    return TrainingProfile({
      TrainingDimensions.power: TrainingStatistics.average(charges),
      TrainingDimensions.timing: TrainingStatistics.average(timingScores),
      TrainingDimensions.control:
          1 - TrainingStatistics.standardDeviation(charges).clamp(0.0, 1.0),
    });
  }
}
