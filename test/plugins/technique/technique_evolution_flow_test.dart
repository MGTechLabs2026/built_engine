// A4 — the authoritative post-training evolution step. Locks that
// `resolveTechniqueEvolutionAfterTraining` is the single place the
// evolution decision is made and the single publisher of
// `TechniqueEvolved`.
import 'package:build_engine/build_engine.dart';
import 'package:build_engine/src/plugins/technique/technique_content.dart';
import 'package:build_engine/src/plugins/technique/technique_definition.dart';
import 'package:build_engine/src/plugins/technique/technique_events.dart';
import 'package:build_engine/src/plugins/technique/technique_evolution.dart';
import 'package:build_engine/src/plugins/technique/technique_lifecycle.dart';
import 'package:build_engine/src/plugins/technique/technique_vocabulary.dart';
import 'package:test/test.dart';

PluginContext _newContext(int seed) {
  final events = EventBus();
  final entities = EntityRegistry(events);
  final components = ComponentStore();
  final rng = RngService(seed);
  final shared = CoreServices(components: components, events: events);
  final context = PluginContext(
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
  context.content.loadAll(techniqueContentDefinitions);
  context.progression.define(const ProgressionDefinition(
      subject: 'technique:basic_punch:knowledge', thresholds: [10]));
  return context;
}

/// Discovers + learns `basic_punch` for a fresh owner and returns it.
({EntityId owner, TechniqueDefinition technique}) _learnedBasicPunch(
    PluginContext context) {
  final owner = context.entities.create();
  final technique = techniqueDefinition(TechniqueIds.basicPunch, context);
  discoverTechnique(owner, technique, context);
  attemptToLearnTechnique(owner, technique, 999, context); // clears the [10] gate
  return (owner: owner, technique: technique);
}

const _speedProfile = TrainingProfile({TrainingDimensions.speed: 0.9});

void main() {
  test('a learned technique with eligible candidates evolves and publishes '
      'exactly one TechniqueEvolved', () {
    final context = _newContext(7);
    final captured = <TechniqueEvolved>[];
    context.events.subscribe<TechniqueEvolved>(captured.add);
    final l = _learnedBasicPunch(context);

    final result = resolveTechniqueEvolutionAfterTraining(
        l.owner, l.technique, _speedProfile, context);

    expect(result.evolved, isTrue);
    expect(captured, hasLength(1));
    expect(captured.single.fromId, TechniqueIds.basicPunch);
    expect(captured.single.toId, result.chosenCandidate!.targetId);
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

  test('a not-yet-learned technique never evolves and never publishes', () {
    final context = _newContext(7);
    final captured = <TechniqueEvolved>[];
    context.events.subscribe<TechniqueEvolved>(captured.add);
    final owner = context.entities.create();
    final technique = techniqueDefinition(TechniqueIds.basicPunch, context);
    discoverTechnique(owner, technique, context); // discovered, NOT learned

    final result = resolveTechniqueEvolutionAfterTraining(
        owner, technique, _speedProfile, context);

    expect(result.evolved, isFalse);
    expect(captured, isEmpty);
  });

  test('a terminal (no-candidate) technique never evolves and never publishes',
      () {
    final context = _newContext(7);
    final captured = <TechniqueEvolved>[];
    context.events.subscribe<TechniqueEvolved>(captured.add);
    final owner = context.entities.create();
    // A master-tier form has no evolution candidates.
    final terminal = techniqueDefinition(TechniqueIds.lightningJab, context);
    discoverTechnique(owner, terminal, context);

    final result = resolveTechniqueEvolutionAfterTraining(
        owner, terminal, _speedProfile, context);

    expect(result.evolved, isFalse);
    expect(captured, isEmpty);
  });

  test('same seed → same chosen candidate (deterministic RNG)', () {
    String? runOnce() {
      final context = _newContext(42);
      final l = _learnedBasicPunch(context);
      return resolveTechniqueEvolutionAfterTraining(
              l.owner, l.technique, _speedProfile, context)
          .chosenCandidate
          ?.targetId;
    }

    expect(runOnce(), isNotNull);
    expect(runOnce(), equals(runOnce()));
  });

  test('publishes the same number of events as evolutions across a seed sweep — '
      'never a second independent publisher', () {
    for (var seed = 1; seed <= 15; seed++) {
      final context = _newContext(seed);
      final captured = <TechniqueEvolved>[];
      context.events.subscribe<TechniqueEvolved>(captured.add);
      final l = _learnedBasicPunch(context);

      final result = resolveTechniqueEvolutionAfterTraining(
          l.owner, l.technique, _speedProfile, context);

      expect(captured.length, result.evolved ? 1 : 0,
          reason: 'seed $seed: event count == evolution count');
    }
  });
}
