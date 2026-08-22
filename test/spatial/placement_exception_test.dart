import 'package:build_engine/build_engine.dart';
import 'package:test/test.dart';

void main() {
  group('InvalidPlacementException', () {
    test('stores the failed rule names', () {
      const exception =
          InvalidPlacementException(['WithinBounds', 'NoCollision']);
      expect(exception.failedRules, equals(['WithinBounds', 'NoCollision']));
    });

    test('toString names the failed rules', () {
      const exception = InvalidPlacementException(['WithinBounds']);
      expect(exception.toString(), contains('WithinBounds'));
    });
  });
}
