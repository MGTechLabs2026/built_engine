import 'package:build_engine/build_engine.dart';
import 'package:build_engine/technique_plugin.dart';
import 'package:test/test.dart';

PluginContext _newContext() {
  final events = EventBus();
  final entities = EntityRegistry(events);
  final components = ComponentStore();
  final rng = RngService(1);
  final shared = CoreServices(components: components, events: events);
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
      shared: shared,
    ),
    queries: QueryEngine(QueryScope(components: components)),
    modifiers: ModifierCollection(),
    content: ContentRegistry(),
    shared: shared,
  );
}

void main() {
  test('declares no dependencies', () {
    expect(TechniquePlugin().dependencies, isEmpty);
  });

  test('initialize registers all 11 techniques and the learning/mastery definitions', () {
    final context = _newContext();
    TechniquePlugin().initialize(context);

    expect(context.content.get(TechniqueIds.basicPunch), isNotNull);
    expect(context.content.get(TechniqueIds.lightPunch), isNotNull);
    expect(context.progression.definitionOf('technique:basic_punch:knowledge'), isNotNull);
    expect(context.mastery.definitionOf('technique:basic_punch'), isNotNull);
  });

  test('every technique — base and evolved — gets a MASTERY axis; only the '
      'three base forms get the LEARNING axis', () {
    final context = _newContext();
    TechniquePlugin().initialize(context);

    for (final def in techniqueContentDefinitions) {
      final id = def['id'] as String;
      final mastery = context.mastery.definitionOf(techniqueSubject(id));
      expect(mastery, isNotNull, reason: '$id should have a mastery rank axis');
      expect(mastery!.thresholds, equals(techniqueMasteryThresholds));
      expect(
        context.progression.definitionOf(techniqueKnowledgeSubject(id)),
        TechniqueIds.bases.contains(id) ? isNotNull : isNull,
        reason: '$id: learning axis only for base forms',
      );
    }
  });

  test('re-initializing on the same context does not throw ContentDuplicateIdException', () {
    final context = _newContext();
    final plugin = TechniquePlugin();
    plugin.initialize(context);
    plugin.unregister(context);

    expect(() => plugin.initialize(context), returnsNormally);
    expect(context.content.get(TechniqueIds.basicPunch).type, equals('technique'));
  });

  test('TechniquePlugin runs standalone (no Combat, no MartialArts) end to end', () {
    final context = _newContext();
    final manager = PluginManager();
    manager.register(TechniquePlugin());
    manager.initialize(context);
    manager.start(context);

    final owner = context.entities.create();
    final basicPunch = techniqueDefinition(TechniqueIds.basicPunch, context);
    context.tome.defineTome(
      TomeDefinition.namedSlots(id: 'basic_tome', slotIds: ['technique']),
    );
    context.tome.createTome(owner, 'basic_tome');

    discoverTechnique(owner, basicPunch, context);
    attemptToLearnTechnique(owner, basicPunch, 10, context);
    addTechniqueToTome(owner, const SlotId('technique'), basicPunch, context);

    expect(
      context.tome.inspect(owner).single.buildComponentRef.contentId,
      equals(TechniqueIds.basicPunch),
    );

    manager.stop(context);
    manager.unregister(context);
  });
}
