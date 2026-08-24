import 'package:build_engine/build_engine.dart';
import 'package:test/test.dart';

void main() {
  const exercise = TimingExercise();

  test('empty attempts yield an empty profile', () {
    expect(exercise.evaluate(const []).dimensions, isEmpty);
  });

  test('a dead-center hit scores perfect timing and reaction', () {
    final profile = exercise.evaluate([
      const TrainingAttempt({'windowStart': 100, 'windowEnd': 200, 'actual': 150}),
    ]);

    expect(profile.dimensions[TrainingDimensions.timing], equals(1.0));
    expect(profile.dimensions[TrainingDimensions.reaction], equals(1.0));
  });

  test('a hit far outside the window scores near zero', () {
    final profile = exercise.evaluate([
      const TrainingAttempt({'windowStart': 100, 'windowEnd': 200, 'actual': 400}),
    ]);

    expect(profile.dimensions[TrainingDimensions.timing], equals(0.0));
    expect(profile.dimensions[TrainingDimensions.reaction], equals(0.0));
  });

  test('consistent center hits score high consistency', () {
    final attempt = const TrainingAttempt({'windowStart': 100, 'windowEnd': 200, 'actual': 150});
    final profile = exercise.evaluate([attempt, attempt, attempt]);

    expect(profile.dimensions[TrainingDimensions.consistency], equals(1.0));
  });

  test('wildly varying hits score lower consistency than steady ones', () {
    final steady = exercise.evaluate([
      const TrainingAttempt({'windowStart': 100, 'windowEnd': 200, 'actual': 150}),
      const TrainingAttempt({'windowStart': 100, 'windowEnd': 200, 'actual': 150}),
    ]);
    final erratic = exercise.evaluate([
      const TrainingAttempt({'windowStart': 100, 'windowEnd': 200, 'actual': 150}),
      const TrainingAttempt({'windowStart': 100, 'windowEnd': 200, 'actual': 400}),
    ]);

    expect(
      erratic.dimensions[TrainingDimensions.consistency]!,
      lessThan(steady.dimensions[TrainingDimensions.consistency]!),
    );
  });

  test('deterministic: the same attempts always produce the same profile', () {
    final attempts = [
      const TrainingAttempt({'windowStart': 100, 'windowEnd': 200, 'actual': 130}),
      const TrainingAttempt({'windowStart': 100, 'windowEnd': 200, 'actual': 180}),
    ];

    final a = exercise.evaluate(attempts).dimensions;
    final b = exercise.evaluate(attempts).dimensions;

    expect(a, equals(b));
  });
}
