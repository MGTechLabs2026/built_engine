import 'package:build_engine/build_engine.dart';
import 'package:test/test.dart';

void main() {
  late EventBus events;
  late ComponentStore components;
  late EntityRegistry entities;
  late DiscoveryTracker discovery;

  setUp(() {
    events = EventBus();
    entities = EntityRegistry(events);
    components = ComponentStore();
    discovery = DiscoveryTracker(components: components, events: events);
  });

  group('creation', () {
    test('an entity with no discovery record reads as unknown', () {
      final id = entities.create();

      expect(discovery.stateOf(id, 'item:iron_sword'), equals(DiscoveryState.unknown));
    });
  });

  group('discover', () {
    test('moves an unknown subject to discovered', () {
      final id = entities.create();

      discovery.discover(id, 'item:iron_sword');

      expect(discovery.stateOf(id, 'item:iron_sword'), equals(DiscoveryState.discovered));
    });

    test('a discovered subject may still be unusable (not automatically unlocked)',
        () {
      final id = entities.create();

      discovery.discover(id, 'item:iron_sword');

      expect(discovery.stateOf(id, 'item:iron_sword'), isNot(DiscoveryState.unlocked));
    });

    test('is a no-op (and publishes no event) if already discovered or unlocked',
        () {
      final id = entities.create();
      discovery.discover(id, 'item:iron_sword');
      final discovered = <SubjectDiscovered>[];
      events.subscribe<SubjectDiscovered>(discovered.add);

      discovery.discover(id, 'item:iron_sword');

      expect(discovered, isEmpty);
    });
  });

  group('unlock', () {
    test('moves a discovered subject to unlocked', () {
      final id = entities.create();
      discovery.discover(id, 'item:iron_sword');

      discovery.unlock(id, 'item:iron_sword');

      expect(discovery.stateOf(id, 'item:iron_sword'), equals(DiscoveryState.unlocked));
    });

    test('auto-promotes an unknown subject through discovered on the way to unlocked',
        () {
      final id = entities.create();
      final discoveredEvents = <SubjectDiscovered>[];
      final unlockedEvents = <SubjectUnlocked>[];
      events.subscribe<SubjectDiscovered>(discoveredEvents.add);
      events.subscribe<SubjectUnlocked>(unlockedEvents.add);

      discovery.unlock(id, 'item:iron_sword');

      expect(discovery.stateOf(id, 'item:iron_sword'), equals(DiscoveryState.unlocked));
      expect(discoveredEvents, hasLength(1));
      expect(unlockedEvents, hasLength(1));
    });

    test('is a no-op if already unlocked', () {
      final id = entities.create();
      discovery.unlock(id, 'item:iron_sword');
      final unlockedEvents = <SubjectUnlocked>[];
      events.subscribe<SubjectUnlocked>(unlockedEvents.add);

      discovery.unlock(id, 'item:iron_sword');

      expect(unlockedEvents, isEmpty);
    });
  });

  group('events', () {
    test('discover publishes SubjectDiscovered with the right id/subject', () {
      final id = entities.create();
      final received = <SubjectDiscovered>[];
      events.subscribe<SubjectDiscovered>(received.add);

      discovery.discover(id, 'item:iron_sword');

      expect(received, hasLength(1));
      expect(received.single.id, equals(id));
      expect(received.single.subject, equals('item:iron_sword'));
    });
  });

  group('query/condition integration', () {
    test('DiscoveredQuery/UnlockedQuery see states written via DiscoveryTracker',
        () {
      final id = entities.create();
      discovery.discover(id, 'item:iron_sword');
      discovery.unlock(id, 'technique:jab');

      final scope = QueryScope(components: components);
      expect(const DiscoveredQuery('item:iron_sword').matches(id, scope), isTrue);
      expect(const UnlockedQuery('item:iron_sword').matches(id, scope), isFalse);
      expect(const DiscoveredQuery('technique:jab').matches(id, scope), isTrue);
      expect(const UnlockedQuery('technique:jab').matches(id, scope), isTrue);
      expect(const DiscoveredQuery('never_touched').matches(id, scope), isFalse);
    });
  });

  group('two unrelated content types', () {
    test('an item and a technique track discovery independently', () {
      final id = entities.create();

      discovery.unlock(id, 'item:iron_sword');
      discovery.discover(id, 'technique:jab');

      expect(discovery.stateOf(id, 'item:iron_sword'), equals(DiscoveryState.unlocked));
      expect(discovery.stateOf(id, 'technique:jab'), equals(DiscoveryState.discovered));
    });
  });

  group('deterministic behavior', () {
    test('the same call sequence yields the same resulting state', () {
      final id1 = entities.create();
      discovery.discover(id1, 'item:iron_sword');
      discovery.unlock(id1, 'item:iron_sword');

      final events2 = EventBus();
      final entities2 = EntityRegistry(events2);
      final components2 = ComponentStore();
      final discovery2 = DiscoveryTracker(components: components2, events: events2);
      final id2 = entities2.create();
      discovery2.discover(id2, 'item:iron_sword');
      discovery2.unlock(id2, 'item:iron_sword');

      expect(
        discovery.stateOf(id1, 'item:iron_sword'),
        equals(discovery2.stateOf(id2, 'item:iron_sword')),
      );
    });
  });
}
