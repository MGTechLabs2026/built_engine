import 'package:build_engine/build_engine.dart';
import 'package:test/test.dart';

void main() {
  group('RngService', () {
    test('the same seed produces the same sequence of doubles', () {
      final a = RngService(42);
      final b = RngService(42);

      final valuesA = List.generate(5, (_) => a.nextDouble());
      final valuesB = List.generate(5, (_) => b.nextDouble());

      expect(valuesA, equals(valuesB));
    });

    test('different seeds produce different first values', () {
      final a = RngService(1);
      final b = RngService(2);

      expect(a.nextDouble(), isNot(equals(b.nextDouble())));
    });

    test('nextInt stays within [0, max)', () {
      final rng = RngService(1);

      for (var i = 0; i < 100; i++) {
        final value = rng.nextInt(10);
        expect(value, greaterThanOrEqualTo(0));
        expect(value, lessThan(10));
      }
    });

    test('chance(0.0) is always false', () {
      final rng = RngService(1);

      for (var i = 0; i < 20; i++) {
        expect(rng.chance(0.0), isFalse);
      }
    });

    test('chance(1.0) is always true', () {
      final rng = RngService(1);

      for (var i = 0; i < 20; i++) {
        expect(rng.chance(1.0), isTrue);
      }
    });
  });
}
