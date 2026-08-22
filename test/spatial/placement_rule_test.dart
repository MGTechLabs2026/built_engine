import 'package:build_engine/build_engine.dart';
import 'package:test/test.dart';

class _FakeContainer implements ContainerView {
  _FakeContainer(this._slots, this._occupants);

  final Set<SlotId> _slots;
  final Map<SlotId, EntityId> _occupants;

  @override
  bool hasSlot(SlotId id) => _slots.contains(id);

  @override
  EntityId? itemAt(SlotId id) => _occupants[id];
}

void main() {
  group('WithinBounds', () {
    test('is satisfied when every slot in the footprint exists', () {
      final container =
          _FakeContainer({const SlotId('a'), const SlotId('b')}, {});
      expect(
        const WithinBounds().isSatisfied(
          container,
          const EntityId(1),
          {const SlotId('a'), const SlotId('b')},
        ),
        isTrue,
      );
    });

    test('is not satisfied when a slot in the footprint does not exist', () {
      final container = _FakeContainer({const SlotId('a')}, {});
      expect(
        const WithinBounds().isSatisfied(
          container,
          const EntityId(1),
          {const SlotId('a'), const SlotId('missing')},
        ),
        isFalse,
      );
    });
  });

  group('NoCollision', () {
    test('is satisfied when every slot in the footprint is empty', () {
      final container = _FakeContainer({const SlotId('a')}, {});
      expect(
        const NoCollision().isSatisfied(
          container,
          const EntityId(1),
          {const SlotId('a')},
        ),
        isTrue,
      );
    });

    test('is not satisfied when a slot is occupied by a different item', () {
      final container = _FakeContainer(
        {const SlotId('a')},
        {const SlotId('a'): const EntityId(2)},
      );
      expect(
        const NoCollision().isSatisfied(
          container,
          const EntityId(1),
          {const SlotId('a')},
        ),
        isFalse,
      );
    });

    test(
        'is satisfied when a slot is occupied by the item itself '
        '(re-validating a move)', () {
      final container = _FakeContainer(
        {const SlotId('a')},
        {const SlotId('a'): const EntityId(1)},
      );
      expect(
        const NoCollision().isSatisfied(
          container,
          const EntityId(1),
          {const SlotId('a')},
        ),
        isTrue,
      );
    });
  });
}
