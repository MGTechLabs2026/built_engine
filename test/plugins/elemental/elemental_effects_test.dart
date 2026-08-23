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

RuleContext _contextFor(EntityId subject, PluginContext context) =>
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
  group('ApplyElementalStatus', () {
    test('fire applies status:burning', () {
      final context = _newContext();
      final entity = context.entities.create();
      const ApplyElementalStatus('fire').apply(_contextFor(entity, context));
      expect(
        context.components.get<StatusComponent>(entity)!.activeStatuses,
        contains('status:burning'),
      );
    });

    test('water applies status:soaked', () {
      final context = _newContext();
      final entity = context.entities.create();
      const ApplyElementalStatus('water')
          .apply(_contextFor(entity, context));
      expect(
        context.components.get<StatusComponent>(entity)!.activeStatuses,
        contains('status:soaked'),
      );
    });

    test('lightning applies status:shocked', () {
      final context = _newContext();
      final entity = context.entities.create();
      const ApplyElementalStatus('lightning')
          .apply(_contextFor(entity, context));
      expect(
        context.components.get<StatusComponent>(entity)!.activeStatuses,
        contains('status:shocked'),
      );
    });
  });
}
