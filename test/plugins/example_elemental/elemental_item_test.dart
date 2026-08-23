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
  group('emberCharm', () {
    test('has the expected id and tags', () {
      expect(emberCharm.id, equals('ember_charm'));
      expect(emberCharm.tags,
          equals({'magic', 'fire', 'elemental', 'trinket'}));
    });

    test('modifiersFor returns a single +4 add punch modifier', () {
      const wearer = EntityId(1);
      final modifiers = emberCharm.modifiersFor(wearer);

      expect(modifiers, hasLength(1));
      final modifier = modifiers.single;
      expect(modifier.target, equals(wearer));
      expect(modifier.stat, equals('punch'));
      expect(modifier.operation, equals(ModifierOperation.add));
      expect(modifier.value, equals(4));
    });
  });

  group('equipElementalItem', () {
    test("registers the item's modifiers against a martial wearer", () {
      final context = _newContext();
      final wearer = context.entities.create();
      AddTag('martial').apply(context.ruleContextFor(wearer));

      equipElementalItem(emberCharm, wearer, context);

      final active = context.modifiers
          .activeModifiersFor(wearer, 'punch', context.components);
      expect(active, hasLength(1));
    });

    test('the modifier does not apply to a non-martial wearer', () {
      final context = _newContext();
      final wearer = context.entities.create();

      equipElementalItem(emberCharm, wearer, context);

      final active = context.modifiers
          .activeModifiersFor(wearer, 'punch', context.components);
      expect(active, isEmpty);
    });

    test('tags the wearer equipped:<id>', () {
      final context = _newContext();
      final wearer = context.entities.create();

      equipElementalItem(emberCharm, wearer, context);

      expect(context.components.get<TagSet>(wearer)!.tags,
          contains('equipped:ember_charm'));
    });
  });
}
