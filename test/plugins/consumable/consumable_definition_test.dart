import 'package:build_engine/build_engine.dart';
import 'package:build_engine/consumable_plugin.dart';
import 'package:test/test.dart';

ContentDefinition _load(Map<String, dynamic> json) =>
    (ContentRegistry()..load(json)).get(json['id'] as String);

void main() {
  group('valid parses', () {
    test('heal → ConsumableHeal, target self', () {
      final d = consumableDefinitionFromContent(_load({
        'id': 'p', 'type': 'consumable', 'tags': <String>[],
        'charges': 2, 'priority': 8, 'effect': {'heal': 20},
      }));
      expect(d.charges, 2);
      expect(d.priority, 8);
      expect(d.target, ConsumableTarget.self);
      expect(d.effect, isA<ConsumableHeal>());
      expect((d.effect as ConsumableHeal).amount, 20);
    });

    test('attack → ConsumableAttack, target enemy; defaults apply', () {
      final d = consumableDefinitionFromContent(_load({
        'id': 'b', 'type': 'consumable', 'tags': <String>[],
        'effect': {'attack': {'damage': 15, 'stat': 'thrown'}},
      }));
      expect(d.charges, 1);
      expect(d.priority, 0);
      expect(d.target, ConsumableTarget.enemy);
      final e = d.effect as ConsumableAttack;
      expect(e.damage, 15);
      expect(e.stat, 'thrown');
    });

    test('grant → ConsumableGrantModifier, target self', () {
      final d = consumableDefinitionFromContent(_load({
        'id': 'g', 'type': 'consumable', 'tags': <String>[],
        'effect': {'grant': {'stat': 'thrown', 'op': 'add', 'value': 6}},
      }));
      final e = d.effect as ConsumableGrantModifier;
      expect(e.stat, 'thrown');
      expect(e.operation, ModifierOperation.add);
      expect(e.value, 6);
      expect(d.target, ConsumableTarget.self);
    });

    test('removeAllStatuses → ConsumableRemoveAllStatuses, target self', () {
      final d = consumableDefinitionFromContent(_load({
        'id': 'c', 'type': 'consumable', 'tags': <String>[],
        'effect': {'removeAllStatuses': true},
      }));
      expect(d.effect, isA<ConsumableRemoveAllStatuses>());
      expect(d.target, ConsumableTarget.self);
    });

    test('explicit matching target is accepted', () {
      final d = consumableDefinitionFromContent(_load({
        'id': 'x', 'type': 'consumable', 'tags': <String>[],
        'target': 'enemy', 'effect': {'attack': {'damage': 5, 'stat': 's'}},
      }));
      expect(d.target, ConsumableTarget.enemy);
    });
  });

  group('rejected — every one throws ContentFieldException at the right path', () {
    // (bad json, expected ContentFieldException.path). Pinning `.path`
    // catches a regression that still throws but for the wrong reason.
    final cases = <(Map<String, dynamic>, String)>[
      ({'id': 'z1', 'type': 'consumable', 'tags': <String>[]}, 'effect'),                                   // effect absent
      ({'id': 'z2', 'type': 'consumable', 'tags': <String>[], 'effect': <String, dynamic>{}}, 'effect'),    // {}
      ({'id': 'z3', 'type': 'consumable', 'tags': <String>[], 'effect': {'heal': 20, 'attack': {'damage': 1, 'stat': 's'}}}, 'effect'), // two variants
      ({'id': 'z4', 'type': 'consumable', 'tags': <String>[], 'effect': {'attack': <String, dynamic>{}}}, 'damage'),                    // missing damage
      ({'id': 'z5', 'type': 'consumable', 'tags': <String>[], 'effect': {'attack': {'damage': 15}}}, 'stat'),                          // missing stat
      ({'id': 'z6', 'type': 'consumable', 'tags': <String>[], 'effect': {'grant': {'stat': 'x'}}}, 'op'),                              // missing op
      ({'id': 'z7', 'type': 'consumable', 'tags': <String>[], 'effect': {'grant': {'stat': 'x', 'op': 'bogus', 'value': 1}}}, 'effect.grant.op'), // bad op
      ({'id': 'z8', 'type': 'consumable', 'tags': <String>[], 'effect': {'heal': '20'}}, 'heal'),          // wrong type
      ({'id': 'z9', 'type': 'consumable', 'tags': <String>[], 'effect': {'heal': -5}}, 'heal'),            // negative
      ({'id': 'z10', 'type': 'consumable', 'tags': <String>[], 'effect': {'unknownKey': 1}}, 'effect'),    // unknown key only
      ({'id': 'z11', 'type': 'consumable', 'tags': <String>[], 'effect': {'heal': 20, 'junk': 1}}, 'effect.junk'), // unknown key alongside valid
      ({'id': 'z12', 'type': 'consumable', 'tags': <String>[], 'target': 'enemy', 'effect': {'heal': 20}}, 'target'),                   // heal + enemy
      ({'id': 'z13', 'type': 'consumable', 'tags': <String>[], 'target': 'self', 'effect': {'attack': {'damage': 5, 'stat': 's'}}}, 'target'), // attack + self
      ({'id': 'z14', 'type': 'consumable', 'tags': <String>[], 'target': 'enemy', 'effect': {'grant': {'stat': 'x', 'op': 'add', 'value': 1}}}, 'target'), // grant + enemy
      ({'id': 'z15', 'type': 'consumable', 'tags': <String>[], 'target': 'enemy', 'effect': {'removeAllStatuses': true}}, 'target'),    // cleanse + enemy
      ({'id': 'z16', 'type': 'consumable', 'tags': <String>[], 'priority': 'high', 'effect': {'heal': 20}}, 'priority'),                // non-num priority
      ({'id': 'z17', 'type': 'consumable', 'tags': <String>[], 'charges': -1, 'effect': {'heal': 20}}, 'charges'),                      // negative charges
    ];

    for (final (bad, expectedPath) in cases) {
      test('${bad['id']}: ${bad['effect'] ?? '(no effect)'} → path "$expectedPath"', () {
        expect(
          () => consumableDefinitionFromContent(_load(bad)),
          throwsA(isA<ContentFieldException>()
              .having((e) => e.path, 'path', expectedPath)),
        );
      });
    }
  });
}
