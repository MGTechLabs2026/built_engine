import 'package:build_engine/build_engine.dart';

/// Per-technique training-dimension weights — content data, not Training
/// Engine logic. Matches the milestone's own example: Basic Punch weights
/// speed/reaction (fast, reactive strikes) higher than power/precision.
const techniqueTrainingWeights = <String, Map<String, double>>{
  'basic_punch': {'speed': 0.3, 'power': 0.2, 'precision': 0.2, 'reaction': 0.3},
  'basic_slash': {'speed': 0.25, 'power': 0.35, 'precision': 0.25, 'reaction': 0.15},
  'basic_guard': {'reaction': 0.4, 'control': 0.3, 'consistency': 0.3},
};

/// Wraps [base] in a [WeightedTrainingExercise] using [techniqueId]'s
/// registered weights, if any — [base] unchanged if [techniqueId] has no
/// entry.
TrainingExercise techniqueTrainingExerciseFor(String techniqueId, TrainingExercise base) {
  final weights = techniqueTrainingWeights[techniqueId];
  return weights == null ? base : WeightedTrainingExercise(base, weights);
}
