import 'package:build_engine/build_engine.dart';
import 'package:build_engine/combat_plugin.dart';
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

void main() {
  test('ItemPlugin.initialize loads every aura RuleDefinition it references', () {
    final ctx = _ctx();
    CombatPlugin().initialize(ctx); // triggers must exist first
    ItemPlugin().initialize(ctx);

    for (final ref in ['cloth_armor', 'training_staff', 'training_shoes',
        'warlords_iron_sword', 'crushing_gauntlets']) {
      final def = itemDefinitionFromContent(ctx.content.get(ref));
      for (final id in def.auraRuleIds) {
        expect(() => ctx.content.rule(id), returnsNormally,
            reason: '$ref -> $id must be loaded');
      }
    }
  });

  test('ItemPlugin.initialize is idempotent for aura rules', () {
    final ctx = _ctx();
    CombatPlugin().initialize(ctx);
    ItemPlugin().initialize(ctx);
    // A second initialize (as after unregister) must not throw a
    // ContentDuplicateIdException on the aura rule ids.
    ItemPlugin()
      ..initialize(ctx)
      ..unregister(ctx);
  });
}
