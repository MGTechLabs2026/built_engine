import 'package:build_engine/build_engine.dart';
import 'package:build_engine/build_interpretation.dart';
import 'package:build_engine/combat_plugin.dart';
import 'package:build_engine/technique_plugin.dart';
import 'package:test/test.dart';

PluginContext _ctx() {
  final events = EventBus();
  final entities = EntityRegistry(events);
  final components = ComponentStore();
  final rng = RngService(1);
  final shared = CoreServices(components: components, events: events);
  final c = PluginContext(
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
  c.content.loadAll(techniqueContentDefinitions);
  return c;
}

void main() {
  test('an attack action carries the sourceRef of its technique component', () {
    final ctx = _ctx();
    final actor = ctx.entities.create();
    final enemy = ctx.entities.create();
    const ref = BuildComponentRef(
      referenceType: techniqueReferenceType,
      contentId: TechniqueIds.basicPunch,
      instanceEntityId: EntityId(99),
    );
    final build = ActiveBuild(owner: actor, components: const [
      BuildComponentRef(
        referenceType: techniqueReferenceType,
        contentId: TechniqueIds.basicPunch,
        instanceEntityId: EntityId(99),
      ),
    ]);

    final actions = const TechniqueActionInterpreter().interpret(
      build: build,
      actor: actor,
      targets: [enemy],
      context: ctx,
    );

    expect(actions, hasLength(1));
    expect(actions.single, isA<AttackAction>());
    expect(actions.single.sourceRef, same(ref));
  });

  test('a guard action carries the sourceRef of its technique component', () {
    final ctx = _ctx();
    final actor = ctx.entities.create();
    final enemy = ctx.entities.create();
    const ref = BuildComponentRef(
      referenceType: techniqueReferenceType,
      contentId: TechniqueIds.basicGuard,
      instanceEntityId: EntityId(7),
    );
    final build = ActiveBuild(owner: actor, components: const [
      BuildComponentRef(
        referenceType: techniqueReferenceType,
        contentId: TechniqueIds.basicGuard,
        instanceEntityId: EntityId(7),
      ),
    ]);

    final actions = const TechniqueActionInterpreter().interpret(
      build: build,
      actor: actor,
      targets: [enemy],
      context: ctx,
    );

    expect(actions.single, isA<SelfEffectAction>());
    expect(actions.single.sourceRef, same(ref));
  });
}
