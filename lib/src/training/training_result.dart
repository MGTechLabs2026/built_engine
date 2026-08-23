import '../entity/entity_id.dart';
import 'training_attempt.dart';
import 'training_profile.dart';

/// A finalized snapshot of one [TrainingSession] — pure data, no decision
/// logic. Training itself never decides anything like "trainee learned
/// Jab"; a separate, not-yet-built evolution/learning system reads a
/// [TrainingResult] to make that call. This type's entire public surface
/// is [trainee]/[subject]/[profile]/[attempts] — nothing resembling a
/// pass/fail or "learned" verdict exists on it.
class TrainingResult {
  const TrainingResult({
    required this.trainee,
    required this.subject,
    required this.profile,
    required this.attempts,
  });

  final EntityId trainee;
  final String subject;
  final TrainingProfile profile;
  final List<TrainingAttempt> attempts;
}
