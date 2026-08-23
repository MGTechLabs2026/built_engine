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
  );
}

void main() {
  group('learnStyle', () {
    test('grants the martial tag and a style:<id> tag', () {
      final context = _newContext();
      final entity = context.entities.create();

      learnStyle(entity, MartialStyles.boxing, context);

      final tags = context.components.get<TagSet>(entity)!.tags;
      expect(tags, containsAll({'martial', 'style:boxing'}));
    });

    test('learning shaolin additionally registers the offense/defense '
        'synergy modifier', () {
      final context = _newContext();
      final entity = context.entities.create();

      learnStyle(entity, MartialStyles.shaolin, context);

      final inactive = context.modifiers
          .activeModifiersFor(entity, 'palm', context.components);
      expect(inactive, isEmpty);

      context.components.add(entity, TagSet({'stance:iron_body'}));
      final active = context.modifiers
          .activeModifiersFor(entity, 'palm', context.components);
      expect(active, hasLength(1));
      expect(active.single.value, equals(4));
      expect(active.single.operation, equals(ModifierOperation.add));
    });

    test('learning boxing or taiChi registers no modifier', () {
      final context = _newContext();
      final boxer = context.entities.create();
      final taiChiPractitioner = context.entities.create();
      context.components.add(boxer, TagSet({'stance:iron_body'}));
      context.components.add(taiChiPractitioner, TagSet({'stance:iron_body'}));

      learnStyle(boxer, MartialStyles.boxing, context);
      learnStyle(taiChiPractitioner, MartialStyles.taiChi, context);

      expect(
        context.modifiers.activeModifiersFor(boxer, 'palm', context.components),
        isEmpty,
      );
      expect(
        context.modifiers
            .activeModifiersFor(taiChiPractitioner, 'palm', context.components),
        isEmpty,
      );
    });

    test('style id constants have the expected values', () {
      expect(MartialStyles.boxing, equals('boxing'));
      expect(MartialStyles.shaolin, equals('shaolin'));
      expect(MartialStyles.taiChi, equals('taiChi'));
    });
  });
}
