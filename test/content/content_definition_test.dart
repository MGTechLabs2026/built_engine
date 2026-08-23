import 'package:build_engine/build_engine.dart';
import 'package:test/test.dart';

void main() {
  group('ContentDefinition', () {
    test('holds every field as given', () {
      const definition = ContentDefinition(
        id: 'dragon_palm',
        type: 'skill',
        tags: {'fire', 'dragon'},
        costEffects: [],
        conditions: [],
        effects: [],
        requires: {'style:shaolin'},
        extra: {'flavorText': 'x'},
        raw: {'id': 'dragon_palm'},
      );

      expect(definition.id, equals('dragon_palm'));
      expect(definition.type, equals('skill'));
      expect(definition.tags, equals({'fire', 'dragon'}));
      expect(definition.requires, equals({'style:shaolin'}));
      expect(definition.extra['flavorText'], equals('x'));
      expect(definition.raw['id'], equals('dragon_palm'));
    });
  });

  group('RuleDefinition', () {
    test('holds id, rule, and raw', () {
      const rule = Rule(trigger: Object, effects: []);
      const definition =
          RuleDefinition(id: 'r1', rule: rule, raw: {'id': 'r1'});

      expect(definition.id, equals('r1'));
      expect(definition.rule, same(rule));
      expect(definition.raw['id'], equals('r1'));
    });
  });
}
