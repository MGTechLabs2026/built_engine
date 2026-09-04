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
            ? CombineOutcome.tierUpgrade
            : CombineOutcome.branchUpgrade;
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
    final seed = _seedForOutcome(CombineOutcome.tierUpgrade, tier: 1, inputCount: 2);
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
    final build = context.tome.resolve(owner, ownedRefs: const []);
    interpreter.interpret(build: build, actor: owner, targets: const [], context: context);

    final active = context.modifiers.activeModifiersFor(owner, 'blade', context.components).toList();
    expect(active, hasLength(1));
    expect(active.single.value, closeTo(4.6, 0.001)); // 4 attack * (1 + 0.15*1) at class 2
  });

  test('a multi-candidate grade branch picks among targets according to trainingWeights', () {
    // The bug this replaced: the old version computed `gradeSeed` from
    // `_seedForOutcome(CombineOutcome.branchUpgrade, tier: 1, inputCount: 2)`
    // — a pure function of constant arguments — so it evaluated to the
    // exact same seed on every loop iteration. Every trial then drew the
    // identical RNG sequence and produced the identical target every time,
    // making `sharpWins` deterministically either 0 or `trials`; the
    // `greaterThan` assertion passed without genuinely exercising
    // `trainingWeights`.
    //
    // Fixed approach: genuinely vary the raw seed used for the actual
    // `combineItems` call. `CombineResolver.resolve`'s very first RNG draw
    // (`rng.nextDouble() * 100`, in `combine_resolver.dart`) decides the
    // fail/tierUpgrade/branchUpgrade bucket, and nothing before it in
    // `combineItems` touches `context.rng` -- so a fresh `RngService(seed)`
    // used standalone to check which bucket a seed lands in reproduces
    // exactly the same first draw a `PluginContext` built from
    // `RngService(seed)` will make inside the real call. Seeds that don't
    // land in the branchUpgrade bucket are skipped (not counted) rather than
    // exercising fail/tierUpgrade, since only a branchUpgrade roll actually
    // reaches the weighted grade-candidate pick this test is about.
    var sharpWins = 0;
    var counted = 0;
    const trials = 60;
    const tier = 1;
    const inputCount = 2;
    final odds = CombineOdds.forAttempt(tier: tier, inputCount: inputCount);

    var rawSeed = 0;
    while (counted < trials) {
      rawSeed++;
      if (rawSeed > 20000) {
        fail('could not find $trials seeds landing in the branchUpgrade bucket '
            'within $rawSeed raw seeds');
      }
      final roll = RngService(rawSeed).nextDouble() * 100;
      final landsInBranchUpgrade = roll >= odds.failPercent + odds.normalPercent;
      if (!landsInBranchUpgrade) continue; // fail/tierUpgrade for this seed -- not a real trial

      counted++;
      final context = _newContext(rawSeed);
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

      final survivor = combineItems(owner, [a, b], context);
      if (context.components.get<ItemInstance>(survivor)!.definitionId == 'sharp_knife') {
        sharpWins++;
      }
    }

    // precision-weighted profile heavily favors sharp_knife; a clear
    // majority among the counted (genuinely branchUpgrade-bucket) trials
    // proves real influence, mirroring technique_evolution_test.dart's
    // statistical assertion style. Hand-verified: dropping the 'training'
    // weight from the content above collapses sharpWins to roughly
    // counted/2 and this assertion fails, confirming the sweep is not
    // vacuous.
    expect(counted, equals(trials));
    expect(sharpWins, greaterThan(counted ~/ 2));
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
