import 'package:build_engine/build_engine.dart';
import 'package:build_engine/martial_arts_plugin.dart';
import 'package:test/test.dart';

void main() {
  group('MartialLoadoutComponent', () {
    test('stores the equipped item ids', () {
      const component = MartialLoadoutComponent(
        equippedItems: [EntityId(1), EntityId(2)],
      );
      expect(
        component.equippedItems,
        equals([const EntityId(1), const EntityId(2)]),
      );
    });

    test('round-trips through toJson/fromJson', () {
      const component = MartialLoadoutComponent(
        equippedItems: [EntityId(3), EntityId(4)],
      );
      final restored = MartialLoadoutComponent.fromJson(component.toJson());
      expect(restored.equippedItems, equals(component.equippedItems));
    });

    test('round-trips an empty loadout', () {
      const component = MartialLoadoutComponent(equippedItems: []);
      final restored = MartialLoadoutComponent.fromJson(component.toJson());
      expect(restored.equippedItems, isEmpty);
    });
  });
}
