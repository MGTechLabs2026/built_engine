import 'training_attempt.dart';
import 'training_exercise.dart';
import 'training_profile.dart';
import 'training_statistics.dart';

/// A timing-window exercise: how close [TrainingAttempt.measurements]'
/// `'actual'` timestamp lands to the `'windowStart'`..`'windowEnd'`
/// window. Generic across any domain that has "act within this window"
/// mechanics (a martial parry window, a magic incantation window, an
/// alchemy stir-timing window, ...) — nothing here is martial-specific.
///
/// `timing`: closeness to the window's center (`1.0` at dead-center,
/// clamped to `0.0` at or beyond either edge).
/// `reaction`: rewards acting at or before center fully (`1.0`); only
/// decays for lateness past center — "don't be late" rather than
/// "hit the exact middle," a deliberately different signal from `timing`.
/// `consistency`: `1.0` minus how much `timing` varies attempt-to-attempt.
class TimingExercise implements TrainingExercise {
  const TimingExercise();

  @override
  TrainingProfile evaluate(List<TrainingAttempt> attempts) {
    if (attempts.isEmpty) return const TrainingProfile({});

    final qualities = <double>[];
    final reactions = <double>[];
    for (final attempt in attempts) {
      final start = attempt.measurements['windowStart']!;
      final end = attempt.measurements['windowEnd']!;
      final actual = attempt.measurements['actual']!;
      final center = (start + end) / 2;
      final halfWidth = (end - start) / 2;

      qualities.add((1 - (actual - center).abs() / halfWidth).clamp(0.0, 1.0));
      reactions.add(actual <= center
          ? 1.0
          : (1 - (actual - center) / halfWidth).clamp(0.0, 1.0));
    }

    return TrainingProfile({
      TrainingDimensions.timing: TrainingStatistics.average(qualities),
      TrainingDimensions.reaction: TrainingStatistics.average(reactions),
      TrainingDimensions.consistency:
          1 - TrainingStatistics.standardDeviation(qualities).clamp(0.0, 1.0),
    });
  }
}
