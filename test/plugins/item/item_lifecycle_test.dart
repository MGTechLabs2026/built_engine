import 'package:build_engine/build_engine.dart';
import 'package:build_engine/src/plugins/item/item_content.dart';
import 'package:build_engine/src/plugins/item/item_events.dart';
import 'package:build_engine/src/plugins/item/item_instance.dart';
import 'package:build_engine/src/plugins/item/item_lifecycle.dart';
import 'package:build_engine/src/plugins/item/item_rules.dart';
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
    for (final rule in buildItemUsabilityRules([
      itemDefinition(ItemIds.ironSword, context),
    ])) {
      context.rules.register(rule);
    }
    context.mastery.define(
      const MasteryDefinition(subject: 'item:iron_sword', thresholds: [10, 25]),
    );
  });

  test('ownItem creates an ItemInstance referencing the definition', () {
    final owner = context.entities.create();

    final itemEntity = ownItem(owner, ItemIds.ironSword, context);

    expect(context.components.get<ItemInstance>(itemEntity)!.definitionId,
        equals(ItemIds.ironSword));
    expect(isItemOwned(owner, ItemIds.ironSword, context), isTrue);
  });

  test('an item can be discovered', () {
    final owner = context.entities.create();
    final ironSword = itemDefinition(ItemIds.ironSword, context);

    discoverItem(owner, ironSword, context);

    expect(context.discovery.stateOf(owner, 'item:iron_sword'),
        equals(DiscoveryState.discovered));
  });

  test('a discovered item stays LOCKED (not usable) with insufficient mastery', () {
    final owner = context.entities.create();
    final ironSword = itemDefinition(ItemIds.ironSword, context);
    discoverItem(owner, ironSword, context);

    expect(isItemUsable(owner, ironSword, context), isFalse);
  });

  test('mastery increases through the generic Mastery system', () {
    final owner = context.entities.create();

    context.mastery.increase(owner, 'item:iron_sword', 10);

    expect(context.mastery.levelOf(owner, 'item:iron_sword'), equals(1));
  });

  test('item becomes USABLE once mastery reaches the required level', () {
    final owner = context.entities.create();
    final ironSword = itemDefinition(ItemIds.ironSword, context);
    discoverItem(owner, ironSword, context);

    context.mastery.increase(owner, 'item:iron_sword', 25);

    expect(isItemUsable(owner, ironSword, context), isTrue);
    // the usability rule also promoted Discovery to unlocked:
    expect(context.discovery.stateOf(owner, 'item:iron_sword'),
        equals(DiscoveryState.unlocked));
  });

  test('an unusable item cannot enter the Tome', () {
    final owner = context.entities.create();
    final ironSword = itemDefinition(ItemIds.ironSword, context);
    discoverItem(owner, ironSword, context);
    context.tome.defineTome(
      TomeDefinition.namedSlots(id: 'basic_tome', slotIds: ['weapon']),
    );
    context.tome.createTome(owner, 'basic_tome');

    expect(
      () => addItemToTome(owner, const SlotId('weapon'), ironSword, context),
      throwsA(isA<ItemNotUsableException>()),
    );
    expect(context.tome.inspect(owner), isEmpty);
  });

  test('a usable item can enter the Tome and becomes ACTIVE', () {
    final owner = context.entities.create();
    final ironSword = itemDefinition(ItemIds.ironSword, context);
    discoverItem(owner, ironSword, context);
    context.mastery.increase(owner, 'item:iron_sword', 25);
    context.tome.defineTome(
      TomeDefinition.namedSlots(id: 'basic_tome', slotIds: ['weapon']),
    );
    context.tome.createTome(owner, 'basic_tome');

    ItemAddedToTome? published;
    context.events.subscribe<ItemAddedToTome>((e) => published = e);

    addItemToTome(owner, const SlotId('weapon'), ironSword, context);

    expect(isItemActive(owner, ItemIds.ironSword, context), isTrue);
    expect(published, isNotNull);
    expect(published!.definitionId, equals(ItemIds.ironSword));
  });

  test('OWNED/DISCOVERED/USABLE/ACTIVE are independently queryable, not one boolean', () {
    final owner = context.entities.create();
    final ironSword = itemDefinition(ItemIds.ironSword, context);
    context.tome.defineTome(
      TomeDefinition.namedSlots(id: 'basic_tome', slotIds: ['weapon']),
    );
    context.tome.createTome(owner, 'basic_tome');
    ownItem(owner, ItemIds.ironSword, context);

    // Owned, but not discovered/usable/active yet.
    expect(isItemOwned(owner, ItemIds.ironSword, context), isTrue);
    expect(isItemUsable(owner, ironSword, context), isFalse);
    expect(isItemActive(owner, ItemIds.ironSword, context), isFalse);

    discoverItem(owner, ironSword, context);
    context.mastery.increase(owner, 'item:iron_sword', 25);
    addItemToTome(owner, const SlotId('weapon'), ironSword, context);

    expect(isItemOwned(owner, ItemIds.ironSword, context), isTrue);
    expect(isItemUsable(owner, ironSword, context), isTrue);
    expect(isItemActive(owner, ItemIds.ironSword, context), isTrue);
  });

  test('an item with no requirement is usable immediately once discovered', () {
    final owner = context.entities.create();
    final knife = itemDefinition(ItemIds.knife, context);

    discoverItem(owner, knife, context);

    expect(isItemUsable(owner, knife, context), isTrue);
  });

  test('addItemToTome without an instance defaults instanceEntityId to null', () {
    final owner = context.entities.create();
    final ironSword = itemDefinition(ItemIds.ironSword, context);
    discoverItem(owner, ironSword, context);
    context.mastery.increase(owner, 'item:iron_sword', 25);
    context.tome.defineTome(
      TomeDefinition.namedSlots(id: 'basic_tome', slotIds: ['weapon']),
    );
    context.tome.createTome(owner, 'basic_tome');

    addItemToTome(owner, const SlotId('weapon'), ironSword, context);

    final placement = context.tome.inspect(owner).single;
    expect(placement.buildComponentRef.instanceEntityId, isNull);
  });

  test('addItemToTome can carry a specific owned instance\'s id', () {
    final owner = context.entities.create();
    final ironSword = itemDefinition(ItemIds.ironSword, context);
    discoverItem(owner, ironSword, context);
    context.mastery.increase(owner, 'item:iron_sword', 25);
    context.tome.defineTome(
      TomeDefinition.namedSlots(id: 'basic_tome', slotIds: ['weapon']),
    );
    context.tome.createTome(owner, 'basic_tome');
    final instanceEntity = ownItem(owner, ItemIds.ironSword, context);

    addItemToTome(owner, const SlotId('weapon'), ironSword, context,
        instanceEntityId: instanceEntity);

    final placement = context.tome.inspect(owner).single;
    expect(placement.buildComponentRef.instanceEntityId, equals(instanceEntity));
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
                ? CombineOutcome.classUpgrade
                : CombineOutcome.gradeUpgrade;
        if (outcome == target) return seed;
      }
      throw StateError('no seed up to $maxSeed produced $target');
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

    test('a non-combinable item (no maxClass declared) throws CombineNotAvailableException', () {
      final owner = context.entities.create();
      final a = ownItem(owner, ItemIds.knife, context);
      final b = ownItem(owner, ItemIds.knife, context);
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

    test('a classUpgrade outcome increments the survivor\'s itemClass', () {
      loadSimpleKnife(context);
      final owner = context.entities.create();
      final a = ownItem(owner, 'simple_knife', context);
      final b = ownItem(owner, 'simple_knife', context);
      context.resources.set(owner, ItemResources.upgradePoints, 10);
      final seed = seedForOutcome(CombineOutcome.classUpgrade, tier: 1, inputCount: 2);
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
      expect(published!.outcome, equals(CombineOutcome.classUpgrade));
      expect(published!.newClass, equals(2));
    });

    test('a gradeUpgrade outcome swaps the survivor\'s definitionId, itemClass unchanged', () {
      loadSimpleKnife(context, gradeEvolution: [
        {'targetId': 'sharp_knife'},
      ]);
      final owner = context.entities.create();
      final a = ownItem(owner, 'simple_knife', context);
      final b = ownItem(owner, 'simple_knife', context);
      context.resources.set(owner, ItemResources.upgradePoints, 10);
      final seed = seedForOutcome(CombineOutcome.gradeUpgrade, tier: 1, inputCount: 2);
      final seededContext = PluginContext(
        entities: context.entities, components: context.components, events: context.events,
        rng: RngService(seed), rules: context.rules, queries: context.queries,
        modifiers: context.modifiers, content: context.content, resources: context.resources,
        mastery: context.mastery, progression: context.progression, discovery: context.discovery,
        tome: context.tome,
      );

      final survivor = combineItems(owner, [a, b], seededContext);

      final instance = context.components.get<ItemInstance>(survivor)!;
      expect(instance.definitionId, equals('sharp_knife'));
      expect(instance.itemClass, equals(1));
    });

    test('a Tome-placed survivor\'s placement is transparently updated', () {
      loadSimpleKnife(context, gradeEvolution: [
        {'targetId': 'sharp_knife'},
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
      final seed = seedForOutcome(CombineOutcome.gradeUpgrade, tier: 1, inputCount: 2);
      final seededContext = PluginContext(
        entities: context.entities, components: context.components, events: context.events,
        rng: RngService(seed), rules: context.rules, queries: context.queries,
        modifiers: context.modifiers, content: context.content, resources: context.resources,
        mastery: context.mastery, progression: context.progression, discovery: context.discovery,
        tome: context.tome,
      );

      final survivor = combineItems(owner, [a, b], seededContext);

      final placement = context.tome.inspect(owner).single;
      expect(placement.buildComponentRef.contentId, equals('sharp_knife'));
      expect(placement.buildComponentRef.instanceEntityId, equals(survivor));
      expect(placement.slot, equals(const SlotId('weapon'))); // slot preserved
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
        {'targetId': 'sharp_knife'},
      ]);
      final owner = context.entities.create();
      final a = ownItem(owner, 'simple_knife', context);
      final b = ownItem(owner, 'simple_knife', context);
      context.resources.set(owner, ItemResources.upgradePoints, 10);
      // any seed that is NOT a fail-bucket roll should still succeed as a
      // gradeUpgrade thanks to the at-max escalation:
      final seed = seedForOutcome(CombineOutcome.classUpgrade, tier: 1, inputCount: 2);
      final seededContext = PluginContext(
        entities: context.entities, components: context.components, events: context.events,
        rng: RngService(seed), rules: context.rules, queries: context.queries,
        modifiers: context.modifiers, content: context.content, resources: context.resources,
        mastery: context.mastery, progression: context.progression, discovery: context.discovery,
        tome: context.tome,
      );

      final survivor = combineItems(owner, [a, b], seededContext);

      expect(context.components.get<ItemInstance>(survivor)!.definitionId, equals('sharp_knife'));
    });
  });
}
