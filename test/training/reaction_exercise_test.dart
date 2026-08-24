import 'package:build_engine/build_engine.dart';
import 'package:test/test.dart';

void main() {
  const exercise = ReactionExercise();

  test('empty attempts yield an empty profile', () {
    expect(exercise.evaluate(const []).dimensions, isEmpty);
  });

  test('an instant response scores perfect reaction and speed', () {
    final profile = exercise.evaluate([
      const TrainingAttempt({'signalTimestamp': 1000, 'responseTimestamp': 1000, 'maxAcceptable': 500}),
    ]);

    expect(profile.dimensions[TrainingDimensions.reaction], equals(1.0));
    expect(profile.dimensions[TrainingDimensions.speed], equals(1.0));
  });

  test('a very slow response scores near-zero reaction and speed', () {
    final profile = exercise.evaluate([
      const TrainingAttempt({'signalTimestamp': 0, 'responseTimestamp': 2000, 'maxAcceptable': 500}),
    ]);

    expect(profile.dimensions[TrainingDimensions.reaction], equals(0.0));
    expect(profile.dimensions[TrainingDimensions.speed], equals(0.0));
  });

  test('steady response times score higher consistency than erratic ones', () {
    final steady = exercise.evaluate([
      const TrainingAttempt({'signalTimestamp': 0, 'responseTimestamp': 100, 'maxAcceptable': 500}),
      const TrainingAttempt({'signalTimestamp': 0, 'responseTimestamp': 100, 'maxAcceptable': 500}),
    ]);
    final erratic = exercise.evaluate([
      const TrainingAttempt({'signalTimestamp': 0, 'responseTimestamp': 50, 'maxAcceptable': 500}),
      const TrainingAttempt({'signalTimestamp': 0, 'responseTimestamp': 480, 'maxAcceptable': 500}),
    ]);

    expect(
      erratic.dimensions[TrainingDimensions.consistency]!,
      lessThan(steady.dimensions[TrainingDimensions.consistency]!),
    );
  });

  test('deterministic: the same attempts always produce the same profile', () {
    final attempts = [
      const TrainingAttempt({'signalTimestamp': 0, 'responseTimestamp': 200, 'maxAcceptable': 500}),
    ];

    expect(exercise.evaluate(attempts).dimensions, equals(exercise.evaluate(attempts).dimensions));
  });
}
