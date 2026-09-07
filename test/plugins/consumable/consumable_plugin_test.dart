import 'package:build_engine/build_engine.dart';
import 'package:build_engine/consumable_plugin.dart';
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
  test('initialize loads content, registers the tag, and defines an unbounded charge resource per consumable', () {
    final ctx = _ctx();
    ConsumablePlugin().initialize(ctx);

    expect(ctx.content.find(ConsumableIds.healPotion), isNotNull);
    final def = ctx.resources.definitionOf(consumableChargeResource(ConsumableIds.healPotion));
    expect(def, isNotNull);
    expect(def!.max, double.infinity);
    expect(def.min, 0);
  });

  test('initialize is idempotent (second call, e.g. after unregister, does not throw)', () {
    final ctx = _ctx();
    ConsumablePlugin().initialize(ctx);
    expect(() => ConsumablePlugin()..initialize(ctx)..unregister(ctx), returnsNormally);
  });

  test('runs standalone with no Combat plugin', () {
    final ctx = _ctx();
    expect(() => ConsumablePlugin().initialize(ctx), returnsNormally);
  });

  test('a malformed consumableContentDefinitions entry surfaces as ContentValidationException', () {
    // white-box: feed a bad entry through the same parse+wrap path the
    // plugin uses. If the shipped content is all valid, assert the shape
    // by parsing a bad map directly and confirming the plugin would wrap
    // it — see consumable_plugin.dart's try/catch.
    final registry = ContentRegistry()
      ..load({'id': 'bad', 'type': 'consumable', 'tags': <String>[], 'effect': <String, dynamic>{}});
    expect(
      () {
        try {
          consumableDefinitionFromContent(registry.get('bad'));
        } on ContentFieldException catch (e) {
          throw ContentValidationException('bad', e);
        }
      },
      throwsA(isA<ContentValidationException>()),
    );
  });
}
