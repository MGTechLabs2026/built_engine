import 'package:build_engine/build_engine.dart';
import 'package:build_engine/technique_plugin.dart';
import 'package:test/test.dart';

PluginContext _newContext() {
  final events = EventBus();
  final entities = EntityRegistry(events);
  final components = ComponentStore();
  final rng = RngService(1);
  final shared = CoreServices(components: components, events: events);
  return PluginContext(
    entities: entities,
    components: components,
    events: events,
    rng: rng,
    rules: RuleEngine(
      entities: entities, components: components, events: events, rng: rng,
      shared: shared),
    queries: QueryEngine(QueryScope(components: components)),
    modifiers: ModifierCollection(),
    content: ContentRegistry(),
    shared: shared,
  );
}

void main() {
  test('initialize loads descriptor content', () {
    final context = _newContext();
    TechniquePlugin().initialize(context);
    final d = techniqueDescriptor('bear', context);
    expect(d.axes['power'], 6);
  });

  test('initialize twice on one context does not double-load', () {
    final context = _newContext();
    final plugin = TechniquePlugin()..initialize(context);
    plugin.initialize(context); // must not throw ContentDuplicateIdException
    expect(techniqueDescriptor('swift', context).axes['speed'], 5);
  });

  test('variant API is exported from the plugin barrel', () {
    final context = _newContext();
    TechniquePlugin().initialize(context);
    final owner = context.entities.create();
    final id = mintTechniqueVariant(owner, 'basic_punch', {'bear'}, context,
        styleId: 'x');
    expect(context.components.get<TechniqueVariant>(id)!.axisProfile['power'], 6);
  });
}
