import 'package:build_engine/physique_plugin.dart';
import 'package:test/test.dart';

void main() {
  test('PhysiqueComponent stores the given physique id', () {
    const component = PhysiqueComponent('sturdy');
    expect(component.physiqueId, equals('sturdy'));
  });
}
