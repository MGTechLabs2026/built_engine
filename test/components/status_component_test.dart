import 'package:build_engine/build_engine.dart';
import 'package:test/test.dart';

void main() {
  group('StatusComponent', () {
    test('stores active statuses', () {
      final status = StatusComponent({'burning'});
      expect(status.activeStatuses, equals({'burning'}));
    });

    test('activeStatuses set is unmodifiable', () {
      final status = StatusComponent({'burning'});
      expect(() => status.activeStatuses.add('frozen'), throwsUnsupportedError);
    });
  });
}
