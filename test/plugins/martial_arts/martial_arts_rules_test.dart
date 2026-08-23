import 'package:build_engine/build_engine.dart';
import 'package:build_engine/combat_plugin.dart';
import 'package:build_engine/martial_arts_plugin.dart';
import 'package:test/test.dart';

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
  test('buildMartialArtsRules returns exactly 4 rules', () {
    expect(buildMartialArtsRules(), hasLength(4));
  });

  group('Shaolin defensive synergy rule', () {
    test('heals the damaged entity while it has stance:iron_body', () {
      final context = _newContext();
      for (final rule in buildMartialArtsRules()) {
        context.rules.register(rule);
      }
      final entity = context.entities.create();
      context.components.add(entity, TagSet({'stance:iron_body'}));
      context.components.add(entity, const HealthComponent(current: 50, max: 100));

      context.events.publish(EntityDamaged(entity, 10));

      expect(context.components.get<HealthComponent>(entity)!.current, equals(52));
    });

    test('does nothing without the stance tag', () {
      final context = _newContext();
      for (final rule in buildMartialArtsRules()) {
        context.rules.register(rule);
      }
      final entity = context.entities.create();
      context.components.add(entity, const HealthComponent(current: 50, max: 100));

      context.events.publish(EntityDamaged(entity, 10));

      expect(context.components.get<HealthComponent>(entity)!.current, equals(50));
    });
  });

  group('Tai Chi counter rule', () {
    test('damages the actor when a target has stance:tai_chi', () {
      final context = _newContext();
      for (final rule in buildMartialArtsRules()) {
        context.rules.register(rule);
      }
      final attacker = context.entities.create();
      final defender = context.entities.create();
      context.components.add(attacker, const HealthComponent(current: 100, max: 100));
      context.components.add(defender, TagSet({'stance:tai_chi'}));
      final battle = context.entities.create();
      final action = AttackAction(
        actor: attacker, targets: [defender], baseDamage: 5, damageStat: 'attack',
      );

      context.events.publish(ActionCompleted(battle, attacker, [defender], action));

      expect(context.components.get<HealthComponent>(attacker)!.current, equals(97));
    });

    test('does nothing when no target has the stance tag', () {
      final context = _newContext();
      for (final rule in buildMartialArtsRules()) {
        context.rules.register(rule);
      }
      final attacker = context.entities.create();
      final defender = context.entities.create();
      context.components.add(attacker, const HealthComponent(current: 100, max: 100));
      final battle = context.entities.create();
      final action = AttackAction(
        actor: attacker, targets: [defender], baseDamage: 5, damageStat: 'attack',
      );

      context.events.publish(ActionCompleted(battle, attacker, [defender], action));

      expect(context.components.get<HealthComponent>(attacker)!.current, equals(100));
    });
  });

  group('trinket passive regen rules', () {
    test('momentum trinket regenerates momentum on the wearer\'s turn', () {
      final context = _newContext();
      for (final rule in buildMartialArtsRules()) {
        context.rules.register(rule);
      }
      final wearer = context.entities.create();
      context.components.add(wearer, TagSet({'equipped:momentum_trinket'}));
      context.components.add(wearer, ResourceComponent({'momentum': 0}));
      final battle = context.entities.create();

      context.events.publish(TurnStarted(battle, wearer, 1));

      expect(
        context.components.get<ResourceComponent>(wearer)!.resources['momentum'],
        equals(3),
      );
    });

    test('qi pendant regenerates qi on the wearer\'s turn', () {
      final context = _newContext();
      for (final rule in buildMartialArtsRules()) {
        context.rules.register(rule);
      }
      final wearer = context.entities.create();
      context.components.add(wearer, TagSet({'equipped:qi_pendant'}));
      context.components.add(wearer, ResourceComponent({'qi': 0}));
      final battle = context.entities.create();

      context.events.publish(TurnStarted(battle, wearer, 1));

      expect(
        context.components.get<ResourceComponent>(wearer)!.resources['qi'],
        equals(2),
      );
    });

    test('neither trinket rule fires without the matching tag', () {
      final context = _newContext();
      for (final rule in buildMartialArtsRules()) {
        context.rules.register(rule);
      }
      final entity = context.entities.create();
      context.components.add(entity, ResourceComponent({'momentum': 0, 'qi': 0}));
      final battle = context.entities.create();

      context.events.publish(TurnStarted(battle, entity, 1));

      final resources = context.components.get<ResourceComponent>(entity)!.resources;
      expect(resources['momentum'], equals(0));
      expect(resources['qi'], equals(0));
    });
  });
}
