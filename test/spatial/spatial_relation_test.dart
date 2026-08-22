import 'package:build_engine/build_engine.dart';
import 'package:test/test.dart';

void main() {
  group('Above / Below', () {
    test('Above holds when a is exactly one row above b, same column', () {
      expect(
        const Above().holds(const Position(0, 1), const Position(1, 1)),
        isTrue,
      );
    });

    test('Above does not hold in the reverse direction', () {
      expect(
        const Above().holds(const Position(1, 1), const Position(0, 1)),
        isFalse,
      );
    });

    test('Below holds when a is exactly one row below b, same column', () {
      expect(
        const Below().holds(const Position(1, 1), const Position(0, 1)),
        isTrue,
      );
    });

    test('Above(a,b) and Below(b,a) agree', () {
      const a = Position(0, 1);
      const b = Position(1, 1);
      expect(const Above().holds(a, b), equals(const Below().holds(b, a)));
    });
  });

  group('Left / Right', () {
    test('Left holds when a is exactly one column left of b, same row', () {
      expect(
        const Left().holds(const Position(2, 0), const Position(2, 1)),
        isTrue,
      );
    });

    test('Right holds when a is exactly one column right of b, same row',
        () {
      expect(
        const Right().holds(const Position(2, 1), const Position(2, 0)),
        isTrue,
      );
    });

    test('Left(a,b) and Right(b,a) agree', () {
      const a = Position(2, 0);
      const b = Position(2, 1);
      expect(const Left().holds(a, b), equals(const Right().holds(b, a)));
    });
  });

  group('Adjacent', () {
    test('holds for each of the four orthogonal neighbors', () {
      const center = Position(1, 1);
      expect(const Adjacent().holds(const Position(0, 1), center), isTrue);
      expect(const Adjacent().holds(const Position(2, 1), center), isTrue);
      expect(const Adjacent().holds(const Position(1, 0), center), isTrue);
      expect(const Adjacent().holds(const Position(1, 2), center), isTrue);
    });

    test('does not hold for a diagonal neighbor', () {
      expect(
        const Adjacent().holds(const Position(0, 0), const Position(1, 1)),
        isFalse,
      );
    });

    test('is symmetric', () {
      const a = Position(0, 1);
      const b = Position(1, 1);
      expect(
        const Adjacent().holds(a, b),
        equals(const Adjacent().holds(b, a)),
      );
    });

    test('does not hold for the same position', () {
      const a = Position(1, 1);
      expect(const Adjacent().holds(a, a), isFalse);
    });
  });

  group('SameRow / SameColumn', () {
    test('SameRow holds for two positions in the same row', () {
      expect(
        const SameRow().holds(const Position(2, 0), const Position(2, 5)),
        isTrue,
      );
    });

    test('SameRow does not hold for different rows', () {
      expect(
        const SameRow().holds(const Position(2, 0), const Position(3, 0)),
        isFalse,
      );
    });

    test('SameColumn holds for two positions in the same column', () {
      expect(
        const SameColumn().holds(const Position(0, 4), const Position(5, 4)),
        isTrue,
      );
    });

    test('SameColumn does not hold for different columns', () {
      expect(
        const SameColumn().holds(const Position(0, 4), const Position(0, 5)),
        isFalse,
      );
    });
  });

  group('distance', () {
    test('is the Manhattan distance between two positions', () {
      expect(distance(const Position(0, 0), const Position(3, 4)), equals(7));
    });

    test('is zero for the same position', () {
      expect(distance(const Position(2, 2), const Position(2, 2)), equals(0));
    });

    test('matches adjacency: distance 1 means orthogonally adjacent', () {
      const a = Position(1, 1);
      const b = Position(1, 2);
      expect(distance(a, b), equals(1));
      expect(const Adjacent().holds(a, b), isTrue);
    });
  });
}
