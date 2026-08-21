import 'package:build_engine/build_engine.dart';
import 'package:test/test.dart';

void main() {
  group('StatComponent', () {
    test('stores named stats', () {
      final stats = StatComponent({'strength': 12});
      expect(stats.stats['strength'], equals(12));
    });

    test('stats map is unmodifiable', () {
      final stats = StatComponent({'strength': 12});
      expect(() => stats.stats['strength'] = 1, throwsUnsupportedError);
    });
  });
}
