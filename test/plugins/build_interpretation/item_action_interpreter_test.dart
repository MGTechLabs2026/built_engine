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

void main() {
  const interpreter = ItemActionInterpreter();

  test('an item with an attack property registers a stat modifier for the actor', () {
    final context = _newContext();
    context.content.loadAll(itemContentDefinitions);
    final actor = context.entities.create();
    final build = ActiveBuild(owner: actor, components: const [
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
    final build = ActiveBuild(owner: actor, components: const [
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
    final build = ActiveBuild(owner: actor, components: const [
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
    final build = ActiveBuild(owner: actor, components: const [
      BuildComponentRef(referenceType: 'technique', contentId: 'basic_punch'),
    ]);

    interpreter.interpret(build: build, actor: actor, targets: const [], context: context);

    expect(context.modifiers.activeModifiersFor(actor, 'blade', context.components), isEmpty);
  });
}
