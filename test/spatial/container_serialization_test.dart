import 'package:build_engine/build_engine.dart';
import 'package:test/test.dart';

void main() {
  group('Container serialization', () {
    test('round-trips a grid container with a placed item', () {
      final container = Container.grid(3, 3);
      container.place(
        const EntityId(1),
        const SlotId('0,0'),
        size: const ItemSize(2, 1),
      );

      final restored = Container.fromJson(container.toJson());

      expect(restored.itemAt(const SlotId('0,0')), equals(const EntityId(1)));
      expect(restored.itemAt(const SlotId('0,1')), equals(const EntityId(1)));
      expect(restored.contains(const EntityId(1)), isTrue);
      expect(restored.positionOf(const EntityId(1)), equals(const Position(0, 0)));
    });

    test('round-trips a named-slot container with a placed item', () {
      final container = Container.namedSlots(['head', 'weapon']);
      container.place(const EntityId(1), const SlotId('head'));

      final restored = Container.fromJson(container.toJson());

      expect(restored.itemAt(const SlotId('head')), equals(const EntityId(1)));
      expect(restored.hasSlot(const SlotId('weapon')), isTrue);
      expect(restored.itemAt(const SlotId('weapon')), isNull);
    });

    test('round-trips rotation', () {
      final container = Container.grid(3, 3);
      container.place(
        const EntityId(1),
        const SlotId('0,0'),
        size: const ItemSize(2, 1),
        rotation: Rotation.deg90,
      );

      final restored = Container.fromJson(container.toJson());

      expect(restored.itemAt(const SlotId('0,0')), equals(const EntityId(1)));
      expect(restored.itemAt(const SlotId('1,0')), equals(const EntityId(1)));
      expect(restored.itemAt(const SlotId('0,1')), isNull);
    });

    test('round-trips an empty container', () {
      final container = Container.grid(2, 2);

      final restored = Container.fromJson(container.toJson());

      expect(restored.hasSlot(const SlotId('0,0')), isTrue);
      expect(restored.hasSlot(const SlotId('1,1')), isTrue);
      expect(restored.contains(const EntityId(1)), isFalse);
    });
  });
}
