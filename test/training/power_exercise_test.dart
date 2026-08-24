import 'package:build_engine/build_engine.dart';
import 'package:test/test.dart';

void main() {
  const exercise = PowerExercise();

  test('empty attempts yield an empty profile', () {
    expect(exercise.evaluate(const []).dimensions, isEmpty);
  });

  test('full charge released exactly on time scores perfect power and timing', () {
    final profile = exercise.evaluate([
      const TrainingAttempt({
        'charge': 1.0,
        'releaseTimestamp': 1000,
        'optimalReleaseTimestamp': 1000,
        'releaseWindow': 200,
      }),
    ]);

    expect(profile.dimensions[TrainingDimensions.power], equals(1.0));
    expect(profile.dimensions[TrainingDimensions.timing], equals(1.0));
  });

  test('no charge released far off-time scores near-zero power and timing', () {
    final profile = exercise.evaluate([
      const TrainingAttempt({
        'charge': 0.0,
        'releaseTimestamp': 2000,
        'optimalReleaseTimestamp': 1000,
        'releaseWindow': 200,
      }),
    ]);

    expect(profile.dimensions[TrainingDimensions.power], equals(0.0));
    expect(profile.dimensions[TrainingDimensions.timing], equals(0.0));
  });

  test('steady charge levels score higher control than erratic ones', () {
    final steady = exercise.evaluate([
      const TrainingAttempt(
          {'charge': 0.8, 'releaseTimestamp': 1000, 'optimalReleaseTimestamp': 1000, 'releaseWindow': 200}),
      const TrainingAttempt(
          {'charge': 0.8, 'releaseTimestamp': 1000, 'optimalReleaseTimestamp': 1000, 'releaseWindow': 200}),
    ]);
    final erratic = exercise.evaluate([
      const TrainingAttempt(
          {'charge': 0.2, 'releaseTimestamp': 1000, 'optimalReleaseTimestamp': 1000, 'releaseWindow': 200}),
      const TrainingAttempt(
          {'charge': 1.0, 'releaseTimestamp': 1000, 'optimalReleaseTimestamp': 1000, 'releaseWindow': 200}),
    ]);

    expect(
      erratic.dimensions[TrainingDimensions.control]!,
      lessThan(steady.dimensions[TrainingDimensions.control]!),
    );
  });

  test('deterministic: the same attempts always produce the same profile', () {
    final attempts = [
      const TrainingAttempt(
          {'charge': 0.6, 'releaseTimestamp': 1050, 'optimalReleaseTimestamp': 1000, 'releaseWindow': 200}),
    ];

    expect(exercise.evaluate(attempts).dimensions, equals(exercise.evaluate(attempts).dimensions));
  });
}
