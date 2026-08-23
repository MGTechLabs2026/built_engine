import 'package:build_engine/build_engine.dart';
import 'package:build_engine/example_elemental_plugin.dart';
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
    content: ContentRegistry(),
  );
}

void main() {
  test('a soaked entity that takes damage also becomes shocked', () {
    final context = _newContext();
    for (final rule in buildElementalRules()) {
      context.rules.register(rule);
    }

    final entity = context.entities.create();
    context.components
        .add(entity, const HealthComponent(current: 100, max: 100));
    context.components.add(entity, StatusComponent({'status:soaked'}));

    context.events.publish(EntityDamaged(entity, 10));

    expect(
      context.components.get<StatusComponent>(entity)!.activeStatuses,
      containsAll(['status:soaked', 'status:shocked']),
    );
  });

  test('an entity that is not soaked is unaffected', () {
    final context = _newContext();
    for (final rule in buildElementalRules()) {
      context.rules.register(rule);
    }

    final entity = context.entities.create();
    context.components
        .add(entity, const HealthComponent(current: 100, max: 100));

    context.events.publish(EntityDamaged(entity, 10));

    expect(context.components.get<StatusComponent>(entity), isNull);
  });
}
