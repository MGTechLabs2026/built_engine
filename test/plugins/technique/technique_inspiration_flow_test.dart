// test/plugins/technique/technique_inspiration_flow_test.dart
import 'package:build_engine/build_engine.dart';
import 'package:build_engine/src/plugins/technique/technique_content.dart';
import 'package:build_engine/src/plugins/technique/technique_descriptor_content.dart';
import 'package:build_engine/src/plugins/technique/technique_events.dart';
import 'package:build_engine/src/plugins/technique/technique_inspiration.dart';
import 'package:build_engine/src/plugins/technique/technique_usage.dart';
import 'package:build_engine/src/plugins/technique/technique_variant.dart';
import 'package:build_engine/src/plugins/technique/technique_variant_lifecycle.dart';
import 'package:test/test.dart';

PluginContext _ctx(int seed) {
  final events = EventBus();
  final entities = EntityRegistry(events);
  final components = ComponentStore();
  final rng = RngService(seed);
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

/// Mint an eligible inspirer: high mastery, plenty of recorded usage.
EntityId _eligibleInspirer(
    PluginContext ctx, EntityId owner, String family, Set<String> descriptors) {
  final id = mintTechniqueVariant(owner, family, descriptors, ctx);
  trainTechniqueVariantMastery(id, 999, ctx); // level 3
  for (var i = 0; i < 20; i++) {
    recordTechniqueVariantUsage(id, ctx);
  }
  return id;
}

/// Scan seeds for one whose run produces a discovery for [body].
int _seedThatDiscovers(bool Function(int seed) body) {
  for (var s = 1; s < 3000; s++) {
    if (body(s)) return s;
  }
  fail('no seed produced a discovery');
}

void main() {
  test('cross-pollination: high-mastery Punch usage inspires a Kick variant', () {
    late TechniqueVariantInspired event;
    var eventCount = 0;

    final seed = _seedThatDiscovers((s) {
      final ctx = _ctx(s);
      final owner = ctx.entities.create();
      _eligibleInspirer(ctx, owner, 'basic_punch', {'bear'});   // power
      _eligibleInspirer(ctx, owner, 'basic_punch', {'swift'});  // speed
      final res = resolveTechniqueInspirationAfterTraining(
        owner, techniqueDefinition('basic_kick', ctx), const {}, ctx);
      return res.discovered;
    });

    final ctx = _ctx(seed);
    final owner = ctx.entities.create();
    final punchA = _eligibleInspirer(ctx, owner, 'basic_punch', {'bear'});
    final punchB = _eligibleInspirer(ctx, owner, 'basic_punch', {'swift'});
    ctx.events.subscribe<TechniqueVariantInspired>((e) {
      event = e;
      eventCount++;
    });

    final res = resolveTechniqueInspirationAfterTraining(
      owner, techniqueDefinition('basic_kick', ctx), const {}, ctx,
      styleId: 'shaolin');

    expect(res.discovered, isTrue);
    expect(eventCount, 1);
    expect(event.familyId, 'basic_kick');
    final minted = ctx.components.get<TechniqueVariant>(event.instanceId)!;
    expect(minted.baseFamilyId, 'basic_kick');
    expect(minted.owner, owner);
    expect(minted.styleId, 'shaolin');
    // Attribution is a subset of {punchA, punchB} and non-empty — the two
    // are the only eligible inspirers, so any attributed id is one of them.
    expect(event.inspirerInstanceIds, isNotEmpty);
    expect(event.inspirerInstanceIds.every({punchA, punchB}.contains), isTrue);
    // seeded by power/speed descriptors → at least one axis is power or speed
    expect(
      minted.axisProfile.keys.any((k) => k == 'power' || k == 'speed'),
      isTrue);
  });

  test('an eligible inspirer that shapes no drawn descriptor is NOT credited', () {
    // heavy Punch (power) + swift Punch (speed) + a wall Guard (endurance).
    // The kick descriptor pool offered is power/speed only, so the
    // endurance Guard is eligible but contributes to nothing drawn.
    late TechniqueVariantInspired event;
    final seed = _seedThatDiscovers((s) {
      final ctx = _ctx(s);
      final owner = ctx.entities.create();
      _eligibleInspirer(ctx, owner, 'basic_punch', {'bear'});   // power
      _eligibleInspirer(ctx, owner, 'basic_punch', {'swift'});  // speed
      _eligibleInspirer(ctx, owner, 'basic_guard', {'wall'});   // endurance
      return resolveTechniqueInspirationAfterTraining(
              owner, techniqueDefinition('basic_kick', ctx), const {}, ctx)
          .discovered;
    });
    final ctx = _ctx(seed);
    final owner = ctx.entities.create();
    final power = _eligibleInspirer(ctx, owner, 'basic_punch', {'bear'});
    final speed = _eligibleInspirer(ctx, owner, 'basic_punch', {'swift'});
    final endur = _eligibleInspirer(ctx, owner, 'basic_guard', {'wall'});
    ctx.events.subscribe<TechniqueVariantInspired>((e) => event = e);

    resolveTechniqueInspirationAfterTraining(
      owner, techniqueDefinition('basic_kick', ctx), const {}, ctx);

    // The launch descriptor pool has power/speed/endurance/precision
    // descriptors; whether an `endurance` descriptor is drawn depends on
    // the seed. Assert the weaker invariant that always holds: the
    // endurance Guard is credited ONLY if an endurance descriptor was
    // actually drawn.
    final drewEndurance = event.descriptorIds.any((id) {
      final def = ctx.content.find(id)!;
      final axes = (def.extra['axes'] as Map);
      final endurance = axes['endurance'];
      return endurance is num && endurance > 0;
    });
    if (event.inspirerInstanceIds.contains(endur)) {
      expect(drewEndurance, isTrue,
          reason: 'the endurance Guard was credited but no endurance '
              'descriptor was drawn');
    }
    // power + speed were definitely in the emphasis; at least one is credited
    expect(
      event.inspirerInstanceIds.any({power, speed}.contains), isTrue);
  });

  test('a newborn inspired variant cannot chain a second discovery', () {
    final seed = _seedThatDiscovers((s) {
      final ctx = _ctx(s);
      final owner = ctx.entities.create();
      _eligibleInspirer(ctx, owner, 'basic_punch', {'bear'});
      _eligibleInspirer(ctx, owner, 'basic_punch', {'swift'});
      return resolveTechniqueInspirationAfterTraining(
              owner, techniqueDefinition('basic_kick', ctx), const {}, ctx)
          .discovered;
    });
    final ctx = _ctx(seed);
    final owner = ctx.entities.create();
    _eligibleInspirer(ctx, owner, 'basic_punch', {'bear'});
    _eligibleInspirer(ctx, owner, 'basic_punch', {'swift'});

    final beforeIds = ownedTechniqueVariants(owner, ctx).toSet();
    final first = resolveTechniqueInspirationAfterTraining(
      owner, techniqueDefinition('basic_kick', ctx), const {}, ctx);
    expect(first.discovered, isTrue);
    // `InspirationResult` carries no instance id (spec §6.1) — the minted
    // variant is the sole new owned instance.
    final newborn = ownedTechniqueVariants(owner, ctx)
        .toSet()
        .difference(beforeIds);
    expect(newborn, hasLength(1));
    final newbornId = newborn.single;

    // The freshly minted variant has mastery 0 / usage 0 → not eligible.
    var events = 0;
    ctx.events.subscribe<TechniqueVariantInspired>((_) => events++);
    // Re-run against the SAME still-eligible punches — still ≤ 1 discovery
    // per call, and the newborn contributes nothing.
    final second = resolveTechniqueInspirationAfterTraining(
      owner, techniqueDefinition('basic_kick', ctx), const {}, ctx);
    expect(second.inspirerInstanceIds, isNot(contains(newbornId)));
    expect(events, lessThanOrEqualTo(1));
  });

  test('below-threshold inspirers → no event, no mint', () {
    final ctx = _ctx(1);
    final owner = ctx.entities.create();
    final weak = mintTechniqueVariant(owner, 'basic_punch', {'bear'}, ctx);
    trainTechniqueVariantMastery(weak, 999, ctx);
    recordTechniqueVariantUsage(weak, ctx); // usage 1 < kMinUsageToInspire
    final before = ctx.components.entitiesWith<TechniqueVariant>().length;
    var events = 0;
    ctx.events.subscribe<TechniqueVariantInspired>((_) => events++);

    final res = resolveTechniqueInspirationAfterTraining(
      owner, techniqueDefinition('basic_kick', ctx), const {}, ctx);

    expect(res.discovered, isFalse);
    expect(events, 0);
    expect(ctx.components.entitiesWith<TechniqueVariant>().length, before);
  });

  test('inspirers are never mutated by a discovery', () {
    final seed = _seedThatDiscovers((s) {
      final ctx = _ctx(s);
      final owner = ctx.entities.create();
      _eligibleInspirer(ctx, owner, 'basic_punch', {'bear'});
      _eligibleInspirer(ctx, owner, 'basic_punch', {'swift'});
      return resolveTechniqueInspirationAfterTraining(
              owner, techniqueDefinition('basic_kick', ctx), const {}, ctx)
          .discovered;
    });
    final ctx = _ctx(seed);
    final owner = ctx.entities.create();
    final a = _eligibleInspirer(ctx, owner, 'basic_punch', {'bear'});
    final aBefore = ctx.components.get<TechniqueVariant>(a)!;
    final aDescriptorsBefore = Set<String>.of(aBefore.descriptorIds);
    final aProfileBefore = Map<String, num>.of(aBefore.axisProfile);
    final aMasteryBefore = techniqueVariantMasteryLevel(a, ctx);
    final aUsageBefore = techniqueVariantUsage(a, ctx);
    _eligibleInspirer(ctx, owner, 'basic_punch', {'swift'});

    resolveTechniqueInspirationAfterTraining(
      owner, techniqueDefinition('basic_kick', ctx), const {}, ctx);

    final aAfter = ctx.components.get<TechniqueVariant>(a)!;
    expect(aAfter.descriptorIds, aDescriptorsBefore); // hard invariant: all four
    expect(aAfter.axisProfile, aProfileBefore);
    expect(techniqueVariantMasteryLevel(a, ctx), aMasteryBefore);
    expect(techniqueVariantUsage(a, ctx), aUsageBefore);
  });
}
