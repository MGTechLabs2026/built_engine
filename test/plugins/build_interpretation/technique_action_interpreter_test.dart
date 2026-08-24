import 'package:build_engine/build_engine.dart';
import 'package:build_engine/build_interpretation.dart';
import 'package:build_engine/combat_plugin.dart';
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
  const interpreter = TechniqueActionInterpreter();

  test('a technique with a damage property resolves to an AttackAction', () {
    final context = _newContext();
    context.content.loadAll(techniqueContentDefinitions);
    final actor = context.entities.create();
    final target = context.entities.create();
    final build = ActiveBuild(owner: actor, components: const [
      BuildComponentRef(referenceType: techniqueReferenceType, contentId: TechniqueIds.basicPunch),
    ]);

    final actions = interpreter.interpret(
      build: build,
      actor: actor,
      targets: [target],
      context: context,
    );

    expect(actions, hasLength(1));
    expect(actions.single, isA<AttackAction>());
    expect((actions.single as AttackAction).baseDamage, equals(6));
  });

  test('a guard-tagged technique resolves to a self-targeted defensive action', () {
    final context = _newContext();
    context.content.loadAll(techniqueContentDefinitions);
    final actor = context.entities.create();
    final build = ActiveBuild(owner: actor, components: const [
      BuildComponentRef(referenceType: techniqueReferenceType, contentId: TechniqueIds.basicGuard),
    ]);

    final actions = interpreter.interpret(
      build: build,
      actor: actor,
      targets: const [],
      context: context,
    );

    expect(actions, hasLength(1));
    expect(actions.single, isA<SelfEffectAction>());
    expect(actions.single.targets, equals([actor]));
  });

  test('basic_slash resolves to an AttackAction (Basic Slash example)', () {
    final context = _newContext();
    context.content.loadAll(techniqueContentDefinitions);
    final actor = context.entities.create();
    final target = context.entities.create();
    final build = ActiveBuild(owner: actor, components: const [
      BuildComponentRef(referenceType: techniqueReferenceType, contentId: TechniqueIds.basicSlash),
    ]);

    final actions = interpreter.interpret(
      build: build,
      actor: actor,
      targets: [target],
      context: context,
    );

    expect(actions.single, isA<AttackAction>());
  });

  test('an unknown/invalid technique id produces no action, not a crash', () {
    final context = _newContext();
    context.content.loadAll(techniqueContentDefinitions);
    final actor = context.entities.create();
    final target = context.entities.create();
    final build = ActiveBuild(owner: actor, components: const [
      BuildComponentRef(referenceType: techniqueReferenceType, contentId: 'not_a_real_technique'),
      BuildComponentRef(referenceType: techniqueReferenceType, contentId: TechniqueIds.basicPunch),
    ]);

    final actions = interpreter.interpret(
      build: build,
      actor: actor,
      targets: [target],
      context: context,
    );

    // the valid entry still resolves; the invalid one is silently skipped
    expect(actions, hasLength(1));
    expect(actions.single, isA<AttackAction>());
  });

  test('a non-technique build component is ignored', () {
    final context = _newContext();
    context.content.loadAll(techniqueContentDefinitions);
    final actor = context.entities.create();
    final build = ActiveBuild(owner: actor, components: const [
      BuildComponentRef(referenceType: 'item', contentId: 'knife'),
    ]);

    expect(
      interpreter.interpret(build: build, actor: actor, targets: const [], context: context),
      isEmpty,
    );
  });

  test('deterministic: interpreting the same build twice yields equal actions', () {
    final context = _newContext();
    context.content.loadAll(techniqueContentDefinitions);
    final actor = context.entities.create();
    final target = context.entities.create();
    final build = ActiveBuild(owner: actor, components: const [
      BuildComponentRef(referenceType: techniqueReferenceType, contentId: TechniqueIds.basicPunch),
    ]);

    AttackAction runOnce() =>
        interpreter.interpret(build: build, actor: actor, targets: [target], context: context).single
            as AttackAction;

    final a = runOnce();
    final b = runOnce();
    expect(a.baseDamage, equals(b.baseDamage));
    expect(a.damageStat, equals(b.damageStat));
  });
}
