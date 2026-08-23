import 'package:build_engine/build_engine.dart';
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

class _Marker {
  const _Marker(this.value);
  final int value;
}

class _MarkerEvent {
  const _MarkerEvent(this.value);
  final int value;
}

void main() {
  group('registerComponentCleanup', () {
    test('removes the component when the entity is destroyed', () {
      final context = _newContext();
      final sdk = PluginSdk(context);
      sdk.registerComponentCleanup<_Marker>();

      final entity = context.entities.create();
      context.components.add(entity, const _Marker(1));
      expect(context.components.get<_Marker>(entity), isNotNull);

      context.entities.destroy(entity);
      expect(context.components.get<_Marker>(entity), isNull);
    });

    test('is cancelled by disposeAll', () {
      final context = _newContext();
      final sdk = PluginSdk(context);
      sdk.registerComponentCleanup<_Marker>();
      sdk.disposeAll();

      final entity = context.entities.create();
      context.components.add(entity, const _Marker(1));
      context.entities.destroy(entity);
      expect(context.components.get<_Marker>(entity), isNotNull);
    });
  });

  group('registerEvent', () {
    test('fires the handler for published events of the given type', () {
      final context = _newContext();
      final sdk = PluginSdk(context);
      final seen = <int>[];
      sdk.registerEvent<_MarkerEvent>((e) => seen.add(e.value));

      context.events.publish(const _MarkerEvent(7));
      expect(seen, equals([7]));
    });

    test('is cancelled by disposeAll', () {
      final context = _newContext();
      final sdk = PluginSdk(context);
      final seen = <int>[];
      sdk.registerEvent<_MarkerEvent>((e) => seen.add(e.value));
      sdk.disposeAll();

      context.events.publish(const _MarkerEvent(7));
      expect(seen, isEmpty);
    });
  });

  group('registerEffect / registerCondition', () {
    test('registered factories are reachable through content.load', () {
      final context = _newContext();
      final sdk = PluginSdk(context);
      sdk.registerEffect('markerEffect', (p) => const Heal(1));
      sdk.registerCondition(
          'markerCondition', (p) => const RandomChance(1.0));

      final definition = context.content.load({
        'id': 'uses_marker',
        'type': 'test',
        'conditions': [
          {'type': 'markerCondition'},
        ],
        'effects': [
          {'type': 'markerEffect'},
        ],
      });

      expect(definition.conditions.single, isA<RandomChance>());
      expect(definition.effects.single, isA<Heal>());
    });
  });

  group('registerRule', () {
    test('fires through the real RuleEngine', () {
      final context = _newContext();
      final sdk = PluginSdk(context);
      sdk.registerRule(Rule(
        trigger: EntityHealed,
        subjectOf: (e) => (e as EntityHealed).id,
        effects: const [ModifyStat('marker', 1)],
      ));

      final entity = context.entities.create();
      context.events.publish(EntityHealed(entity, 5));

      expect(
        context.components.get<StatComponent>(entity)!.stats['marker'],
        equals(1),
      );
    });

    test('is cancelled by disposeAll', () {
      final context = _newContext();
      final sdk = PluginSdk(context);
      sdk.registerRule(Rule(
        trigger: EntityHealed,
        subjectOf: (e) => (e as EntityHealed).id,
        effects: const [ModifyStat('marker', 1)],
      ));
      sdk.disposeAll();

      final entity = context.entities.create();
      context.events.publish(EntityHealed(entity, 5));

      expect(context.components.get<StatComponent>(entity), isNull);
    });
  });

  group('registerTag', () {
    test('records tags with their description', () {
      final context = _newContext();
      final sdk = PluginSdk(context);
      sdk.registerTag('element:fire', description: 'Fire-aligned.');
      sdk.registerTag('element:water');

      expect(sdk.tags['element:fire'], equals('Fire-aligned.'));
      expect(sdk.tags['element:water'], equals(''));
      expect(sdk.tags, hasLength(2));
    });
  });

  group('registerContent / registerContentBatch', () {
    test('registerContent delegates to content.load', () {
      final context = _newContext();
      final sdk = PluginSdk(context);
      final definition = sdk.registerContent({'id': 'a', 'type': 'skill'});
      expect(context.content.get('a'), same(definition));
    });

    test('registerContentBatch delegates to content.loadAll', () {
      final context = _newContext();
      final sdk = PluginSdk(context);
      final definitions = sdk.registerContentBatch([
        {'id': 'a', 'type': 'skill'},
        {'id': 'b', 'type': 'skill'},
      ]);
      expect(definitions, hasLength(2));
      expect(context.content.get('a'), isNotNull);
      expect(context.content.get('b'), isNotNull);
    });
  });

  group('registerAsset', () {
    test('loads an asset with the given id/type and data in extra', () {
      final context = _newContext();
      final sdk = PluginSdk(context);
      final definition = sdk.registerAsset(
        id: 'fire_icon',
        data: {'path': 'assets/fire.png'},
      );

      expect(definition.id, equals('fire_icon'));
      expect(definition.type, equals('asset'));
      expect(definition.extra['path'], equals('assets/fire.png'));
    });

    test('data cannot override the fixed id/type', () {
      final context = _newContext();
      final sdk = PluginSdk(context);
      final definition = sdk.registerAsset(
        id: 'fire_icon',
        data: {'id': 'hijacked', 'type': 'hijacked'},
      );

      expect(definition.id, equals('fire_icon'));
      expect(definition.type, equals('asset'));
    });
  });

  group('registerLocalization / localize', () {
    test('round-trips a registered string', () {
      final context = _newContext();
      final sdk = PluginSdk(context);
      sdk.registerLocalization(
          locale: 'en', key: 'fireball.name', value: 'Fireball');

      expect(sdk.localize('en', 'fireball.name'), equals('Fireball'));
    });

    test('returns null when not found', () {
      final context = _newContext();
      final sdk = PluginSdk(context);
      expect(sdk.localize('en', 'nonexistent'), isNull);
    });

    test(
        'returns null for an id that exists but is not a localization '
        'entry', () {
      final context = _newContext();
      final sdk = PluginSdk(context);
      sdk.registerContent({'id': 'en:not_localization', 'type': 'skill'});
      expect(sdk.localize('en', 'not_localization'), isNull);
    });
  });

  group('disposeAll', () {
    test('is safe to call twice', () {
      final context = _newContext();
      final sdk = PluginSdk(context);
      sdk.registerEvent<_MarkerEvent>((_) {});
      sdk.disposeAll();
      expect(sdk.disposeAll, returnsNormally);
    });
  });
}
