import 'package:build_engine/build_engine.dart';
import 'package:test/test.dart';

void main() {
  late EventBus events;
  late ComponentStore components;
  late EntityRegistry entities;
  late ResourcePool resources;

  setUp(() {
    events = EventBus();
    entities = EntityRegistry(events);
    components = ComponentStore();
    resources = ResourcePool(components: components, events: events);
  });

  group('creation', () {
    test('an entity with no ResourceComponent reads as 0 current, unbounded max',
        () {
      final id = entities.create();

      expect(resources.currentOf(id, 'stamina'), equals(0));
      expect(resources.maximumOf('stamina'), equals(double.infinity));
    });

    test('define registers bounds queryable via stateOf', () {
      final id = entities.create();
      resources.define(const ResourceDefinition(id: 'stamina', max: 100));
      components.add(id, ResourceComponent({'stamina': 40}));

      final state = resources.stateOf(id, 'stamina');

      expect(state.current, equals(40));
      expect(state.max, equals(100));
    });
  });

  group('bounds / clamp', () {
    test('clampValue restricts to the registered [min, max]', () {
      resources.define(const ResourceDefinition(id: 'stamina', max: 100));

      expect(resources.clampValue('stamina', 150), equals(100));
      expect(resources.clampValue('stamina', -10), equals(0));
      expect(resources.clampValue('stamina', 50), equals(50));
    });

    test('add clamps the stored value to the registered maximum', () {
      final id = entities.create();
      resources.define(const ResourceDefinition(id: 'stamina', max: 100));
      components.add(id, ResourceComponent({'stamina': 90}));

      resources.add(id, 'stamina', 50);

      expect(resources.currentOf(id, 'stamina'), equals(100));
    });

    test('subtract clamps the stored value to the registered minimum', () {
      final id = entities.create();
      resources.define(const ResourceDefinition(id: 'stamina', max: 100));
      components.add(id, ResourceComponent({'stamina': 10}));

      resources.subtract(id, 'stamina', 50);

      expect(resources.currentOf(id, 'stamina'), equals(0));
    });

    test('an undefined resource floors at zero but has no upper bound', () {
      final id = entities.create();

      resources.add(id, 'unregistered', 1000000);

      expect(resources.currentOf(id, 'unregistered'), equals(1000000));
    });
  });

  group('consume', () {
    test('subtracts the amount when affordable', () {
      final id = entities.create();
      components.add(id, ResourceComponent({'mana': 30}));

      resources.consume(id, 'mana', 20);

      expect(resources.currentOf(id, 'mana'), equals(10));
    });
  });

  group('restore', () {
    test('adds the amount, clamped to the registered maximum', () {
      final id = entities.create();
      resources.define(const ResourceDefinition(id: 'mana', max: 50));
      components.add(id, ResourceComponent({'mana': 40}));

      resources.restore(id, 'mana', 30);

      expect(resources.currentOf(id, 'mana'), equals(50));
    });
  });

  group('insufficient resource', () {
    test('canAfford is false and consume throws without mutating', () {
      final id = entities.create();
      components.add(id, ResourceComponent({'mana': 5}));

      expect(resources.canAfford(id, 'mana', 20), isFalse);
      expect(
        () => resources.consume(id, 'mana', 20),
        throwsA(isA<InsufficientResourceException>()),
      );
      expect(resources.currentOf(id, 'mana'), equals(5));
    });
  });

  group('events', () {
    test('set publishes ResourceChanged with the actual delta applied', () {
      final id = entities.create();
      resources.define(const ResourceDefinition(id: 'mana', max: 100));
      components.add(id, ResourceComponent({'mana': 50}));
      final received = <ResourceChanged>[];
      events.subscribe<ResourceChanged>(received.add);

      resources.add(id, 'mana', 70); // clamps to 100, actual delta is 50

      expect(received, hasLength(1));
      expect(received.single.id, equals(id));
      expect(received.single.resource, equals('mana'));
      expect(received.single.delta, equals(50));
      expect(received.single.newCurrent, equals(100));
    });

    test('no event is published when a clamped set does not change anything',
        () {
      final id = entities.create();
      resources.define(const ResourceDefinition(id: 'mana', max: 100));
      components.add(id, ResourceComponent({'mana': 100}));
      final received = <ResourceChanged>[];
      events.subscribe<ResourceChanged>(received.add);

      resources.add(id, 'mana', 50); // already at max

      expect(received, isEmpty);
    });
  });

  group('query/condition integration', () {
    test('ResourceAboveQuery/ResourceBelowQuery see values written via ResourcePool',
        () {
      final id = entities.create();
      resources.define(const ResourceDefinition(id: 'stamina', max: 100));
      components.add(id, ResourceComponent({'stamina': 10}));

      resources.add(id, 'stamina', 40);

      final scope = QueryScope(components: components);
      expect(
        const ResourceAboveQuery('stamina', 30).matches(id, scope),
        isTrue,
      );
      expect(
        const ResourceBelowQuery('stamina', 100).matches(id, scope),
        isTrue,
      );
    });
  });

  group('deterministic behavior', () {
    test('the same call sequence yields the same resulting state', () {
      final id1 = entities.create();
      resources.define(const ResourceDefinition(id: 'stamina', max: 100));
      components.add(id1, ResourceComponent({'stamina': 50}));
      resources.add(id1, 'stamina', 30);
      resources.subtract(id1, 'stamina', 10);

      final events2 = EventBus();
      final entities2 = EntityRegistry(events2);
      final components2 = ComponentStore();
      final resources2 = ResourcePool(components: components2, events: events2);
      final id2 = entities2.create();
      resources2.define(const ResourceDefinition(id: 'stamina', max: 100));
      components2.add(id2, ResourceComponent({'stamina': 50}));
      resources2.add(id2, 'stamina', 30);
      resources2.subtract(id2, 'stamina', 10);

      expect(
        resources.currentOf(id1, 'stamina'),
        equals(resources2.currentOf(id2, 'stamina')),
      );
    });
  });
}
