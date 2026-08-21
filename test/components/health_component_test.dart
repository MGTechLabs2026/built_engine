import 'package:build_engine/build_engine.dart';
import 'package:test/test.dart';

void main() {
  group('HealthComponent', () {
    test('stores current and max', () {
      const health = HealthComponent(current: 80, max: 100);
      expect(health.current, equals(80));
      expect(health.max, equals(100));
    });
  });
}
