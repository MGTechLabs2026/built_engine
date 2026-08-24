import 'package:build_engine/build_engine.dart';
import 'package:build_engine/item_plugin.dart';
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
