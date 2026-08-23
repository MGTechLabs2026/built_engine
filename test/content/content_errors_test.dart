import 'package:build_engine/build_engine.dart';
import 'package:test/test.dart';

void main() {
  group('content exceptions', () {
    test('ContentFieldException composes path and problem', () {
      final exception =
          ContentFieldException('amount', 'required num field missing');
      expect(exception, isA<ContentSystemException>());
      expect(
        exception.toString(),
        equals('amount — required num field missing'),
      );
    });

    test(
        'ContentValidationException names the definition and wraps the '
        'field error', () {
      final field = ContentFieldException(
          'effects[0].amount', 'required num field missing');
      final exception = ContentValidationException('dragon_palm', field);
      expect(exception.toString(), contains('dragon_palm'));
      expect(exception.toString(), contains('effects[0].amount'));
    });

    test('ContentDuplicateIdException names the id', () {
      final exception = ContentDuplicateIdException('dragon_palm');
      expect(exception.toString(), contains('dragon_palm'));
    });

    test('ContentDependencyException names both the definition and the '
        'missing id', () {
      final exception =
          ContentDependencyException('dragon_palm', 'style:shaolin');
      expect(exception.toString(), contains('dragon_palm'));
      expect(exception.toString(), contains('style:shaolin'));
    });

    test('ContentNotFoundException names the id', () {
      final exception = ContentNotFoundException('nonexistent');
      expect(exception.toString(), contains('nonexistent'));
    });

    test('UnknownContentFactoryException names the kind and key', () {
      final exception =
          UnknownContentFactoryException('effect', 'summonDragon');
      expect(exception.toString(), contains('effect'));
      expect(exception.toString(), contains('summonDragon'));
    });
  });
}
