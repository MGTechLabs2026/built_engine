/// Pins the *standalone* (Combat-absent) semantics of the plugins' aura
/// content: the `auras` content key still parses, but the aura
/// `RuleDefinition`s themselves are deliberately skipped because their
/// Combat-owned triggers are not registered. Order-dependent by design —
/// a composition that wants auras must initialize `CombatPlugin` first.
/// This test exists so that constraint cannot be silently broken *or*
/// silently "fixed" without a deliberate update here.
library;

import 'package:build_engine/build_engine.dart';
import 'package:build_engine/item_plugin.dart';
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
  test('ItemPlugin initializes with no CombatPlugin and skips its aura rules', () {
    final ctx = _ctx();
    expect(() => ItemPlugin().initialize(ctx), returnsNormally);

    // The content key survives — an item still *declares* its aura.
    expect(
      itemDefinitionFromContent(ctx.content.get('cloth_armor')).auraRuleIds,
      ['aura.regen_weave'],
    );

    // ...but the RuleDefinition it names was never loaded, because the
    // Combat-owned trigger is absent.
    expect(ctx.content.hasTrigger('TurnStarted'), isFalse);
    expect(() => ctx.content.rule('aura.regen_weave'),
        throwsA(isA<ContentNotFoundException>()));
  });

  test('TechniquePlugin initializes with no CombatPlugin and skips its aura rules', () {
    final ctx = _ctx();
    expect(() => TechniquePlugin().initialize(ctx), returnsNormally);

    expect(
      techniqueDefinitionFromContent(ctx.content.get('basic_guard')).auraRuleIds,
      isNotEmpty,
    );

    expect(ctx.content.hasTrigger('TurnStarted'), isFalse);
    for (final id in techniqueDefinitionFromContent(ctx.content.get('basic_guard')).auraRuleIds) {
      expect(() => ctx.content.rule(id), throwsA(isA<ContentNotFoundException>()));
    }
  });
}
