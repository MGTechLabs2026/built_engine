import 'package:build_engine/build_engine.dart';
import 'package:build_engine/build_interpretation.dart';
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
  // charges: heal_potion 1, big_potion 3
  c.content.loadAll([
    {'id': 'heal_potion', 'type': 'consumable', 'tags': <String>[], 'charges': 1, 'effect': {'heal': 5}},
    {'id': 'big_potion', 'type': 'consumable', 'tags': <String>[], 'charges': 3, 'effect': {'heal': 5}},
  ]);
  for (final id in ['heal_potion', 'big_potion']) {
    c.resources.define(ResourceDefinition(id: consumableChargeResource(id), min: 0, max: double.infinity));
  }
  return c;
}

BuildComponentRef _ref(String id) => BuildComponentRef(referenceType: consumableReferenceType, contentId: id);

ResolvedBuild _build(EntityId owner, {List<BuildComponentRef> hung = const [], List<BuildComponentRef> ownedOnly = const []}) =>
    ResolvedBuild(owner: owner, active: hung, owned: [...hung, ...ownedOnly]);

void main() {
  test('grant sums per-copy charges into one pool per content id; 3 refs → 3 (no clamp)', () {
    final ctx = _ctx();
    final owner = ctx.entities.create();
    const ConsumableBinder().grant(
      build: _build(owner, hung: [_ref('heal_potion'), _ref('heal_potion'), _ref('heal_potion')]),
      context: ctx,
    );
    expect(ctx.resources.currentOf(owner, consumableChargeResource('heal_potion')), 3);
  });

  test('different consumables → independent pools; charges honoured', () {
    final ctx = _ctx();
    final owner = ctx.entities.create();
    const ConsumableBinder().grant(
      build: _build(owner, hung: [_ref('heal_potion'), _ref('big_potion')]),
      context: ctx,
    );
    expect(ctx.resources.currentOf(owner, consumableChargeResource('heal_potion')), 1);
    expect(ctx.resources.currentOf(owner, consumableChargeResource('big_potion')), 3);
  });

  test('only build.active consumables count', () {
    final ctx = _ctx();
    final owner = ctx.entities.create();
    const ConsumableBinder().grant(
      build: _build(owner, ownedOnly: [_ref('heal_potion')]),
      context: ctx,
    );
    expect(ctx.resources.currentOf(owner, consumableChargeResource('heal_potion')), 0);
  });

  test('dispose zeroes granted pools and removes consumable:<id>:<owner> modifiers; idempotent', () {
    final ctx = _ctx();
    final owner = ctx.entities.create();
    // simulate a GrantModifier having run this fight
    ctx.modifiers.add(Modifier(
      source: ModifierSource('consumable:heal_potion:${owner.value}'),
      target: owner, stat: 'thrown', operation: ModifierOperation.add, value: 6));

    final charges = const ConsumableBinder().grant(build: _build(owner, hung: [_ref('heal_potion')]), context: ctx);
    expect(ctx.resources.currentOf(owner, consumableChargeResource('heal_potion')), 1);

    charges.dispose();
    charges.dispose(); // idempotent

    expect(ctx.resources.currentOf(owner, consumableChargeResource('heal_potion')), 0);
    expect(ctx.modifiers.activeModifiersFor(owner, 'thrown', ctx.components), isEmpty);
  });

  test('lifecycle: dispose old → resolve new → grant new applies a placement change', () {
    final ctx = _ctx();
    final owner = ctx.entities.create();
    final first = const ConsumableBinder().grant(
      build: _build(owner, hung: [_ref('heal_potion'), _ref('heal_potion')]), context: ctx);
    expect(ctx.resources.currentOf(owner, consumableChargeResource('heal_potion')), 2);

    first.dispose(); // pool → 0
    const ConsumableBinder().grant(build: _build(owner, hung: [_ref('heal_potion')]), context: ctx);
    expect(ctx.resources.currentOf(owner, consumableChargeResource('heal_potion')), 1);
  });

  test('dispose on an empty binding does not throw', () {
    final ctx = _ctx();
    final owner = ctx.entities.create();
    expect(() => const ConsumableBinder().grant(build: _build(owner), context: ctx).dispose(), returnsNormally);
  });
}
