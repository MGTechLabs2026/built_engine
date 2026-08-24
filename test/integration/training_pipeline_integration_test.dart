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
      'a TrainingResult carries enough to drive mastery increase, technique '
      'learning, and evolution weighting — without Training calling any of '
      'them itself', () {
    final context = _newContext();
    TechniquePlugin().initialize(context);
    final character = context.entities.create();
    final basicPunch = techniqueDefinition(TechniqueIds.basicPunch, context);

    final exercise = techniqueTrainingExerciseFor(TechniqueIds.basicPunch, const TimingExercise());
    final session = TrainingSession(
      trainee: character,
      subject: techniqueSubject(TechniqueIds.basicPunch),
      exercise: exercise,
    );
    session.submitAttempt(const TrainingAttempt({'windowStart': 100, 'windowEnd': 200, 'actual': 150}));
    session.submitAttempt(const TrainingAttempt({'windowStart': 100, 'windowEnd': 200, 'actual': 140}));
    final result = session.complete();

    expect(result.trainee, equals(character));
    expect(result.subject, equals(techniqueSubject(TechniqueIds.basicPunch)));
    expect(result.profile.dimensions, isNotEmpty);

    // Mastery increase — driven by the caller, using result.trainee/.subject:
    context.mastery.increase(result.trainee, result.subject, 10);
    expect(context.mastery.progressOf(result.trainee, result.subject), equals(10));

    // Technique learning — driven by the caller, using result.trainee:
    discoverTechnique(result.trainee, basicPunch, context);
    final learning = attemptToLearnTechnique(result.trainee, basicPunch, 10, context);
    expect(learning.learned, isTrue);

    // Evolution weighting — driven by the caller, using result.profile:
    final evolution = evolveTechnique(result.trainee, basicPunch, result.profile, context);
    expect(evolution.evolved, isTrue);
  });

  test('deterministic: an identical training session always yields an identical result', () {
    TrainingResult runOnce() {
      final session = TrainingSession(
        trainee: const EntityId(1),
        subject: 'technique:basic_punch',
        exercise: techniqueTrainingExerciseFor(TechniqueIds.basicPunch, const TimingExercise()),
      );
      session.submitAttempt(const TrainingAttempt({'windowStart': 100, 'windowEnd': 200, 'actual': 160}));
      session.submitAttempt(const TrainingAttempt({'windowStart': 100, 'windowEnd': 200, 'actual': 145}));
      return session.complete();
    }

    expect(runOnce().profile.dimensions, equals(runOnce().profile.dimensions));
  });
}
