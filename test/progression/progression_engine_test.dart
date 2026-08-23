import 'package:build_engine/build_engine.dart';
import 'package:test/test.dart';

void main() {
  late EventBus events;
  late ComponentStore components;
  late EntityRegistry entities;
  late ProgressionEngine progression;

  setUp(() {
    events = EventBus();
    entities = EntityRegistry(events);
    components = ComponentStore();
    progression = ProgressionEngine(components: components, events: events);
  });

  group('creation', () {
    test('an entity with no progression reads as 0 experience, tier 0', () {
      final id = entities.create();

      expect(progression.experienceOf(id, 'item:brass_knuckles'), equals(0));
      expect(progression.tierOf(id, 'item:brass_knuckles'), equals(0));
    });

    test('define registers thresholds queryable via stateOf', () {
      final id = entities.create();
      progression.define(
        const ProgressionDefinition(
          subject: 'item:brass_knuckles',
          thresholds: [10, 30, 60],
        ),
      );
      components.add(id, MasteryComponent({'item:brass_knuckles': 15}));

      final state = progression.stateOf(id, 'item:brass_knuckles');

      expect(state.experience, equals(15));
      expect(state.tier, equals(1));
    });
  });

  group('experience accumulation and tier crossing', () {
    test('addExperience accumulates and tierOf reflects crossed thresholds',
        () {
      final id = entities.create();
      progression.define(
        const ProgressionDefinition(
          subject: 'technique:jab',
          thresholds: [10, 30, 60],
        ),
      );

      progression.addExperience(id, 'technique:jab', 25);

      expect(progression.experienceOf(id, 'technique:jab'), equals(25));
      expect(progression.tierOf(id, 'technique:jab'), equals(1));
    });

    test('crossing multiple tiers in a single grant publishes one event per tier',
        () {
      final id = entities.create();
      progression.define(
        const ProgressionDefinition(
          subject: 'cultivation:core_formation',
          thresholds: [10, 30, 60],
        ),
      );
      final reached = <ProgressionTierReached>[];
      events.subscribe<ProgressionTierReached>(reached.add);

      progression.addExperience(id, 'cultivation:core_formation', 65);

      expect(reached.map((e) => e.tier), equals([1, 2, 3]));
      expect(progression.tierOf(id, 'cultivation:core_formation'), equals(3));
    });

    test('a subject with no registered definition never reaches a tier', () {
      final id = entities.create();

      progression.addExperience(id, 'unregistered', 1000);

      expect(progression.experienceOf(id, 'unregistered'), equals(1000));
      expect(progression.tierOf(id, 'unregistered'), equals(0));
    });

    test('experience floors at zero', () {
      final id = entities.create();

      progression.addExperience(id, 'technique:jab', -50);

      expect(progression.experienceOf(id, 'technique:jab'), equals(0));
    });
  });

  group('unlock', () {
    test('sets experience to the tier\'s threshold, granting that tier', () {
      final id = entities.create();
      progression.define(
        const ProgressionDefinition(
          subject: 'technique:jab',
          thresholds: [10, 30, 60],
        ),
      );

      progression.unlock(id, 'technique:jab', 1);

      expect(progression.tierOf(id, 'technique:jab'), equals(1));
      expect(progression.experienceOf(id, 'technique:jab'), equals(10));
    });

    test('never regresses progress already beyond the requested tier', () {
      final id = entities.create();
      progression.define(
        const ProgressionDefinition(
          subject: 'technique:jab',
          thresholds: [10, 30, 60],
        ),
      );
      progression.addExperience(id, 'technique:jab', 50);

      progression.unlock(id, 'technique:jab', 1);

      expect(progression.experienceOf(id, 'technique:jab'), equals(50));
    });

    test('throws ArgumentError for a tier below 1', () {
      final id = entities.create();
      progression.define(
        const ProgressionDefinition(
          subject: 'technique:jab',
          thresholds: [10],
        ),
      );

      expect(
        () => progression.unlock(id, 'technique:jab', 0),
        throwsArgumentError,
      );
    });

    test('throws ArgumentError for a tier beyond the registered thresholds',
        () {
      final id = entities.create();
      progression.define(
        const ProgressionDefinition(
          subject: 'technique:jab',
          thresholds: [10],
        ),
      );

      expect(
        () => progression.unlock(id, 'technique:jab', 2),
        throwsArgumentError,
      );
    });
  });

  group('events', () {
    test('addExperience publishes ProgressionChanged with the actual delta',
        () {
      final id = entities.create();
      final received = <ProgressionChanged>[];
      events.subscribe<ProgressionChanged>(received.add);

      progression.addExperience(id, 'item:brass_knuckles', 15);

      expect(received, hasLength(1));
      expect(received.single.id, equals(id));
      expect(received.single.subject, equals('item:brass_knuckles'));
      expect(received.single.delta, equals(15));
      expect(received.single.newExperience, equals(15));
    });

    test('no event when a floored add does not change anything', () {
      final id = entities.create();
      final received = <ProgressionChanged>[];
      events.subscribe<ProgressionChanged>(received.add);

      progression.addExperience(id, 'item:brass_knuckles', -10); // already 0

      expect(received, isEmpty);
    });
  });

  group('deterministic behavior', () {
    test('the same call sequence yields the same resulting state', () {
      final id1 = entities.create();
      progression.define(
        const ProgressionDefinition(subject: 'technique:jab', thresholds: [10, 30]),
      );
      progression.addExperience(id1, 'technique:jab', 15);
      progression.addExperience(id1, 'technique:jab', 10);

      final events2 = EventBus();
      final entities2 = EntityRegistry(events2);
      final components2 = ComponentStore();
      final progression2 =
          ProgressionEngine(components: components2, events: events2);
      final id2 = entities2.create();
      progression2.define(
        const ProgressionDefinition(subject: 'technique:jab', thresholds: [10, 30]),
      );
      progression2.addExperience(id2, 'technique:jab', 15);
      progression2.addExperience(id2, 'technique:jab', 10);

      expect(
        progression.stateOf(id1, 'technique:jab').experience,
        equals(progression2.stateOf(id2, 'technique:jab').experience),
      );
      expect(
        progression.stateOf(id1, 'technique:jab').tier,
        equals(progression2.stateOf(id2, 'technique:jab').tier),
      );
    });
  });
}
