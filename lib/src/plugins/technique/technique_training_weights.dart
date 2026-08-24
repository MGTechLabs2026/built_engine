import 'package:build_engine/build_engine.dart';

import 'technique_definition.dart';

/// Wraps [base] in a [WeightedTrainingExercise] using [technique]'s own
/// content-defined [TechniqueDefinition.trainingWeights], if any — [base]
/// unchanged if [technique] has none. Reads content data
/// (`technique_content.dart`'s `'training'` field) rather than a
/// hand-written Dart constant — see `ARCHITECTURE_AUDIT.md`'s category-7
/// finding, now fixed.
TrainingExercise techniqueTrainingExerciseFor(
  TechniqueDefinition technique,
  TrainingExercise base,
) =>
    technique.trainingWeights.isEmpty
        ? base
        : WeightedTrainingExercise(base, technique.trainingWeights);
