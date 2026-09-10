import 'package:build_engine/affix_plugin.dart';
import 'package:build_engine/build_engine.dart';
import 'package:build_engine/item_plugin.dart';
import 'package:test/test.dart';

PluginContext _ctx() {
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

AffixDefinition _keen(PluginContext ctx) {
  ctx.content.load({
    'id': 'af_keen',
    'type': 'affix',
    'tags': ['affix', 'affix_pool:item_prefix', 'lean:neutral'],
    'label': 'Keen',
    'category': 'item_prefix',
    'mechanic': {'kind': 'weapon_stat_bonus', 'amount': 3},
  });
  return affixDefinition('af_keen', ctx);
}

AffixDefinition _heal12(PluginContext ctx) {
  ctx.content.load({
    'id': 'af_grounding',
    'type': 'affix',
    'tags': ['affix', 'affix_pool:technique_prefix', 'lean:force'],
    'label': 'Grounding',
    'category': 'technique_prefix',
    'mechanic': {'kind': 'heal', 'amount': 12},
  });
  return affixDefinition('af_grounding', ctx);
}

AffixDefinition _bank2(PluginContext ctx) {
  ctx.content.load({
    'id': 'af_drilled',
    'type': 'affix',
    'tags': ['affix', 'affix_pool:technique_prefix', 'lean:neutral'],
    'label': 'Drilled',
    'category': 'technique_prefix',
    'mechanic': {'kind': 'bank_progression', 'amount': 2},
  });
  return affixDefinition('af_drilled', ctx);
}

void main() {
  test('WeaponStatBonus binds the resolved stat to the ItemInstance, returns the mechanic kind', () {
    final ctx = _ctx();
    ItemPlugin().initialize(ctx);
    final owner = ctx.entities.create();
    final instance = ownItem(owner, ItemIds.knife, ctx); // knife has a 'blade' tag
    final r = applyAffixMechanic(
        _keen(ctx), ItemInstanceTarget(instance: instance, itemId: ItemIds.knife), ctx);
    expect(r.stat, 'weapon_stat_bonus');
    // the mechanical bind still uses the WeaponStatTags-resolved tag
    expect(ctx.components.get<ItemInstance>(instance)!.statBonuses['blade'], 3);
  });

  test('two WeaponStatBonus applications accumulate on the same copy', () {
    final ctx = _ctx();
    ItemPlugin().initialize(ctx);
    final owner = ctx.entities.create();
    final instance = ownItem(owner, ItemIds.knife, ctx);
    final target = ItemInstanceTarget(instance: instance, itemId: ItemIds.knife);
    final keen = _keen(ctx);
    applyAffixMechanic(keen, target, ctx); // +3
    applyAffixMechanic(keen, target, ctx); // +3
    expect(ctx.components.get<ItemInstance>(instance)!.statBonuses['blade'], 6);
  });

  test('ImmediateHeal raises HealthComponent.current, clamped, returns stat "heal"', () {
    final ctx = _ctx();
    final c = ctx.entities.create();
    ctx.components.add(c, const HealthComponent(current: 90, max: 100));
    final r = applyAffixMechanic(_heal12(ctx), CharacterTarget(character: c), ctx);
    expect(r.stat, 'heal');
    expect(ctx.components.get<HealthComponent>(c)!.current, 100); // clamped to max
  });

  test('BankProgression adds upgrade points, returns stat "bank_progression"', () {
    final ctx = _ctx();
    ItemPlugin().initialize(ctx); // defines the upgradePoints resource
    final c = ctx.entities.create();
    final r = applyAffixMechanic(_bank2(ctx), CharacterTarget(character: c), ctx);
    expect(r.stat, 'bank_progression');
    expect(ctx.resources.currentOf(c, ItemResources.upgradePoints), 2);
  });

  test('mechanic / target mismatch throws ArgumentError', () {
    final ctx = _ctx();
    ItemPlugin().initialize(ctx);
    final c = ctx.entities.create();
    expect(
        () => applyAffixMechanic(_keen(ctx), CharacterTarget(character: c), ctx),
        throwsArgumentError);
    final owner = ctx.entities.create();
    final instance = ownItem(owner, ItemIds.knife, ctx);
    expect(
        () => applyAffixMechanic(
            _heal12(ctx), ItemInstanceTarget(instance: instance, itemId: ItemIds.knife), ctx),
        throwsArgumentError);
  });
}
