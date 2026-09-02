import 'package:build_engine/build_engine.dart';
import 'package:build_engine/src/plugins/technique/technique_content.dart';
import 'package:build_engine/src/plugins/technique/technique_variant_lifecycle.dart';
import 'package:build_engine/src/plugins/technique/technique_vocabulary.dart';
import 'package:test/test.dart';

void main() {
  test('inspiration tuning constants have their spec values', () {
    expect(kInspirationBaseChance, 0.05);
    expect(kInspirationConcentrationGain, 0.55);
    expect(kMinMasteryToInspire, 1);
    expect(kMinUsageToInspire, 3);
    expect(kInspirationExcludeRetries, 3);
    expect(kInspirationStrongMasteryBar, 2);
    expect(kInspirationStrongWeightBar, 6.0);
    expect(techniqueFamilyTagPrefix, 'family:');
  });

  test('techniqueFamilyOf maps an evolved id to its base family', () {
    final ctx = _ctx()..content.loadAll(techniqueContentDefinitions);
    expect(techniqueFamilyOf(TechniqueIds.heavyPunch, ctx), TechniqueIds.basicPunch);
    expect(techniqueFamilyOf(TechniqueIds.basicKick, ctx), TechniqueIds.basicKick);
  });

  test('requireTechniqueVariant throws for an unknown instance', () {
    final ctx = _ctx();
    expect(
      () => requireTechniqueVariant(const EntityId(123), ctx),
      throwsA(isA<TechniqueVariantNotFoundException>()),
    );
  });
}

PluginContext _ctx() {
  final events = EventBus();
  final entities = EntityRegistry(events);
  final components = ComponentStore();
  final rng = RngService(1);
  final shared = CoreServices(components: components, events: events);
  return PluginContext(
    entities: entities, components: components, events: events, rng: rng,
    rules: RuleEngine(
      entities: entities, components: components, events: events,
      rng: rng, shared: shared),
    queries: QueryEngine(QueryScope(components: components)),
    modifiers: ModifierCollection(),
    content: ContentRegistry(),
    shared: shared,
  );
}
