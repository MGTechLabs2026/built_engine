import 'package:build_engine/build_engine.dart';

/// Per-item training-dimension weights — content data, not Training
/// Engine logic.
const itemTrainingWeights = <String, Map<String, double>>{
  'knife': {'speed': 0.4, 'precision': 0.4, 'control': 0.2},
  'iron_sword': {'power': 0.4, 'precision': 0.3, 'control': 0.3},
  'gloves': {'speed': 0.35, 'reaction': 0.35, 'power': 0.3},
};

/// Wraps [base] in a [WeightedTrainingExercise] using [itemId]'s
/// registered weights, if any — [base] unchanged if [itemId] has no entry.
TrainingExercise itemTrainingExerciseFor(String itemId, TrainingExercise base) {
  final weights = itemTrainingWeights[itemId];
  return weights == null ? base : WeightedTrainingExercise(base, weights);
}
