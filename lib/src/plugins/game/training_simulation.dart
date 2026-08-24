import 'package:build_engine/build_engine.dart';

/// Synthesizes [count] `TrainingAttempt`s for the real `TimingExercise` —
/// the game layer's stand-in for a real player's actual input (no UI
/// exists yet). Attempt quality varies via `rng.nextDouble()` — never
/// `dart:math` directly — so a run's training outcomes (and therefore
/// mastery/learning/evolution) depend on the seed, exactly as the
/// milestone requires ("the seed determines randomness").
List<TrainingAttempt> generateTrainingAttempts(RngService rng, {int count = 3}) => [
      for (var i = 0; i < count; i++)
        TrainingAttempt({
          'windowStart': 100,
          'windowEnd': 200,
          'actual': 100 + rng.nextDouble() * 100,
        }),
    ];

/// Turns a `TrainingResult.profile` into a single experience/mastery gain
/// amount — the average of every scored dimension, scaled up to a
/// magnitude that meaningfully crosses the Item/Technique plugins'
/// registered thresholds (`[8, 25]`-ish). Reuses the existing
/// `TrainingStatistics.average` rather than re-deriving a mean.
num trainingGain(TrainingProfile profile) {
  if (profile.dimensions.isEmpty) return 0;
  return TrainingStatistics.average(profile.dimensions.values.toList()) * 20;
}

/// A deterministic Fisher-Yates shuffle driven by [rng] — never
/// `dart:math`'s own `List.shuffle` (which reaches for `dart:math`'s
/// `Random` internally), so the reward pool's order stays reproducible
/// from the run's own seed.
List<T> seededShuffle<T>(List<T> items, RngService rng) {
  final result = List<T>.of(items);
  for (var i = result.length - 1; i > 0; i--) {
    final j = rng.nextInt(i + 1);
    final swap = result[i];
    result[i] = result[j];
    result[j] = swap;
  }
  return result;
}
