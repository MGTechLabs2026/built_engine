import 'package:build_engine/build_engine.dart';
import 'package:build_engine/martial_arts_plugin.dart';
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
  group('content lists', () {
    test('martialItems has 5 entries and martialTrinkets has 3', () {
      expect(martialItems, hasLength(5));
      expect(martialTrinkets, hasLength(3));
    });

    test('every item/trinket id is unique', () {
      final ids = [...martialItems, ...martialTrinkets].map((i) => i.id);
      expect(ids.toSet(), hasLength(8));
    });
  });

  group('equipItem', () {
    test('creates an item entity carrying the item\'s tags', () {
      final context = _newContext();
      final wearer = context.entities.create();

      final itemEntity = equipItem(brassKnuckles, wearer, context);

      expect(
        context.components.get<TagSet>(itemEntity)!.tags,
        equals(brassKnuckles.tags),
      );
    });

    test('registers the item\'s modifiers against the wearer', () {
      final context = _newContext();
      final wearer = context.entities.create();

      equipItem(brassKnuckles, wearer, context);

      final resolved = const ModifierResolver().resolve(
        10,
        context.modifiers.activeModifiersFor(wearer, 'punch', context.components),
      );
      expect(resolved, equals(16));
    });

    test('add and multiply modifiers from different items stack correctly',
        () {
      final context = _newContext();
      final wearer = context.entities.create();

      equipItem(brassKnuckles, wearer, context); // +6 add to punch
      equipItem(weightedVest, wearer, context); // x1.1 multiply on punch

      final resolved = const ModifierResolver().resolve(
        10,
        context.modifiers.activeModifiersFor(wearer, 'punch', context.components),
      );
      expect(resolved, closeTo((10 + 6) * 1.1, 0.0001));
    });

    test('grants the wearer an equipped:<id> tag without erasing other tags',
        () {
      final context = _newContext();
      final wearer = context.entities.create();
      learnStyle(wearer, MartialStyles.boxing, context);

      equipItem(brassKnuckles, wearer, context);

      final tags = context.components.get<TagSet>(wearer)!.tags;
      expect(tags, containsAll({'martial', 'style:boxing', 'equipped:brass_knuckles'}));
    });

    test('records the equipped item on MartialLoadoutComponent, '
        'accumulating across multiple equips', () {
      final context = _newContext();
      final wearer = context.entities.create();

      final first = equipItem(brassKnuckles, wearer, context);
      final second = equipItem(momentumTrinket, wearer, context);

      final loadout = context.components.get<MartialLoadoutComponent>(wearer)!;
      expect(loadout.equippedItems, equals([first, second]));
    });

    test('trinkets with no static modifiers register none', () {
      final context = _newContext();
      final wearer = context.entities.create();

      equipItem(momentumTrinket, wearer, context);

      expect(
        context.modifiers
            .activeModifiersFor(wearer, 'momentum', context.components),
        isEmpty,
      );
    });

    test('counterstrike ring only boosts internal damage while the tai chi '
        'stance tag is active', () {
      final context = _newContext();
      final wearer = context.entities.create();

      equipItem(counterstrikeRing, wearer, context);

      expect(
        context.modifiers
            .activeModifiersFor(wearer, 'internal', context.components),
        isEmpty,
      );

      context.components.add(
        wearer,
        TagSet({...context.components.get<TagSet>(wearer)!.tags, 'stance:tai_chi'}),
      );

      final active = context.modifiers
          .activeModifiersFor(wearer, 'internal', context.components);
      expect(active, hasLength(1));
      expect(active.single.value, equals(3));
    });
  });
}
