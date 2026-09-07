import 'package:build_engine/build_engine.dart';
import 'package:build_engine/build_interpretation.dart';
import 'package:build_engine/combat_plugin.dart';
import 'package:build_engine/consumable_plugin.dart';
import 'package:test/test.dart';

PluginContext _ctx() {
  final events = EventBus();
  final entities = EntityRegistry(events);
  final components = ComponentStore();
  final rng = RngService(1);
  final c = PluginContext(
    entities: entities,
    components: components,
    events: events,
    rng: rng,
    rules: RuleEngine(entities: entities, components: components, events: events, rng: rng),
    queries: QueryEngine(QueryScope(components: components)),
    modifiers: ModifierCollection(),
    content: ContentRegistry(),
  );
  c.content.loadAll([
    {'id': 'hp', 'type': 'consumable', 'tags': <String>[], 'priority': 8, 'effect': {'heal': 20}},
    {'id': 'fb', 'type': 'consumable', 'tags': <String>[], 'priority': 4, 'effect': {'attack': {'damage': 15, 'stat': 'thrown'}}},
    {'id': 'pt', 'type': 'consumable', 'tags': <String>[], 'priority': 6, 'effect': {'grant': {'stat': 'thrown', 'op': 'add', 'value': 6}}},
    {'id': 'ct', 'type': 'consumable', 'tags': <String>[], 'priority': 5, 'effect': {'removeAllStatuses': true}},
  ]);
  return c;
}

ResolvedBuild _build(EntityId owner, {List<BuildComponentRef> hung = const [], List<BuildComponentRef> ownedOnly = const []}) =>
    ResolvedBuild(owner: owner, active: hung, owned: [...hung, ...ownedOnly]);

BuildComponentRef _ref(String id) => BuildComponentRef(referenceType: consumableReferenceType, contentId: id);

void main() {
  const interp = ConsumableActionInterpreter();

  test('heal → SelfEffectAction with Heal + ConsumeResource + priority + sourceRef', () {
    final ctx = _ctx();
    final owner = ctx.entities.create();
    final enemy = ctx.entities.create();
    final actions = interp.interpret(build: _build(owner, hung: [_ref('hp')]), actor: owner, targets: [enemy], context: ctx);
    final a = actions.single as SelfEffectAction;
    expect(a.selfEffects.single, isA<Heal>());
    expect(a.priority, 8);
    expect(a.sourceRef, _ref('hp'));
    expect(a.costEffects.single, isA<ConsumeResource>());
    expect((a.costEffects.single as ConsumeResource).resource, consumableChargeResource('hp'));
  });

  test('attack → AttackAction targeting the passed enemy; empty targets → no action', () {
    final ctx = _ctx();
    final owner = ctx.entities.create();
    final enemy = ctx.entities.create();
    final withEnemy = interp.interpret(build: _build(owner, hung: [_ref('fb')]), actor: owner, targets: [enemy], context: ctx);
    final a = withEnemy.single as AttackAction;
    expect(a.baseDamage, 15);
    expect(a.damageStat, 'thrown');
    expect(a.targets, [enemy]);
    expect(a.priority, 4);

    final noTargets = interp.interpret(build: _build(owner, hung: [_ref('fb')]), actor: owner, targets: const [], context: ctx);
    expect(noTargets, isEmpty);
  });

  test('grant → SelfEffectAction carrying a GrantModifier with the consumable sourceKey', () {
    final ctx = _ctx();
    final owner = ctx.entities.create();
    final actions = interp.interpret(build: _build(owner, hung: [_ref('pt')]), actor: owner, targets: const [], context: ctx);
    final g = (actions.single as SelfEffectAction).selfEffects.single as GrantModifier;
    expect(g.stat, 'thrown');
    expect(g.operation, ModifierOperation.add);
    expect(g.value, 6);
    expect(g.sourceKey, 'consumable:pt');
  });

  test('removeAllStatuses → SelfEffectAction with RemoveAllStatuses', () {
    final ctx = _ctx();
    final owner = ctx.entities.create();
    final actions = interp.interpret(build: _build(owner, hung: [_ref('ct')]), actor: owner, targets: const [], context: ctx);
    expect((actions.single as SelfEffectAction).selfEffects.single, isA<RemoveAllStatuses>());
  });

  test('owned-but-not-hung consumable → no action; hung item/technique ref ignored', () {
    final ctx = _ctx();
    final owner = ctx.entities.create();
    expect(interp.interpret(build: _build(owner, ownedOnly: [_ref('hp')]), actor: owner, targets: const [], context: ctx), isEmpty);
    expect(
      interp.interpret(
        build: _build(owner, hung: [const BuildComponentRef(referenceType: 'item', contentId: 'x')]),
        actor: owner, targets: const [], context: ctx),
      isEmpty,
    );
  });

  test('auraRules returns const []', () {
    final ctx = _ctx();
    final owner = ctx.entities.create();
    expect(interp.auraRules(build: _build(owner, hung: [_ref('hp')]), context: ctx), isEmpty);
  });
}
