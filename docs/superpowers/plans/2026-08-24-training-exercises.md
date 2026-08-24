# Training Exercises Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement the 5 concrete `TrainingExercise` types
(`training_exercise.dart`'s own doc comment already previews exactly these
names: `TimingExercise`, `PrecisionExercise`, `ReactionExercise`,
`PowerExercise`, `ComboExercise`) plus a generic per-subject weighting
decorator, on top of the existing, unmodified Training framework.

**Architecture:** Pure additive Core files under `lib/src/training/` — no
new plugin, no `ComponentStore`/`EventBus`/`PluginContext` dependency at
all (mirrors `TrainingSession`'s own "plain, standalone object" design).
Each exercise implements the existing `TrainingExercise` interface
(`evaluate(List<TrainingAttempt>) -> TrainingProfile`) with a specific,
documented measurement-key convention. `TrainingAttempt`'s existing
`Map<String, double> measurements` bag **is** the "abstract input
representation" the milestone calls `ExerciseAttempt` — reused verbatim,
not reinvented, per "do not replace the Training framework." A new
`WeightedTrainingExercise` decorator (also just another `TrainingExercise`)
scales a wrapped exercise's output per-dimension by a caller-supplied
weight map — this is how "weights belong in content definitions, not the
Training Engine" is satisfied: the Engine gets a generic multiply-by-weight
primitive; the actual weight *numbers* for Basic Punch/Slash/Guard/Knife/
Iron Sword/Gloves live as new small content files inside the existing
Technique/Item plugins (each plugin owns its own subjects' weights — no
new plugin, no cross-plugin coupling).

**Tech Stack:** Dart 3.7, `package:test`, `dart:math` (pure math only,
same precedent as `modifier_resolver.dart`'s `math.min`/`math.max` — never
`dart:math`'s `Random`, per the engine's determinism rule).

**Spec:** The milestone brief in the current conversation.

## Global Constraints

- Do not replace/modify `TrainingSession`, `TrainingResult`,
  `TrainingAttempt`, or the `TrainingExercise` interface — additive only.
  (`TrainingProfile`'s `TrainingDimensions` constants class gets 2 new
  constants added — additive, not a behavior change.)
- No exercise may put martial-arts/magic/alchemy/domain vocabulary into
  Core — every exercise is generic; only the *weight numbers* in the two
  plugin-level content files are martial-flavored.
- Every exercise must be a pure, deterministic function of its attempts —
  no randomness, no wall-clock (matches the existing interface contract).
- The engine must stay headless: no Flutter/`dart:ui` import anywhere, and
  no dependency on Combat.
- Training must not call Evolution/Mastery/Progression itself — it only
  produces `TrainingProfile`/`TrainingResult`; applying them is the
  caller's job (proven, not just asserted, via an integration test).
- `dart analyze` must stay clean and no existing test may regress.
- Do not commit.

---

## File Structure

```
lib/src/training/
  training_statistics.dart        - TrainingStatistics.average/.standardDeviation
  timing_exercise.dart            - TimingExercise
  precision_exercise.dart         - PrecisionExercise
  reaction_exercise.dart          - ReactionExercise
  power_exercise.dart             - PowerExercise
  combo_exercise.dart             - ComboExercise
  weighted_training_exercise.dart - WeightedTrainingExercise
  training_profile.dart           - MODIFIED: add `timing`/`execution` to TrainingDimensions

lib/src/plugins/technique/
  technique_training_weights.dart - techniqueTrainingWeights + techniqueTrainingExerciseFor()
lib/src/plugins/item/
  item_training_weights.dart      - itemTrainingWeights + itemTrainingExerciseFor()
lib/technique_plugin.dart         - MODIFIED: export technique_training_weights.dart
lib/item_plugin.dart              - MODIFIED: export item_training_weights.dart
lib/build_engine.dart             - MODIFIED: export the 6 new lib/src/training/ files

test/training/
  training_statistics_test.dart
  timing_exercise_test.dart
  precision_exercise_test.dart
  reaction_exercise_test.dart
  power_exercise_test.dart
  combo_exercise_test.dart
  weighted_training_exercise_test.dart   - profile weighting + arbitrary training subject
  training_no_ui_or_combat_dependency_test.dart

test/integration/
  training_pipeline_integration_test.dart - TrainingResult -> mastery/learning/evolution demo, determinism
```

---

### Task 1: `TrainingStatistics` helper

**Files:**
- Create: `lib/src/training/training_statistics.dart`
- Test: `test/training/training_statistics_test.dart`

**Interfaces:**
- Produces: `TrainingStatistics.average(List<double>) -> double`, `TrainingStatistics.standardDeviation(List<double>) -> double`.

- [ ] **Step 1: Write `training_statistics.dart`**

```dart
import 'dart:math' as math;

/// Pure numeric helpers shared by every concrete `TrainingExercise` —
/// namespaced under one class (the same convention `ContentField` uses)
/// so the package's public surface doesn't gain generic top-level names
/// like `average`. Extracted once, rather than duplicated across
/// `TimingExercise`/`PrecisionExercise`/`ReactionExercise`/
/// `PowerExercise`/`ComboExercise`, all five of which need the same
/// "how consistent were these scores" computation.
class TrainingStatistics {
  const TrainingStatistics._();

  /// The arithmetic mean of [values]; `0.0` for an empty list.
  static double average(List<double> values) {
    if (values.isEmpty) return 0.0;
    return values.reduce((a, b) => a + b) / values.length;
  }

  /// The population standard deviation of [values]; `0.0` for fewer than
  /// 2 values (nothing to vary against).
  static double standardDeviation(List<double> values) {
    if (values.length < 2) return 0.0;
    final mean = average(values);
    final variance = average([for (final v in values) (v - mean) * (v - mean)]);
    return math.sqrt(variance);
  }
}
```

- [ ] **Step 2: Write the failing test**

```dart
import 'package:build_engine/build_engine.dart';
import 'package:test/test.dart';

void main() {
  test('average of an empty list is 0.0', () {
    expect(TrainingStatistics.average(const []), equals(0.0));
  });

  test('average computes the arithmetic mean', () {
    expect(TrainingStatistics.average(const [1.0, 2.0, 3.0]), equals(2.0));
  });

  test('standardDeviation of identical values is 0.0', () {
    expect(TrainingStatistics.standardDeviation(const [0.5, 0.5, 0.5]), equals(0.0));
  });

  test('standardDeviation of a single value is 0.0', () {
    expect(TrainingStatistics.standardDeviation(const [0.9]), equals(0.0));
  });

  test('standardDeviation is positive for varying values', () {
    expect(TrainingStatistics.standardDeviation(const [0.0, 1.0]), closeTo(0.5, 0.0001));
  });
}
```

- [ ] **Step 3: Run to verify fail, then pass** — `dart test test/training/training_statistics_test.dart`

---

### Task 2: `TrainingDimensions` additions

**Files:**
- Modify: `lib/src/training/training_profile.dart`

- [ ] **Step 1: Add `timing`/`execution` constants**

```dart
abstract final class TrainingDimensions {
  static const speed = 'speed';
  static const power = 'power';
  static const precision = 'precision';
  static const reaction = 'reaction';
  static const control = 'control';
  static const rhythm = 'rhythm';
  static const accuracy = 'accuracy';
  static const consistency = 'consistency';
  static const timing = 'timing';
  static const execution = 'execution';
}
```

(No new test file — covered by every exercise test in Tasks 3–7, each of
which asserts on `TrainingDimensions.timing`/`.execution`.)

---

### Task 3: `TimingExercise`

**Files:**
- Create: `lib/src/training/timing_exercise.dart`
- Test: `test/training/timing_exercise_test.dart`

**Measurement keys (per attempt):** `windowStart`, `windowEnd`, `actual` (a
consistent time unit, e.g. ms — the exercise never interprets the unit).

- [ ] **Step 1: Write `timing_exercise.dart`**

```dart
import 'training_attempt.dart';
import 'training_exercise.dart';
import 'training_profile.dart';
import 'training_statistics.dart';

/// A timing-window exercise: how close [TrainingAttempt.measurements]'
/// `'actual'` timestamp lands to the `'windowStart'`..`'windowEnd'`
/// window. Generic across any domain that has "act within this window"
/// mechanics (a martial parry window, a magic incantation window, an
/// alchemy stir-timing window, ...) — nothing here is martial-specific.
///
/// `timing`: closeness to the window's center (`1.0` at dead-center,
/// clamped to `0.0` at or beyond either edge).
/// `reaction`: rewards acting at or before center fully (`1.0`); only
/// decays for lateness past center — "don't be late" rather than
/// "hit the exact middle," a deliberately different signal from `timing`.
/// `consistency`: `1.0` minus how much `timing` varies attempt-to-attempt.
class TimingExercise implements TrainingExercise {
  const TimingExercise();

  @override
  TrainingProfile evaluate(List<TrainingAttempt> attempts) {
    if (attempts.isEmpty) return const TrainingProfile({});

    final qualities = <double>[];
    final reactions = <double>[];
    for (final attempt in attempts) {
      final start = attempt.measurements['windowStart']!;
      final end = attempt.measurements['windowEnd']!;
      final actual = attempt.measurements['actual']!;
      final center = (start + end) / 2;
      final halfWidth = (end - start) / 2;

      qualities.add((1 - (actual - center).abs() / halfWidth).clamp(0.0, 1.0));
      reactions.add(actual <= center
          ? 1.0
          : (1 - (actual - center) / halfWidth).clamp(0.0, 1.0));
    }

    return TrainingProfile({
      TrainingDimensions.timing: TrainingStatistics.average(qualities),
      TrainingDimensions.reaction: TrainingStatistics.average(reactions),
      TrainingDimensions.consistency:
          1 - TrainingStatistics.standardDeviation(qualities).clamp(0.0, 1.0),
    });
  }
}
```

- [ ] **Step 2: Write the failing test**

```dart
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
```

- [ ] **Step 3: Run to verify fail, then pass** — `dart test test/training/timing_exercise_test.dart`

---

### Task 4: `PrecisionExercise`

**Files:**
- Create: `lib/src/training/precision_exercise.dart`
- Test: `test/training/precision_exercise_test.dart`

**Measurement keys:** `targetX`, `targetY`, `actionX`, `actionY`,
`tolerance` (a radius, in the caller's own unit).

- [ ] **Step 1: Write `precision_exercise.dart`**

```dart
import 'dart:math' as math;

import 'training_attempt.dart';
import 'training_exercise.dart';
import 'training_profile.dart';
import 'training_statistics.dart';

/// A spatial-accuracy exercise: how close `('actionX','actionY')` lands
/// to `('targetX','targetY')`, within a `'tolerance'` radius — generic
/// across any "hit this spot" mechanic (a martial strike zone, an
/// alchemy pour target, a crafting tap point).
///
/// `accuracy`: average closeness to the target (`1.0` at dead center,
/// `0.0` at or beyond `tolerance`).
/// `precision`: how tightly attempts group together (low variance in
/// distance-from-target) — distinct from `accuracy`: a trainee can group
/// tightly (high precision) while consistently missing the true target
/// (low accuracy), or vice versa.
/// `control`: the fraction of attempts that landed within `tolerance` at
/// all (a hit-rate, distinct from the continuous `accuracy` score).
class PrecisionExercise implements TrainingExercise {
  const PrecisionExercise();

  @override
  TrainingProfile evaluate(List<TrainingAttempt> attempts) {
    if (attempts.isEmpty) return const TrainingProfile({});

    final distances = <double>[];
    final accuracyScores = <double>[];
    final hits = <double>[];
    for (final attempt in attempts) {
      final dx = attempt.measurements['actionX']! - attempt.measurements['targetX']!;
      final dy = attempt.measurements['actionY']! - attempt.measurements['targetY']!;
      final distance = math.sqrt(dx * dx + dy * dy);
      final tolerance = attempt.measurements['tolerance']!;

      distances.add(distance);
      accuracyScores.add((1 - distance / tolerance).clamp(0.0, 1.0));
      hits.add(distance <= tolerance ? 1.0 : 0.0);
    }
    final tolerance = attempts.first.measurements['tolerance']!;

    return TrainingProfile({
      TrainingDimensions.accuracy: TrainingStatistics.average(accuracyScores),
      TrainingDimensions.precision:
          1 - (TrainingStatistics.standardDeviation(distances) / tolerance).clamp(0.0, 1.0),
      TrainingDimensions.control: TrainingStatistics.average(hits),
    });
  }
}
```

- [ ] **Step 2: Write the failing test**

```dart
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
```

- [ ] **Step 3: Run to verify fail, then pass** — `dart test test/training/precision_exercise_test.dart`

---

### Task 5: `ReactionExercise`

**Files:**
- Create: `lib/src/training/reaction_exercise.dart`
- Test: `test/training/reaction_exercise_test.dart`

**Measurement keys:** `signalTimestamp`, `responseTimestamp`,
`maxAcceptable` (the same time unit as the timestamps).

- [ ] **Step 1: Write `reaction_exercise.dart`**

```dart
import 'training_attempt.dart';
import 'training_exercise.dart';
import 'training_profile.dart';
import 'training_statistics.dart';

/// A stimulus-response exercise: how quickly `'responseTimestamp'` follows
/// `'signalTimestamp'`, relative to `'maxAcceptable'` — generic across any
/// "react to this cue" mechanic (a martial counter window, a magic
/// interrupt, a crafting quality-time cue).
///
/// `reaction`: response speed relative to the attempt's own
/// `'maxAcceptable'` threshold (task-specific).
/// `speed`: response speed on a fixed 1000-unit absolute scale — a
/// task-independent raw-reflexes signal, deliberately different from
/// `reaction`'s task-relative one.
/// `consistency`: `1.0` minus how much `reaction` varies attempt-to-attempt.
class ReactionExercise implements TrainingExercise {
  const ReactionExercise();

  @override
  TrainingProfile evaluate(List<TrainingAttempt> attempts) {
    if (attempts.isEmpty) return const TrainingProfile({});

    final reactionScores = <double>[];
    final speedScores = <double>[];
    for (final attempt in attempts) {
      final responseTime = attempt.measurements['responseTimestamp']! -
          attempt.measurements['signalTimestamp']!;
      final maxAcceptable = attempt.measurements['maxAcceptable']!;

      reactionScores.add((1 - responseTime / maxAcceptable).clamp(0.0, 1.0));
      speedScores.add((1 - responseTime / 1000).clamp(0.0, 1.0));
    }

    return TrainingProfile({
      TrainingDimensions.reaction: TrainingStatistics.average(reactionScores),
      TrainingDimensions.speed: TrainingStatistics.average(speedScores),
      TrainingDimensions.consistency:
          1 - TrainingStatistics.standardDeviation(reactionScores).clamp(0.0, 1.0),
    });
  }
}
```

- [ ] **Step 2: Write the failing test**

```dart
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
```

- [ ] **Step 3: Run to verify fail, then pass** — `dart test test/training/reaction_exercise_test.dart`

---

### Task 6: `PowerExercise`

**Files:**
- Create: `lib/src/training/power_exercise.dart`
- Test: `test/training/power_exercise_test.dart`

**Measurement keys:** `charge` (0.0–1.0), `releaseTimestamp`,
`optimalReleaseTimestamp`, `releaseWindow`.

- [ ] **Step 1: Write `power_exercise.dart`**

```dart
import 'training_attempt.dart';
import 'training_exercise.dart';
import 'training_profile.dart';
import 'training_statistics.dart';

/// A charge-and-release exercise: how much `'charge'` (0.0–1.0) was built
/// up and how close `'releaseTimestamp'` lands to
/// `'optimalReleaseTimestamp'` (within `'releaseWindow'`) — generic across
/// any "build up then release" mechanic (a martial haymaker, a magic
/// spell charge, an alchemy heat build-up).
///
/// `power`: average charge level reached.
/// `timing`: closeness of release to the optimal moment.
/// `control`: `1.0` minus how much `charge` varies attempt-to-attempt —
/// steady effort control, distinct from raw `power` output.
class PowerExercise implements TrainingExercise {
  const PowerExercise();

  @override
  TrainingProfile evaluate(List<TrainingAttempt> attempts) {
    if (attempts.isEmpty) return const TrainingProfile({});

    final charges = <double>[];
    final timingScores = <double>[];
    for (final attempt in attempts) {
      final charge = attempt.measurements['charge']!.clamp(0.0, 1.0);
      final release = attempt.measurements['releaseTimestamp']!;
      final optimal = attempt.measurements['optimalReleaseTimestamp']!;
      final window = attempt.measurements['releaseWindow']!;

      charges.add(charge);
      timingScores.add((1 - (release - optimal).abs() / window).clamp(0.0, 1.0));
    }

    return TrainingProfile({
      TrainingDimensions.power: TrainingStatistics.average(charges),
      TrainingDimensions.timing: TrainingStatistics.average(timingScores),
      TrainingDimensions.control:
          1 - TrainingStatistics.standardDeviation(charges).clamp(0.0, 1.0),
    });
  }
}
```

- [ ] **Step 2: Write the failing test**

```dart
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
```

- [ ] **Step 3: Run to verify fail, then pass** — `dart test test/training/power_exercise_test.dart`

---

### Task 7: `ComboExercise`

**Files:**
- Create: `lib/src/training/combo_exercise.dart`
- Test: `test/training/combo_exercise_test.dart`

**Measurement keys:** `length` (step count), `expected_$i`/`actual_$i` for
`i` in `0..length-1` (numeric step codes), `expectedDurationMs`,
`actualDurationMs`.

- [ ] **Step 1: Write `combo_exercise.dart`**

```dart
import 'training_attempt.dart';
import 'training_exercise.dart';
import 'training_profile.dart';
import 'training_statistics.dart';

/// A sequence exercise: how many of `length` numerically-coded steps
/// (`'expected_0'`/`'actual_0'`, `'expected_1'`/`'actual_1'`, ...) matched,
/// and how closely `'actualDurationMs'` matched `'expectedDurationMs'` —
/// generic across any "perform this sequence" mechanic (a martial combo,
/// a magic incantation sequence, an alchemy step order, a crafting
/// recipe sequence). Step codes are opaque numbers the caller assigns;
/// this exercise never interprets what a code means.
///
/// `accuracy`: fraction of steps that matched, per attempt, averaged.
/// `rhythm`: how closely the whole sequence's overall pacing matched the
/// expected duration.
/// `consistency`: `1.0` minus how much per-attempt `accuracy` varies.
/// `execution`: `accuracy * rhythm` per attempt, averaged — a holistic
/// "how clean was the whole performance" signal distinct from either
/// factor alone.
class ComboExercise implements TrainingExercise {
  const ComboExercise();

  @override
  TrainingProfile evaluate(List<TrainingAttempt> attempts) {
    if (attempts.isEmpty) return const TrainingProfile({});

    final accuracyScores = <double>[];
    final rhythmScores = <double>[];
    final executionScores = <double>[];
    for (final attempt in attempts) {
      final length = attempt.measurements['length']!.round();
      var matches = 0;
      for (var i = 0; i < length; i++) {
        if (attempt.measurements['expected_$i'] == attempt.measurements['actual_$i']) {
          matches++;
        }
      }
      final accuracy = length == 0 ? 0.0 : matches / length;

      final expectedDuration = attempt.measurements['expectedDurationMs']!;
      final actualDuration = attempt.measurements['actualDurationMs']!;
      final rhythm =
          (1 - (actualDuration - expectedDuration).abs() / expectedDuration).clamp(0.0, 1.0);

      accuracyScores.add(accuracy);
      rhythmScores.add(rhythm);
      executionScores.add(accuracy * rhythm);
    }

    return TrainingProfile({
      TrainingDimensions.accuracy: TrainingStatistics.average(accuracyScores),
      TrainingDimensions.rhythm: TrainingStatistics.average(rhythmScores),
      TrainingDimensions.consistency:
          1 - TrainingStatistics.standardDeviation(accuracyScores).clamp(0.0, 1.0),
      TrainingDimensions.execution: TrainingStatistics.average(executionScores),
    });
  }
}
```

- [ ] **Step 2: Write the failing test**

```dart
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
```

- [ ] **Step 3: Run to verify fail, then pass** — `dart test test/training/combo_exercise_test.dart`

---

### Task 8: `WeightedTrainingExercise` + content weight maps

**Files:**
- Create: `lib/src/training/weighted_training_exercise.dart`
- Create: `lib/src/plugins/technique/technique_training_weights.dart`
- Create: `lib/src/plugins/item/item_training_weights.dart`
- Test: `test/training/weighted_training_exercise_test.dart`

**Interfaces:**
- Produces: `WeightedTrainingExercise(TrainingExercise inner, Map<String, double> weights) implements TrainingExercise`.
- Produces: `techniqueTrainingWeights` (`Map<String, Map<String, double>>`), `techniqueTrainingExerciseFor(String id, TrainingExercise base)`.
- Produces: `itemTrainingWeights`, `itemTrainingExerciseFor(String id, TrainingExercise base)`.

- [ ] **Step 1: Write `weighted_training_exercise.dart`**

```dart
import 'training_attempt.dart';
import 'training_exercise.dart';
import 'training_profile.dart';

/// Scales a wrapped exercise's output profile per-dimension by [weights]
/// — the generic primitive that lets "how much each dimension matters for
/// this particular subject" live in content, never hardcoded in the
/// Training Engine itself. A dimension with no entry in [weights] passes
/// through unscaled (multiplied by `1.0`). Just another `TrainingExercise`
/// — composes with any of the 5 concrete exercises, or a future one,
/// without either side knowing about the other.
class WeightedTrainingExercise implements TrainingExercise {
  const WeightedTrainingExercise(this.inner, this.weights);

  final TrainingExercise inner;
  final Map<String, double> weights;

  @override
  TrainingProfile evaluate(List<TrainingAttempt> attempts) {
    final raw = inner.evaluate(attempts);
    return TrainingProfile({
      for (final entry in raw.dimensions.entries)
        entry.key: entry.value * (weights[entry.key] ?? 1.0),
    });
  }
}
```

- [ ] **Step 2: Write `technique_training_weights.dart`**

```dart
import 'package:build_engine/build_engine.dart';

/// Per-technique training-dimension weights — content data, not Training
/// Engine logic. Matches the milestone's own example: Basic Punch weights
/// speed/reaction (fast, reactive strikes) higher than power/precision.
const techniqueTrainingWeights = <String, Map<String, double>>{
  'basic_punch': {'speed': 0.3, 'power': 0.2, 'precision': 0.2, 'reaction': 0.3},
  'basic_slash': {'speed': 0.25, 'power': 0.35, 'precision': 0.25, 'reaction': 0.15},
  'basic_guard': {'reaction': 0.4, 'control': 0.3, 'consistency': 0.3},
};

/// Wraps [base] in a [WeightedTrainingExercise] using [techniqueId]'s
/// registered weights, if any — [base] unchanged if [techniqueId] has no
/// entry.
TrainingExercise techniqueTrainingExerciseFor(String techniqueId, TrainingExercise base) {
  final weights = techniqueTrainingWeights[techniqueId];
  return weights == null ? base : WeightedTrainingExercise(base, weights);
}
```

- [ ] **Step 3: Write `item_training_weights.dart`**

```dart
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
```

- [ ] **Step 4: Write the failing test** — `test/training/weighted_training_exercise_test.dart` (profile weighting + arbitrary training subject)

```dart
import 'package:build_engine/build_engine.dart';
import 'package:build_engine/technique_plugin.dart';
import 'package:test/test.dart';

class _FixedExercise implements TrainingExercise {
  const _FixedExercise(this.profile);
  final TrainingProfile profile;

  @override
  TrainingProfile evaluate(List<TrainingAttempt> attempts) => profile;
}

void main() {
  test('weighting scales each dimension by its configured weight', () {
    const fixed = _FixedExercise(TrainingProfile({'speed': 0.8, 'power': 0.8}));
    const weighted = WeightedTrainingExercise(fixed, {'speed': 0.3, 'power': 0.2});

    final profile = weighted.evaluate(const []);

    expect(profile.dimensions['speed'], closeTo(0.24, 0.0001));
    expect(profile.dimensions['power'], closeTo(0.16, 0.0001));
  });

  test('a dimension with no configured weight passes through unscaled', () {
    const fixed = _FixedExercise(TrainingProfile({'reaction': 0.5}));
    const weighted = WeightedTrainingExercise(fixed, {'speed': 0.3});

    expect(weighted.evaluate(const []).dimensions['reaction'], equals(0.5));
  });

  test('profile weighting: basic_punch weighting favors speed/reaction over power/precision', () {
    const rawProfile = TrainingProfile({'speed': 0.8, 'power': 0.8, 'precision': 0.8, 'reaction': 0.8});
    const fixed = _FixedExercise(rawProfile);

    final weighted = techniqueTrainingExerciseFor('basic_punch', fixed).evaluate(const []);

    expect(weighted.dimensions['speed'], equals(weighted.dimensions['reaction']));
    expect(weighted.dimensions['speed']! > weighted.dimensions['power']!, isTrue);
  });

  test('an item with no configured weights returns the base exercise unchanged', () {
    const fixed = _FixedExercise(TrainingProfile({'speed': 0.5}));

    final result = itemTrainingExerciseFor('unregistered_item', fixed);

    expect(result, same(fixed));
  });

  test('arbitrary training subject: an unrelated made-up subject can define its own weights '
      'with zero Technique/Item plugin involvement', () {
    const fixed = _FixedExercise(TrainingProfile({'precision': 0.9, 'power': 0.4}));
    const weighted = WeightedTrainingExercise(fixed, {'precision': 0.7, 'power': 0.1});

    final profile = weighted.evaluate(const []);

    expect(profile.dimensions['precision'], closeTo(0.63, 0.0001));
    expect(profile.dimensions['power'], closeTo(0.04, 0.0001));
  });
}
```

- [ ] **Step 5: Wire the new files into the public barrels**

Add to `lib/build_engine.dart` (alongside the existing `training/` exports):

```dart
export 'src/training/combo_exercise.dart';
export 'src/training/power_exercise.dart';
export 'src/training/precision_exercise.dart';
export 'src/training/reaction_exercise.dart';
export 'src/training/timing_exercise.dart';
export 'src/training/training_statistics.dart';
export 'src/training/weighted_training_exercise.dart';
```

Add to `lib/technique_plugin.dart`:

```dart
export 'src/plugins/technique/technique_training_weights.dart';
```

Add to `lib/item_plugin.dart`:

```dart
export 'src/plugins/item/item_training_weights.dart';
```

- [ ] **Step 6: Run to verify fail, then pass** — `dart test test/training/weighted_training_exercise_test.dart`

---

### Task 9: No-UI / no-Combat dependency test + full pipeline integration test

**Files:**
- Create: `test/training/training_no_ui_or_combat_dependency_test.dart`
- Create: `test/integration/training_pipeline_integration_test.dart`

- [ ] **Step 1: Write `training_no_ui_or_combat_dependency_test.dart`**

```dart
import 'dart:io';

import 'package:test/test.dart';

void main() {
  final files = Directory('lib/src/training')
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'));

  for (final forbidden in ['flutter', 'dart:ui', 'combat_plugin.dart', 'plugins/combat']) {
    test('no file under lib/src/training references "$forbidden"', () {
      for (final file in files) {
        expect(
          file.readAsStringSync(),
          isNot(contains(forbidden)),
          reason: '${file.path} must not reference "$forbidden"',
        );
      }
    });
  }
}
```

(This is a targeted, standalone check — `test/integration/architecture_dependency_test.dart`'s
existing group H already independently proves every Core directory,
`lib/src/training` included, never references any plugin barrel including
`combat_plugin.dart`; this file adds the explicit Flutter/`dart:ui` check
the milestone names directly.)

- [ ] **Step 2: Write `training_pipeline_integration_test.dart`**

```dart
import 'package:build_engine/build_engine.dart';
import 'package:build_engine/technique_plugin.dart';
import 'package:test/test.dart';

PluginContext _newContext() {
  final events = EventBus();
  final entities = EntityRegistry(events);
  final components = ComponentStore();
  final rng = RngService(1);
  final mastery = MasteryTracker(components: components, events: events);
  final progression =
      ProgressionEngine(components: components, events: events, mastery: mastery);
  final discovery = DiscoveryTracker(components: components, events: events);
  return PluginContext(
    entities: entities,
    components: components,
    events: events,
    rng: rng,
    rules: RuleEngine(
      entities: entities,
      components: components,
      events: events,
      rng: rng,
      mastery: mastery,
      progression: progression,
      discovery: discovery,
    ),
    queries: QueryEngine(QueryScope(components: components)),
    modifiers: ModifierCollection(),
    content: ContentRegistry(),
    mastery: mastery,
    progression: progression,
    discovery: discovery,
  );
}

void main() {
  test(
      'a TrainingResult carries enough to drive mastery increase, technique '
      'learning, and evolution weighting — without Training calling any of '
      'them itself', () {
    final context = _newContext();
    TechniquePlugin().initialize(context);
    final character = context.entities.create();
    final basicPunch = techniqueDefinition(TechniqueIds.basicPunch, context);

    final exercise = techniqueTrainingExerciseFor(TechniqueIds.basicPunch, const TimingExercise());
    final session = TrainingSession(
      trainee: character,
      subject: techniqueSubject(TechniqueIds.basicPunch),
      exercise: exercise,
    );
    session.submitAttempt(const TrainingAttempt({'windowStart': 100, 'windowEnd': 200, 'actual': 150}));
    session.submitAttempt(const TrainingAttempt({'windowStart': 100, 'windowEnd': 200, 'actual': 140}));
    final result = session.complete();

    expect(result.trainee, equals(character));
    expect(result.subject, equals(techniqueSubject(TechniqueIds.basicPunch)));
    expect(result.profile.dimensions, isNotEmpty);

    // Mastery increase — driven by the caller, using result.trainee/.subject:
    context.mastery.increase(result.trainee, result.subject, 10);
    expect(context.mastery.progressOf(result.trainee, result.subject), equals(10));

    // Technique learning — driven by the caller, using result.trainee:
    discoverTechnique(result.trainee, basicPunch, context);
    final learning = attemptToLearnTechnique(result.trainee, basicPunch, 10, context);
    expect(learning.learned, isTrue);

    // Evolution weighting — driven by the caller, using result.profile:
    final evolution = evolveTechnique(result.trainee, basicPunch, result.profile, context);
    expect(evolution.evolved, isTrue);
  });

  test('deterministic: an identical training session always yields an identical result', () {
    TrainingResult runOnce() {
      final session = TrainingSession(
        trainee: const EntityId(1),
        subject: 'technique:basic_punch',
        exercise: techniqueTrainingExerciseFor(TechniqueIds.basicPunch, const TimingExercise()),
      );
      session.submitAttempt(const TrainingAttempt({'windowStart': 100, 'windowEnd': 200, 'actual': 160}));
      session.submitAttempt(const TrainingAttempt({'windowStart': 100, 'windowEnd': 200, 'actual': 145}));
      return session.complete();
    }

    expect(runOnce().profile.dimensions, equals(runOnce().profile.dimensions));
  });
}
```

- [ ] **Step 3: Run to verify fail, then pass**

Run: `dart test test/training/ test/integration/training_pipeline_integration_test.dart`

---

### Task 10: Full quality gate

- [ ] **Step 1:** `dart test` — expect PASS, baseline 814 + this plan's new tests, zero regressions.
- [ ] **Step 2:** `dart analyze` — expect `No issues found!`.
- [ ] **Step 3:** Do not commit (per milestone instructions) unless the user explicitly asks.

---

## Self-Review Notes

- **Spec coverage:** all 5 exercise types — Tasks 3–7, each with the exact
  named inputs/outputs. `ExerciseAttempt`-equivalent — `TrainingAttempt`
  reused, not reinvented (documented in Architecture). Content weights,
  not hardcoded in the Engine — Task 8 (weights live in 2 plugin files;
  the Engine only gets the generic `WeightedTrainingExercise` primitive).
  `TrainingResult` sufficiency for mastery/learning/evolution — Task 9's
  integration test proves it structurally (no new fields needed). "Training
  does not directly decide evolution" — true by construction: no file
  under `lib/src/training/` imports anything Evolution-related. All 12
  named test areas — Tasks 1, 3–9.
- **Not implemented, by design:** no Flutter/UI code anywhere (verified by
  Task 9's dependency test), no real training minigame simulation (tests
  submit raw `TrainingAttempt` measurement maps directly, exactly what a
  future UI layer would translate real input into).
