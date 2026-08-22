import 'package:build_engine/build_engine.dart';
import 'package:test/test.dart';

void main() {
  test('grid and named-slot containers work through identical machinery', () {
    const sword = EntityId(1);
    const shield = EntityId(2);
    const helmet = EntityId(3);

    // --- Grid-shaped container ---
    final grid = Container.grid(4, 4);

    grid.place(sword, const SlotId('0,0'), size: const ItemSize(2, 1));
    grid.place(shield, const SlotId('1,0'));

    expect(grid.itemAt(const SlotId('0,0')), equals(sword));
    expect(grid.itemAt(const SlotId('0,1')), equals(sword));
    expect(grid.contains(shield), isTrue);

    // Collision: sword's second footprint cell can't take a third item.
    expect(grid.canPlace(helmet, const SlotId('0,1')), isFalse);

    // Adjacency: relatesTo compares anchor positions, not full footprints
    // — sword's anchor (0,0) and shield's anchor (1,0) are one row apart,
    // same column, so they ARE adjacent (unlike sword's non-anchor
    // footprint cell (0,1), which relatesTo never looks at).
    expect(grid.relatesTo(const Adjacent(), sword, shield), isTrue);
    expect(distance(grid.positionOf(sword)!, grid.positionOf(shield)!), equals(1));

    // Movement.
    grid.move(sword, const SlotId('2,0'), size: const ItemSize(2, 1));
    expect(grid.itemAt(const SlotId('0,0')), isNull);
    expect(grid.itemAt(const SlotId('2,0')), equals(sword));

    // Removal.
    grid.remove(shield);
    expect(grid.contains(shield), isFalse);
    expect(grid.itemAt(const SlotId('1,0')), isNull);

    // Serialization round-trip.
    final restoredGrid = Container.fromJson(grid.toJson());
    expect(restoredGrid.itemAt(const SlotId('2,0')), equals(sword));
    expect(restoredGrid.itemAt(const SlotId('2,1')), equals(sword));

    // --- Named-slot container: same machinery, no shape-specific code ---
    final board = Container.namedSlots(['head', 'weapon', 'feet']);

    board.place(helmet, const SlotId('head'));
    board.place(sword, const SlotId('weapon'));

    expect(board.itemAt(const SlotId('head')), equals(helmet));
    expect(board.contains(sword), isTrue);

    // A named-slot container has no positions, so relatesTo is always
    // false, not a crash — well-defined, not an error case.
    expect(board.relatesTo(const Adjacent(), helmet, sword), isFalse);

    // The same NoCollision/WithinBounds rules apply: an oversized item
    // (no position to expand into) is rejected exactly like an
    // out-of-bounds grid placement.
    expect(
      board.canPlace(shield, const SlotId('feet'), size: const ItemSize(2, 1)),
      isFalse,
    );

    // Movement and removal work identically.
    board.move(sword, const SlotId('feet'));
    expect(board.itemAt(const SlotId('weapon')), isNull);
    expect(board.itemAt(const SlotId('feet')), equals(sword));

    board.remove(helmet);
    expect(board.contains(helmet), isFalse);

    // Serialization round-trip.
    final restoredBoard = Container.fromJson(board.toJson());
    expect(restoredBoard.itemAt(const SlotId('feet')), equals(sword));
    expect(restoredBoard.hasSlot(const SlotId('head')), isTrue);
    expect(restoredBoard.contains(helmet), isFalse);
  });
}
