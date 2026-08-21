import 'package:build_engine/build_engine.dart';
import 'package:test/test.dart';

void main() {
  group('ResourceComponent', () {
    test('stores named resources', () {
      final resources = ResourceComponent({'stamina': 50});
      expect(resources.resources['stamina'], equals(50));
    });

    test('resources map is unmodifiable', () {
      final resources = ResourceComponent({'stamina': 50});
      expect(() => resources.resources['stamina'] = 10, throwsUnsupportedError);
    });
  });
}
