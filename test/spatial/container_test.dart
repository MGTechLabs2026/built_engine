import 'package:build_engine/build_engine.dart';
import 'package:test/test.dart';

class _AlwaysReject implements PlacementRule {
  @override
  bool isSatisfied(
    ContainerView container,
    EntityId item,
    Set<SlotId> footprint,
  ) =>
      false;
}

void main() {
  group('Container.grid construction', () {
    test('creates one slot per cell with a position', () {
      final container = Container.grid(2, 2);
      expect(container.hasSlot(const SlotId('0,0')), isTrue);
      expect(container.hasSlot(const SlotId('1,1')), isTrue);
      expect(container.hasSlot(const SlotId('2,0')), isFalse);
    });
  });

  group('Container.namedSlots construction', () {
    test('creates one slot per given id, with no position', () {
      final container = Container.namedSlots(['head', 'weapon']);
      expect(container.hasSlot(const SlotId('head')), isTrue);
      expect(container.hasSlot(const SlotId('weapon')), isTrue);
      expect(container.hasSlot(const SlotId('feet')), isFalse);
    });
  });

  group('placement', () {
    test('places a 1x1 item on a grid container', () {
      final container = Container.grid(3, 3);
      const item = EntityId(1);

      container.place(item, const SlotId('0,0'));

      expect(container.itemAt(const SlotId('0,0')), equals(item));
      expect(container.contains(item), isTrue);
      expect(container.positionOf(item), equals(const Position(0, 0)));
    });

    test('places a multi-cell item, occupying its full footprint', () {
      final container = Container.grid(3, 3);
      const item = EntityId(1);

      container.place(item, const SlotId('0,0'), size: const ItemSize(2, 1));

      expect(container.itemAt(const SlotId('0,0')), equals(item));
      expect(container.itemAt(const SlotId('0,1')), equals(item));
      expect(container.itemAt(const SlotId('1,0')), isNull);
    });

    test('places an item on a named slot', () {
      final container = Container.namedSlots(['head', 'weapon']);
      const item = EntityId(1);

      container.place(item, const SlotId('head'));

      expect(container.itemAt(const SlotId('head')), equals(item));
      expect(container.positionOf(item), isNull);
    });

    test('canPlace returns true without mutating the container', () {
      final container = Container.grid(3, 3);
      const item = EntityId(1);

      expect(container.canPlace(item, const SlotId('0,0')), isTrue);
      expect(container.contains(item), isFalse);
    });

    test('place throws InvalidPlacementException when canPlace would be '
        'false', () {
      final container = Container.grid(1, 1);
      const item = EntityId(1);

      expect(
        () => container.place(
          item,
          const SlotId('0,0'),
          size: const ItemSize(2, 2),
        ),
        throwsA(isA<InvalidPlacementException>()),
      );
    });

    test('an extra PlacementRule can reject a placement canPlace would '
        'otherwise allow', () {
      final container = Container.grid(3, 3);
      const item = EntityId(1);

      expect(
        container.canPlace(
          item,
          const SlotId('0,0'),
          extraRules: [_AlwaysReject()],
        ),
        isFalse,
      );
    });
  });

  group('collision', () {
    test('rejects placing a second item overlapping the first', () {
      final container = Container.grid(3, 3);
      container.place(
        const EntityId(1),
        const SlotId('0,0'),
        size: const ItemSize(2, 1),
      );

      expect(
        container.canPlace(const EntityId(2), const SlotId('0,1')),
        isFalse,
      );
    });

    test('allows placing a second item that does not overlap the first', () {
      final container = Container.grid(3, 3);
      container.place(
        const EntityId(1),
        const SlotId('0,0'),
        size: const ItemSize(2, 1),
      );

      expect(
        container.canPlace(const EntityId(2), const SlotId('1,0')),
        isTrue,
      );
    });
  });

  group('movement', () {
    test('moves an item to a new position', () {
      final container = Container.grid(3, 3);
      const item = EntityId(1);
      container.place(item, const SlotId('0,0'));

      container.move(item, const SlotId('2,2'));

      expect(container.itemAt(const SlotId('0,0')), isNull);
      expect(container.itemAt(const SlotId('2,2')), equals(item));
      expect(container.positionOf(item), equals(const Position(2, 2)));
    });

    test('a rejected move leaves the item at its original position '
        'unchanged', () {
      final container = Container.grid(3, 3);
      const item = EntityId(1);
      const blocker = EntityId(2);
      container.place(item, const SlotId('0,0'));
      container.place(blocker, const SlotId('2,2'));

      expect(
        () => container.move(item, const SlotId('2,2')),
        throwsA(isA<InvalidPlacementException>()),
      );
      expect(container.itemAt(const SlotId('0,0')), equals(item));
      expect(container.positionOf(item), equals(const Position(0, 0)));
    });

    test('moving an item to overlap its own current footprint succeeds', () {
      final container = Container.grid(3, 3);
      const item = EntityId(1);
      container.place(item, const SlotId('0,0'), size: const ItemSize(2, 1));

      container.move(item, const SlotId('0,1'), size: const ItemSize(2, 1));

      expect(container.itemAt(const SlotId('0,1')), equals(item));
      expect(container.itemAt(const SlotId('0,2')), equals(item));
      expect(container.itemAt(const SlotId('0,0')), isNull);
    });
  });

  group('removal', () {
    test('removes an item, freeing every slot it occupied', () {
      final container = Container.grid(3, 3);
      const item = EntityId(1);
      container.place(item, const SlotId('0,0'), size: const ItemSize(2, 1));

      container.remove(item);

      expect(container.itemAt(const SlotId('0,0')), isNull);
      expect(container.itemAt(const SlotId('0,1')), isNull);
      expect(container.contains(item), isFalse);
    });

    test('removing an item not in the container is a no-op', () {
      final container = Container.grid(3, 3);
      expect(() => container.remove(const EntityId(1)), returnsNormally);
    });
  });

  group('adjacency (relatesTo)', () {
    test('relatesTo reports Adjacent between two items in neighboring '
        'cells', () {
      final container = Container.grid(3, 3);
      container.place(const EntityId(1), const SlotId('1,1'));
      container.place(const EntityId(2), const SlotId('1,2'));

      expect(
        container.relatesTo(
          const Adjacent(),
          const EntityId(1),
          const EntityId(2),
        ),
        isTrue,
      );
    });

    test('relatesTo is false when one item has no position', () {
      final container = Container.namedSlots(['head', 'weapon']);
      container.place(const EntityId(1), const SlotId('head'));
      container.place(const EntityId(2), const SlotId('weapon'));

      expect(
        container.relatesTo(
          const Adjacent(),
          const EntityId(1),
          const EntityId(2),
        ),
        isFalse,
      );
    });
  });

  group('rotation', () {
    test('a rotated item occupies the swapped footprint', () {
      final container = Container.grid(3, 3);
      const item = EntityId(1);

      container.place(
        item,
        const SlotId('0,0'),
        size: const ItemSize(2, 1),
        rotation: Rotation.deg90,
      );

      // Effective size after 90 degrees: (1, 2) — 1 column, 2 rows.
      expect(container.itemAt(const SlotId('0,0')), equals(item));
      expect(container.itemAt(const SlotId('1,0')), equals(item));
      expect(container.itemAt(const SlotId('0,1')), isNull);
    });
  });

  group('boundaries', () {
    test('rejects a placement extending past the grid edge', () {
      final container = Container.grid(2, 2);
      expect(
        container.canPlace(
          const EntityId(1),
          const SlotId('1,1'),
          size: const ItemSize(2, 2),
        ),
        isFalse,
      );
    });

    test('rejects an unsupported size on a named (position-less) slot', () {
      final container = Container.namedSlots(['head']);
      expect(
        container.canPlace(
          const EntityId(1),
          const SlotId('head'),
          size: const ItemSize(2, 1),
        ),
        isFalse,
      );
    });

    test('rejects placing on a slot id that does not exist', () {
      final container = Container.grid(2, 2);
      expect(
        container.canPlace(const EntityId(1), const SlotId('9,9')),
        isFalse,
      );
    });
  });
}
