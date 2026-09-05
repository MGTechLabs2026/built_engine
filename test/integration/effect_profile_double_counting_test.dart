import 'package:build_engine/build_engine.dart';
import 'package:build_engine/build_interpretation.dart';
import 'package:build_engine/combat_plugin.dart';
import 'package:build_engine/item_plugin.dart';
import 'package:build_engine/technique_plugin.dart';
import 'package:test/test.dart';

PluginContext _ctx() {
  final events = EventBus();
  final entities = EntityRegistry(events);
  final components = ComponentStore();
  final rng = RngService(1);
  final shared = CoreServices(components: components, events: events);
  final c = PluginContext(
    entities: entities, components: components, events: events, rng: rng,
    rules: RuleEngine(
      entities: entities, components: components, events: events,
      rng: rng, shared: shared),
    queries: QueryEngine(QueryScope(components: components)),
    modifiers: ModifierCollection(),
    content: ContentRegistry(),
    shared: shared,
  );
  ItemPlugin().initialize(c);
  TechniquePlugin().initialize(c);
  return c;
}

num _stat(PluginContext ctx, EntityId owner, String stat) => const ModifierResolver()
    .resolve(0, ctx.modifiers.activeModifiersFor(owner, stat, ctx.components));

void main() {
  test('Scenario A — a loose (owned, unhung) item: supporting does not count',
      () {
    final ctx = _ctx();
    final owner = ctx.entities.create();
    final knife = itemDefinition(ItemIds.knife, ctx);
    final instanceId = ownItem(owner, knife.id, ctx);
    ctx.tome.defineTome(TomeDefinition.namedSlots(id: 't', slotIds: ['s0']));
    ctx.tome.createTome(owner, 't');
    // NOT inserted into the Tome — stays loose.
    const interp = ItemActionInterpreter();
    final build = ctx.tome.resolve(owner, ownedRefs: [
      BuildComponentRef(referenceType: itemReferenceType, contentId: knife.id,
          instanceEntityId: instanceId),
    ]);
    interp.interpret(build: build, actor: owner, targets: const [], context: ctx);
    final stat = WeaponStatTags.matchOrFallback(knife.tags, 'item:${knife.id}');
    expect(_stat(ctx, owner, stat), 0);
  });

  test('Scenario B — a hung item: supporting counts', () {
    final ctx = _ctx();
    final owner = ctx.entities.create();
    final knife = itemDefinition(ItemIds.knife, ctx);
    final instanceId = ownItem(owner, knife.id, ctx);
    ctx.tome.defineTome(TomeDefinition.namedSlots(id: 't', slotIds: ['s0']));
    ctx.tome.createTome(owner, 't');
    ctx.tome.insert(owner, const SlotId('s0'),
        BuildComponentRef(referenceType: itemReferenceType, contentId: knife.id,
            instanceEntityId: instanceId));
    const interp = ItemActionInterpreter();
    final build = ctx.tome.resolve(owner, ownedRefs: [
      BuildComponentRef(referenceType: itemReferenceType, contentId: knife.id,
          instanceEntityId: instanceId),
    ]);
    interp.interpret(build: build, actor: owner, targets: const [], context: ctx);
    final stat = WeaponStatTags.matchOrFallback(knife.tags, 'item:${knife.id}');
    expect(_stat(ctx, owner, stat), greaterThan(0));
  });

  test('Scenario C — a loose technique variant: neither supporting nor '
      'active counts (nothing hung, nothing acted)', () {
    final ctx = _ctx();
    final owner = ctx.entities.create();
    final instanceId = mintTechniqueVariant(owner, 'basic_punch', {'strong'}, ctx);
    // Not hung; no AttackAction built from it.
    expect(
      requireTechniqueVariant(instanceId, ctx).effectProfile().tier(EffectTier.supporting),
      isEmpty,
    );
  });

  test('Scenario D — a hung, used technique variant: active folds into '
      "this action's own baseDamage", () {
    final ctx = _ctx();
    final owner = ctx.entities.create();
    final instanceId = mintVariantForLegacyEvolvedId(owner, 'heavy_punch', ctx);
    final ref = BuildComponentRef(
        referenceType: techniqueReferenceType, contentId: 'basic_punch',
        instanceEntityId: instanceId);
    const interp = TechniqueActionInterpreter();
    final build = ResolvedBuild(owner: owner, active: [ref], owned: [ref]);
    final actions = interp.interpret(
        build: build, actor: owner, targets: [const EntityId(999)], context: ctx);
    final variant = requireTechniqueVariant(instanceId, ctx);
    final power = variant.effectProfile().amount(EffectTier.active, 'power');
    expect((actions.single as AttackAction).baseDamage,
        techniqueDefinition('basic_punch', ctx).properties['damage']! + power);
  });

  test('Scenario E — two variants of the same family stay distinct: one '
      "variant's active power never leaks into the other's action", () {
    final ctx = _ctx();
    final owner = ctx.entities.create();
    final strong = mintVariantForLegacyEvolvedId(owner, 'heavy_punch', ctx); // +power
    final base = mintTechniqueVariant(owner, 'basic_punch', const {}, ctx); // +0 power
    const interp = TechniqueActionInterpreter();

    final strongRef = BuildComponentRef(
        referenceType: techniqueReferenceType, contentId: 'basic_punch',
        instanceEntityId: strong);
    final baseRef = BuildComponentRef(
        referenceType: techniqueReferenceType, contentId: 'basic_punch',
        instanceEntityId: base);

    final strongAction = interp.interpret(
      build: ResolvedBuild(owner: owner, active: [strongRef], owned: [strongRef, baseRef]),
      actor: owner, targets: [const EntityId(999)], context: ctx,
    ).single as AttackAction;
    final baseAction = interp.interpret(
      build: ResolvedBuild(owner: owner, active: [baseRef], owned: [strongRef, baseRef]),
      actor: owner, targets: [const EntityId(999)], context: ctx,
    ).single as AttackAction;

    expect(strongAction.baseDamage, greaterThan(baseAction.baseDamage));
  });
}
