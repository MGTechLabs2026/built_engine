// test/plugins/technique/technique_variant_lifecycle_test.dart
import 'package:build_engine/build_engine.dart';
import 'package:build_engine/src/plugins/technique/technique_descriptor_content.dart';
import 'package:build_engine/src/plugins/technique/technique_events.dart';
import 'package:build_engine/src/plugins/technique/technique_variant.dart';
import 'package:build_engine/src/plugins/technique/technique_variant_lifecycle.dart';
import 'package:build_engine/src/plugins/technique/technique_vocabulary.dart';
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
  late PluginContext context;
  late EntityId owner;

  setUp(() {
    context = _newContext();
    context.content.loadAll(techniqueDescriptorContentDefinitions);
    owner = context.entities.create();
  });

  test('mint creates a live instance, owner-stamped, with a composed profile', () {
    final id = mintTechniqueVariant(
      owner, 'basic_punch', {'bear', 'thunder'}, context,
      styleId: 'wing_chun',
    );
    expect(context.entities.isAlive(id), isTrue);
    final v = context.components.get<TechniqueVariant>(id)!;
    expect(v.owner, owner);                         // rule 5
    expect(v.baseFamilyId, 'basic_punch');
    expect(v.descriptorIds, {'bear', 'thunder'});
    expect(v.axisProfile['power'], 13);             // bear 6 + thunder 7
    expect(v.axisProfile['speed'], -1);            // bear's secondary axis (rule 1)
    expect(v.styleId, 'wing_chun');
  });

  test('mint applies the style centre additively', () {
    final id = mintTechniqueVariant(
      owner, 'basic_kick', {'swift'}, context,
      styleCentre: const {'speed': 3},
    );
    expect(context.components.get<TechniqueVariant>(id)!.axisProfile['speed'], 8);
  });

  test('mint registers a per-instance mastery definition', () {
    final id = mintTechniqueVariant(owner, 'basic_punch', const {}, context);
    expect(
      context.mastery.definitionOf(techniqueInstanceSubject(id)),
      isNotNull,
    );
  });

  test('mint publishes TechniqueVariantMinted', () {
    TechniqueVariantMinted? seen;
    context.events.subscribe<TechniqueVariantMinted>((e) => seen = e);
    final id = mintTechniqueVariant(owner, 'basic_slash', {'iron'}, context);
    expect(seen, isNotNull);
    expect(seen!.instanceId, id);
    expect(seen!.baseFamilyId, 'basic_slash');
  });

  test('mint with an unknown descriptor throws', () {
    expect(
      () => mintTechniqueVariant(owner, 'basic_punch', {'nonsense'}, context),
      throwsA(isA<UnknownTechniqueDescriptorException>()),
    );
  });

  test('a basic variant mints with an empty profile', () {
    final id = mintTechniqueVariant(owner, 'basic_guard', const {}, context);
    expect(context.components.get<TechniqueVariant>(id)!.axisProfile, isEmpty);
  });
}
