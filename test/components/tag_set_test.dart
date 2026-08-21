import 'package:build_engine/build_engine.dart';
import 'package:test/test.dart';

void main() {
  group('TagSet', () {
    test('stores the given tags', () {
      final tagSet = TagSet({'fire', 'dragon'});
      expect(tagSet.tags, equals({'fire', 'dragon'}));
    });

    test('tags set is unmodifiable', () {
      final tagSet = TagSet({'fire'});
      expect(() => tagSet.tags.add('ice'), throwsUnsupportedError);
    });
  });
}
