import 'position.dart';

/// A boolean relation between two positions. Combinators (`and`/`or`/
/// `not`) are deliberately not provided — unlike `Query`, composability
/// wasn't requested here and there's no concrete use case yet.
abstract class SpatialRelation {
  bool holds(Position a, Position b);
}

/// Whether [a] is exactly one row above [b], in the same column. Row 0 is
/// the top; row increases downward.
class Above implements SpatialRelation {
  const Above();

  @override
  bool holds(Position a, Position b) => a.row == b.row - 1 && a.col == b.col;
}

/// Whether [a] is exactly one row below [b], in the same column.
class Below implements SpatialRelation {
  const Below();

  @override
  bool holds(Position a, Position b) => a.row == b.row + 1 && a.col == b.col;
}

/// Whether [a] is exactly one column to the left of [b], in the same row.
class Left implements SpatialRelation {
  const Left();

  @override
  bool holds(Position a, Position b) => a.col == b.col - 1 && a.row == b.row;
}

/// Whether [a] is exactly one column to the right of [b], in the same row.
class Right implements SpatialRelation {
  const Right();

  @override
  bool holds(Position a, Position b) => a.col == b.col + 1 && a.row == b.row;
}

/// Whether [a] and [b] are orthogonally adjacent — one of [Above],
/// [Below], [Left], or [Right] — never diagonal.
class Adjacent implements SpatialRelation {
  const Adjacent();

  @override
  bool holds(Position a, Position b) =>
      const Above().holds(a, b) ||
      const Below().holds(a, b) ||
      const Left().holds(a, b) ||
      const Right().holds(a, b);
}

/// Whether [a] and [b] are in the same row.
class SameRow implements SpatialRelation {
  const SameRow();

  @override
  bool holds(Position a, Position b) => a.row == b.row;
}

/// Whether [a] and [b] are in the same column.
class SameColumn implements SpatialRelation {
  const SameColumn();

  @override
  bool holds(Position a, Position b) => a.col == b.col;
}

/// Manhattan distance between [a] and [b] — not a boolean relation
/// (unlike the seven [SpatialRelation]s above), since it isn't one.
int distance(Position a, Position b) =>
    (a.row - b.row).abs() + (a.col - b.col).abs();
