import 'package:build_engine/build_engine.dart';
import 'package:build_engine/src/plugins/game/run_decision_policy.dart';
import 'package:test/test.dart';

void main() {
  test('item target round-trips', () {
    final t = const TrainItemTarget('iron_sword');
    expect(t.encode(), 'item:iron_sword');
    expect(RunTrainingTarget.decode('item:iron_sword'), t);
  });

  test('technique family target round-trips', () {
    final t = const TrainTechniqueTarget('basic_punch');
    expect(t.encode(), 'technique:basic_punch');
    expect(RunTrainingTarget.decode('technique:basic_punch'), t);
  });

  test('technique variant-instance target round-trips', () {
    final t = TrainTechniqueTarget('basic_punch',
        variantInstanceId: const EntityId(42));
    expect(t.encode(), 'technique:basic_punch#42');
    expect(RunTrainingTarget.decode('technique:basic_punch#42'), t);
  });

  test('decode rejects an unknown prefix', () {
    expect(() => RunTrainingTarget.decode('spell:fireball'),
        throwsFormatException);
  });

  test('DefaultRunDecisionPolicy.chooseTrainingTarget returns the first', () {
    const p = DefaultRunDecisionPolicy();
    final chosen = p.chooseTrainingTarget(const [
      TrainItemTarget('a'),
      TrainTechniqueTarget('basic_kick'),
    ]);
    expect(chosen, const TrainItemTarget('a'));
  });
}
