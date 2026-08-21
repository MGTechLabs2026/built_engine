import 'package:build_engine/build_engine.dart';
import 'package:test/test.dart';

void main() {
  group('EntityRegistry', () {
    test('create returns unique sequential ids', () {
      final registry = EntityRegistry(EventBus());

      final first = registry.create();
      final second = registry.create();
      final third = registry.create();

      expect(first, isNot(equals(second)));
      expect(second, isNot(equals(third)));
      expect(second.value, equals(first.value + 1));
      expect(third.value, equals(second.value + 1));
    });

    test('a created entity is alive', () {
      final registry = EntityRegistry(EventBus());
      final id = registry.create();

      expect(registry.isAlive(id), isTrue);
    });

    test('a destroyed entity is no longer alive', () {
      final registry = EntityRegistry(EventBus());
      final id = registry.create();

      registry.destroy(id);

      expect(registry.isAlive(id), isFalse);
    });

    test('destroying an unknown entity throws StateError', () {
      final registry = EntityRegistry(EventBus());

      expect(() => registry.destroy(const EntityId(999)), throwsStateError);
    });

    test('destroying an already-destroyed entity throws StateError', () {
      final registry = EntityRegistry(EventBus());
      final id = registry.create();
      registry.destroy(id);

      expect(() => registry.destroy(id), throwsStateError);
    });

    test('all returns exactly the currently-alive entities', () {
      final registry = EntityRegistry(EventBus());
      final a = registry.create();
      final b = registry.create();
      registry.destroy(a);
      final c = registry.create();

      expect(registry.all.toSet(), equals({b, c}));
    });

    test('create publishes EntityCreated with the new id', () {
      final events = EventBus();
      final registry = EntityRegistry(events);
      final received = <EntityId>[];
      events.subscribe<EntityCreated>((event) => received.add(event.id));

      final id = registry.create();

      expect(received, equals([id]));
    });

    test('destroy publishes EntityDestroyed with the destroyed id', () {
      final events = EventBus();
      final registry = EntityRegistry(events);
      final received = <EntityId>[];
      events.subscribe<EntityDestroyed>((event) => received.add(event.id));

      final id = registry.create();
      registry.destroy(id);

      expect(received, equals([id]));
    });
  });
}
