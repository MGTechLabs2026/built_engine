import 'training_attempt.dart';
import 'training_profile.dart';

/// A pure evaluation strategy turning a trainee's practice attempts into a
/// [TrainingProfile]. Plugins implement this directly — no registry, the
/// same "implement directly" pattern `Condition`/`Effect`/`PlacementRule`/
/// `CombatAction` already use.
///
/// [evaluate] sees the *whole* attempt history, not one attempt at a time,
/// so each concrete exercise picks its own aggregation strategy (average,
/// best-of, recency-weighted, ...) — the framework prescribes none. Future
/// exercises (not implemented here — this is only the interface):
/// `TimingExercise`, `PrecisionExercise`, `ReactionExercise`,
/// `PowerExercise`, `ComboExercise`.
///
/// Must be a pure function of [attempts] — no randomness, no wall-clock,
/// no hidden state — so a [TrainingSession]'s result stays deterministic.
abstract class TrainingExercise {
  TrainingProfile evaluate(List<TrainingAttempt> attempts);
}
