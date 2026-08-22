import 'package:build_engine/build_engine.dart';
import 'package:test/test.dart';

void main() {
  group('SlotId', () {
    test('two ids with the same id are equal', () {
      expect(const SlotId('head'), equals(const SlotId('head')));
    });

    test('ids with different values are not equal', () {
      expect(const SlotId('head'), isNot(equals(const SlotId('weapon'))));
    });

    test('equal ids have equal hashCodes', () {
      expect(const SlotId('x').hashCode, equals(const SlotId('x').hashCode));
    });
  });

  group('Slot', () {
    test('stores its id and position', () {
      const slot = Slot(SlotId('0,0'), position: Position(0, 0));
      expect(slot.id, equals(const SlotId('0,0')));
      expect(slot.position, equals(const Position(0, 0)));
    });

    test('position defaults to null', () {
      const slot = Slot(SlotId('head'));
      expect(slot.position, isNull);
    });
  });
}
