import 'package:build_engine/build_engine.dart';
import 'package:build_engine/consumable_plugin.dart';
import 'package:test/test.dart';

void main() {
  test('all shipped consumables load and parse to the expected shapes', () {
    final registry = ContentRegistry()..loadAll(consumableContentDefinitions);

    final heal = consumableDefinitionFromContent(registry.get(ConsumableIds.healPotion));
    expect(heal.effect, isA<ConsumableHeal>());
    expect((heal.effect as ConsumableHeal).amount, 20);
    expect(heal.target, ConsumableTarget.self);
    expect(heal.priority, 8);

    final bomb = consumableDefinitionFromContent(registry.get(ConsumableIds.firebomb));
    final ba = bomb.effect as ConsumableAttack;
    expect(ba.damage, 15);
    expect(ba.stat, 'thrown');
    expect(bomb.target, ConsumableTarget.enemy);
    expect(bomb.priority, 4);

    final tonic = consumableDefinitionFromContent(registry.get(ConsumableIds.powerTonic));
    final tg = tonic.effect as ConsumableGrantModifier;
    expect(tg.stat, 'thrown');
    expect(tg.operation, ModifierOperation.add);
    expect(tg.value, 6);
    expect(tonic.target, ConsumableTarget.self);
    expect(tonic.priority, 6);

    final cleanse = consumableDefinitionFromContent(registry.get(ConsumableIds.cleanseTonic));
    expect(cleanse.effect, isA<ConsumableRemoveAllStatuses>());
    expect(cleanse.target, ConsumableTarget.self);
    expect(cleanse.priority, 5);

    for (final id in [
      ConsumableIds.healPotion,
      ConsumableIds.firebomb,
      ConsumableIds.powerTonic,
      ConsumableIds.cleanseTonic,
    ]) {
      final def = consumableDefinitionFromContent(registry.get(id));
      expect(def.charges, 1, reason: id);
      expect(def.tags, contains('consumable'), reason: id);
    }
  });

  test(
      'ConsumablePlugin.initialize defines an unbounded charge resource for '
      'every shipped consumable', () {
    final events = EventBus();
    final entities = EntityRegistry(events);
    final components = ComponentStore();
    final rng = RngService(1);
    final ctx = PluginContext(
      entities: entities,
      components: components,
      events: events,
      rng: rng,
      rules: RuleEngine(
          entities: entities, components: components, events: events, rng: rng),
      queries: QueryEngine(QueryScope(components: components)),
      modifiers: ModifierCollection(),
      content: ContentRegistry(),
    );
    ConsumablePlugin().initialize(ctx);
    for (final id in [
      ConsumableIds.healPotion,
      ConsumableIds.firebomb,
      ConsumableIds.powerTonic,
      ConsumableIds.cleanseTonic,
    ]) {
      final def = ctx.resources.definitionOf(consumableChargeResource(id));
      expect(def, isNotNull, reason: id);
      expect(def!.max, double.infinity, reason: id);
    }
  });
}
