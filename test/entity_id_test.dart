import 'package:build_engine/build_engine.dart';
import 'package:test/test.dart';

void main() {
  group('EntityId', () {
    test('two ids with the same value are equal', () {
      expect(const EntityId(1), equals(const EntityId(1)));
    });

    test('ids with different values are not equal', () {
      expect(const EntityId(1), isNot(equals(const EntityId(2))));
    });

    test('equal ids have equal hashCodes', () {
      expect(const EntityId(7).hashCode, equals(const EntityId(7).hashCode));
    });

    test('compareTo orders by value', () {
      expect(const EntityId(1).compareTo(const EntityId(2)), lessThan(0));
      expect(const EntityId(2).compareTo(const EntityId(1)), greaterThan(0));
      expect(const EntityId(2).compareTo(const EntityId(2)), equals(0));
    });

    test('exposes its underlying value', () {
      expect(const EntityId(42).value, equals(42));
    });

    test('toString is human-readable', () {
      expect(const EntityId(3).toString(), contains('3'));
    });
  });
}
