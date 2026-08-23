import 'package:build_engine/build_engine.dart';
import 'package:build_engine/combat_plugin.dart';
import 'package:build_engine/martial_arts_plugin.dart';
import 'package:test/test.dart';

RuleContext _contextFor(Object triggerEvent, {ComponentStore? components}) {
  final events = EventBus();
  return RuleContext(
    subject: null,
    triggerEvent: triggerEvent,
    entities: EntityRegistry(events),
    components: components ?? ComponentStore(),
    events: events,
    rng: RngService(1),
    eventCounts: EventCounter(events),
  );
}

void main() {
  group('TaiChiCounterCondition', () {
    const attacker = EntityId(1);
    const battle = EntityId(99);

    test('matches when a target has the tai chi stance tag', () {
      final components = ComponentStore();
      const defender = EntityId(2);
      components.add(defender, TagSet({'stance:tai_chi'}));
      final action = AttackAction(
        actor: attacker,
        targets: const [defender],
        baseDamage: 5,
        damageStat: 'attack',
      );

      final matches = const TaiChiCounterCondition().evaluate(
        _contextFor(
          ActionCompleted(battle, attacker, const [defender], action),
          components: components,
        ),
      );

      expect(matches, isTrue);
    });

    test('does not match when no target has the stance tag', () {
      final components = ComponentStore();
      const defender = EntityId(2);
      final action = AttackAction(
        actor: attacker,
        targets: const [defender],
        baseDamage: 5,
        damageStat: 'attack',
      );

      final matches = const TaiChiCounterCondition().evaluate(
        _contextFor(
          ActionCompleted(battle, attacker, const [defender], action),
          components: components,
        ),
      );

      expect(matches, isFalse);
    });

    test('matches if any of several targets has the stance tag', () {
      final components = ComponentStore();
      const defenderA = EntityId(2);
      const defenderB = EntityId(3);
      components.add(defenderB, TagSet({'stance:tai_chi'}));
      final action = AttackAction(
        actor: attacker,
        targets: const [defenderA, defenderB],
        baseDamage: 5,
        damageStat: 'attack',
      );

      final matches = const TaiChiCounterCondition().evaluate(
        _contextFor(
          ActionCompleted(battle, attacker, const [defenderA, defenderB], action),
          components: components,
        ),
      );

      expect(matches, isTrue);
    });

    test('does not match a different event type', () {
      final matches = const TaiChiCounterCondition().evaluate(
        _contextFor(const Object()),
      );
      expect(matches, isFalse);
    });

    test('does not match ActionStarted (only ActionCompleted)', () {
      final components = ComponentStore();
      const defender = EntityId(2);
      components.add(defender, TagSet({'stance:tai_chi'}));
      final action = AttackAction(
        actor: attacker,
        targets: const [defender],
        baseDamage: 5,
        damageStat: 'attack',
      );

      final matches = const TaiChiCounterCondition().evaluate(
        _contextFor(
          ActionStarted(battle, attacker, const [defender], action),
          components: components,
        ),
      );

      expect(matches, isFalse);
    });
  });
}
