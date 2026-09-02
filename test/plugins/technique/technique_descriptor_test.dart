import 'package:build_engine/build_engine.dart';
import 'package:build_engine/src/plugins/technique/technique_descriptor.dart';
import 'package:build_engine/src/plugins/technique/technique_descriptor_content.dart';
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
      entities: entities,
      components: components,
      events: events,
      rng: rng,
      shared: shared,
    ),
    queries: QueryEngine(QueryScope(components: components)),
    modifiers: ModifierCollection(),
    content: ContentRegistry(),
    shared: shared,
  );
}

void main() {
  test('techniqueDescriptorFromContent parses a multi-axis descriptor directly', () {
    final registry = ContentRegistry();
    registry.loadAll(const [
      {
        'id': 'bear',
        'type': 'technique',
        'tags': ['technique_descriptor', 'beast'],
        'axes': {'power': 6, 'speed': -1},
      },
    ]);
    final d = techniqueDescriptorFromContent(registry.get('bear'));
    expect(d.id, 'bear');
    expect(d.axes, {'power': 6, 'speed': -1});
    expect(d.tags, contains('beast'));
  });

  test('techniqueDescriptor accessor resolves a descriptor from loaded content', () {
    final context = _newContext();
    context.content.loadAll(const [
      {
        'id': 'bear',
        'type': 'technique',
        'tags': ['technique_descriptor', 'beast'],
        'axes': {'power': 6, 'speed': -1},
      },
    ]);
    final d = techniqueDescriptor('bear', context);
    expect(d.id, 'bear');
    expect(d.axes, {'power': 6, 'speed': -1});
    expect(d.tags, contains('beast'));
  });

  test('techniqueDescriptor accessor throws for an unknown descriptor id', () {
    final context = _newContext();
    expect(
      () => techniqueDescriptor('no_such', context),
      throwsA(isA<UnknownTechniqueDescriptorException>()),
    );
  });

  test('launch descriptor content loads and every entry is a valid descriptor', () {
    final registry = ContentRegistry();
    registry.loadAll(techniqueDescriptorContentDefinitions);
    for (final raw in techniqueDescriptorContentDefinitions) {
      final id = raw['id'] as String;
      final d = techniqueDescriptorFromContent(registry.get(id));
      expect(d.axes, isNotEmpty, reason: '$id has no axes');
      for (final axis in d.axes.keys) {
        expect(TechniqueAxes.all, contains(axis),
            reason: '$id references unknown axis $axis');
      }
    }
    // at least one descriptor whose primary (largest-magnitude) axis is each launch axis
    for (final axis in TechniqueAxes.all) {
      final hit = techniqueDescriptorContentDefinitions.any((r) =>
          (r['axes'] as Map).containsKey(axis));
      expect(hit, isTrue, reason: 'no descriptor touches axis $axis');
    }
    // at least one descriptor is genuinely multi-axis (rule 1)
    expect(
      techniqueDescriptorContentDefinitions.any((r) => (r['axes'] as Map).length > 1),
      isTrue,
    );
  });
}
