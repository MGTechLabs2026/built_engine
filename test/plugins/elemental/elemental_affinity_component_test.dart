import 'package:build_engine/elemental_plugin.dart';
import 'package:test/test.dart';

void main() {
  test('ElementalAffinityComponent stores the given affinities', () {
    const component = ElementalAffinityComponent({'fire': 5, 'water': 2});
    expect(component.affinities, equals({'fire': 5, 'water': 2}));
  });
}
