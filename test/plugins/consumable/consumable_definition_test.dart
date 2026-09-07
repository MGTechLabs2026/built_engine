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

  group('rejected — every one throws ContentFieldException', () {
    Matcher throwsField() => throwsA(isA<ContentFieldException>());

    for (final bad in <Map<String, dynamic>>[
      {'id': 'z1', 'type': 'consumable', 'tags': <String>[]},                                   // effect absent
      {'id': 'z2', 'type': 'consumable', 'tags': <String>[], 'effect': <String, dynamic>{}},    // {}
      {'id': 'z3', 'type': 'consumable', 'tags': <String>[], 'effect': {'heal': 20, 'attack': {'damage': 1, 'stat': 's'}}}, // two variants
      {'id': 'z4', 'type': 'consumable', 'tags': <String>[], 'effect': {'attack': <String, dynamic>{}}},                    // missing damage/stat
      {'id': 'z5', 'type': 'consumable', 'tags': <String>[], 'effect': {'attack': {'damage': 15}}},                         // missing stat
      {'id': 'z6', 'type': 'consumable', 'tags': <String>[], 'effect': {'grant': {'stat': 'x'}}},                           // missing op/value
      {'id': 'z7', 'type': 'consumable', 'tags': <String>[], 'effect': {'grant': {'stat': 'x', 'op': 'bogus', 'value': 1}}}, // bad op
      {'id': 'z8', 'type': 'consumable', 'tags': <String>[], 'effect': {'heal': '20'}},          // wrong type
      {'id': 'z9', 'type': 'consumable', 'tags': <String>[], 'effect': {'heal': -5}},            // negative
      {'id': 'z10', 'type': 'consumable', 'tags': <String>[], 'effect': {'unknownKey': 1}},      // unknown key only
      {'id': 'z11', 'type': 'consumable', 'tags': <String>[], 'effect': {'heal': 20, 'junk': 1}}, // unknown key alongside valid
      {'id': 'z12', 'type': 'consumable', 'tags': <String>[], 'target': 'enemy', 'effect': {'heal': 20}},                   // heal + enemy
      {'id': 'z13', 'type': 'consumable', 'tags': <String>[], 'target': 'self', 'effect': {'attack': {'damage': 5, 'stat': 's'}}}, // attack + self
      {'id': 'z14', 'type': 'consumable', 'tags': <String>[], 'target': 'enemy', 'effect': {'grant': {'stat': 'x', 'op': 'add', 'value': 1}}}, // grant + enemy
      {'id': 'z15', 'type': 'consumable', 'tags': <String>[], 'target': 'enemy', 'effect': {'removeAllStatuses': true}},    // cleanse + enemy
    ]) {
      test('${bad['id']}: ${bad['effect'] ?? '(no effect)'} target=${bad['target']}', () {
        expect(() => consumableDefinitionFromContent(_load(bad)), throwsField());
      });
    }
  });
}
