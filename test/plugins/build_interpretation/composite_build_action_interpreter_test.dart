import 'package:build_engine/build_engine.dart';
import 'package:build_engine/build_interpretation.dart';
import 'package:build_engine/combat_plugin.dart';
import 'package:build_engine/item_plugin.dart';
import 'package:build_engine/technique_plugin.dart';
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
  test('multiple build components combine: an item boosts a technique\'s resolved damage', () {
    final context = _newContext();
    context.content.loadAll(techniqueContentDefinitions);
    context.content.loadAll(itemContentDefinitions);
    const interpreter = CompositeBuildActionInterpreter([
      TechniqueActionInterpreter(),
      ItemActionInterpreter(),
    ]);

    final actor = context.entities.create();
    final target = context.entities.create();
    // Basic Punch ('fist', damage 6) + Gloves ('fist', attack 1) — both
    // tag 'fist', so Gloves' modifier lands on exactly the stat Basic
    // Punch's AttackAction reads.
    final build = ActiveBuild(owner: actor, components: const [
      BuildComponentRef(referenceType: techniqueReferenceType, contentId: TechniqueIds.basicPunch),
      BuildComponentRef(referenceType: itemReferenceType, contentId: ItemIds.gloves),
    ]);

    final actions = interpreter.interpret(
      build: build,
      actor: actor,
      targets: [target],
      context: context,
    );

    // Gloves contributes no standalone action — only the punch's AttackAction:
    expect(actions, hasLength(1));
    final attack = actions.single as AttackAction;
    expect(attack.baseDamage, equals(6)); // raw, unmodified

    // Combined at execution time, through the existing Modifier Engine:
    final effects = attack.effectsFor(target, context);
    expect(effects.single, isA<Damage>());
    expect((effects.single as Damage).amount, equals(7)); // 6 + 1
  });

  test('an unrecognized reference type is ignored by every interpreter', () {
    final context = _newContext();
    const interpreter = CompositeBuildActionInterpreter([
      TechniqueActionInterpreter(),
      ItemActionInterpreter(),
    ]);
    final actor = context.entities.create();
    final build = ActiveBuild(owner: actor, components: const [
      BuildComponentRef(referenceType: 'currency', contentId: 'gold'),
    ]);

    expect(
      interpreter.interpret(build: build, actor: actor, targets: const [], context: context),
      isEmpty,
    );
  });
}
