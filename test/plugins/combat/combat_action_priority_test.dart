import 'package:build_engine/build_engine.dart';
import 'package:build_engine/build_interpretation.dart';
import 'package:build_engine/combat_plugin.dart';
import 'package:test/test.dart';

void main() {
  test('AttackAction.priority defaults to 0 and is settable', () {
    expect(const AttackAction(actor: EntityId(1), targets: [], baseDamage: 1, damageStat: 's').priority, 0);
    expect(
      const AttackAction(actor: EntityId(1), targets: [], baseDamage: 1, damageStat: 's', priority: 7).priority,
      7,
    );
  });

  test('SelfEffectAction.priority defaults to 0 and is settable', () {
    expect(const SelfEffectAction(actor: EntityId(1)).priority, 0);
    expect(const SelfEffectAction(actor: EntityId(1), priority: 5).priority, 5);
  });
}
