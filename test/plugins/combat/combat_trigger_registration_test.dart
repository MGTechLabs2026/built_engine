import 'package:build_engine/build_engine.dart';
import 'package:build_engine/combat_plugin.dart';
import 'package:test/test.dart';

PluginContext _ctx() {
  final events = EventBus();
  final entities = EntityRegistry(events);
  final components = ComponentStore();
  final rng = RngService(1);
  return PluginContext(
    entities: entities,
    components: components,
    events: events,
    rng: rng,
    rules: RuleEngine(entities: entities, components: components, events: events, rng: rng),
    queries: QueryEngine(QueryScope(components: components)),
    modifiers: ModifierCollection(),
    content: ContentRegistry(),
  );
}

void main() {
  test('TurnStarted / TurnEnded / ActionCompleted are registered as triggers with an actor subject', () {
    final ctx = _ctx();
    CombatPlugin().initialize(ctx);

    final owner = ctx.entities.create();
    final battle = ctx.entities.create();
    ctx.components.add(owner, const HealthComponent(current: 50, max: 100));

    // A loadRule against each key must succeed (unknown trigger throws)
    // and fire with the event actor as subject.
    for (final key in ['TurnStarted', 'TurnEnded', 'ActionCompleted']) {
      ctx.content.loadRule({
        'id': 'probe_$key',
        'trigger': key,
        'effects': [{'type': 'heal', 'amount': 1}],
      });
      ctx.rules.register(ctx.content.rule('probe_$key').rule);
    }

    final before = ctx.components.get<HealthComponent>(owner)!.current;
    ctx.events.publish(TurnStarted(battle, owner, 1));
    ctx.events.publish(TurnEnded(battle, owner, 1));
    ctx.events.publish(ActionCompleted(battle, owner, const [], AttackAction(actor: owner, targets: const [], baseDamage: 0, damageStat: 'x')));
    expect(ctx.components.get<HealthComponent>(owner)!.current, before + 3);
  });
}
