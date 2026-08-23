import 'package:build_engine/build_engine.dart';
// Direct src import until Task 3 adds the barrel export
// (`export 'src/plugins/martial_arts/martial_item_content.dart'` to
// `package:build_engine/martial_arts_plugin.dart`) — adding that export
// is Task 3 wiring, not part of this task. Once exported, both imports
// resolve to the same declarations and this line can be removed.
import 'package:build_engine/src/plugins/martial_arts/martial_item_content.dart';
import 'package:build_engine/martial_arts_plugin.dart';
import 'package:test/test.dart';

void main() {
  test('all 8 item/trinket definitions load atomically as a batch', () {
    final registry = ContentRegistry();
    final definitions = registry.loadAll(martialItemContentDefinitions);
    expect(definitions, hasLength(8));
    expect(registry.allOfType('martial_item'), hasLength(5));
    expect(registry.allOfType('martial_trinket'), hasLength(3));
  });

  group('martialItemDefinitionFromContent', () {
    test('parses an item with a single unconditional modifier', () {
      final registry = ContentRegistry();
      registry.loadAll(martialItemContentDefinitions);
      final definition = martialItemDefinitionFromContent(
          registry.get(MartialItemIds.brassKnuckles));

      expect(definition.id, equals('brass_knuckles'));
      expect(definition.tags, equals({'martial', 'fist', 'western'}));

      final wearer = const EntityId(1);
      final modifiers = definition.modifiersFor(wearer);
      expect(modifiers, hasLength(1));
      expect(modifiers.single.target, equals(wearer));
      expect(modifiers.single.stat, equals('punch'));
      expect(modifiers.single.operation, equals(ModifierOperation.add));
      expect(modifiers.single.value, equals(6));
      expect(modifiers.single.condition, isNull);
    });

    test('parses a trinket with an empty modifiers list', () {
      final registry = ContentRegistry();
      registry.loadAll(martialItemContentDefinitions);
      final definition = martialItemDefinitionFromContent(
          registry.get(MartialItemIds.momentumTrinket));

      expect(definition.modifiersFor(const EntityId(1)), isEmpty);
    });

    test('parses a conditional modifier gated by a tag', () {
      final registry = ContentRegistry();
      registry.loadAll(martialItemContentDefinitions);
      final definition = martialItemDefinitionFromContent(
          registry.get(MartialItemIds.counterstrikeRing));

      final modifiers = definition.modifiersFor(const EntityId(1));
      expect(modifiers, hasLength(1));
      expect(modifiers.single.condition, isNotNull);
      expect(modifiers.single.stat, equals('internal'));
      expect(modifiers.single.value, equals(3));
    });

    test('parses a multiply-operation modifier', () {
      final registry = ContentRegistry();
      registry.loadAll(martialItemContentDefinitions);
      final definition = martialItemDefinitionFromContent(
          registry.get(MartialItemIds.weightedVest));

      final modifiers = definition.modifiersFor(const EntityId(1));
      expect(modifiers.single.operation, equals(ModifierOperation.multiply));
      expect(modifiers.single.value, equals(1.1));
    });
  });

  test('martialItem resolves and parses in one call', () {
    final registry = ContentRegistry();
    registry.loadAll(martialItemContentDefinitions);
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

    final definition = martialItem(MartialItemIds.ironPalmWraps, context);
    expect(definition.id, equals('iron_palm_wraps'));
  });
}
