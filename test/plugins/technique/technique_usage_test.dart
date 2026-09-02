import 'package:build_engine/build_engine.dart';
import 'package:build_engine/src/plugins/technique/technique_content.dart';
import 'package:build_engine/src/plugins/technique/technique_descriptor_content.dart';
import 'package:build_engine/src/plugins/technique/technique_usage.dart';
import 'package:build_engine/src/plugins/technique/technique_variant_lifecycle.dart';
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
  c.content.loadAll(techniqueDescriptorContentDefinitions);
  c.content.loadAll(techniqueContentDefinitions);
  return c;
}

void main() {
  late PluginContext ctx;
  late EntityId owner;
  setUp(() {
    ctx = _ctx();
    owner = ctx.entities.create();
  });

  test('usage starts at zero and increments per recorded action', () {
    final id = mintTechniqueVariant(owner, 'basic_punch', {'bear'}, ctx);
    expect(techniqueVariantUsage(id, ctx), 0);
    recordTechniqueVariantUsage(id, ctx);
    recordTechniqueVariantUsage(id, ctx);
    expect(techniqueVariantUsage(id, ctx), 2);
  });

  test('two instances are tracked independently', () {
    final a = mintTechniqueVariant(owner, 'basic_punch', {'bear'}, ctx);
    final b = mintTechniqueVariant(owner, 'basic_kick', {'swift'}, ctx);
    recordTechniqueVariantUsage(a, ctx);
    expect(techniqueVariantUsage(a, ctx), 1);
    expect(techniqueVariantUsage(b, ctx), 0);
  });

  test('an unknown instance id throws', () {
    expect(() => recordTechniqueVariantUsage(const EntityId(999), ctx),
        throwsA(isA<TechniqueVariantNotFoundException>()));
    expect(() => techniqueVariantUsage(const EntityId(999), ctx),
        throwsA(isA<TechniqueVariantNotFoundException>()));
  });

  test('removeTechniqueVariant drops the usage entry', () {
    final id = mintTechniqueVariant(owner, 'basic_punch', {'bear'}, ctx);
    recordTechniqueVariantUsage(id, ctx);
    removeTechniqueVariant(id, ctx);
    final usage = ctx.components.get<TechniqueUsageComponent>(owner);
    expect(usage == null || !usage.byInstance.containsKey(id), isTrue);
  });

  test('forgetTechniqueVariantUsage on an absent instance is a no-op', () {
    final id = mintTechniqueVariant(owner, 'basic_punch', {'bear'}, ctx);
    forgetTechniqueVariantUsage(id, ctx); // never recorded
    expect(techniqueVariantUsage(id, ctx), 0);
  });
}
