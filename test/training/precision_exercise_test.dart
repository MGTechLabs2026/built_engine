import 'package:build_engine/build_engine.dart';
import 'package:test/test.dart';

void main() {
  const exercise = PrecisionExercise();

  test('empty attempts yield an empty profile', () {
    expect(exercise.evaluate(const []).dimensions, isEmpty);
  });

  test('a dead-center hit scores perfect accuracy and control', () {
    final profile = exercise.evaluate([
      const TrainingAttempt({'targetX': 0, 'targetY': 0, 'actionX': 0, 'actionY': 0, 'tolerance': 10}),
    ]);

    expect(profile.dimensions[TrainingDimensions.accuracy], equals(1.0));
    expect(profile.dimensions[TrainingDimensions.control], equals(1.0));
  });

  test('a miss far outside tolerance scores near-zero accuracy and control', () {
    final profile = exercise.evaluate([
      const TrainingAttempt({'targetX': 0, 'targetY': 0, 'actionX': 100, 'actionY': 0, 'tolerance': 10}),
    ]);

    expect(profile.dimensions[TrainingDimensions.accuracy], equals(0.0));
    expect(profile.dimensions[TrainingDimensions.control], equals(0.0));
  });

  test('identically-repeated misses still score perfect precision (tight grouping)', () {
    final attempt = const TrainingAttempt(
        {'targetX': 0, 'targetY': 0, 'actionX': 5, 'actionY': 0, 'tolerance': 10});
    final profile = exercise.evaluate([attempt, attempt]);

    expect(profile.dimensions[TrainingDimensions.precision], equals(1.0));
  });

  test('scattered distances score lower precision than tight ones', () {
    final tight = exercise.evaluate([
      const TrainingAttempt({'targetX': 0, 'targetY': 0, 'actionX': 5, 'actionY': 0, 'tolerance': 10}),
      const TrainingAttempt({'targetX': 0, 'targetY': 0, 'actionX': 5, 'actionY': 0, 'tolerance': 10}),
    ]);
    final scattered = exercise.evaluate([
      const TrainingAttempt({'targetX': 0, 'targetY': 0, 'actionX': 0, 'actionY': 0, 'tolerance': 10}),
      const TrainingAttempt({'targetX': 0, 'targetY': 0, 'actionX': 9, 'actionY': 0, 'tolerance': 10}),
    ]);

    expect(
      scattered.dimensions[TrainingDimensions.precision]!,
      lessThan(tight.dimensions[TrainingDimensions.precision]!),
    );
  });

  test('deterministic: the same attempts always produce the same profile', () {
    final attempts = [
      const TrainingAttempt({'targetX': 0, 'targetY': 0, 'actionX': 3, 'actionY': 4, 'tolerance': 10}),
    ];

    expect(exercise.evaluate(attempts).dimensions, equals(exercise.evaluate(attempts).dimensions));
  });
}
