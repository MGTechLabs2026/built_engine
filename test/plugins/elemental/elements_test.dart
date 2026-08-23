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

void main() {
  group('attuneToElement', () {
    test('grants the element:<id> tag', () {
      final context = _newContext();
      final entity = context.entities.create();

      attuneToElement(entity, Elements.fire, 5, context);

      expect(context.components.get<TagSet>(entity)!.tags,
          contains('element:fire'));
    });

    test('sets the affinity level in ElementalAffinityComponent', () {
      final context = _newContext();
      final entity = context.entities.create();

      attuneToElement(entity, Elements.fire, 5, context);

      expect(
        context.components.get<ElementalAffinityComponent>(entity)!
            .affinities['fire'],
        equals(5),
      );
    });

    test('attuning to a second element preserves the first', () {
      final context = _newContext();
      final entity = context.entities.create();

      attuneToElement(entity, Elements.fire, 5, context);
      attuneToElement(entity, Elements.water, 3, context);

      final affinities = context.components
          .get<ElementalAffinityComponent>(entity)!
          .affinities;
      expect(affinities['fire'], equals(5));
      expect(affinities['water'], equals(3));

      final tags = context.components.get<TagSet>(entity)!.tags;
      expect(tags, containsAll(['element:fire', 'element:water']));
    });

    test('re-attuning to the same element overwrites its affinity', () {
      final context = _newContext();
      final entity = context.entities.create();

      attuneToElement(entity, Elements.fire, 5, context);
      attuneToElement(entity, Elements.fire, 9, context);

      expect(
        context.components.get<ElementalAffinityComponent>(entity)!
            .affinities['fire'],
        equals(9),
      );
    });
  });
}
