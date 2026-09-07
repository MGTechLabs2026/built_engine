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

  test('a malformed consumable definition makes initialize() throw '
      'ContentValidationException (wrapping the ContentFieldException)', () {
    // Drive the PRODUCTION path, not a re-implementation of it. Pre-load a
    // malformed entry under a shipped id: the plugin's "already loaded?"
    // guard then skips registerContentBatch, its validation loop calls
    // `context.content.get('heal_potion')` and hits this bad map, and
    // `consumableDefinitionFromContent` throws the ContentFieldException
    // that `initialize`'s own `on ContentFieldException` catch wraps.
    final ctx = _ctx();
    ctx.content.load({
      'id': ConsumableIds.healPotion,
      'type': 'consumable',
      'tags': <String>[],
      'effect': <String, dynamic>{}, // zero recognized variants
    });

    Object? thrown;
    try {
      ConsumablePlugin().initialize(ctx);
    } catch (e) {
      thrown = e;
    }
    // The wrapper fired — not a bare ContentFieldException and not an
    // unwrapped TypeError leaking past `on ContentFieldException`.
    expect(thrown, isA<ContentValidationException>());
    expect(thrown.toString(), contains(ConsumableIds.healPotion));
  });
}
