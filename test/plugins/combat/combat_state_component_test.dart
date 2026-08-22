import 'package:build_engine/build_engine.dart';
import 'package:build_engine/combat_plugin.dart';
import 'package:test/test.dart';

void main() {
  group('CombatStateComponent', () {
    test('stores all fields', () {
      const component = CombatStateComponent(
        participants: [EntityId(1), EntityId(2)],
        currentTurnIndex: 1,
        round: 3,
        active: true,
      );
      expect(
        component.participants,
        equals([const EntityId(1), const EntityId(2)]),
      );
      expect(component.currentTurnIndex, equals(1));
      expect(component.round, equals(3));
      expect(component.active, isTrue);
    });

    test('round-trips through toJson/fromJson', () {
      const component = CombatStateComponent(
        participants: [EntityId(1), EntityId(2), EntityId(3)],
        currentTurnIndex: 2,
        round: 5,
        active: false,
      );
      final restored = CombatStateComponent.fromJson(component.toJson());
      expect(restored.participants, equals(component.participants));
      expect(restored.currentTurnIndex, equals(2));
      expect(restored.round, equals(5));
      expect(restored.active, isFalse);
    });

    test('round-trips an empty participant list', () {
      const component = CombatStateComponent(
        participants: [],
        currentTurnIndex: 0,
        round: 1,
        active: true,
      );
      final restored = CombatStateComponent.fromJson(component.toJson());
      expect(restored.participants, isEmpty);
    });
  });
}
