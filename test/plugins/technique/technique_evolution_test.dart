import 'package:build_engine/build_engine.dart';
import 'package:build_engine/src/plugins/technique/technique_content.dart';
import 'package:build_engine/src/plugins/technique/technique_evolution.dart';
import 'package:build_engine/src/plugins/technique/technique_vocabulary.dart';
import 'package:test/test.dart';

PluginContext _newContext(int seed) {
  final events = EventBus();
  final entities = EntityRegistry(events);
  final components = ComponentStore();
  final rng = RngService(seed);
  return PluginContext(
    entities: entities,
    components: components,
    events: events,
    rng: rng,
    rules: RuleEngine(entities: entities, components: components, events: events, rng: rng),
    queries: QueryEngine(QueryScope(components: components)),
    modifiers: ModifierCollection(),
    content: ContentRegistry(),
  );
}

void main() {
  test('branching evolution resolves to exactly one of the 4 basic_punch branches', () {
    final context = _newContext(7);
    context.content.loadAll(techniqueContentDefinitions);
    final basicPunch = techniqueDefinition(TechniqueIds.basicPunch, context);
    final owner = context.entities.create();

    final result = evolveTechnique(
      owner,
      basicPunch,
      const TrainingProfile({TrainingDimensions.speed: 0.5}),
      context,
    );

    expect(result.evolved, isTrue);
    expect(
      [
        TechniqueIds.lightPunch,
        TechniqueIds.heavyPunch,
        TechniqueIds.fastPunch,
        TechniqueIds.counterPunch,
      ],
      contains(result.chosenCandidate!.targetId),
    );
  });

  test('a high-speed training profile makes fast_punch win meaningfully more often', () {
    var fastWins = 0;
    const trials = 50;
    for (var seed = 0; seed < trials; seed++) {
      final context = _newContext(seed);
      context.content.loadAll(techniqueContentDefinitions);
      final basicPunch = techniqueDefinition(TechniqueIds.basicPunch, context);
      final owner = context.entities.create();

      final result = evolveTechnique(
        owner,
        basicPunch,
        const TrainingProfile({TrainingDimensions.speed: 0.95}),
        context,
      );
      if (result.chosenCandidate?.targetId == TechniqueIds.fastPunch) fastWins++;
    }

    // With 4 roughly-equal-weight candidates and speed at 0.95, fast_punch's
    // weight (~1.95) dominates the other three (~1.0 each); a bare-plurality
    // threshold (trials/4) already exceeds chance (25%) and is what the
    // profile's influence is being asserted against.
    expect(fastWins, greaterThan(trials ~/ 4));
  });

  test('deterministic: the same seed yields the same chosen candidate', () {
    EvolutionCandidate? runOnce() {
      final context = _newContext(42);
      context.content.loadAll(techniqueContentDefinitions);
      final basicSlash = techniqueDefinition(TechniqueIds.basicSlash, context);
      final owner = context.entities.create();
      return evolveTechnique(
        owner,
        basicSlash,
        const TrainingProfile({TrainingDimensions.power: 0.7}),
        context,
      ).chosenCandidate;
    }

    expect(runOnce()?.targetId, equals(runOnce()?.targetId));
  });
}
