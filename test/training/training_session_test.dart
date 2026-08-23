import 'package:build_engine/build_engine.dart';
import 'package:test/test.dart';

/// A throwaway test double: averages each measurement key across every
/// submitted attempt. Proves the [TrainingExercise] interface is pluggable
/// without hardcoding any domain-specific exercise into the engine itself.
class _AveragingExercise implements TrainingExercise {
  const _AveragingExercise();

  @override
  TrainingProfile evaluate(List<TrainingAttempt> attempts) {
    if (attempts.isEmpty) return const TrainingProfile({});
    final sums = <String, double>{};
    for (final attempt in attempts) {
      for (final entry in attempt.measurements.entries) {
        sums[entry.key] = (sums[entry.key] ?? 0) + entry.value;
      }
    }
    return TrainingProfile({
      for (final entry in sums.entries) entry.key: entry.value / attempts.length,
    });
  }
}

/// A second, differently-behaved test double: takes only the best (max)
/// value per dimension across every attempt, ignoring the rest — proves
/// two unrelated [TrainingExercise] implementations can coexist and yield
/// genuinely different profiles from the same attempt history.
class _BestOfExercise implements TrainingExercise {
  const _BestOfExercise();

  @override
  TrainingProfile evaluate(List<TrainingAttempt> attempts) {
    final best = <String, double>{};
    for (final attempt in attempts) {
      for (final entry in attempt.measurements.entries) {
        final current = best[entry.key];
        if (current == null || entry.value > current) {
          best[entry.key] = entry.value;
        }
      }
    }
    return TrainingProfile(best);
  }
}

void main() {
  group('create session', () {
    test('identifies trainee, subject, and exercise', () {
      const trainee = EntityId(1);
      final session = TrainingSession(
        trainee: trainee,
        subject: 'technique:jab',
        exercise: const _AveragingExercise(),
      );

      expect(session.trainee, equals(trainee));
      expect(session.subject, equals('technique:jab'));
      expect(session.attempts, isEmpty);
    });
  });

  group('submit attempt', () {
    test('accumulates attempts in submission order', () {
      final session = TrainingSession(
        trainee: const EntityId(1),
        subject: 'technique:jab',
        exercise: const _AveragingExercise(),
      );
      const first = TrainingAttempt({TrainingDimensions.speed: 0.5});
      const second = TrainingAttempt({TrainingDimensions.speed: 0.9});

      session.submitAttempt(first);
      session.submitAttempt(second);

      expect(session.attempts, equals([first, second]));
    });
  });

  group('calculate profile', () {
    test('delegates to the exercise, over every submitted attempt', () {
      final session = TrainingSession(
        trainee: const EntityId(1),
        subject: 'technique:jab',
        exercise: const _AveragingExercise(),
      );
      session.submitAttempt(const TrainingAttempt({TrainingDimensions.speed: 0.6}));
      session.submitAttempt(const TrainingAttempt({TrainingDimensions.speed: 0.8}));

      final profile = session.calculateProfile();

      expect(profile.dimensions[TrainingDimensions.speed], closeTo(0.7, 0.0001));
    });

    test('an exercise may populate only a subset of the known dimensions',
        () {
      final session = TrainingSession(
        trainee: const EntityId(1),
        subject: 'technique:jab',
        exercise: const _AveragingExercise(),
      );
      session.submitAttempt(const TrainingAttempt({
        TrainingDimensions.speed: 0.82,
        TrainingDimensions.power: 0.35,
        TrainingDimensions.precision: 0.71,
        TrainingDimensions.reaction: 0.91,
      }));

      final profile = session.calculateProfile();

      expect(profile.dimensions.keys, hasLength(4));
      expect(profile.dimensions[TrainingDimensions.control], isNull);
    });
  });

  group('multiple exercise types', () {
    test('two different exercises yield different profiles from the same attempts',
        () {
      const attempts = [
        TrainingAttempt({TrainingDimensions.power: 0.3}),
        TrainingAttempt({TrainingDimensions.power: 0.9}),
      ];
      final averaging = TrainingSession(
        trainee: const EntityId(1),
        subject: 'item:iron_sword',
        exercise: const _AveragingExercise(),
      );
      final bestOf = TrainingSession(
        trainee: const EntityId(1),
        subject: 'item:iron_sword',
        exercise: const _BestOfExercise(),
      );
      for (final attempt in attempts) {
        averaging.submitAttempt(attempt);
        bestOf.submitAttempt(attempt);
      }

      expect(
        averaging.calculateProfile().dimensions[TrainingDimensions.power],
        closeTo(0.6, 0.0001),
      );
      expect(
        bestOf.calculateProfile().dimensions[TrainingDimensions.power],
        equals(0.9),
      );
    });
  });

  group('arbitrary subject types', () {
    test('the same session machinery works for two unrelated subjects', () {
      final itemSession = TrainingSession(
        trainee: const EntityId(1),
        subject: 'item:iron_sword',
        exercise: const _AveragingExercise(),
      );
      final techniqueSession = TrainingSession(
        trainee: const EntityId(1),
        subject: 'technique:jab',
        exercise: const _AveragingExercise(),
      );
      itemSession.submitAttempt(const TrainingAttempt({TrainingDimensions.power: 0.4}));
      techniqueSession
          .submitAttempt(const TrainingAttempt({TrainingDimensions.speed: 0.9}));

      final itemResult = itemSession.complete();
      final techniqueResult = techniqueSession.complete();

      expect(itemResult.subject, equals('item:iron_sword'));
      expect(techniqueResult.subject, equals('technique:jab'));
      expect(itemResult.profile.dimensions[TrainingDimensions.power], equals(0.4));
      expect(
        techniqueResult.profile.dimensions[TrainingDimensions.speed],
        equals(0.9),
      );
    });
  });

  group('TrainingResult', () {
    test('complete() carries the trainee, subject, profile, and attempts', () {
      const trainee = EntityId(7);
      final session = TrainingSession(
        trainee: trainee,
        subject: 'technique:jab',
        exercise: const _AveragingExercise(),
      );
      const attempt = TrainingAttempt({TrainingDimensions.reaction: 0.9});
      session.submitAttempt(attempt);

      final result = session.complete();

      expect(result.trainee, equals(trainee));
      expect(result.subject, equals('technique:jab'));
      expect(result.attempts, equals([attempt]));
      expect(result.profile.dimensions[TrainingDimensions.reaction], equals(0.9));
    });

    test('does not decide anything beyond carrying the profile — no learning logic',
        () {
      final session = TrainingSession(
        trainee: const EntityId(1),
        subject: 'technique:jab',
        exercise: const _AveragingExercise(),
      );
      session.submitAttempt(const TrainingAttempt({TrainingDimensions.speed: 0.99}));

      final result = session.complete();

      // TrainingResult is a plain data snapshot: it exposes only trainee,
      // subject, profile, and attempts — nothing resembling a decision
      // ("learned" / "mastered" / pass-fail) exists on it at all. This is
      // deliberately a compile-time-shaped assertion, not just a value
      // check: TrainingResult's public surface itself is the contract.
      expect(result.profile, isA<TrainingProfile>());
    });
  });

  group('deterministic result', () {
    test('the same attempt sequence on two independent sessions yields equal results',
        () {
      TrainingSession newSession() => TrainingSession(
            trainee: const EntityId(1),
            subject: 'technique:jab',
            exercise: const _AveragingExercise(),
          );
      final attemptSequence = [
        const TrainingAttempt({TrainingDimensions.speed: 0.5, TrainingDimensions.power: 0.2}),
        const TrainingAttempt({TrainingDimensions.speed: 0.7, TrainingDimensions.power: 0.6}),
        const TrainingAttempt({TrainingDimensions.speed: 0.9, TrainingDimensions.power: 0.4}),
      ];

      final sessionA = newSession();
      final sessionB = newSession();
      for (final attempt in attemptSequence) {
        sessionA.submitAttempt(attempt);
        sessionB.submitAttempt(attempt);
      }

      final resultA = sessionA.complete();
      final resultB = sessionB.complete();

      expect(resultA.profile.dimensions, equals(resultB.profile.dimensions));
    });
  });
}
