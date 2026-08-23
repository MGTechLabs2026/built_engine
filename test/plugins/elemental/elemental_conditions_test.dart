import 'package:build_engine/build_engine.dart';
import 'package:build_engine/elemental_plugin.dart';
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

RuleContext _contextFor(EntityId? subject, PluginContext context) =>
    RuleContext(
      subject: subject,
      triggerEvent: const Object(),
      entities: context.entities,
      components: context.components,
      events: context.events,
      rng: context.rng,
      eventCounts: context.rules.eventCounts,
    );

void main() {
  group('HasElementalAffinity', () {
    test('matches when affinity is at or above the threshold', () {
      final context = _newContext();
      final entity = context.entities.create();
      attuneToElement(entity, Elements.fire, 5, context);

      expect(
        const HasElementalAffinity('fire', 5)
            .evaluate(_contextFor(entity, context)),
        isTrue,
      );
      expect(
        const HasElementalAffinity('fire', 6)
            .evaluate(_contextFor(entity, context)),
        isFalse,
      );
    });

    test('treats a missing component as zero affinity', () {
      final context = _newContext();
      final entity = context.entities.create();

      expect(
        const HasElementalAffinity('fire', 1)
            .evaluate(_contextFor(entity, context)),
        isFalse,
      );
    });

    test('returns false with no subject', () {
      final context = _newContext();
      expect(
        const HasElementalAffinity('fire', 0)
            .evaluate(_contextFor(null, context)),
        isFalse,
      );
    });
  });
}
