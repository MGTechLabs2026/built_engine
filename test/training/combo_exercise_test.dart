import 'package:build_engine/build_engine.dart';
import 'package:test/test.dart';

void main() {
  const exercise = ComboExercise();

  const perfectAttempt = TrainingAttempt({
    'length': 3,
    'expected_0': 1, 'actual_0': 1,
    'expected_1': 2, 'actual_1': 2,
    'expected_2': 3, 'actual_2': 3,
    'expectedDurationMs': 900,
    'actualDurationMs': 900,
  });

  const poorAttempt = TrainingAttempt({
    'length': 3,
    'expected_0': 1, 'actual_0': 9,
    'expected_1': 2, 'actual_1': 9,
    'expected_2': 3, 'actual_2': 9,
    'expectedDurationMs': 900,
    'actualDurationMs': 2700,
  });

  test('empty attempts yield an empty profile', () {
    expect(exercise.evaluate(const []).dimensions, isEmpty);
  });

  test('a perfectly matched, on-tempo sequence scores perfect accuracy/rhythm/execution', () {
    final profile = exercise.evaluate([perfectAttempt]);

    expect(profile.dimensions[TrainingDimensions.accuracy], equals(1.0));
    expect(profile.dimensions[TrainingDimensions.rhythm], equals(1.0));
    expect(profile.dimensions[TrainingDimensions.execution], equals(1.0));
  });

  test('a fully mismatched, off-tempo sequence scores near-zero accuracy/rhythm/execution', () {
    final profile = exercise.evaluate([poorAttempt]);

    expect(profile.dimensions[TrainingDimensions.accuracy], equals(0.0));
    expect(profile.dimensions[TrainingDimensions.rhythm], equals(0.0));
    expect(profile.dimensions[TrainingDimensions.execution], equals(0.0));
  });

  test('repeated perfect attempts score higher consistency than mixed ones', () {
    final steady = exercise.evaluate([perfectAttempt, perfectAttempt]);
    final mixed = exercise.evaluate([perfectAttempt, poorAttempt]);

    expect(
      mixed.dimensions[TrainingDimensions.consistency]!,
      lessThan(steady.dimensions[TrainingDimensions.consistency]!),
    );
  });

  test('deterministic: the same attempts always produce the same profile', () {
    expect(
      exercise.evaluate([perfectAttempt, poorAttempt]).dimensions,
      equals(exercise.evaluate([perfectAttempt, poorAttempt]).dimensions),
    );
  });
}
