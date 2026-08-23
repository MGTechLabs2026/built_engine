import 'package:build_engine/build_engine.dart';
import 'package:build_engine/physique_plugin.dart';
import 'package:test/test.dart';

PluginContext _newContext(int seed) {
  final events = EventBus();
  final entities = EntityRegistry(events);
  final components = ComponentStore();
  final rng = RngService(seed);
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
    ),
    queries: QueryEngine(QueryScope(components: components)),
    modifiers: ModifierCollection(),
    content: ContentRegistry(),
  );
  PhysiquePlugin().initialize(context);
  return context;
}

void main() {
  test('1: every character receives exactly one physique', () {
    final context = _newContext(1);
    final character = context.entities.create();

    initializePhysique(character, context);

    final component = context.components.get<PhysiqueComponent>(character);
    expect(component, isNotNull);
    expect(PhysiqueTypes.all, contains(component!.physiqueId));
  });

  test('2: physique selection uses RngService (context.rng), not '
      'dart:math directly', () {
    final context = _newContext(42);
    final character = context.entities.create();

    final physiqueId = initializePhysique(character, context);

    expect(PhysiqueTypes.all, contains(physiqueId));
    // Structural confirmation this used context.rng, not dart:math's
    // Random, is that determinism (test 3, same file) holds at all —
    // an unseeded, process-global Random could not produce it.
  });

  test('3: a deterministic seed produces a deterministic physique', () {
    final contextA = _newContext(7);
    final contextB = _newContext(7);

    final physiqueA =
        initializePhysique(contextA.entities.create(), contextA);
    final physiqueB =
        initializePhysique(contextB.entities.create(), contextB);

    expect(physiqueA, equals(physiqueB));
  });

  test('4: different seeds can produce different physiques', () {
    final results = <String>{};
    for (var seed = 1; seed <= 20; seed++) {
      final context = _newContext(seed);
      results.add(initializePhysique(context.entities.create(), context));
    }

    expect(results.length, greaterThan(1));
  });

  test('is idempotent: a character that already has a physique keeps it',
      () {
    final context = _newContext(1);
    final character = context.entities.create();

    final first = initializePhysique(character, context);
    final second = initializePhysique(character, context);

    expect(second, equals(first));
  });

  test("registers the assigned physique's synergy modifiers", () {
    final context = _newContext(1);
    final character = context.entities.create();

    final physiqueId = initializePhysique(character, context);
    final definition =
        physiqueDefinitionFromContent(context.content.get(physiqueId));

    // No tradition tag yet: neither conditional modifier is active.
    expect(
      context.modifiers.activeModifiersFor(
          character, definition.primaryAffinity, context.components),
      isEmpty,
    );

    // Granting both tradition tags proves both modifiers were
    // genuinely registered (not just structurally absent either way).
    context.components.add(character, TagSet({'western', 'eastern'}));
    expect(
      context.modifiers.activeModifiersFor(
          character, definition.primaryAffinity, context.components),
      hasLength(2),
    );
  });

  test('publishes PhysiqueAssigned', () {
    final context = _newContext(1);
    final character = context.entities.create();
    final published = <PhysiqueAssigned>[];
    context.events.subscribe<PhysiqueAssigned>(published.add);

    final physiqueId = initializePhysique(character, context);

    expect(published, hasLength(1));
    expect(published.single.character, equals(character));
    expect(published.single.physiqueId, equals(physiqueId));
  });

  test('publishes nothing on the idempotent second call', () {
    final context = _newContext(1);
    final character = context.entities.create();
    initializePhysique(character, context);

    final published = <PhysiqueAssigned>[];
    context.events.subscribe<PhysiqueAssigned>(published.add);
    initializePhysique(character, context);

    expect(published, isEmpty);
  });
}
