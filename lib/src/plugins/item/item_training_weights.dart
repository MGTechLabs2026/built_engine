import 'package:build_engine/build_engine.dart';

import 'item_definition.dart';

/// Wraps [base] in a [WeightedTrainingExercise] using [item]'s own
/// content-defined [ItemDefinition.trainingWeights], if any — [base]
/// unchanged if [item] has none. Reads content data
/// (`item_content.dart`'s `'training'` field) rather than a hand-written
/// Dart constant — see `ARCHITECTURE_AUDIT.md`'s category-7 finding, now
/// fixed.
TrainingExercise itemTrainingExerciseFor(ItemDefinition item, TrainingExercise base) =>
    item.trainingWeights.isEmpty ? base : WeightedTrainingExercise(base, item.trainingWeights);
