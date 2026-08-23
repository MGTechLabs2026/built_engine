import 'package:build_engine/physique_plugin.dart';
import 'package:test/test.dart';

void main() {
  test('PhysiqueTypes names the four physiques', () {
    expect(PhysiqueTypes.sturdy, equals('sturdy'));
    expect(PhysiqueTypes.power, equals('power'));
    expect(PhysiqueTypes.burst, equals('burst'));
    expect(PhysiqueTypes.endurance, equals('endurance'));
  });

  test('PhysiqueTypes.all lists all four, in a fixed order', () {
    expect(
      PhysiqueTypes.all,
      equals([
        PhysiqueTypes.sturdy,
        PhysiqueTypes.power,
        PhysiqueTypes.burst,
        PhysiqueTypes.endurance,
      ]),
    );
  });
}
