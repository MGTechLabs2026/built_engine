import 'package:build_engine/build_engine.dart';
import 'package:test/test.dart';

void main() {
  group('ModifierCollection', () {
    test('activeModifiersFor returns modifiers matching target and stat', () {
      final collection = ModifierCollection();
      const source = ModifierSource('item_a');
      const target = EntityId(1);
      const other = EntityId(2);
      collection.add(Modifier(
        source: source,
        target: target,
        stat: 'damage',
        operation: ModifierOperation.add,
        value: 5,
      ));
      collection.add(Modifier(
        source: source,
        target: other,
        stat: 'damage',
        operation: ModifierOperation.add,
        value: 5,
      ));
      collection.add(Modifier(
        source: source,
        target: target,
        stat: 'armor',
        operation: ModifierOperation.add,
        value: 5,
      ));

      final active =
          collection.activeModifiersFor(target, 'damage', ComponentStore());

      expect(active.length, equals(1));
      expect(active.single.target, equals(target));
      expect(active.single.stat, equals('damage'));
    });

    test('stacking: multiple modifiers on the same target+stat are all returned',
        () {
      final collection = ModifierCollection();
      const target = EntityId(1);
      collection.add(Modifier(
        source: const ModifierSource('a'),
        target: target,
        stat: 'damage',
        operation: ModifierOperation.add,
        value: 5,
      ));
      collection.add(Modifier(
        source: const ModifierSource('b'),
        target: target,
        stat: 'damage',
        operation: ModifierOperation.add,
        value: 3,
      ));

      final active =
          collection.activeModifiersFor(target, 'damage', ComponentStore());

      expect(active.length, equals(2));
    });

    test('removeBySource removes only modifiers from that source', () {
      final collection = ModifierCollection();
      const target = EntityId(1);
      const sourceA = ModifierSource('a');
      const sourceB = ModifierSource('b');
      collection.add(Modifier(
        source: sourceA,
        target: target,
        stat: 'damage',
        operation: ModifierOperation.add,
        value: 5,
      ));
      collection.add(Modifier(
        source: sourceB,
        target: target,
        stat: 'damage',
        operation: ModifierOperation.add,
        value: 3,
      ));

      collection.removeBySource(sourceA);
      final active =
          collection.activeModifiersFor(target, 'damage', ComponentStore());

      expect(active.length, equals(1));
      expect(active.single.source, equals(sourceB));
    });

    test('tick decrements duration and expires modifiers that reach zero', () {
      final collection = ModifierCollection();
      const target = EntityId(1);
      collection.add(Modifier(
        source: const ModifierSource('temp'),
        target: target,
        stat: 'damage',
        operation: ModifierOperation.add,
        value: 5,
        duration: 2,
      ));

      expect(
        collection.activeModifiersFor(target, 'damage', ComponentStore()).length,
        equals(1),
      );

      collection.tick();
      expect(
        collection.activeModifiersFor(target, 'damage', ComponentStore()).length,
        equals(1),
      );

      collection.tick();
      expect(
        collection.activeModifiersFor(target, 'damage', ComponentStore()).length,
        equals(0),
      );
    });

    test('tick does not affect permanent (duration: null) modifiers', () {
      final collection = ModifierCollection();
      const target = EntityId(1);
      collection.add(Modifier(
        source: const ModifierSource('permanent'),
        target: target,
        stat: 'damage',
        operation: ModifierOperation.add,
        value: 5,
      ));

      for (var i = 0; i < 10; i++) {
        collection.tick();
      }

      expect(
        collection.activeModifiersFor(target, 'damage', ComponentStore()).length,
        equals(1),
      );
    });

    test('conditional modifiers: only active when their condition matches', () {
      final collection = ModifierCollection();
      const target = EntityId(1);
      final components = ComponentStore();
      collection.add(Modifier(
        source: const ModifierSource('conditional'),
        target: target,
        stat: 'damage',
        operation: ModifierOperation.add,
        value: 10,
        condition: HasTagQuery('enraged'),
      ));

      expect(
        collection.activeModifiersFor(target, 'damage', components).length,
        equals(0),
      );

      components.add(target, TagSet({'enraged'}));

      expect(
        collection.activeModifiersFor(target, 'damage', components).length,
        equals(1),
      );
    });

    test('activeModifiersFor returns modifiers in registration order', () {
      final collection = ModifierCollection();
      const target = EntityId(1);
      final first = Modifier(
        source: const ModifierSource('first'),
        target: target,
        stat: 'damage',
        operation: ModifierOperation.override,
        value: 1,
      );
      final second = Modifier(
        source: const ModifierSource('second'),
        target: target,
        stat: 'damage',
        operation: ModifierOperation.override,
        value: 2,
      );
      collection.add(first);
      collection.add(second);

      final active =
          collection.activeModifiersFor(target, 'damage', ComponentStore()).toList();

      expect(active, equals([first, second]));
    });

    test('activeModifiersFor returns a snapshot, safe to iterate while mutating '
        'the collection', () {
      final collection = ModifierCollection();
      const target = EntityId(1);
      collection.add(Modifier(
        source: const ModifierSource('a'),
        target: target,
        stat: 'damage',
        operation: ModifierOperation.add,
        value: 5,
      ));
      collection.add(Modifier(
        source: const ModifierSource('b'),
        target: target,
        stat: 'damage',
        operation: ModifierOperation.add,
        value: 3,
      ));

      final snapshot =
          collection.activeModifiersFor(target, 'damage', ComponentStore());

      expect(
        () {
          for (final modifier in snapshot) {
            collection.removeBySource(modifier.source);
          }
        },
        returnsNormally,
      );
      expect(snapshot.length, equals(2));
    });
  });
}
