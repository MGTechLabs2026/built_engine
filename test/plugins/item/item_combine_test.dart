import 'package:build_engine/build_engine.dart';
import 'package:build_engine/src/plugins/item/item_combine.dart';
import 'package:build_engine/src/plugins/item/item_content.dart';
import 'package:build_engine/src/plugins/item/item_events.dart';
import 'package:build_engine/src/plugins/item/item_instance.dart';
import 'package:build_engine/src/plugins/item/item_lifecycle.dart';
import 'package:build_engine/src/plugins/item/item_vocabulary.dart';
import 'package:test/test.dart';

// Shares `mastery`/`discovery` between `RuleEngine` and `PluginContext` —
// required per ARCHITECTURE.md's bootstrap example whenever a Rule (fired
// through RuleEngine) needs to see mastery/discovery state written through
// `PluginContext.mastery`/`.discovery` directly, as this plugin's own
// usability rule does. Relying on each side's own default would silently
// give them two independent trackers (ARCHITECTURE_AUDIT.md's Observation B).
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

  setUp(() {
    context = _newContext();
    context.content.loadAll(itemContentDefinitions);
  });

  group('combineItems', () {
    // A standalone combinable item (not part of the shipped 6-item
    // content set), loaded fresh in each test that needs it, mirroring
    // how test/combine/combine_resolver_test.dart uses inline content
    // rather than touching itemContentDefinitions.
    void loadSimpleKnife(PluginContext ctx, {int maxClass = 3, List<Map<String, dynamic>>? gradeEvolution}) {
      ctx.content.load({
        'id': 'simple_knife',
        'type': 'weapon',
        'tags': ['item', 'weapon'],
        'properties': {'attack': 2},
        'maxClass': maxClass,
        if (gradeEvolution != null) 'gradeEvolution': gradeEvolution,
      });
      if (gradeEvolution != null) {
        for (final entry in gradeEvolution) {
          ctx.content.load({
            'id': entry['targetId'],
            'type': 'weapon',
            'tags': ['item', 'weapon'],
            'properties': {'attack': 4},
          });
        }
      }
    }

    int seedForOutcome(
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

    // A seed where a 2-input tierUpgrade combine's `CombineResolver`-
    // chosen `survivorIndex` lands on the SECOND input — used to prove
    // combineItems' Tome-placement survivor override actually overrides
    // something, rather than coincidentally matching (unlike the "two
    // currently-placed" test above, whose fixed seed happens to draw
    // survivorIndex == 0, the already-placed instance).
    int seedForSecondIndexSurvivor({required int tier, required int inputCount, int maxSeed = 2000}) {
      final odds = CombineOdds.forAttempt(tier: tier, inputCount: inputCount);
      for (var seed = 1; seed <= maxSeed; seed++) {
        final rng = RngService(seed);
        final roll = rng.nextDouble() * 100;
        final outcome = roll < odds.failPercent
            ? CombineOutcome.fail
            : roll < odds.failPercent + odds.normalPercent
                ? CombineOutcome.tierUpgrade
                : CombineOutcome.branchUpgrade;
        // tierUpgrade at a non-max tier draws exactly one further value —
        // survivorIndex — matching CombineResolver.resolve's own sequence.
        if (outcome == CombineOutcome.tierUpgrade && rng.nextInt(inputCount) == inputCount - 1) {
          return seed;
        }
      }
      throw StateError('no seed up to $maxSeed produced the desired combination');
    }

    test('combining fewer than 2 instances throws ArgumentError', () {
      loadSimpleKnife(context);
      final owner = context.entities.create();
      final only = ownItem(owner, 'simple_knife', context);

      expect(
        () => combineItems(owner, [only], context),
        throwsArgumentError,
      );
    });

    test('combining the same owned instance entity twice throws ArgumentError '
        'and consumes nothing', () {
      loadSimpleKnife(context);
      final owner = context.entities.create();
      final a = ownItem(owner, 'simple_knife', context);
      context.resources.set(owner, ItemResources.upgradePoints, 10);

      expect(
        () => combineItems(owner, [a, a], context),
        throwsArgumentError,
      );
      expect(context.resources.currentOf(owner, ItemResources.upgradePoints), equals(10));
    });

    test('mismatched definitionId throws CombineMismatchException', () {
      loadSimpleKnife(context);
      final owner = context.entities.create();
      final a = ownItem(owner, 'simple_knife', context);
      final b = ownItem(owner, ItemIds.knife, context);
      context.resources.set(owner, ItemResources.upgradePoints, 10);

      expect(
        () => combineItems(owner, [a, b], context),
        throwsA(isA<CombineMismatchException>()),
      );
    });

    test('combining an instance owned by a different entity throws ArgumentError '
        'and consumes nothing from owner', () {
      loadSimpleKnife(context);
      final owner = context.entities.create();
      final other = context.entities.create();
      final mine = ownItem(owner, 'simple_knife', context);
      final theirs = ownItem(other, 'simple_knife', context);
      context.resources.set(owner, ItemResources.upgradePoints, 10);

      expect(
        () => combineItems(owner, [mine, theirs], context),
        throwsArgumentError,
      );
      expect(context.resources.currentOf(owner, ItemResources.upgradePoints), equals(10));
      // neither instance was touched
      expect(context.components.get<ItemInstance>(mine), isNotNull);
      expect(context.components.get<ItemInstance>(theirs), isNotNull);
    });

    test('a non-combinable item (no maxClass declared) throws CombineNotAvailableException', () {
      context.content.load({
        'id': 'plain_item',
        'type': 'weapon',
        'tags': ['item', 'weapon'],
        'properties': {'attack': 1},
      });
      final owner = context.entities.create();
      final a = ownItem(owner, 'plain_item', context);
      final b = ownItem(owner, 'plain_item', context);
      context.resources.set(owner, ItemResources.upgradePoints, 10);

      expect(
        () => combineItems(owner, [a, b], context),
        throwsA(isA<CombineNotAvailableException>()),
      );
    });

    test('insufficient upgrade_points throws InsufficientResourceException and consumes nothing', () {
      loadSimpleKnife(context);
      final owner = context.entities.create();
      final a = ownItem(owner, 'simple_knife', context);
      final b = ownItem(owner, 'simple_knife', context);
      // no upgrade_points granted at all

      expect(
        () => combineItems(owner, [a, b], context),
        throwsA(isA<InsufficientResourceException>()),
      );
      expect(context.resources.currentOf(owner, ItemResources.upgradePoints), equals(0));
    });

    test('a fail outcome destroys exactly N-1 inputs and leaves the survivor unchanged', () {
      loadSimpleKnife(context);
      final owner = context.entities.create();
      final a = ownItem(owner, 'simple_knife', context);
      final b = ownItem(owner, 'simple_knife', context);
      context.resources.set(owner, ItemResources.upgradePoints, 10);
      final seed = seedForOutcome(CombineOutcome.fail, tier: 1, inputCount: 2);
      final seededContext = PluginContext(
        entities: context.entities, components: context.components, events: context.events,
        rng: RngService(seed), rules: context.rules, queries: context.queries,
        modifiers: context.modifiers, content: context.content, resources: context.resources,
        mastery: context.mastery, progression: context.progression, discovery: context.discovery,
        tome: context.tome,
      );

      ItemCombineFailed? published;
      context.events.subscribe<ItemCombineFailed>((e) => published = e);

      final survivor = combineItems(owner, [a, b], seededContext);

      final survivingInstances =
          [a, b].where((e) => context.components.get<ItemInstance>(e) != null).toList();
      expect(survivingInstances, equals([survivor]));
      expect(context.components.get<ItemInstance>(survivor)!.itemClass, equals(1));
      expect(context.components.get<ItemInstance>(survivor)!.definitionId, equals('simple_knife'));
      expect(published, isNotNull);
      expect(context.resources.currentOf(owner, ItemResources.upgradePoints), equals(9));
    });

    test('a tierUpgrade outcome increments the survivor\'s itemClass', () {
      loadSimpleKnife(context);
      final owner = context.entities.create();
      final a = ownItem(owner, 'simple_knife', context);
      final b = ownItem(owner, 'simple_knife', context);
      context.resources.set(owner, ItemResources.upgradePoints, 10);
      final seed = seedForOutcome(CombineOutcome.tierUpgrade, tier: 1, inputCount: 2);
      final seededContext = PluginContext(
        entities: context.entities, components: context.components, events: context.events,
        rng: RngService(seed), rules: context.rules, queries: context.queries,
        modifiers: context.modifiers, content: context.content, resources: context.resources,
        mastery: context.mastery, progression: context.progression, discovery: context.discovery,
        tome: context.tome,
      );

      ItemCombineSucceeded? published;
      context.events.subscribe<ItemCombineSucceeded>((e) => published = e);

      final survivor = combineItems(owner, [a, b], seededContext);

      final instance = context.components.get<ItemInstance>(survivor)!;
      expect(instance.itemClass, equals(2));
      expect(instance.definitionId, equals('simple_knife'));
      expect(published!.outcome, equals(CombineOutcome.tierUpgrade));
      expect(published!.newClass, equals(2));
    });

    test('a branchUpgrade outcome swaps the survivor\'s definitionId, itemClass unchanged', () {
      loadSimpleKnife(context, gradeEvolution: [
        {'targetId': 'fixture_sharp_knife'},
      ]);
      final owner = context.entities.create();
      final a = ownItem(owner, 'simple_knife', context);
      final b = ownItem(owner, 'simple_knife', context);
      context.resources.set(owner, ItemResources.upgradePoints, 10);
      final seed = seedForOutcome(CombineOutcome.branchUpgrade, tier: 1, inputCount: 2);
      final seededContext = PluginContext(
        entities: context.entities, components: context.components, events: context.events,
        rng: RngService(seed), rules: context.rules, queries: context.queries,
        modifiers: context.modifiers, content: context.content, resources: context.resources,
        mastery: context.mastery, progression: context.progression, discovery: context.discovery,
        tome: context.tome,
      );

      final survivor = combineItems(owner, [a, b], seededContext);

      final instance = context.components.get<ItemInstance>(survivor)!;
      expect(instance.definitionId, equals('fixture_sharp_knife'));
      expect(instance.itemClass, equals(1));
    });

    test('a Tome-placed survivor\'s placement is transparently updated', () {
      loadSimpleKnife(context, gradeEvolution: [
        {'targetId': 'fixture_sharp_knife'},
      ]);
      final owner = context.entities.create();
      final a = ownItem(owner, 'simple_knife', context);
      final b = ownItem(owner, 'simple_knife', context);
      context.resources.set(owner, ItemResources.upgradePoints, 10);
      context.tome.defineTome(
        TomeDefinition.namedSlots(id: 'basic_tome', slotIds: ['weapon']),
      );
      context.tome.createTome(owner, 'basic_tome');
      context.tome.insert(
        owner,
        const SlotId('weapon'),
        BuildComponentRef(
          referenceType: itemReferenceType, contentId: 'simple_knife', instanceEntityId: a),
      );
      final seed = seedForOutcome(CombineOutcome.branchUpgrade, tier: 1, inputCount: 2);
      final seededContext = PluginContext(
        entities: context.entities, components: context.components, events: context.events,
        rng: RngService(seed), rules: context.rules, queries: context.queries,
        modifiers: context.modifiers, content: context.content, resources: context.resources,
        mastery: context.mastery, progression: context.progression, discovery: context.discovery,
        tome: context.tome,
      );

      final survivor = combineItems(owner, [a, b], seededContext);

      final placement = context.tome.inspect(owner).single;
      expect(placement.buildComponentRef.contentId, equals('fixture_sharp_knife'));
      expect(placement.buildComponentRef.instanceEntityId, equals(survivor));
      expect(placement.slot, equals(const SlotId('weapon'))); // slot preserved
    });

    test('two currently-placed combined instances do not crash, and only '
        'the survivor\'s own slot is updated', () {
      loadSimpleKnife(context);
      final owner = context.entities.create();
      final a = ownItem(owner, 'simple_knife', context);
      final b = ownItem(owner, 'simple_knife', context);
      context.resources.set(owner, ItemResources.upgradePoints, 10);
      context.tome.defineTome(
        TomeDefinition.namedSlots(id: 'basic_tome', slotIds: ['weapon', 'offhand']),
      );
      context.tome.createTome(owner, 'basic_tome');
      context.tome.insert(
        owner,
        const SlotId('weapon'),
        BuildComponentRef(
          referenceType: itemReferenceType, contentId: 'simple_knife', instanceEntityId: a),
      );
      context.tome.insert(
        owner,
        const SlotId('offhand'),
        BuildComponentRef(
          referenceType: itemReferenceType, contentId: 'simple_knife', instanceEntityId: b),
      );
      final seed = seedForOutcome(CombineOutcome.tierUpgrade, tier: 1, inputCount: 2);
      final seededContext = PluginContext(
        entities: context.entities, components: context.components, events: context.events,
        rng: RngService(seed), rules: context.rules, queries: context.queries,
        modifiers: context.modifiers, content: context.content, resources: context.resources,
        mastery: context.mastery, progression: context.progression, discovery: context.discovery,
        tome: context.tome,
      );

      late EntityId survivor;
      expect(() => survivor = combineItems(owner, [a, b], seededContext), returnsNormally);

      final survivorPlacement = context.tome
          .inspect(owner)
          .where((p) => p.buildComponentRef.instanceEntityId == survivor)
          .single;
      expect(survivorPlacement.buildComponentRef.contentId, equals('simple_knife'));
      expect(context.components.get<ItemInstance>(survivor)!.itemClass, equals(2));
    });

    test('a non-survivor\'s own separate Tome placement is cleaned up, not left '
        'dangling, so exactly one placement remains after the combine', () {
      loadSimpleKnife(context);
      final owner = context.entities.create();
      final a = ownItem(owner, 'simple_knife', context);
      final b = ownItem(owner, 'simple_knife', context);
      context.resources.set(owner, ItemResources.upgradePoints, 10);
      context.tome.defineTome(
        TomeDefinition.namedSlots(id: 'basic_tome', slotIds: ['weapon', 'offhand']),
      );
      context.tome.createTome(owner, 'basic_tome');
      context.tome.insert(
        owner,
        const SlotId('weapon'),
        BuildComponentRef(
          referenceType: itemReferenceType, contentId: 'simple_knife', instanceEntityId: a),
      );
      context.tome.insert(
        owner,
        const SlotId('offhand'),
        BuildComponentRef(
          referenceType: itemReferenceType, contentId: 'simple_knife', instanceEntityId: b),
      );
      final seed = seedForOutcome(CombineOutcome.tierUpgrade, tier: 1, inputCount: 2);
      final seededContext = PluginContext(
        entities: context.entities, components: context.components, events: context.events,
        rng: RngService(seed), rules: context.rules, queries: context.queries,
        modifiers: context.modifiers, content: context.content, resources: context.resources,
        mastery: context.mastery, progression: context.progression, discovery: context.discovery,
        tome: context.tome,
      );

      // Both inputs are Tome-placed; the placed-instance-preference logic
      // (`instanceEntities.firstWhere(placedIds.contains, ...)`) picks the
      // first one found in `[a, b]` order, i.e. `a`, leaving `b`'s own
      // placement (in 'offhand') a genuinely separate, non-survivor
      // placement that must be cleaned up rather than left dangling.
      final survivor = combineItems(owner, [a, b], seededContext);

      final placements = context.tome.inspect(owner);
      expect(placements, hasLength(1));
      expect(placements.single.buildComponentRef.instanceEntityId, equals(survivor));
      expect(placements.single.buildComponentRef.contentId, equals('simple_knife'));
    });

    test('when only one input is Tome-placed, that one survives even if '
        'CombineResolver\'s own RNG pick would have chosen the other', () {
      loadSimpleKnife(context);
      final owner = context.entities.create();
      final a = ownItem(owner, 'simple_knife', context); // placed
      final b = ownItem(owner, 'simple_knife', context); // unplaced
      context.resources.set(owner, ItemResources.upgradePoints, 10);
      context.tome.defineTome(
        TomeDefinition.namedSlots(id: 'basic_tome', slotIds: ['weapon']),
      );
      context.tome.createTome(owner, 'basic_tome');
      context.tome.insert(
        owner,
        const SlotId('weapon'),
        BuildComponentRef(
          referenceType: itemReferenceType, contentId: 'simple_knife', instanceEntityId: a),
      );
      final seed = seedForSecondIndexSurvivor(tier: 1, inputCount: 2);
      final seededContext = PluginContext(
        entities: context.entities, components: context.components, events: context.events,
        rng: RngService(seed), rules: context.rules, queries: context.queries,
        modifiers: context.modifiers, content: context.content, resources: context.resources,
        mastery: context.mastery, progression: context.progression, discovery: context.discovery,
        tome: context.tome,
      );

      // Passing [a, b] means CombineResolver's own RNG-chosen survivorIndex
      // for this seed points at `b` (index 1) — but `a` is the one that's
      // Tome-placed, so it must be the one that actually survives.
      final survivor = combineItems(owner, [a, b], seededContext);

      expect(survivor, equals(a));
      expect(context.components.get<ItemInstance>(a), isNotNull);
      expect(context.components.get<ItemInstance>(b), isNull);
      final placement = context.tome.inspect(owner).single;
      expect(placement.buildComponentRef.instanceEntityId, equals(a));
      expect(placement.buildComponentRef.contentId, equals('simple_knife'));
      expect(context.components.get<ItemInstance>(a)!.itemClass, equals(2));
    });

    test('an unrelated placed instance of the same definitionId is left untouched', () {
      loadSimpleKnife(context);
      final owner = context.entities.create();
      final a = ownItem(owner, 'simple_knife', context);
      final b = ownItem(owner, 'simple_knife', context);
      final unrelated = ownItem(owner, 'simple_knife', context); // not part of this combine call
      context.resources.set(owner, ItemResources.upgradePoints, 10);
      context.tome.defineTome(
        TomeDefinition.namedSlots(id: 'basic_tome', slotIds: ['weapon', 'offhand']),
      );
      context.tome.createTome(owner, 'basic_tome');
      context.tome.insert(
        owner,
        const SlotId('offhand'),
        BuildComponentRef(
          referenceType: itemReferenceType, contentId: 'simple_knife', instanceEntityId: unrelated),
      );
      final seed = seedForOutcome(CombineOutcome.tierUpgrade, tier: 1, inputCount: 2);
      final seededContext = PluginContext(
        entities: context.entities, components: context.components, events: context.events,
        rng: RngService(seed), rules: context.rules, queries: context.queries,
        modifiers: context.modifiers, content: context.content, resources: context.resources,
        mastery: context.mastery, progression: context.progression, discovery: context.discovery,
        tome: context.tome,
      );

      combineItems(owner, [a, b], seededContext);

      final placement = context.tome.inspect(owner).single;
      expect(placement.slot, equals(const SlotId('offhand')));
      expect(placement.buildComponentRef.contentId, equals('simple_knife'));
      expect(placement.buildComponentRef.instanceEntityId, equals(unrelated));
    });

    test('combining an unplaced item leaves the Tome untouched', () {
      loadSimpleKnife(context);
      final owner = context.entities.create();
      final a = ownItem(owner, 'simple_knife', context);
      final b = ownItem(owner, 'simple_knife', context);
      context.resources.set(owner, ItemResources.upgradePoints, 10);
      context.tome.defineTome(
        TomeDefinition.namedSlots(id: 'basic_tome', slotIds: ['weapon']),
      );
      context.tome.createTome(owner, 'basic_tome');

      combineItems(owner, [a, b], context);

      expect(context.tome.inspect(owner), isEmpty);
    });

    test('at maxClass with no grade path, combine throws CombineNotAvailableException', () {
      loadSimpleKnife(context, maxClass: 1); // already at its own cap, no gradeEvolution
      final owner = context.entities.create();
      final a = ownItem(owner, 'simple_knife', context);
      final b = ownItem(owner, 'simple_knife', context);
      context.resources.set(owner, ItemResources.upgradePoints, 10);

      expect(
        () => combineItems(owner, [a, b], context),
        throwsA(isA<CombineNotAvailableException>()),
      );
      expect(context.resources.currentOf(owner, ItemResources.upgradePoints), equals(10)); // untouched
    });

    test('at maxClass with a grade path available, combine proceeds toward grade upgrades only', () {
      loadSimpleKnife(context, maxClass: 1, gradeEvolution: [
        {'targetId': 'fixture_sharp_knife'},
      ]);
      final owner = context.entities.create();
      final a = ownItem(owner, 'simple_knife', context);
      final b = ownItem(owner, 'simple_knife', context);
      context.resources.set(owner, ItemResources.upgradePoints, 10);
      // any seed that is NOT a fail-bucket roll should still succeed as a
      // branchUpgrade thanks to the at-max escalation:
      final seed = seedForOutcome(CombineOutcome.tierUpgrade, tier: 1, inputCount: 2);
      final seededContext = PluginContext(
        entities: context.entities, components: context.components, events: context.events,
        rng: RngService(seed), rules: context.rules, queries: context.queries,
        modifiers: context.modifiers, content: context.content, resources: context.resources,
        mastery: context.mastery, progression: context.progression, discovery: context.discovery,
        tome: context.tome,
      );

      final survivor = combineItems(owner, [a, b], seededContext);

      expect(context.components.get<ItemInstance>(survivor)!.definitionId, equals('fixture_sharp_knife'));
    });
  });

  group('canCombine', () {
    test('true for two owned same-definition same-class knives below maxClass', () {
      final owner = context.entities.create();
      final a = ownItem(owner, ItemIds.knife, context);
      final b = ownItem(owner, ItemIds.knife, context);

      expect(canCombine(owner, [a, b], context), isTrue);
    });

    test('false when definitionId or itemClass mismatch', () {
      final owner = context.entities.create();
      final knife = ownItem(owner, ItemIds.knife, context);
      final sword = ownItem(owner, ItemIds.ironSword, context);
      final knifeHigherClass = ownItem(owner, ItemIds.knife, context);
      context.components.add(
        knifeHigherClass,
        ItemInstance(definitionId: ItemIds.knife, owner: owner, itemClass: 2),
      );

      expect(canCombine(owner, [knife, sword], context), isFalse);
      expect(canCombine(owner, [knife, knifeHigherClass], context), isFalse);
    });

    test('false when already at maxClass with no eligible grade path', () {
      final owner = context.entities.create();
      // masterworkSharpKnife has maxClass 9 and no gradeEvolution entries at all.
      final a = ownItem(owner, ItemIds.masterworkSharpKnife, context);
      final b = ownItem(owner, ItemIds.masterworkSharpKnife, context);
      for (final e in [a, b]) {
        context.components.add(
          e,
          ItemInstance(definitionId: ItemIds.masterworkSharpKnife, owner: owner, itemClass: 9),
        );
      }

      expect(canCombine(owner, [a, b], context), isFalse);
    });

    test('false for fewer than 2 instances, and never throws', () {
      final owner = context.entities.create();
      final a = ownItem(owner, ItemIds.knife, context);

      expect(canCombine(owner, [a], context), isFalse);
      expect(canCombine(owner, [], context), isFalse);
    });

    test('does not mutate state or consume resources', () {
      final owner = context.entities.create();
      final a = ownItem(owner, ItemIds.knife, context);
      final b = ownItem(owner, ItemIds.knife, context);
      context.resources.set(owner, ItemResources.upgradePoints, 5);

      canCombine(owner, [a, b], context);

      expect(context.resources.currentOf(owner, ItemResources.upgradePoints), equals(5));
      expect(context.components.get<ItemInstance>(a), isNotNull);
      expect(context.components.get<ItemInstance>(b), isNotNull);
    });
  });
}
