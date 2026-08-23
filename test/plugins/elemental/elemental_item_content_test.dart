// NOTE: the direct `src/` import below is TEMPORARY —
// `elementalItemContentDefinitions`, `elementalItemDefinitionFromContent`,
// and `elementalItem` are not yet exported from
// `package:build_engine/elemental_plugin.dart`; Task 5 adds that barrel
// export, at which point this import is flagged by the analyzer's
// `unnecessary_import` lint and must be removed by Task 5 (same
// deferral pattern as Task 2 / `martial_item_content_test.dart`).
import 'package:build_engine/src/plugins/elemental/elemental_item_content.dart';

import 'package:build_engine/build_engine.dart';
import 'package:build_engine/elemental_plugin.dart';
import 'package:test/test.dart';

void main() {
  test('the 1 item definition loads as a batch', () {
    final registry = ContentRegistry();
    final definitions = registry.loadAll(elementalItemContentDefinitions);
    expect(definitions, hasLength(1));
    expect(registry.allOfType('elemental_item'), hasLength(1));
  });

  test('elementalItemDefinitionFromContent parses id, tags, and a single '
      'conditional modifier', () {
    final registry = ContentRegistry();
    registry.loadAll(elementalItemContentDefinitions);
    final definition = elementalItemDefinitionFromContent(
        registry.get(ElementalItemIds.emberCharm));

    expect(definition.id, equals('ember_charm'));
    expect(definition.tags, equals({'magic', 'fire', 'elemental', 'trinket'}));

    final wearer = const EntityId(1);
    final modifiers = definition.modifiersFor(wearer);
    expect(modifiers, hasLength(1));
    expect(modifiers.single.target, equals(wearer));
    expect(modifiers.single.stat, equals('punch'));
    expect(modifiers.single.operation, equals(ModifierOperation.add));
    expect(modifiers.single.value, equals(4));
    expect(modifiers.single.condition, isNotNull);
  });

  test('elementalItem resolves and parses in one call', () {
    final registry = ContentRegistry();
    registry.loadAll(elementalItemContentDefinitions);
    final context = PluginContext(
      entities: EntityRegistry(EventBus()),
      components: ComponentStore(),
      events: EventBus(),
      rng: RngService(1),
      rules: RuleEngine(
        entities: EntityRegistry(EventBus()),
        components: ComponentStore(),
        events: EventBus(),
        rng: RngService(1),
      ),
      queries: QueryEngine(QueryScope(components: ComponentStore())),
      modifiers: ModifierCollection(),
      content: registry,
    );

    final definition = elementalItem(ElementalItemIds.emberCharm, context);
    expect(definition.id, equals('ember_charm'));
  });
}
