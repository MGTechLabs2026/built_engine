import 'package:build_engine/combat_plugin.dart';
import 'package:test/test.dart';

void main() {
  group('CombatantComponent', () {
    test('stores team and initiative', () {
      const component = CombatantComponent(team: 'alpha', initiative: 5);
      expect(component.team, equals('alpha'));
      expect(component.initiative, equals(5));
    });

    test('initiative defaults to 0', () {
      const component = CombatantComponent(team: 'alpha');
      expect(component.initiative, equals(0));
    });

    test('round-trips through toJson/fromJson', () {
      const component = CombatantComponent(team: 'beta', initiative: 3);
      final restored = CombatantComponent.fromJson(component.toJson());
      expect(restored.team, equals('beta'));
      expect(restored.initiative, equals(3));
    });
  });
}
