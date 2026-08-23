import 'package:build_engine/build_engine.dart';
import 'package:test/test.dart';

void main() {
  late EventBus events;
  late ComponentStore components;
  late EntityRegistry entities;
  late MasteryTracker mastery;

  setUp(() {
    events = EventBus();
    entities = EntityRegistry(events);
    components = ComponentStore();
    mastery = MasteryTracker(components: components, events: events);
  });

  group('creation', () {
    test('an owner with no mastery reads as 0 progress, level 0', () {
      final owner = entities.create();

      expect(mastery.progressOf(owner, 'item:iron_sword'), equals(0));
      expect(mastery.levelOf(owner, 'item:iron_sword'), equals(0));
    });

    test('define registers thresholds queryable via recordOf', () {
      final owner = entities.create();
      mastery.define(
        const MasteryDefinition(subject: 'item:iron_sword', thresholds: [10, 30]),
      );
      components.add(owner, MasteryComponent({'item:iron_sword': 15}));

      final record = mastery.recordOf(owner, 'item:iron_sword');

      expect(record.owner, equals(owner));
      expect(record.subject, equals('item:iron_sword'));
      expect(record.progress, equals(15));
      expect(record.level, equals(1));
    });
  });

  group('increase and level crossing', () {
    test('increase accumulates and levelOf reflects crossed thresholds', () {
      final owner = entities.create();
      mastery.define(
        const MasteryDefinition(subject: 'technique:jab', thresholds: [10, 30, 60]),
      );

      mastery.increase(owner, 'technique:jab', 25);

      expect(mastery.progressOf(owner, 'technique:jab'), equals(25));
      expect(mastery.levelOf(owner, 'technique:jab'), equals(1));
    });

    test('crossing multiple levels in a single grant publishes one event per level',
        () {
      final owner = entities.create();
      mastery.define(
        const MasteryDefinition(subject: 'technique:jab', thresholds: [10, 30, 60]),
      );
      final reached = <MasteryLevelReached>[];
      events.subscribe<MasteryLevelReached>(reached.add);

      mastery.increase(owner, 'technique:jab', 65);

      expect(reached.map((e) => e.level), equals([1, 2, 3]));
    });

    test('a subject with no registered definition never reaches a level', () {
      final owner = entities.create();

      mastery.increase(owner, 'unregistered', 1000);

      expect(mastery.progressOf(owner, 'unregistered'), equals(1000));
      expect(mastery.levelOf(owner, 'unregistered'), equals(0));
    });

    test('progress floors at zero', () {
      final owner = entities.create();

      mastery.increase(owner, 'technique:jab', -50);

      expect(mastery.progressOf(owner, 'technique:jab'), equals(0));
    });
  });

  group('events', () {
    test('increase publishes MasteryChanged with the actual delta', () {
      final owner = entities.create();
      final received = <MasteryChanged>[];
      events.subscribe<MasteryChanged>(received.add);

      mastery.increase(owner, 'item:iron_sword', 15);

      expect(received, hasLength(1));
      expect(received.single.owner, equals(owner));
      expect(received.single.subject, equals('item:iron_sword'));
      expect(received.single.delta, equals(15));
      expect(received.single.newProgress, equals(15));
    });

    test('no event when a floored increase does not change anything', () {
      final owner = entities.create();
      final received = <MasteryChanged>[];
      events.subscribe<MasteryChanged>(received.add);

      mastery.increase(owner, 'item:iron_sword', -10); // already 0

      expect(received, isEmpty);
    });
  });

  group('two unrelated content types share the same tracker', () {
    test('an item and a technique progress independently through one MasteryTracker',
        () {
      final owner = entities.create();
      mastery.define(
        const MasteryDefinition(subject: 'item:iron_sword', thresholds: [20, 50]),
      );
      mastery.define(
        const MasteryDefinition(subject: 'technique:jab', thresholds: [10, 30]),
      );

      mastery.increase(owner, 'item:iron_sword', 25);
      mastery.increase(owner, 'technique:jab', 15);

      expect(mastery.levelOf(owner, 'item:iron_sword'), equals(1));
      expect(mastery.levelOf(owner, 'technique:jab'), equals(1));
      expect(mastery.progressOf(owner, 'item:iron_sword'), equals(25));
      expect(mastery.progressOf(owner, 'technique:jab'), equals(15));

      // Further leveling one subject doesn't affect the other.
      mastery.increase(owner, 'item:iron_sword', 30);
      expect(mastery.levelOf(owner, 'item:iron_sword'), equals(2));
      expect(mastery.levelOf(owner, 'technique:jab'), equals(1));
    });
  });

  group('deterministic behavior', () {
    test('the same call sequence yields the same resulting state', () {
      final owner1 = entities.create();
      mastery.define(
        const MasteryDefinition(subject: 'item:iron_sword', thresholds: [10, 30]),
      );
      mastery.increase(owner1, 'item:iron_sword', 15);
      mastery.increase(owner1, 'item:iron_sword', 10);

      final events2 = EventBus();
      final entities2 = EntityRegistry(events2);
      final components2 = ComponentStore();
      final mastery2 = MasteryTracker(components: components2, events: events2);
      final owner2 = entities2.create();
      mastery2.define(
        const MasteryDefinition(subject: 'item:iron_sword', thresholds: [10, 30]),
      );
      mastery2.increase(owner2, 'item:iron_sword', 15);
      mastery2.increase(owner2, 'item:iron_sword', 10);

      expect(
        mastery.recordOf(owner1, 'item:iron_sword').progress,
        equals(mastery2.recordOf(owner2, 'item:iron_sword').progress),
      );
      expect(
        mastery.recordOf(owner1, 'item:iron_sword').level,
        equals(mastery2.recordOf(owner2, 'item:iron_sword').level),
      );
    });
  });
}
