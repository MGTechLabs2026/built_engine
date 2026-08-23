import '../entity/entity_id.dart';
import 'training_attempt.dart';
import 'training_exercise.dart';
import 'training_profile.dart';
import 'training_result.dart';

/// One trainee's interactive practice session against one [subject] using
/// one [exercise] — a plain, standalone object with no `ComponentStore`/
/// `EventBus`/`PluginContext` dependency at all, since a session is a
/// short-lived interaction, not persistent per-entity state. Fully
/// headless: construct it, submit attempts, read the result — nothing
/// else required, no UI, no game loop.
///
/// [subject] is an opaque string (e.g. `"technique:jab"`, `"item
/// :iron_sword"`), the same convention `MasteryTracker`/`ProgressionEngine`
/// /`DiscoveryTracker` already use — Training never interprets it, so it
/// works identically for any subject a plugin invents.
class TrainingSession {
  TrainingSession({required this.trainee, required this.subject, required this.exercise});

  final EntityId trainee;
  final String subject;
  final TrainingExercise exercise;
  final List<TrainingAttempt> _attempts = [];

  /// Every attempt submitted so far, in submission order.
  List<TrainingAttempt> get attempts => List.unmodifiable(_attempts);

  /// Records [attempt] as part of this session.
  void submitAttempt(TrainingAttempt attempt) => _attempts.add(attempt);

  /// Runs [exercise] over every attempt submitted so far. Calling this
  /// again after more attempts are submitted re-evaluates from scratch —
  /// [TrainingExercise.evaluate] is a pure function of the whole history,
  /// so this stays deterministic for a fixed attempt sequence.
  TrainingProfile calculateProfile() => exercise.evaluate(attempts);

  /// Finalizes this session into a [TrainingResult] — the only thing
  /// Training hands to anything else. Carries the profile plus enough
  /// context (trainee, subject, the full attempt history) for a separate
  /// evolution/learning system to interpret later; makes no interpretation
  /// itself.
  TrainingResult complete() => TrainingResult(
        trainee: trainee,
        subject: subject,
        profile: calculateProfile(),
        attempts: attempts,
      );
}
