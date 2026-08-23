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
  test('declares no dependencies', () {
    expect(ExampleElementalPlugin().dependencies, isEmpty);
  });

  test('initialize registers the content definitions and the rule', () {
    final context = _newContext();
    final plugin = ExampleElementalPlugin();
    plugin.initialize(context);

    expect(context.content.get('fireball'), isNotNull);
    expect(context.content.get('tidal_wave'), isNotNull);
    expect(context.content.get('spark_bolt'), isNotNull);

    final entity = context.entities.create();
    context.components
        .add(entity, const HealthComponent(current: 10, max: 10));
    context.components.add(entity, StatusComponent({'status:soaked'}));
    context.events.publish(EntityDamaged(entity, 1));
    expect(
      context.components.get<StatusComponent>(entity)!.activeStatuses,
      contains('status:shocked'),
    );
  });

  test('unregister stops the rule and component cleanup from firing', () {
    final context = _newContext();
    final plugin = ExampleElementalPlugin();
    plugin.initialize(context);
    plugin.unregister(context);

    final entity = context.entities.create();
    context.components
        .add(entity, const HealthComponent(current: 10, max: 10));
    context.components.add(entity, StatusComponent({'status:soaked'}));
    context.events.publish(EntityDamaged(entity, 1));
    expect(
      context.components.get<StatusComponent>(entity)!.activeStatuses,
      isNot(contains('status:shocked')),
    );

    attuneToElement(entity, Elements.fire, 1, context);
    context.entities.destroy(entity);
    expect(context.components.get<ElementalAffinityComponent>(entity),
        isNotNull);
  });

  test('re-initializing on the same context does not throw '
      'ContentDuplicateIdException', () {
    final context = _newContext();
    final plugin = ExampleElementalPlugin();
    plugin.initialize(context);
    plugin.unregister(context);

    expect(() => plugin.initialize(context), returnsNormally);
    expect(context.content.get('fireball').type, equals('spell'));
  });
}
