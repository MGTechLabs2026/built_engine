import 'package:build_engine/build_engine.dart';
import 'package:test/test.dart';

void main() {
  test('PluginContext exposes every constructor argument unchanged', () {
    final events = EventBus();
    final entities = EntityRegistry(events);
    final components = ComponentStore();
    final rng = RngService(1);
    final rules = RuleEngine(
      entities: entities,
      components: components,
      events: events,
      rng: rng,
    );
    final queries = QueryEngine(QueryScope(components: components));
    final modifiers = ModifierCollection();

    final context = PluginContext(
      entities: entities,
      components: components,
      events: events,
      rng: rng,
      rules: rules,
      queries: queries,
      modifiers: modifiers,
    );

    expect(context.entities, same(entities));
    expect(context.components, same(components));
    expect(context.events, same(events));
    expect(context.rng, same(rng));
    expect(context.rules, same(rules));
    expect(context.queries, same(queries));
    expect(context.modifiers, same(modifiers));
  });
}
