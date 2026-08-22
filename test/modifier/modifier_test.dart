import 'package:build_engine/build_engine.dart';
import 'package:test/test.dart';

void main() {
  group('ModifierSource', () {
    test('two sources with the same id are equal', () {
      expect(const ModifierSource('item_a'), equals(const ModifierSource('item_a')));
    });

    test('sources with different ids are not equal', () {
      expect(
        const ModifierSource('item_a'),
        isNot(equals(const ModifierSource('item_b'))),
      );
    });

    test('equal sources have equal hashCodes', () {
      expect(
        const ModifierSource('x').hashCode,
        equals(const ModifierSource('x').hashCode),
      );
    });
  });

  group('Modifier', () {
    test('stores all its fields', () {
      const modifier = Modifier(
        source: ModifierSource('item_a'),
        target: EntityId(1),
        stat: 'damage',
        operation: ModifierOperation.add,
        value: 5,
        priority: 2,
        duration: 3,
      );

      expect(modifier.source, equals(const ModifierSource('item_a')));
      expect(modifier.target, equals(const EntityId(1)));
      expect(modifier.stat, equals('damage'));
      expect(modifier.operation, equals(ModifierOperation.add));
      expect(modifier.value, equals(5));
      expect(modifier.priority, equals(2));
      expect(modifier.duration, equals(3));
      expect(modifier.condition, isNull);
    });

    test('priority defaults to 0 and duration/condition default to null', () {
      const modifier = Modifier(
        source: ModifierSource('item_a'),
        target: EntityId(1),
        stat: 'damage',
        operation: ModifierOperation.add,
        value: 5,
      );

      expect(modifier.priority, equals(0));
      expect(modifier.duration, isNull);
      expect(modifier.condition, isNull);
    });
  });
}
