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
  test('all 9 technique/stance definitions load atomically as a batch',
      () {
    final registry = ContentRegistry();
    final definitions = registry.loadAll(martialTechniqueContentDefinitions);
    expect(definitions, hasLength(9));
    expect(registry.allOfType('technique'), hasLength(9));
  });

  group('martialTechniqueFromDefinition', () {
    test('builds an attack technique with baseDamage/damageStat from '
        'extra', () {
      final registry = ContentRegistry();
      registry.loadAll(martialTechniqueContentDefinitions);
      final actor = const EntityId(1);
      final target = const EntityId(2);

      final action = martialTechniqueFromDefinition(
        registry.get('jab'),
        actor: actor,
        targets: [target],
      );

      expect(action.actor, equals(actor));
      expect(action.targets, equals([target]));
      expect(action.baseDamage, equals(6));
      expect(action.damageStat, equals('punch'));
      expect(action.costEffects, hasLength(1));
      expect(action.costEffects.single, isA<ModifyResource>());
      expect(action.selfEffects, isEmpty);
      expect(action.conditions, hasLength(1));
      expect(action.tags, contains('fist'));
    });

    test('builds a stance with its effects as selfEffects, not '
        'costEffects', () {
      final registry = ContentRegistry();
      registry.loadAll(martialTechniqueContentDefinitions);
      final actor = const EntityId(1);

      final action = martialTechniqueFromDefinition(
        registry.get('guard_stance'),
        actor: actor,
        targets: [actor],
      );

      expect(action.baseDamage, isNull);
      expect(action.damageStat, isNull);
      expect(action.costEffects, isEmpty);
      expect(action.selfEffects, hasLength(2));
      expect(action.selfEffects.whereType<AddTag>(), hasLength(1));
      expect(action.selfEffects.whereType<ModifyResource>(), hasLength(1));
    });
  });

  group('the 9 convenience factory functions', () {
    test('produce the same shape as looking the content up directly', () {
      final actor = const EntityId(1);
      final target = const EntityId(2);

      final viaFactory = jab(actor: actor, targets: [target]);

      final registry = ContentRegistry();
      registry.loadAll(martialTechniqueContentDefinitions);
      final viaLookup = martialTechniqueFromDefinition(
        registry.get('jab'),
        actor: actor,
        targets: [target],
      );

      expect(viaFactory.baseDamage, equals(viaLookup.baseDamage));
      expect(viaFactory.damageStat, equals(viaLookup.damageStat));
      expect(viaFactory.tags, equals(viaLookup.tags));
      expect(viaFactory.costEffects, hasLength(viaLookup.costEffects.length));
    });
  });

  test('MartialArtsPlugin.initialize loads the same 9 definitions into '
      'the real, shared PluginContext.content', () {
    final context = _newContext();
    final plugin = MartialArtsPlugin();
    plugin.initialize(context);

    expect(context.content.allOfType('technique'), hasLength(9));
    expect(context.content.get('jab').type, equals('technique'));
  });

  test('re-initializing MartialArtsPlugin on the same context does not '
      'throw ContentDuplicateIdException', () {
    final context = _newContext();
    final plugin = MartialArtsPlugin();
    plugin.initialize(context);
    plugin.unregister(context);

    expect(() => plugin.initialize(context), returnsNormally);
    expect(context.content.allOfType('technique'), hasLength(9));
  });
}
