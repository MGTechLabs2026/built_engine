import 'package:build_engine/build_engine.dart';
import 'package:test/test.dart';

void main() {
  test('registerBuiltInContentFactories registers every built-in effect, '
      'condition, and trigger', () {
    final registry = ContentRegistry();

    final definition = registry.load({
      'id': 'uses_every_built_in',
      'type': 'test',
      'conditions': [
        {'type': 'hasTag', 'tag': 'x'},
      ],
      'effects': [
        {'type': 'damage', 'amount': 1},
      ],
    });
    expect(definition.conditions.single, isA<HasTag>());
    expect(definition.effects.single, isA<Damage>());

    final rule = registry.loadRule({
      'id': 'uses_every_built_in_trigger',
      'trigger': 'EntityDamaged',
      'effects': [
        {'type': 'heal', 'amount': 1},
      ],
    });
    expect(rule.rule.trigger, equals(EntityDamaged));
  });

  test('a fresh ContentRegistry always has the built-ins registered '
      'independently', () {
    final a = ContentRegistry();
    final b = ContentRegistry();

    a.load({
      'id': 'a',
      'type': 'test',
      'effects': [
        {'type': 'damage', 'amount': 1},
      ],
    });
    b.load({
      'id': 'b',
      'type': 'test',
      'effects': [
        {'type': 'damage', 'amount': 1},
      ],
    });

    expect(a.find('b'), isNull);
    expect(b.find('a'), isNull);
  });
}
