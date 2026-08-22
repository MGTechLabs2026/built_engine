import 'package:build_engine/build_engine.dart';
import 'package:test/test.dart';

void main() {
  group('Position', () {
    test('two positions with the same row/col are equal', () {
      expect(const Position(1, 2), equals(const Position(1, 2)));
    });

    test('positions with different row or col are not equal', () {
      expect(const Position(1, 2), isNot(equals(const Position(1, 3))));
      expect(const Position(1, 2), isNot(equals(const Position(2, 2))));
    });

    test('equal positions have equal hashCodes', () {
      expect(
        const Position(1, 2).hashCode,
        equals(const Position(1, 2).hashCode),
      );
    });
  });

  group('ItemSize', () {
    test('stores width and height', () {
      const size = ItemSize(2, 3);
      expect(size.width, equals(2));
      expect(size.height, equals(3));
    });

    test('rotated at 0 and 180 degrees keeps the same dimensions', () {
      const size = ItemSize(2, 1);
      expect(size.rotated(Rotation.deg0), equals(const ItemSize(2, 1)));
      expect(size.rotated(Rotation.deg180), equals(const ItemSize(2, 1)));
    });

    test('rotated at 90 and 270 degrees swaps width and height', () {
      const size = ItemSize(2, 1);
      expect(size.rotated(Rotation.deg90), equals(const ItemSize(1, 2)));
      expect(size.rotated(Rotation.deg270), equals(const ItemSize(1, 2)));
    });

    test('equal sizes are equal', () {
      expect(const ItemSize(2, 3), equals(const ItemSize(2, 3)));
    });
  });
}
