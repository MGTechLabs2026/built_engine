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
    final content = ContentRegistry();

    final context = PluginContext(
      entities: entities,
      components: components,
      events: events,
      rng: rng,
      rules: rules,
      queries: queries,
      modifiers: modifiers,
      content: content,
    );

    expect(context.entities, same(entities));
    expect(context.components, same(components));
    expect(context.events, same(events));
    expect(context.rng, same(rng));
    expect(context.rules, same(rules));
    expect(context.queries, same(queries));
    expect(context.modifiers, same(modifiers));
    expect(context.content, same(content));
  });

  group('ruleContextFor', () {
    test('builds a RuleContext wired to this context\'s own services', () {
      final events = EventBus();
      final entities = EntityRegistry(events);
      final components = ComponentStore();
      final rng = RngService(1);
      final context = PluginContext(
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
      final subject = entities.create();

      final ruleContext = context.ruleContextFor(subject);

      expect(ruleContext.subject, equals(subject));
      expect(ruleContext.entities, same(entities));
      expect(ruleContext.components, same(components));
      expect(ruleContext.events, same(events));
      expect(ruleContext.rng, same(rng));
      expect(ruleContext.eventCounts, same(context.rules.eventCounts));
    });

    test('defaults triggerEvent to a bare marker object', () {
      final context = PluginContext(
        entities: EntityRegistry(EventBus()),
        components: ComponentStore(),
        events: EventBus(),
        rng: RngService(1),
        rules: RuleEngine(
          entities: EntityRegistry(EventBus()),
          components: ComponentStore(),
          events: EventBus(),
          rng: RngService(1),
        ),
        queries: QueryEngine(QueryScope(components: ComponentStore())),
        modifiers: ModifierCollection(),
        content: ContentRegistry(),
      );
      final subject = context.entities.create();

      final ruleContext = context.ruleContextFor(subject);

      expect(ruleContext.triggerEvent, isA<Object>());
    });

    test('accepts an explicit triggerEvent', () {
      final context = PluginContext(
        entities: EntityRegistry(EventBus()),
        components: ComponentStore(),
        events: EventBus(),
        rng: RngService(1),
        rules: RuleEngine(
          entities: EntityRegistry(EventBus()),
          components: ComponentStore(),
          events: EventBus(),
          rng: RngService(1),
        ),
        queries: QueryEngine(QueryScope(components: ComponentStore())),
        modifiers: ModifierCollection(),
        content: ContentRegistry(),
      );
      final subject = context.entities.create();
      final event = Object();

      final ruleContext = context.ruleContextFor(subject, triggerEvent: event);

      expect(ruleContext.triggerEvent, same(event));
    });
  });
}
