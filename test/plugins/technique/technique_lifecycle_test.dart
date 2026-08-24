import 'package:build_engine/build_engine.dart';
import 'package:build_engine/src/plugins/technique/technique_content.dart';
import 'package:build_engine/src/plugins/technique/technique_definition.dart';
import 'package:build_engine/src/plugins/technique/technique_events.dart';
import 'package:build_engine/src/plugins/technique/technique_lifecycle.dart';
import 'package:build_engine/src/plugins/technique/technique_vocabulary.dart';
import 'package:test/test.dart';

// Shares `mastery`/`progression`/`discovery` between RuleEngine and
// PluginContext, per ARCHITECTURE.md's bootstrap example — required
// whenever a caller writes through PluginContext.progression/.mastery
// directly and also reads through context.ruleContextFor (as
// isTechniqueDiscovered/attemptToLearnTechnique's requirements check do).
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
  late PluginContext context;
  late TechniqueDefinition basicPunch;

  setUp(() {
    context = _newContext();
    context.content.loadAll(techniqueContentDefinitions);
    basicPunch = techniqueDefinition(TechniqueIds.basicPunch, context);
    context.progression.define(
      const ProgressionDefinition(subject: 'technique:basic_punch:knowledge', thresholds: [10]),
    );
    context.mastery.define(
      const MasteryDefinition(subject: 'technique:basic_punch', thresholds: [5, 15, 30]),
    );
  });

  test('a technique can be discovered', () {
    final owner = context.entities.create();

    discoverTechnique(owner, basicPunch, context);

    expect(isTechniqueDiscovered(owner, basicPunch, context), isTrue);
  });

  test('learning without discovery throws', () {
    final owner = context.entities.create();

    expect(
      () => attemptToLearnTechnique(owner, basicPunch, 10, context),
      throwsA(isA<TechniqueNotDiscoveredException>()),
    );
  });

  test('a learning attempt below the threshold yields progress, not learned', () {
    final owner = context.entities.create();
    discoverTechnique(owner, basicPunch, context);

    final result = attemptToLearnTechnique(owner, basicPunch, 4, context);

    expect(result.learned, isFalse);
    expect(result.totalExperience, equals(4));
    expect(isTechniqueLearned(owner, basicPunch, context), isFalse);
  });

  test('a learning attempt that crosses the threshold succeeds -> LEARNED', () {
    final owner = context.entities.create();
    discoverTechnique(owner, basicPunch, context);
    attemptToLearnTechnique(owner, basicPunch, 4, context);

    final result = attemptToLearnTechnique(owner, basicPunch, 6, context);

    expect(result.learned, isTrue);
    expect(isTechniqueLearned(owner, basicPunch, context), isTrue);
  });

  test('mastery independence: training mastery does not affect learned state, '
      'and learning does not affect mastery', () {
    final owner = context.entities.create();
    discoverTechnique(owner, basicPunch, context);

    trainTechniqueMastery(owner, basicPunch, 30, context);
    expect(techniqueMasteryLevel(owner, basicPunch, context), equals(3));
    expect(isTechniqueLearned(owner, basicPunch, context), isFalse);

    attemptToLearnTechnique(owner, basicPunch, 10, context);
    expect(isTechniqueLearned(owner, basicPunch, context), isTrue);
    // mastery, trained independently above, is unaffected by learning:
    expect(techniqueMasteryLevel(owner, basicPunch, context), equals(3));
  });

  test('a discovered-but-unlearned technique cannot enter the Tome', () {
    final owner = context.entities.create();
    discoverTechnique(owner, basicPunch, context);
    context.tome.defineTome(
      TomeDefinition.namedSlots(id: 'basic_tome', slotIds: ['technique']),
    );
    context.tome.createTome(owner, 'basic_tome');

    expect(
      () => addTechniqueToTome(owner, const SlotId('technique'), basicPunch, context),
      throwsA(isA<TechniqueNotLearnedException>()),
    );
    expect(context.tome.inspect(owner), isEmpty);
  });

  test('a learned technique can enter the Tome', () {
    final owner = context.entities.create();
    discoverTechnique(owner, basicPunch, context);
    attemptToLearnTechnique(owner, basicPunch, 10, context);
    context.tome.defineTome(
      TomeDefinition.namedSlots(id: 'basic_tome', slotIds: ['technique']),
    );
    context.tome.createTome(owner, 'basic_tome');

    TechniqueAddedToTome? published;
    context.events.subscribe<TechniqueAddedToTome>((e) => published = e);

    addTechniqueToTome(owner, const SlotId('technique'), basicPunch, context);

    expect(
      context.tome.inspect(owner).single.buildComponentRef.contentId,
      equals(TechniqueIds.basicPunch),
    );
    expect(published, isNotNull);
  });
}
