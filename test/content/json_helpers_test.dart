import 'package:build_engine/build_engine.dart';
import 'package:test/test.dart';

void main() {
  group('ContentField.requireString', () {
    test('returns the string when present and non-empty', () {
      expect(
          ContentField.requireString({'tag': 'fire'}, 'tag'), equals('fire'));
    });

    test('throws when missing', () {
      expect(() => ContentField.requireString({}, 'tag'),
          throwsA(isA<ContentFieldException>()));
    });

    test('throws when empty', () {
      expect(() => ContentField.requireString({'tag': ''}, 'tag'),
          throwsA(isA<ContentFieldException>()));
    });

    test('throws when wrong type', () {
      expect(() => ContentField.requireString({'tag': 5}, 'tag'),
          throwsA(isA<ContentFieldException>()));
    });
  });

  group('ContentField.requireNum', () {
    test('returns the num when present', () {
      expect(ContentField.requireNum({'amount': 15}, 'amount'), equals(15));
    });

    test('throws when missing or wrong type', () {
      expect(() => ContentField.requireNum({}, 'amount'),
          throwsA(isA<ContentFieldException>()));
      expect(() => ContentField.requireNum({'amount': 'x'}, 'amount'),
          throwsA(isA<ContentFieldException>()));
    });
  });

  group('ContentField.requireMap', () {
    test('returns a String-keyed copy when present', () {
      final result = ContentField.requireMap(
          {'cost': {'resource': 'qi'}}, 'cost');
      expect(result, equals({'resource': 'qi'}));
    });

    test('throws when missing or wrong type', () {
      expect(() => ContentField.requireMap({}, 'cost'),
          throwsA(isA<ContentFieldException>()));
      expect(() => ContentField.requireMap({'cost': 'x'}, 'cost'),
          throwsA(isA<ContentFieldException>()));
    });
  });

  group('ContentField.optionalMapList', () {
    test('returns an empty list when absent', () {
      expect(ContentField.optionalMapList({}, 'effects'), isEmpty);
    });

    test('returns the parsed list when present', () {
      final result = ContentField.optionalMapList({
        'effects': [
          {'type': 'damage', 'amount': 15},
        ],
      }, 'effects');
      expect(
          result,
          equals([
            {'type': 'damage', 'amount': 15},
          ]));
    });

    test('throws when an entry is not an object', () {
      expect(
        () => ContentField.optionalMapList({
          'effects': [1],
        }, 'effects'),
        throwsA(isA<ContentFieldException>()),
      );
    });

    test('throws when the field itself is not an array', () {
      expect(
        () => ContentField.optionalMapList({'effects': 'x'}, 'effects'),
        throwsA(isA<ContentFieldException>()),
      );
    });
  });

  group('ContentField.optionalStringSet', () {
    test('returns an empty set when absent', () {
      expect(ContentField.optionalStringSet({}, 'tags'), isEmpty);
    });

    test('returns the parsed set when present', () {
      expect(
        ContentField.optionalStringSet({
          'tags': ['fire', 'dragon'],
        }, 'tags'),
        equals({'fire', 'dragon'}),
      );
    });

    test('throws when an entry is not a string', () {
      expect(
        () => ContentField.optionalStringSet({
          'tags': [1],
        }, 'tags'),
        throwsA(isA<ContentFieldException>()),
      );
    });
  });
}
