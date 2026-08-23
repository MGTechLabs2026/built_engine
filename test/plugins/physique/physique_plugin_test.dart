import 'package:build_engine/build_engine.dart';
import 'package:build_engine/physique_plugin.dart';
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
  test('has id "physique", a version, and no dependencies', () {
    final plugin = PhysiquePlugin();
    expect(plugin.id, equals('physique'));
    expect(plugin.version, isNotEmpty);
    expect(plugin.dependencies, isEmpty);
  });

  test('initialize loads all 4 physique content definitions', () {
    final context = _newContext();
    PhysiquePlugin().initialize(context);

    expect(context.content.allOfType('physique'), hasLength(4));
    for (final id in PhysiqueTypes.all) {
      expect(context.content.get(id), isNotNull);
    }
  });

  test('removes PhysiqueComponent when its entity is destroyed', () {
    final context = _newContext();
    final plugin = PhysiquePlugin();
    plugin.initialize(context);

    final character = context.entities.create();
    initializePhysique(character, context);
    expect(context.components.has<PhysiqueComponent>(character), isTrue);

    context.entities.destroy(character);

    expect(context.components.has<PhysiqueComponent>(character), isFalse);
  });

  test('component cleanup stops after unregister', () {
    final context = _newContext();
    final plugin = PhysiquePlugin();
    plugin.initialize(context);

    final character = context.entities.create();
    initializePhysique(character, context);

    plugin.unregister(context);
    context.entities.destroy(character);

    expect(context.components.has<PhysiqueComponent>(character), isTrue);
  });

  test('re-initializing on the same context does not throw '
      'ContentDuplicateIdException', () {
    final context = _newContext();
    final plugin = PhysiquePlugin();
    plugin.initialize(context);
    plugin.unregister(context);

    expect(() => plugin.initialize(context), returnsNormally);
    expect(context.content.allOfType('physique'), hasLength(4));
  });

  test('registers, initializes, starts, stops, and unregisters through '
      'PluginManager with no other plugin present', () {
    final context = _newContext();
    final manager = PluginManager();
    manager.register(PhysiquePlugin());

    manager.initialize(context);
    manager.start(context);

    final character = context.entities.create();
    final physiqueId = initializePhysique(character, context);
    expect(PhysiqueTypes.all, contains(physiqueId));

    expect(() => manager.stop(context), returnsNormally);
    expect(() => manager.unregister(context), returnsNormally);
  });
}
