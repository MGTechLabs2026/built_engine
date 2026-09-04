// Every non-base technique id in TechniqueIds that resolves as loaded
// content must migrate through mintVariantForLegacyEvolvedId without a
// LegacyTechniqueMigrationException (spec SP1 §5.1 / §18).
import 'package:build_engine/build_engine.dart';
import 'package:build_engine/technique_plugin.dart';
import 'package:test/test.dart';

PluginContext _ctx() {
  final events = EventBus();
  final entities = EntityRegistry(events);
  final components = ComponentStore();
  final rng = RngService(1);
  final shared = CoreServices(components: components, events: events);
  final c = PluginContext(
    entities: entities, components: components, events: events, rng: rng,
    rules: RuleEngine(
      entities: entities, components: components, events: events,
      rng: rng, shared: shared),
    queries: QueryEngine(QueryScope(components: components)),
    modifiers: ModifierCollection(),
    content: ContentRegistry(),
    shared: shared,
  );
  TechniquePlugin().initialize(c);
  return c;
}

/// Every id declared on TechniqueIds via reflbefore-free enumeration:
/// the static list the plugin itself loads.
Iterable<String> _allTechniqueContentIds() =>
    techniqueContentDefinitions.map((d) => d['id'] as String);

void main() {
  test('every evolved (non-base) shipped technique id migrates to a variant',
      () {
    final ctx = _ctx();
    final owner = ctx.entities.create();
    final evolved = _allTechniqueContentIds()
        .where((id) => !TechniqueIds.bases.contains(id));
    expect(evolved, isNotEmpty);
    for (final id in evolved) {
      final instance = mintVariantForLegacyEvolvedId(owner, id, ctx);
      final v = ctx.components.get<TechniqueVariant>(instance)!;
      expect(TechniqueIds.bases, contains(v.baseFamilyId),
          reason: '$id mapped to non-base ${v.baseFamilyId}');
      expect(v.descriptorIds, isNotEmpty,
          reason: '$id migrated with no descriptors');
      for (final d in v.descriptorIds) {
        expect(() => techniqueDescriptor(d, ctx), returnsNormally,
            reason: '$id references unknown descriptor $d');
      }
    }
  });

  test('an evolved content id with no mapping still fails loudly', () {
    final ctx = _ctx();
    // Inject a throwaway evolved-shaped content def with no map entry.
    ctx.content.loadAll(const [
      {
        'id': 'sp1_unmapped_probe',
        'type': 'technique',
        'name': 'Unmapped Probe',
        'tier': 'intermediate',
        'tags': ['technique', 'fist'],
        'properties': {'damage': 7},
      },
    ]);
    final owner = ctx.entities.create();
    expect(
      () => mintVariantForLegacyEvolvedId(owner, 'sp1_unmapped_probe', ctx),
      throwsA(isA<LegacyTechniqueMigrationException>()),
    );
  });
}
