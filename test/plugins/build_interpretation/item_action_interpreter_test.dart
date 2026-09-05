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

/// [hung] refs are hung (both `active` and `owned`); [ownedOnly] refs are
/// owned but not on the Tome (`owned`-only) — proving "not hung -> no
/// modifier" under the new supporting-only-while-hung model.
ResolvedBuild _build(
  EntityId owner, {
  List<BuildComponentRef> hung = const [],
  List<BuildComponentRef> ownedOnly = const [],
}) =>
    ResolvedBuild(owner: owner, active: hung, owned: [...hung, ...ownedOnly]);

void main() {
  const interpreter = ItemActionInterpreter();

  test('an item with an attack property registers a stat modifier for the actor', () {
    final context = _newContext();
    context.content.loadAll(itemContentDefinitions);
    final actor = context.entities.create();
    final build = _build(actor, hung: const [
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
    final build = _build(actor, hung: const [
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
    final build = _build(actor, hung: const [
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
    final build = _build(actor, hung: const [
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
    final build = _build(actor, hung: [
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
    final build = _build(actor, hung: const [
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

    final build = _build(actor, hung: [
      BuildComponentRef(
        referenceType: itemReferenceType,
        contentId: ItemIds.ironSword,
        instanceEntityId: copy,
      ),
    ]);

    interpreter.interpret(
        build: build, actor: actor, targets: const [], context: context);

    final blade =
        context.modifiers.activeModifiersFor(actor, 'blade', context.components).toList();
    // base attack 3 + affix 5, now summed into one modifier per stat.
    expect(blade, hasLength(1));
    expect(blade.single.value, equals(8));
    expect(blade.single.source, equals(const ModifierSource('effectprofile:item:blade')));

    // re-interpreting doesn't stack the summed modifier
    interpreter.interpret(
        build: build, actor: actor, targets: const [], context: context);
    expect(
        context.modifiers.activeModifiersFor(actor, 'blade', context.components),
        hasLength(1));
  });

  test('an unhung affixed copy grants nothing', () {
    final context = _newContext();
    context.content.loadAll(itemContentDefinitions);
    final actor = context.entities.create();
    final copy = ownItem(actor, ItemIds.ironSword, context);
    addItemStatBonuses(copy, {'blade': 5}, context);

    // owned but not on the Tome -- supporting tier only counts while hung.
    // A modifier is still emitted for 'blade' (the stat key surfaces from
    // the owned profile), but EffectProfileResolver sums permanent-over-
    // owned + supporting-over-hung, and this item contributes neither
    // while unhung -- so its value is 0, same net effect as "no modifier"
    // under the old per-ref direct-modifier model.
    interpreter.interpret(
        build: _build(actor, ownedOnly: [
          BuildComponentRef(
            referenceType: itemReferenceType,
            contentId: ItemIds.ironSword,
            instanceEntityId: copy,
          ),
        ]),
        actor: actor,
        targets: const [],
        context: context);

    final blade =
        context.modifiers.activeModifiersFor(actor, 'blade', context.components).toList();
    expect(blade, hasLength(1));
    expect(blade.single.value, equals(0));
  });
}
