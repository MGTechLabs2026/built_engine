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
