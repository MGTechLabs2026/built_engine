// test/plugins/technique/technique_variant_lifecycle_test.dart
import 'package:build_engine/build_engine.dart';
import 'package:build_engine/src/plugins/technique/technique_content.dart';
import 'package:build_engine/src/plugins/technique/technique_descriptor.dart';
import 'package:build_engine/src/plugins/technique/technique_descriptor_content.dart';
import 'package:build_engine/src/plugins/technique/technique_events.dart';
import 'package:build_engine/src/plugins/technique/technique_lifecycle.dart';
import 'package:build_engine/src/plugins/technique/technique_variant.dart';
import 'package:build_engine/src/plugins/technique/technique_variant_lifecycle.dart';
import 'package:build_engine/src/plugins/technique/technique_variant_resolver.dart';
import 'package:build_engine/src/plugins/technique/technique_vocabulary.dart'
    show TechniqueIds, techniqueInstanceSubject;
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
    // F2 validates the base family at mint time, so every test needs the
    // technique content loaded — not just the ones that hang / remove.
    context.content.loadAll(techniqueContentDefinitions);
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

  test('mint with an unknown descriptor throws and creates no entity', () {
    final before = context.entities.all.length;
    expect(
      () => mintTechniqueVariant(owner, 'basic_punch', {'nonsense'}, context),
      throwsA(isA<UnknownTechniqueDescriptorException>()),
    );
    expect(context.entities.all.length, before);
    expect(context.components.entitiesWith<TechniqueVariant>(), isEmpty);
  });

  test('a basic variant mints with an empty profile', () {
    final id = mintTechniqueVariant(owner, 'basic_guard', const {}, context);
    expect(context.components.get<TechniqueVariant>(id)!.axisProfile, isEmpty);
  });

  group('hangTechniqueVariant', () {
    setUp(() {
      context.progression.define(const ProgressionDefinition(
          subject: 'technique:basic_punch:knowledge', thresholds: [10]));
      for (final def in techniqueContentDefinitions) {
        context.mastery.define(MasteryDefinition(
            subject: 'technique:${def['id']}', thresholds: const [5, 15, 30]));
      }
      context.tome.defineTome(
        TomeDefinition.namedSlots(
            id: 'sp0a_tome', slotIds: ['s0', 's1', 's2', 's3', 's4']),
      );
      context.tome.createTome(owner, 'sp0a_tome');
    });

    test('a derived variant hangs without a learning gate, ref carries the instance', () {
      final id = mintTechniqueVariant(
          owner, 'basic_punch', {'bear'}, context, styleId: 'wing_chun');

      hangTechniqueVariant(const SlotId('s0'), id, context);

      final placements = context.tome.inspect(owner);
      expect(placements, hasLength(1));
      expect(placements.single.buildComponentRef.contentId, 'basic_punch');
      expect(placements.single.buildComponentRef.instanceEntityId, id); // rule 4
    });

    test('a basic variant is gated on the family being learned', () {
      final id = mintTechniqueVariant(owner, 'basic_punch', const {}, context);
      expect(
        () => hangTechniqueVariant(const SlotId('s0'), id, context),
        throwsA(isA<TechniqueNotLearnedException>()),
      );

      final family = techniqueDefinition('basic_punch', context);
      discoverTechnique(owner, family, context);
      attemptToLearnTechnique(owner, family, 10, context);

      hangTechniqueVariant(const SlotId('s0'), id, context);
      expect(context.tome.inspect(owner), hasLength(1));
    });

    test('hanging an unknown instance id throws', () {
      expect(
        () => hangTechniqueVariant(const SlotId('s0'), const EntityId(999), context),
        throwsA(isA<TechniqueVariantNotFoundException>()),
      );
    });

    test('hang publishes TechniqueAddedToTome with the instance id', () {
      TechniqueAddedToTome? seen;
      context.events.subscribe<TechniqueAddedToTome>((e) => seen = e);
      final id = mintTechniqueVariant(owner, 'basic_slash', {'iron'}, context,
          styleId: 'boxing');
      hangTechniqueVariant(const SlotId('s0'), id, context);
      expect(seen?.instanceId, id);
    });
  });

  group('ownership + per-instance mastery', () {
    test('ownedTechniqueVariants returns exactly this owner\'s instances', () {
      final other = context.entities.create();
      final a = mintTechniqueVariant(owner, 'basic_punch', {'bear'}, context,
          styleId: 's');
      final b = mintTechniqueVariant(owner, 'basic_kick', const {}, context);
      final theirs = mintTechniqueVariant(other, 'basic_slash', {'iron'}, context,
          styleId: 's');

      final owned = ownedTechniqueVariants(owner, context);
      expect(owned, containsAll(<EntityId>[a, b]));
      expect(owned, isNot(contains(theirs)));   // rule 5
    });

    test('two instances of the same base master independently', () {
      final a = mintTechniqueVariant(owner, 'basic_punch', {'bear'}, context,
          styleId: 's');
      final b = mintTechniqueVariant(owner, 'basic_punch', {'swift'}, context,
          styleId: 's');

      trainTechniqueVariantMastery(a, 20, context); // no owner arg (rule 5)

      expect(techniqueVariantMasteryLevel(a, context), greaterThan(0));
      expect(techniqueVariantMasteryLevel(b, context), 0);
    });
  });

  group('removeTechniqueVariant', () {
    setUp(() {
      for (final def in techniqueContentDefinitions) {
        context.mastery.define(MasteryDefinition(
            subject: 'technique:${def['id']}', thresholds: const [5, 15, 30]));
      }
      context.tome.defineTome(TomeDefinition.namedSlots(
          id: 'sp0a_tome', slotIds: ['s0', 's1', 's2', 's3', 's4']));
      context.tome.createTome(owner, 'sp0a_tome');
    });

    test('removes the placement, the progress, the component, and the entity', () {
      final id = mintTechniqueVariant(owner, 'basic_punch', {'bear'}, context,
          styleId: 'wing_chun');
      hangTechniqueVariant(const SlotId('s0'), id, context);
      trainTechniqueVariantMastery(id, 10, context);

      removeTechniqueVariant(id, context);

      expect(context.tome.inspect(owner), isEmpty);
      expect(context.components.get<TechniqueVariant>(id), isNull);
      expect(context.entities.isAlive(id), isFalse);
      expect(
        context.mastery.progressOf(owner, techniqueInstanceSubject(id)),
        0,
      );
      // T7: the per-instance MasteryDefinition is deliberately NOT
      // unregistered (MasteryTracker has no undefine) — it survives removal.
      expect(
        context.mastery.definitionOf(techniqueInstanceSubject(id)),
        isNotNull,
      );
    });

    test('publishes TechniqueVariantRemoved', () {
      TechniqueVariantRemoved? seen;
      context.events.subscribe<TechniqueVariantRemoved>((e) => seen = e);
      final id = mintTechniqueVariant(owner, 'basic_kick', const {}, context);
      removeTechniqueVariant(id, context);
      expect(seen?.instanceId, id);
    });

    test('removing an unknown instance throws', () {
      expect(
        () => removeTechniqueVariant(const EntityId(999), context),
        throwsA(isA<TechniqueVariantNotFoundException>()),
      );
    });
  });

  group('legacy coexistence', () {
    test('mints a variant for a legacy evolved id with mapped descriptors', () {
      final id = mintVariantForLegacyEvolvedId(
          owner, TechniqueIds.heavyPunch, context, styleId: 'boxing');
      final v = context.components.get<TechniqueVariant>(id)!;
      expect(v.baseFamilyId, TechniqueIds.basicPunch);
      expect(v.descriptorIds, contains('strong'));
      expect(v.styleId, 'boxing'); // T6: legacy shim forwards styleId
      // profile matches the resolver over the mapped descriptors (no style
      // centre passed, so composeAxisProfile({}, ...) == the resolver output)
      final expected = const TechniqueVariantResolver().resolve([
        for (final d in v.descriptorIds) techniqueDescriptor(d, context),
      ]);
      expect(v.axisProfile, expected);
      // Test A: the migrated instance carries its own per-instance mastery
      // subject, not the base family's.
      expect(context.mastery.definitionOf(techniqueInstanceSubject(id)),
          isNotNull);
    });

    test('legacy ids still resolve as plain definitions (nothing broke)', () {
      expect(
        techniqueDefinition(TechniqueIds.lightningJab, context).id,
        TechniqueIds.lightningJab,
      );
    });

    test('Test D: a base id through the legacy shim mints a plain variant', () {
      // A base family is not an evolved-technique migration — it legitimately
      // has no descriptors and is not rejected.
      final id = mintVariantForLegacyEvolvedId(
          owner, TechniqueIds.basicSlash, context);
      expect(context.components.get<TechniqueVariant>(id)!.descriptorIds, isEmpty);
    });

    test('Test C: a completely unknown id fails with content-not-found, '
        'not a migration exception', () {
      expect(
        () => mintVariantForLegacyEvolvedId(
            owner, 'no_such_technique_at_all', context),
        throwsA(isA<ContentNotFoundException>()),
      );
    });
  });

  group('whole-branch review hardening', () {
    // T2: the full hand-authored evolved-id set that the legacy shim maps.
    const mappedEvolvedIds = <String>[
      TechniqueIds.heavyPunch,
      TechniqueIds.fastPunch,
      TechniqueIds.lightPunch,
      TechniqueIds.hammerBlow,
      TechniqueIds.mountainBreaker,
      TechniqueIds.lightningJab,
      TechniqueIds.flashStrike,
      TechniqueIds.thunderFlash,
      TechniqueIds.heavySlash,
      TechniqueIds.quickSlash,
      TechniqueIds.lightningSlash,
      TechniqueIds.mountainCleave,
      TechniqueIds.ironPalm,
      TechniqueIds.thunderPalm,
      TechniqueIds.lightningFinger,
      TechniqueIds.needleFinger,
      TechniqueIds.piercingFinger,
      TechniqueIds.thrustKick,
      TechniqueIds.spinningKick,
      TechniqueIds.whirlwindKick,
    ];

    test('T2: every legacy mapping mints a real base family with resolvable '
        'descriptors', () {
      for (final legacyId in mappedEvolvedIds) {
        final id = mintVariantForLegacyEvolvedId(owner, legacyId, context);
        final v = context.components.get<TechniqueVariant>(id)!;
        expect(TechniqueIds.bases, contains(v.baseFamilyId),
            reason: '$legacyId mapped to non-base ${v.baseFamilyId}');
        for (final d in v.descriptorIds) {
          expect(() => techniqueDescriptor(d, context), returnsNormally,
              reason: '$legacyId references unknown descriptor $d');
        }
      }
    });

    test('Test B: an unmapped evolved id is rejected, not collapsed to a basic',
        () {
      final before = context.entities.all.length;
      // counter_punch is an evolved id (tier intermediate) with no entry in
      // _legacyEvolvedDescriptors — it must fail loudly.
      expect(
        () => mintVariantForLegacyEvolvedId(
            owner, TechniqueIds.counterPunch, context),
        throwsA(isA<LegacyTechniqueMigrationException>()),
      );
      // Test E: the failed migration left no orphan entity and no variant
      // component behind.
      expect(context.entities.all.length, before);
      expect(context.components.entitiesWith<TechniqueVariant>(), isEmpty);
    });

    test('T4: _requireVariant guards train / level against a bad instance id',
        () {
      expect(
        () => trainTechniqueVariantMastery(const EntityId(999), 5, context),
        throwsA(isA<TechniqueVariantNotFoundException>()),
      );
      expect(
        () => techniqueVariantMasteryLevel(const EntityId(999), context),
        throwsA(isA<TechniqueVariantNotFoundException>()),
      );
    });

    test('T5: mint with a bad baseFamilyId throws content-not-found', () {
      expect(
        () => mintTechniqueVariant(owner, 'no_such_family', const {}, context),
        throwsA(isA<ContentNotFoundException>()),
      );
    });
  });
}
