/// One practice attempt's raw input/performance data — an opaque,
/// string-keyed bag of numeric measurements. The framework never
/// interprets [measurements]; only a concrete `TrainingExercise` knows
/// what keys to expect (e.g. a timing exercise's own
/// `inputTimestampMs`/`targetTimestampMs`).
class TrainingAttempt {
  const TrainingAttempt(this.measurements);

  final Map<String, double> measurements;
}
