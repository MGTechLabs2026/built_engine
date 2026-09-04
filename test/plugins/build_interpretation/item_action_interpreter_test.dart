import 'package:build_engine/build_engine.dart';
import 'package:build_engine/build_interpretation.dart';
import 'package:build_engine/item_plugin.dart';
import 'package:test/test.dart';

PluginContext _newContext() {
  final events = EventBus();
  final entities = EntityRegistry(events);
  final components = ComponentStore();
  final rng = RngService(1);
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

ResolvedBuild _build(EntityId owner, List<BuildComponentRef> refs) =>
    ResolvedBuild(owner: owner, active: refs, owned: refs);

void main() {
  const interpreter = ItemActionInterpreter();

  test('an item with an attack property registers a stat modifier for the actor', () {
    final context = _newContext();
    context.content.loadAll(itemContentDefinitions);
    final actor = context.entities.create();
    final build = _build(actor, const [
      BuildComponentRef(referenceType: itemReferenceType, contentId: ItemIds.ironSword),
    ]);

    final actions = interpreter.interpret(
      build: build,
      actor: actor,
      targets: const [],
      context: context,
    );

    expect(actions, isEmpty); // items contribute modifiers, not standalone actions
    final active =
        context.modifiers.activeModifiersFor(actor, 'blade', context.components).toList();
    expect(active, hasLength(1));
    expect(active.single.value, equals(3)); // iron_sword's 'attack' property
  });

  test('re-interpreting the same build does not stack duplicate modifiers', () {
    final context = _newContext();
    context.content.loadAll(itemContentDefinitions);
    final actor = context.entities.create();
    final build = _build(actor, const [
      BuildComponentRef(referenceType: itemReferenceType, contentId: ItemIds.ironSword),
    ]);

    interpreter.interpret(build: build, actor: actor, targets: const [], context: context);
    interpreter.interpret(build: build, actor: actor, targets: const [], context: context);

    expect(
      context.modifiers.activeModifiersFor(actor, 'blade', context.components),
      hasLength(1),
    );
  });

  test('an unknown/invalid item id produces no modifier, not a crash', () {
    final context = _newContext();
    context.content.loadAll(itemContentDefinitions);
    final actor = context.entities.create();
    final build = _build(actor, const [
      BuildComponentRef(referenceType: itemReferenceType, contentId: 'not_a_real_item'),
    ]);

    expect(
      () => interpreter.interpret(build: build, actor: actor, targets: const [], context: context),
      returnsNormally,
    );
  });

  test('a non-item build component is ignored', () {
    final context = _newContext();
    context.content.loadAll(itemContentDefinitions);
    final actor = context.entities.create();
    final build = _build(actor, const [
      BuildComponentRef(referenceType: 'technique', contentId: 'basic_punch'),
    ]);

    interpreter.interpret(build: build, actor: actor, targets: const [], context: context);

    expect(context.modifiers.activeModifiersFor(actor, 'blade', context.components), isEmpty);
  });

  test('a placed item with a class-3 instance scales its attack modifier', () {
    final context = _newContext();
    context.content.loadAll(itemContentDefinitions);
    final actor = context.entities.create();
    final instanceEntity = context.entities.create();
    context.components.add(
      instanceEntity,
      ItemInstance(definitionId: ItemIds.ironSword, owner: actor, itemClass: 3),
    );
    final build = _build(actor, [
      BuildComponentRef(
        referenceType: itemReferenceType,
        contentId: ItemIds.ironSword,
        instanceEntityId: instanceEntity,
      ),
    ]);

    interpreter.interpret(build: build, actor: actor, targets: const [], context: context);

    final active =
        context.modifiers.activeModifiersFor(actor, 'blade', context.components).toList();
    expect(active, hasLength(1));
    expect(active.single.value, closeTo(3.9, 0.001)); // 3 attack * (1 + 0.15*2)
  });

  test('a placed item with no instanceEntityId falls back to class 1 (unscaled)', () {
    final context = _newContext();
    context.content.loadAll(itemContentDefinitions);
    final actor = context.entities.create();
    final build = _build(actor, const [
      BuildComponentRef(referenceType: itemReferenceType, contentId: ItemIds.ironSword),
    ]);

    interpreter.interpret(build: build, actor: actor, targets: const [], context: context);

    final active =
        context.modifiers.activeModifiersFor(actor, 'blade', context.components).toList();
    expect(active.single.value, equals(3)); // unscaled
  });

  test('a hung copy\'s per-instance affix stat bonuses become modifiers', () {
    final context = _newContext();
    context.content.loadAll(itemContentDefinitions);
    final actor = context.entities.create();
    final copy = ownItem(actor, ItemIds.ironSword, context);
    addItemStatBonuses(copy, {'blade': 5}, context);

    final build = _build(actor, [
      BuildComponentRef(
        referenceType: itemReferenceType,
        contentId: ItemIds.ironSword,
        instanceEntityId: copy,
      ),
    ]);

    interpreter.interpret(
        build: build, actor: actor, targets: const [], context: context);

    final blade =
        context.modifiers.activeModifiersFor(actor, 'blade', context.components);
    // base attack 3 + affix 5, as two separate modifiers on the same stat
    expect(blade.map((m) => m.value).toList()..sort(), [3, 5]);

    // re-interpreting doesn't stack the affix modifier
    interpreter.interpret(
        build: build, actor: actor, targets: const [], context: context);
    expect(
        context.modifiers.activeModifiersFor(actor, 'blade', context.components),
        hasLength(2));
  });

  test('an unhung affixed copy grants nothing', () {
    final context = _newContext();
    context.content.loadAll(itemContentDefinitions);
    final actor = context.entities.create();
    final copy = ownItem(actor, ItemIds.ironSword, context);
    addItemStatBonuses(copy, {'blade': 5}, context);

    // empty build — the copy is owned but not on the Tome
    interpreter.interpret(
        build: _build(actor, const []),
        actor: actor,
        targets: const [],
        context: context);

    expect(
        context.modifiers.activeModifiersFor(actor, 'blade', context.components),
        isEmpty);
  });
}
