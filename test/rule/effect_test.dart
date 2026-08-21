import 'package:build_engine/build_engine.dart';
import 'package:test/test.dart';

class _Harness {
  _Harness()
      : events = EventBus(),
        components = ComponentStore() {
    entities = EntityRegistry(events);
  }

  final EventBus events;
  final ComponentStore components;
  late final EntityRegistry entities;

  RuleContext contextFor(EntityId? subject) => RuleContext(
        subject: subject,
        triggerEvent: const Object(),
        entities: entities,
        components: components,
        events: events,
        rng: RngService(1),
        eventCounts: EventCounter(events),
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
