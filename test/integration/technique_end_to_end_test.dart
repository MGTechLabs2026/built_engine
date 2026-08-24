import 'package:build_engine/build_engine.dart';
import 'package:build_engine/technique_plugin.dart';
import 'package:test/test.dart';

PluginContext _newContext() {
  final events = EventBus();
  final entities = EntityRegistry(events);
  final components = ComponentStore();
  final rng = RngService(1);
  final mastery = MasteryTracker(components: components, events: events);
  final progression =
      ProgressionEngine(components: components, events: events, mastery: mastery);
  final discovery = DiscoveryTracker(components: components, events: events);
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
      mastery: mastery,
      progression: progression,
      discovery: discovery,
    ),
    queries: QueryEngine(QueryScope(components: components)),
    modifiers: ModifierCollection(),
    content: ContentRegistry(),
    mastery: mastery,
    progression: progression,
    discovery: discovery,
  );
}

void main() {
  test(
      'full technique lifecycle: discover -> learning (progress) -> learned '
      '-> Tome -> evolution', () {
    final context = _newContext();
    TechniquePlugin().initialize(context);
    context.tome.defineTome(
      TomeDefinition.namedSlots(id: 'basic_tome', slotIds: ['technique']),
    );
    final character = context.characters.create();
    context.tome.createTome(character, 'basic_tome');
    final basicPunch = techniqueDefinition(TechniqueIds.basicPunch, context);

    // discover
    discoverTechnique(character, basicPunch, context);
    expect(isTechniqueDiscovered(character, basicPunch, context), isTrue);
    expect(isTechniqueLearned(character, basicPunch, context), isFalse);
    expect(
      () => addTechniqueToTome(character, const SlotId('technique'), basicPunch, context),
      throwsA(isA<TechniqueNotLearnedException>()),
    );

    // learning: below threshold -> still not learned (LEARNING)
    final partial = attemptToLearnTechnique(character, basicPunch, 6, context);
    expect(partial.learned, isFalse);
    expect(isTechniqueLearned(character, basicPunch, context), isFalse);

    // learning: crosses threshold -> learned
    final complete = attemptToLearnTechnique(character, basicPunch, 4, context);
    expect(complete.learned, isTrue);
    expect(isTechniqueLearned(character, basicPunch, context), isTrue);

    // Tome
    addTechniqueToTome(character, const SlotId('technique'), basicPunch, context);
    final build = context.tome.resolve(character);
    expect(
      build.components.any((c) =>
          c.referenceType == techniqueReferenceType && c.contentId == TechniqueIds.basicPunch),
      isTrue,
    );

    // evolution — a separate, explicit operation
    final evolution = evolveTechnique(
      character,
      basicPunch,
      const TrainingProfile({TrainingDimensions.power: 0.8}),
      context,
    );
    expect(evolution.evolved, isTrue);
  });

  test('deterministic: two identically-seeded runs learn and evolve the same way', () {
    (bool, String?) runOnce() {
      final context = _newContext();
      TechniquePlugin().initialize(context);
      final character = context.characters.create();
      final basicSlash = techniqueDefinition(TechniqueIds.basicSlash, context);

      discoverTechnique(character, basicSlash, context);
      final result = attemptToLearnTechnique(character, basicSlash, 10, context);
      final evolution = evolveTechnique(
        character,
        basicSlash,
        const TrainingProfile({TrainingDimensions.speed: 0.7}),
        context,
      );
      return (result.learned, evolution.chosenCandidate?.targetId);
    }

    expect(runOnce(), equals(runOnce()));
  });
}
