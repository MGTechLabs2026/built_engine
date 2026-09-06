import 'package:build_engine/build_engine.dart';
import 'package:build_engine/combat_plugin.dart';
import 'package:build_engine/technique_plugin.dart';
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
  test('TechniquePlugin.initialize loads every aura RuleDefinition it references', () {
    final ctx = _ctx();
    CombatPlugin().initialize(ctx); // triggers must exist first
    TechniquePlugin().initialize(ctx);

    for (final ref in ['basic_guard', 'basic_slash']) {
      final def = techniqueDefinitionFromContent(ctx.content.get(ref));
      for (final id in def.auraRuleIds) {
        expect(ctx.content.rule(id), isNotNull, reason: '$ref -> $id must be loaded');
      }
    }
  });

  test('TechniquePlugin.initialize is idempotent for aura rules', () {
    final ctx = _ctx();
    CombatPlugin().initialize(ctx);
    TechniquePlugin().initialize(ctx);
    // A second initialize (as after unregister) must not throw a
    // ContentDuplicateIdException on the aura rule ids.
    TechniquePlugin()
      ..initialize(ctx)
      ..unregister(ctx);
  });
}
