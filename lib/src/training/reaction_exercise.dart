import 'training_attempt.dart';
import 'training_exercise.dart';
import 'training_profile.dart';
import 'training_statistics.dart';

/// A stimulus-response exercise: how quickly `'responseTimestamp'` follows
/// `'signalTimestamp'`, relative to `'maxAcceptable'` — generic across any
/// "react to this cue" mechanic (a martial counter window, a magic
/// interrupt, a crafting quality-time cue).
///
/// `reaction`: response speed relative to the attempt's own
/// `'maxAcceptable'` threshold (task-specific).
/// `speed`: response speed on a fixed 1000-unit absolute scale — a
/// task-independent raw-reflexes signal, deliberately different from
/// `reaction`'s task-relative one.
/// `consistency`: `1.0` minus how much `reaction` varies attempt-to-attempt.
class ReactionExercise implements TrainingExercise {
  const ReactionExercise();

  @override
  TrainingProfile evaluate(List<TrainingAttempt> attempts) {
    if (attempts.isEmpty) return const TrainingProfile({});

    final reactionScores = <double>[];
    final speedScores = <double>[];
    for (final attempt in attempts) {
      final responseTime = attempt.measurements['responseTimestamp']! -
          attempt.measurements['signalTimestamp']!;
      final maxAcceptable = attempt.measurements['maxAcceptable']!;

      reactionScores.add((1 - responseTime / maxAcceptable).clamp(0.0, 1.0));
      speedScores.add((1 - responseTime / 1000).clamp(0.0, 1.0));
    }

    return TrainingProfile({
      TrainingDimensions.reaction: TrainingStatistics.average(reactionScores),
      TrainingDimensions.speed: TrainingStatistics.average(speedScores),
      TrainingDimensions.consistency:
          1 - TrainingStatistics.standardDeviation(reactionScores).clamp(0.0, 1.0),
    });
  }
}
