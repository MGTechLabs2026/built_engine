import 'package:build_engine/build_engine.dart';
import 'package:build_engine/physique_plugin.dart';
import 'package:test/test.dart';

void main() {
  test('PhysiqueAssigned stores the character and physique id', () {
    const character = EntityId(1);
    const event = PhysiqueAssigned(character, 'sturdy');
    expect(event.character, equals(character));
    expect(event.physiqueId, equals('sturdy'));
  });
}
