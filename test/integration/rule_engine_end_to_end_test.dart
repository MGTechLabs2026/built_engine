import 'package:build_engine/build_engine.dart';
import 'package:test/test.dart';

class _SkillUsed {
  const _SkillUsed(this.actor);
  final EntityId actor;
}

void main() {
  test('Event -> Rule -> Condition -> Effect -> State change, end to end',
      () {
    final events = EventBus();
    final components = ComponentStore();
    final entities = EntityRegistry(events);
    final ruleEngine = RuleEngine(
      entities: entities,
      components: components,
      events: events,
      rng: RngService(1),
    );

    final actor = entities.create();
    components.add(actor, TagSet({'fire', 'dragon'}));
    components.add(actor, const HealthComponent(current: 100, max: 100));

    final damaged = <EntityId>[];
    events.subscribe<EntityDamaged>((event) => damaged.add(event.id));

    ruleEngine.register(Rule(
      trigger: _SkillUsed,
      subjectOf: (event) => (event as _SkillUsed).actor,
      conditions: [HasTag('fire'), HasTag('dragon')],
      effects: [const Damage(10)],
    ));

    events.publish(_SkillUsed(actor));

    expect(components.get<HealthComponent>(actor)!.current, equals(90));
    expect(damaged, equals([actor]));
  });

  test('a rule whose conditions fail leaves state unchanged', () {
    final events = EventBus();
    final components = ComponentStore();
    final entities = EntityRegistry(events);
    final ruleEngine = RuleEngine(
      entities: entities,
      components: components,
      events: events,
      rng: RngService(1),
    );

    final actor = entities.create();
    components.add(actor, TagSet({'ice'}));
    components.add(actor, const HealthComponent(current: 100, max: 100));

    ruleEngine.register(Rule(
      trigger: _SkillUsed,
      subjectOf: (event) => (event as _SkillUsed).actor,
      conditions: [HasTag('fire')],
      effects: [const Damage(10)],
    ));

    events.publish(_SkillUsed(actor));

    expect(components.get<HealthComponent>(actor)!.current, equals(100));
  });

  test('Query Engine finds entities independent of any rule', () {
    final components = ComponentStore();
    const a = EntityId(1);
    const b = EntityId(2);
    components.add(a, TagSet({'enemy'}));
    components.add(a, const HealthComponent(current: 20, max: 100));
    components.add(b, TagSet({'enemy'}));
    components.add(b, const HealthComponent(current: 90, max: 100));
    final engine = QueryEngine(QueryScope(components: components));

    final lowHealthEnemies = engine.evaluate(
      [a, b],
      HasTagQuery('enemy').and(const HealthBelowQuery(50)),
    );

    expect(lowHealthEnemies.toSet(), equals({a}));
  });
}
