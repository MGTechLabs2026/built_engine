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
        shared: shared),
    queries: QueryEngine(QueryScope(components: components)),
    modifiers: ModifierCollection(),
    content: ContentRegistry(),
    shared: shared,
  );
  TechniquePlugin().initialize(c);
  return c;
}

// The real `ActiveBuild` constructor is
// `ActiveBuild({required owner, required components})` — the brief's
// `ActiveBuild([ref])` shorthand does not exist, so the helper threads the
// owner through.
ActiveBuild _build(EntityId owner, BuildComponentRef ref) =>
    ActiveBuild(owner: owner, components: [ref]);

void main() {
  const interp = TechniqueActionInterpreter();

  test('a null-instance technique ref keeps base-family damage', () {
    final ctx = _ctx();
    final actor = ctx.entities.create();
    final target = ctx.entities.create();
    final actions = interp.interpret(
        build: _build(
            actor,
            const BuildComponentRef(
                referenceType: techniqueReferenceType,
                contentId: 'basic_punch')),
        actor: actor,
        targets: [target],
        context: ctx);
    expect((actions.single as AttackAction).baseDamage, 6); // basic_punch
  });

  test('a variant ref folds axisProfile["power"] into baseDamage', () {
    final ctx = _ctx();
    final actor = ctx.entities.create();
    final target = ctx.entities.create();
    // heavy_punch maps to {'strong'} => power +4 over basic_punch's 6.
    final instance = mintVariantForLegacyEvolvedId(actor, 'heavy_punch', ctx);
    final actions = interp.interpret(
        build: _build(
            actor,
            BuildComponentRef(
                referenceType: techniqueReferenceType,
                contentId: 'basic_punch',
                instanceEntityId: instance)),
        actor: actor,
        targets: [target],
        context: ctx);
    expect((actions.single as AttackAction).baseDamage, 10); // 6 + 4
  });

  test('baseDamage is floored at 1 when power is strongly negative', () {
    final ctx = _ctx();
    final actor = ctx.entities.create();
    final target = ctx.entities.create();
    // A real {'light','lightning'} variant on basic_punch: power -2 + -1 = -3,
    // so 6 + (-3) = 3 — still >= 1, no clamp yet.
    final instance = mintTechniqueVariant(
        actor, 'basic_punch', {'light', 'lightning'}, ctx);
    final a1 = interp.interpret(
        build: _build(
            actor,
            BuildComponentRef(
                referenceType: techniqueReferenceType,
                contentId: 'basic_punch',
                instanceEntityId: instance)),
        actor: actor,
        targets: [target],
        context: ctx);
    expect((a1.single as AttackAction).baseDamage, 3);

    // A synthetic extreme-negative variant proves the clamp: 6 + (-99) < 1.
    final instance2 = ctx.entities.create();
    ctx.components.add<TechniqueVariant>(
      instance2,
      TechniqueVariant(
        owner: actor,
        baseFamilyId: 'basic_punch',
        descriptorIds: const {},
        axisProfile: const {'power': -99},
      ),
    );
    final a2 = interp.interpret(
        build: _build(
            actor,
            BuildComponentRef(
                referenceType: techniqueReferenceType,
                contentId: 'basic_punch',
                instanceEntityId: instance2)),
        actor: actor,
        targets: [target],
        context: ctx);
    expect((a2.single as AttackAction).baseDamage, 1);
  });

  test('a guard-family variant still emits SelfEffectAction', () {
    final ctx = _ctx();
    final actor = ctx.entities.create();
    final target = ctx.entities.create();
    final instance =
        mintTechniqueVariant(actor, 'basic_guard', const {}, ctx);
    final actions = interp.interpret(
        build: _build(
            actor,
            BuildComponentRef(
                referenceType: techniqueReferenceType,
                contentId: 'basic_guard',
                instanceEntityId: instance)),
        actor: actor,
        targets: [target],
        context: ctx);
    expect(actions.single, isA<SelfEffectAction>());
  });
}
