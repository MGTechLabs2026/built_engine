import 'package:build_engine/build_engine.dart';
import 'package:build_engine/combat_plugin.dart';
import 'package:test/test.dart';

class _HealAction extends CombatAction {
  const _HealAction({
    required this.actor,
    required this.targets,
    required this.amount,
  });

  @override
  final EntityId actor;
  @override
  final List<EntityId> targets;
  final num amount;

  // conditions/costEffects are not overridden — CombatAction's own
  // `const []` defaults apply, since this class `extends CombatAction`.

  @override
  List<Effect> effectsFor(EntityId target, PluginContext context) =>
      [Heal(amount)];
}

PluginContext _newContext() {
  final events = EventBus();
  final entities = EntityRegistry(events);
  final components = ComponentStore();
  final rng = RngService(1);
  return PluginContext(
    entities: entities,
    components: components,
    events: events,
    rng: rng,
    rules: RuleEngine(
      entities: entities,
      components: components,
      events: events,
      rng: rng,
    ),
    queries: QueryEngine(QueryScope(components: components)),
    modifiers: ModifierCollection(),
  );
}

void main() {
  group('AttackAction', () {
    test('effectsFor applies flat base damage with no modifiers registered',
        () {
      final context = _newContext();
      final actor = context.entities.create();
      final target = context.entities.create();
      final action = AttackAction(
        actor: actor,
        targets: [target],
        baseDamage: 10,
        damageStat: 'attack',
      );

      final effects = action.effectsFor(target, context);

      expect(effects, hasLength(1));
      expect(effects.single, isA<Damage>());
      expect((effects.single as Damage).amount, equals(10));
    });

    test('effectsFor resolves damage through a registered modifier', () {
      final context = _newContext();
      final actor = context.entities.create();
      final target = context.entities.create();
      context.modifiers.add(Modifier(
        source: const ModifierSource('rage'),
        target: actor,
        stat: 'attack',
        operation: ModifierOperation.multiply,
        value: 2,
      ));
      final action = AttackAction(
        actor: actor,
        targets: [target],
        baseDamage: 10,
        damageStat: 'attack',
      );

      final effects = action.effectsFor(target, context);

      expect((effects.single as Damage).amount, equals(20));
    });

    test('a modifier registered for a different stat does not apply', () {
      final context = _newContext();
      final actor = context.entities.create();
      final target = context.entities.create();
      context.modifiers.add(Modifier(
        source: const ModifierSource('armor'),
        target: actor,
        stat: 'defense',
        operation: ModifierOperation.add,
        value: 100,
      ));
      final action = AttackAction(
        actor: actor,
        targets: [target],
        baseDamage: 10,
        damageStat: 'attack',
      );

      final effects = action.effectsFor(target, context);

      expect((effects.single as Damage).amount, equals(10));
    });

    test('conditions and costEffects default to empty', () {
      final action = AttackAction(
        actor: const EntityId(1),
        targets: const [EntityId(2)],
        baseDamage: 5,
        damageStat: 'attack',
      );
      expect(action.conditions, isEmpty);
      expect(action.costEffects, isEmpty);
    });

    test('conditions and costEffects can be supplied', () {
      final action = AttackAction(
        actor: const EntityId(1),
        targets: const [EntityId(2)],
        baseDamage: 5,
        damageStat: 'attack',
        conditions: [const RandomChance(0.9)],
        costEffects: const [ModifyResource('stamina', -5)],
      );
      expect(action.conditions, hasLength(1));
      expect(action.costEffects, hasLength(1));
    });
  });

  group('a custom CombatAction (Heal)', () {
    test(
        'effectsFor returns a Heal effect, proving the same interface '
        'handles healing without a dedicated HealAction class', () {
      final context = _newContext();
      final actor = context.entities.create();
      final target = context.entities.create();
      final action = _HealAction(actor: actor, targets: [target], amount: 15);

      final effects = action.effectsFor(target, context);

      expect(effects.single, isA<Heal>());
      expect((effects.single as Heal).amount, equals(15));
    });
  });
}
