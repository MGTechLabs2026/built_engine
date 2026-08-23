import 'package:build_engine/elemental_plugin.dart';
import 'package:test/test.dart';

void main() {
  test('ElementalResources names the resource Elemental spends', () {
    expect(ElementalResources.mana, equals('mana'));
  });

  test('ElementalStatuses names the three status tags Elemental '
      'applies', () {
    expect(ElementalStatuses.burning, equals('status:burning'));
    expect(ElementalStatuses.soaked, equals('status:soaked'));
    expect(ElementalStatuses.shocked, equals('status:shocked'));
  });
}
