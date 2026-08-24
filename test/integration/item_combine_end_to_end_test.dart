// test/integration/item_combine_end_to_end_test.dart
import 'package:build_engine/build_engine.dart';
import 'package:build_engine/build_interpretation.dart';
import 'package:build_engine/item_plugin.dart';
import 'package:test/test.dart';

PluginContext _newContext(int seed) {
  final events = EventBus();
  final entities = EntityRegistry(events);
  final components = ComponentStore();
  final rng = RngService(seed);
  final shared = CoreServices(components: components, events: events);
  return PluginContext(
    entities: entities,
    components: components,
    events: events,
    rng: rng,
    rules: RuleEngine(
      entities: entities, components: components, events: events, rng: rng, shared: shared,
    ),
    queries: QueryEngine(QueryScope(components: components)),
    modifiers: ModifierCollection(),
    content: ContentRegistry(),
    shared: shared,
  );
}

int _seedForOutcome(
  CombineOutcome target, {
  required int tier,
  required int inputCount,
  int maxSeed = 1000,
}) {
  final odds = CombineOdds.forAttempt(tier: tier, inputCount: inputCount);
  for (var seed = 1; seed <= maxSeed; seed++) {
    final roll = RngService(seed).nextDouble() * 100;
    final outcome = roll < odds.failPercent
        ? CombineOutcome.fail
        : roll < odds.failPercent + odds.normalPercent
            ? CombineOutcome.classUpgrade
            : CombineOutcome.gradeUpgrade;
    if (outcome == target) return seed;
  }
  throw StateError('no seed up to $maxSeed produced $target');
}

void loadDagger(PluginContext ctx) {
  ctx.content.load({
    'id': 'dagger',
    'type': 'weapon',
    'tags': ['item', 'weapon', 'blade'],
    'properties': {'attack': 4},
    'maxClass': 6,
  });
}

void main() {
  test('combining a Tome-placed item scales its live combat stat via ActiveBuild', () {
    final seed = _seedForOutcome(CombineOutcome.classUpgrade, tier: 1, inputCount: 2);
    final context = _newContext(seed);
    ItemPlugin().initialize(context);
    loadDagger(context);
    final owner = context.entities.create();
    final a = ownItem(owner, 'dagger', context);
    final b = ownItem(owner, 'dagger', context);
    context.resources.add(owner, ItemResources.upgradePoints, 10);
    context.tome.defineTome(TomeDefinition.namedSlots(id: 'basic_tome', slotIds: ['weapon']));
    context.tome.createTome(owner, 'basic_tome');
    context.tome.insert(
      owner,
      const SlotId('weapon'),
      BuildComponentRef(referenceType: itemReferenceType, contentId: 'dagger', instanceEntityId: a),
    );

    combineItems(owner, [a, b], context);

    const interpreter = ItemActionInterpreter();
    final build = context.tome.resolve(owner);
    interpreter.interpret(build: build, actor: owner, targets: const [], context: context);

    final active = context.modifiers.activeModifiersFor(owner, 'blade', context.components).toList();
    expect(active, hasLength(1));
    expect(active.single.value, closeTo(4.6, 0.001)); // 4 attack * (1 + 0.15*1) at class 2
  });

  test('a multi-candidate grade branch picks among targets according to trainingWeights', () {
    var sharpWins = 0;
    const trials = 60;
    for (var seed = 1; seed <= trials; seed++) {
      final context = _newContext(seed);
      ItemPlugin().initialize(context);
      context.content.load({
        'id': 'branching_knife',
        'type': 'weapon',
        'tags': ['item', 'weapon'],
        'properties': {'attack': 2},
        'maxClass': 3,
        'training': {'precision': 0.9},
        'gradeEvolution': [
          {'targetId': 'sharp_knife', 'tags': ['precision']},
          {'targetId': 'heavy_knife', 'tags': ['power']},
        ],
      });
      final owner = context.entities.create();
      final a = ownItem(owner, 'branching_knife', context);
      final b = ownItem(owner, 'branching_knife', context);
      context.resources.add(owner, ItemResources.upgradePoints, 10);
      final gradeSeed = _seedForOutcome(CombineOutcome.gradeUpgrade, tier: 1, inputCount: 2);
      final seededContext = PluginContext(
        entities: context.entities, components: context.components, events: context.events,
        rng: RngService(gradeSeed), rules: context.rules, queries: context.queries,
        modifiers: context.modifiers, content: context.content, resources: context.resources,
        mastery: context.mastery, progression: context.progression, discovery: context.discovery,
        tome: context.tome,
      );

      final survivor = combineItems(owner, [a, b], seededContext);
      if (context.components.get<ItemInstance>(survivor)!.definitionId == 'sharp_knife') {
        sharpWins++;
      }
    }

    // precision-weighted profile heavily favors sharp_knife; a clear
    // majority across the sweep proves real influence, mirroring
    // technique_evolution_test.dart's statistical assertion style.
    expect(sharpWins, greaterThan(trials ~/ 2));
  });

  test('a fully terminal item (maxClass reached, no grade path) cannot be combined', () {
    final context = _newContext(1);
    ItemPlugin().initialize(context);
    context.content.load({
      'id': 'masterwork_knife',
      'type': 'weapon',
      'tags': ['item', 'weapon'],
      'properties': {'attack': 10},
      'maxClass': 1,
    });
    final owner = context.entities.create();
    final a = ownItem(owner, 'masterwork_knife', context);
    final b = ownItem(owner, 'masterwork_knife', context);
    context.resources.add(owner, ItemResources.upgradePoints, 10);

    expect(
      () => combineItems(owner, [a, b], context),
      throwsA(isA<CombineNotAvailableException>()),
    );
  });
}
