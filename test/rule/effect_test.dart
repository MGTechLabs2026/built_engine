import 'package:build_engine/build_engine.dart';
import 'package:test/test.dart';

class _Harness {
  _Harness()
      : events = EventBus(),
        components = ComponentStore() {
    entities = EntityRegistry(events);
    resources = ResourcePool(components: components, events: events);
    mastery = MasteryTracker(components: components, events: events);
    progression =
        ProgressionEngine(components: components, events: events, mastery: mastery);
  }

  final EventBus events;
  final ComponentStore components;
  late final EntityRegistry entities;
  late final ResourcePool resources;
  late final MasteryTracker mastery;
  late final ProgressionEngine progression;

  RuleContext contextFor(EntityId? subject) => RuleContext(
        subject: subject,
        triggerEvent: const Object(),
        entities: entities,
        components: components,
        events: events,
        rng: RngService(1),
        eventCounts: EventCounter(events),
        resources: resources,
        mastery: mastery,
        progression: progression,
      );
}

void main() {
  group('Damage', () {
    test('reduces health and publishes EntityDamaged', () {
      final harness = _Harness();
      final subject = harness.entities.create();
      harness.components
          .add(subject, const HealthComponent(current: 100, max: 100));
      final damaged = <EntityId>[];
      harness.events.subscribe<EntityDamaged>((e) => damaged.add(e.id));

      const Damage(30).apply(harness.contextFor(subject));

      expect(
        harness.components.get<HealthComponent>(subject)!.current,
        equals(70),
      );
      expect(damaged, equals([subject]));
    });

    test('clamps at 0 and publishes EntityKilled', () {
      final harness = _Harness();
      final subject = harness.entities.create();
      harness.components
          .add(subject, const HealthComponent(current: 10, max: 100));
      final killed = <EntityId>[];
      harness.events.subscribe<EntityKilled>((e) => killed.add(e.id));

      const Damage(50).apply(harness.contextFor(subject));

      expect(
        harness.components.get<HealthComponent>(subject)!.current,
        equals(0),
      );
      expect(killed, equals([subject]));
    });

    test('does not destroy the entity on death', () {
      final harness = _Harness();
      final subject = harness.entities.create();
      harness.components
          .add(subject, const HealthComponent(current: 10, max: 100));

      const Damage(50).apply(harness.contextFor(subject));

      expect(harness.entities.isAlive(subject), isTrue);
    });

    test('no-ops with no subject', () {
      final harness = _Harness();
      expect(
        () => const Damage(10).apply(harness.contextFor(null)),
        returnsNormally,
      );
    });

    test('no-ops when the subject has no HealthComponent', () {
      final harness = _Harness();
      final subject = harness.entities.create();

      expect(
        () => const Damage(10).apply(harness.contextFor(subject)),
        returnsNormally,
      );
      expect(harness.components.has<HealthComponent>(subject), isFalse);
    });

    test('does not re-publish EntityKilled on an already-dead subject', () {
      final harness = _Harness();
      final subject = harness.entities.create();
      harness.components
          .add(subject, const HealthComponent(current: 0, max: 100));
      final killed = <EntityId>[];
      harness.events.subscribe<EntityKilled>((e) => killed.add(e.id));

      const Damage(10).apply(harness.contextFor(subject));

      expect(killed, isEmpty);
    });

    test('EntityDamaged reports the amount actually applied, not requested',
        () {
      final harness = _Harness();
      final subject = harness.entities.create();
      harness.components
          .add(subject, const HealthComponent(current: 10, max: 100));
      final damaged = <num>[];
      harness.events.subscribe<EntityDamaged>((e) => damaged.add(e.amount));

      const Damage(50).apply(harness.contextFor(subject));

      expect(damaged, equals([10]));
    });
  });

  group('Heal', () {
    test('increases health and publishes EntityHealed, clamped to max', () {
      final harness = _Harness();
      final subject = harness.entities.create();
      harness.components
          .add(subject, const HealthComponent(current: 90, max: 100));
      final healed = <EntityId>[];
      harness.events.subscribe<EntityHealed>((e) => healed.add(e.id));

      const Heal(30).apply(harness.contextFor(subject));

      expect(
        harness.components.get<HealthComponent>(subject)!.current,
        equals(100),
      );
      expect(healed, equals([subject]));
    });

    test('EntityHealed reports the amount actually applied, not requested',
        () {
      final harness = _Harness();
      final subject = harness.entities.create();
      harness.components
          .add(subject, const HealthComponent(current: 90, max: 100));
      final healed = <num>[];
      harness.events.subscribe<EntityHealed>((e) => healed.add(e.amount));

      const Heal(30).apply(harness.contextFor(subject));

      expect(healed, equals([10]));
    });
  });

  group('ModifyStat', () {
    test('adds delta to an existing stat', () {
      final harness = _Harness();
      final subject = harness.entities.create();
      harness.components.add(subject, StatComponent({'strength': 10}));

      const ModifyStat('strength', 5).apply(harness.contextFor(subject));

      expect(
        harness.components.get<StatComponent>(subject)!.stats['strength'],
        equals(15),
      );
    });

    test('treats a missing stat/component as zero', () {
      final harness = _Harness();
      final subject = harness.entities.create();

      const ModifyStat('strength', 5).apply(harness.contextFor(subject));

      expect(
        harness.components.get<StatComponent>(subject)!.stats['strength'],
        equals(5),
      );
    });
  });

  group('ModifyResource', () {
    test('adds delta to an existing resource', () {
      final harness = _Harness();
      final subject = harness.entities.create();
      harness.components.add(subject, ResourceComponent({'stamina': 20}));

      const ModifyResource('stamina', -5).apply(harness.contextFor(subject));

      expect(
        harness.components.get<ResourceComponent>(subject)!.resources['stamina'],
        equals(15),
      );
    });

    test('publishes ResourceChanged via the shared ResourcePool', () {
      final harness = _Harness();
      final subject = harness.entities.create();
      harness.components.add(subject, ResourceComponent({'stamina': 20}));
      final received = <ResourceChanged>[];
      harness.events.subscribe<ResourceChanged>(received.add);

      const ModifyResource('stamina', -5).apply(harness.contextFor(subject));

      expect(received, hasLength(1));
      expect(received.single.delta, equals(-5));
      expect(received.single.newCurrent, equals(15));
    });
  });

  group('ConsumeResource', () {
    test('subtracts the amount when affordable', () {
      final harness = _Harness();
      final subject = harness.entities.create();
      harness.components.add(subject, ResourceComponent({'mana': 30}));

      const ConsumeResource('mana', 20).apply(harness.contextFor(subject));

      expect(
        harness.components.get<ResourceComponent>(subject)!.resources['mana'],
        equals(10),
      );
    });

    test('no-ops without mutating or publishing when unaffordable', () {
      final harness = _Harness();
      final subject = harness.entities.create();
      harness.components.add(subject, ResourceComponent({'mana': 5}));
      final received = <ResourceChanged>[];
      harness.events.subscribe<ResourceChanged>(received.add);

      const ConsumeResource('mana', 20).apply(harness.contextFor(subject));

      expect(
        harness.components.get<ResourceComponent>(subject)!.resources['mana'],
        equals(5),
      );
      expect(received, isEmpty);
    });
  });

  group('RestoreResource', () {
    test('adds the amount, clamped to the registered maximum', () {
      final harness = _Harness();
      harness.resources.define(const ResourceDefinition(id: 'mana', max: 50));
      final subject = harness.entities.create();
      harness.components.add(subject, ResourceComponent({'mana': 40}));

      const RestoreResource('mana', 30).apply(harness.contextFor(subject));

      expect(
        harness.components.get<ResourceComponent>(subject)!.resources['mana'],
        equals(50),
      );
    });
  });

  group('GrantProgressionExperience', () {
    test('accumulates experience via the shared ProgressionEngine', () {
      final harness = _Harness();
      harness.progression.define(
        const ProgressionDefinition(subject: 'technique:jab', thresholds: [10, 30]),
      );
      final subject = harness.entities.create();

      const GrantProgressionExperience('technique:jab', 15)
          .apply(harness.contextFor(subject));

      expect(harness.progression.experienceOf(subject, 'technique:jab'), equals(15));
      expect(harness.progression.tierOf(subject, 'technique:jab'), equals(1));
    });
  });

  group('UnlockProgressionTier', () {
    test('sets experience to the tier\'s threshold', () {
      final harness = _Harness();
      harness.progression.define(
        const ProgressionDefinition(subject: 'technique:jab', thresholds: [10, 30]),
      );
      final subject = harness.entities.create();

      const UnlockProgressionTier('technique:jab', 2)
          .apply(harness.contextFor(subject));

      expect(harness.progression.tierOf(subject, 'technique:jab'), equals(2));
    });

    test('no-ops for a tier beyond the registered thresholds', () {
      final harness = _Harness();
      harness.progression.define(
        const ProgressionDefinition(subject: 'technique:jab', thresholds: [10]),
      );
      final subject = harness.entities.create();

      const UnlockProgressionTier('technique:jab', 5)
          .apply(harness.contextFor(subject));

      expect(harness.progression.experienceOf(subject, 'technique:jab'), equals(0));
    });
  });

  group('IncreaseMastery', () {
    test('accumulates progress via the shared MasteryTracker', () {
      final harness = _Harness();
      harness.mastery.define(
        const MasteryDefinition(subject: 'item:iron_sword', thresholds: [10, 30]),
      );
      final subject = harness.entities.create();

      const IncreaseMastery('item:iron_sword', 15).apply(harness.contextFor(subject));

      expect(harness.mastery.progressOf(subject, 'item:iron_sword'), equals(15));
      expect(harness.mastery.levelOf(subject, 'item:iron_sword'), equals(1));
    });

    test('the same effect/condition pair works for two unrelated subjects', () {
      final harness = _Harness();
      harness.mastery.define(
        const MasteryDefinition(subject: 'item:iron_sword', thresholds: [10, 30]),
      );
      harness.mastery.define(
        const MasteryDefinition(subject: 'technique:jab', thresholds: [20, 40]),
      );
      final subject = harness.entities.create();
      final context = harness.contextFor(subject);

      const IncreaseMastery('item:iron_sword', 15).apply(context);
      const IncreaseMastery('technique:jab', 25).apply(context);

      expect(MasteryAtLeast('item:iron_sword', 1).evaluate(context), isTrue);
      expect(MasteryAtLeast('item:iron_sword', 2).evaluate(context), isFalse);
      expect(MasteryAtLeast('technique:jab', 1).evaluate(context), isTrue);
      expect(MasteryAtLeast('technique:jab', 2).evaluate(context), isFalse);
      expect(harness.mastery.progressOf(subject, 'item:iron_sword'), equals(15));
      expect(harness.mastery.progressOf(subject, 'technique:jab'), equals(25));
    });
  });

  group('DiscoverSubject / UnlockSubject', () {
    test('DiscoverSubject moves an unknown subject to discovered', () {
      final harness = _Harness();
      final subject = harness.entities.create();

      const DiscoverSubject('item:iron_sword').apply(harness.contextFor(subject));

      final discovery = DiscoveryTracker(
        components: harness.components,
        events: harness.events,
      );
      expect(
        discovery.stateOf(subject, 'item:iron_sword'),
        equals(DiscoveryState.discovered),
      );
    });

    test('UnlockSubject moves a subject to unlocked, auto-discovering it first',
        () {
      final harness = _Harness();
      final subject = harness.entities.create();

      const UnlockSubject('item:iron_sword').apply(harness.contextFor(subject));

      final discovery = DiscoveryTracker(
        components: harness.components,
        events: harness.events,
      );
      expect(
        discovery.stateOf(subject, 'item:iron_sword'),
        equals(DiscoveryState.unlocked),
      );
    });
  });

  group('ApplyStatus / RemoveStatus', () {
    test('ApplyStatus adds a status, creating the component if absent', () {
      final harness = _Harness();
      final subject = harness.entities.create();

      const ApplyStatus('burning').apply(harness.contextFor(subject));

      expect(
        harness.components.get<StatusComponent>(subject)!.activeStatuses,
        contains('burning'),
      );
    });

    test('RemoveStatus removes an active status', () {
      final harness = _Harness();
      final subject = harness.entities.create();
      harness.components.add(subject, StatusComponent({'burning', 'stunned'}));

      const RemoveStatus('burning').apply(harness.contextFor(subject));

      expect(
        harness.components.get<StatusComponent>(subject)!.activeStatuses,
        equals({'stunned'}),
      );
    });

    test('RemoveStatus no-ops when the subject has no StatusComponent', () {
      final harness = _Harness();
      final subject = harness.entities.create();

      expect(
        () => const RemoveStatus('burning').apply(harness.contextFor(subject)),
        returnsNormally,
      );
      expect(harness.components.has<StatusComponent>(subject), isFalse);
    });
  });

  group('AddTag / RemoveTag', () {
    test('AddTag adds a tag, creating the component if absent', () {
      final harness = _Harness();
      final subject = harness.entities.create();

      const AddTag('fire').apply(harness.contextFor(subject));

      expect(harness.components.get<TagSet>(subject)!.tags, contains('fire'));
    });

    test('RemoveTag removes a tag', () {
      final harness = _Harness();
      final subject = harness.entities.create();
      harness.components.add(subject, TagSet({'fire', 'dragon'}));

      const RemoveTag('fire').apply(harness.contextFor(subject));

      expect(harness.components.get<TagSet>(subject)!.tags, equals({'dragon'}));
    });
  });

  group('CreateEntity', () {
    test('creates a new entity distinct from the subject', () {
      final harness = _Harness();
      final subject = harness.entities.create();

      const CreateEntity().apply(harness.contextFor(subject));

      expect(harness.entities.all.length, equals(2));
    });

    test('attaches a TagSet when tags are given', () {
      final harness = _Harness();

      const CreateEntity(tags: {'loot'}).apply(harness.contextFor(null));

      final created = harness.entities.all.single;
      expect(harness.components.get<TagSet>(created)!.tags, equals({'loot'}));
    });

    test('attaches no TagSet when tags are empty', () {
      final harness = _Harness();

      const CreateEntity().apply(harness.contextFor(null));

      final created = harness.entities.all.single;
      expect(harness.components.has<TagSet>(created), isFalse);
    });
  });

  group('DestroyEntity', () {
    test('destroys the subject', () {
      final harness = _Harness();
      final subject = harness.entities.create();

      const DestroyEntity().apply(harness.contextFor(subject));

      expect(harness.entities.isAlive(subject), isFalse);
    });

    test('no-ops on an already-destroyed subject rather than throwing', () {
      final harness = _Harness();
      final subject = harness.entities.create();
      harness.entities.destroy(subject);

      expect(
        () => const DestroyEntity().apply(harness.contextFor(subject)),
        returnsNormally,
      );
    });
  });

  group('TransformEntity', () {
    test('replaces the entire TagSet', () {
      final harness = _Harness();
      final subject = harness.entities.create();
      harness.components.add(subject, TagSet({'unidentified'}));

      const TransformEntity({'identified', 'potion'})
          .apply(harness.contextFor(subject));

      expect(
        harness.components.get<TagSet>(subject)!.tags,
        equals({'identified', 'potion'}),
      );
    });
  });
}
