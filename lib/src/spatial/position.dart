/// A grid coordinate within a `Container`. Row 0 is the top; row increases
/// downward (standard screen/array convention).
class Position {
  const Position(this.row, this.col);

  final int row;
  final int col;

  @override
  bool operator ==(Object other) =>
      other is Position && other.row == row && other.col == col;

  @override
  int get hashCode => Object.hash(row, col);

  @override
  String toString() => 'Position($row, $col)';
}

/// An item's footprint size, in grid cells.
class ItemSize {
  const ItemSize(this.width, this.height);

  final int width;
  final int height;

  /// The effective size after applying [rotation] — width/height swap on
  /// a 90 or 270 degree rotation, unchanged on 0/180. Only the item's
  /// bounding-box dimensions matter here (an axis-aligned rectangle), not
  /// per-cell shape.
  ItemSize rotated(Rotation rotation) {
    switch (rotation) {
      case Rotation.deg0:
      case Rotation.deg180:
        return this;
      case Rotation.deg90:
      case Rotation.deg270:
        return ItemSize(height, width);
    }
  }

  @override
  bool operator ==(Object other) =>
      other is ItemSize && other.width == width && other.height == height;

  @override
  int get hashCode => Object.hash(width, height);

  @override
  String toString() => 'ItemSize($width x $height)';
}

/// How many quarter-turns clockwise an item is rotated.
enum Rotation { deg0, deg90, deg180, deg270 }
