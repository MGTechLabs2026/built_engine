import 'package:build_engine/build_engine.dart';
import 'package:test/test.dart';

class _Evt {
  const _Evt();
}

void main() {
  test('RuleContext.modifiers defaults to a fresh ModifierCollection when unsupplied', () {
    final events = EventBus();
    final ctx = RuleContext(
      subject: null,
      triggerEvent: const _Evt(),
      entities: EntityRegistry(events),
      components: ComponentStore(),
      events: events,
      rng: RngService(1),
      eventCounts: EventCounter(events),
    );
    expect(ctx.modifiers, isA<ModifierCollection>());
  });

  test('ruleContextFor supplies the PluginContext own ModifierCollection (identity)', () {
    final events = EventBus();
    final entities = EntityRegistry(events);
    final components = ComponentStore();
    final rng = RngService(1);
    final modifiers = ModifierCollection();
    final context = PluginContext(
      entities: entities,
      components: components,
      events: events,
      rng: rng,
      rules: RuleEngine(entities: entities, components: components, events: events, rng: rng),
      queries: QueryEngine(QueryScope(components: components)),
      modifiers: modifiers,
      content: ContentRegistry(),
    );
    final ruleContext = context.ruleContextFor(const EntityId(1));
    expect(identical(ruleContext.modifiers, modifiers), isTrue);
  });
}
