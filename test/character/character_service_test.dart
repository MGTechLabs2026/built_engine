import 'package:build_engine/build_engine.dart';
import 'package:test/test.dart';

void main() {
  late EventBus events;
  late EntityRegistry entities;
  late ComponentStore components;
  late CharacterService characters;

  setUp(() {
    events = EventBus();
    entities = EntityRegistry(events);
    components = ComponentStore();
    characters = CharacterService(
      entities: entities,
      components: components,
      events: events,
    );
  });

  group('CharacterService.create', () {
    test('returns a live entity carrying a CharacterComponent', () {
      final id = characters.create();

      expect(entities.isAlive(id), isTrue);
      expect(components.has<CharacterComponent>(id), isTrue);
    });

    test('publishes exactly one CharacterCreated event for the new id', () {
      final received = <CharacterCreated>[];
      events.subscribe<CharacterCreated>(received.add);

      final id = characters.create();

      expect(received, hasLength(1));
      expect(received.single.id, equals(id));
    });

    test('a character entity composes with an arbitrary future component',
        () {
      final id = characters.create();

      components.add(id, const HealthComponent(current: 10, max: 10));

      expect(components.get<HealthComponent>(id)!.current, equals(10));
      expect(components.has<CharacterComponent>(id), isTrue);
    });

    test('same call sequence yields the same deterministic id sequence', () {
      final firstRunIds = [
        characters.create(),
        characters.create(),
        characters.create(),
      ];

      final events2 = EventBus();
      final entities2 = EntityRegistry(events2);
      final components2 = ComponentStore();
      final characters2 = CharacterService(
        entities: entities2,
        components: components2,
        events: events2,
      );
      final secondRunIds = [
        characters2.create(),
        characters2.create(),
        characters2.create(),
      ];

      expect(
        firstRunIds.map((id) => id.value),
        equals(secondRunIds.map((id) => id.value)),
      );
    });
  });

  group('character destruction', () {
    test('destroying the entity removes its CharacterComponent', () {
      final id = characters.create();

      entities.destroy(id);

      expect(components.has<CharacterComponent>(id), isFalse);
    });
  });
}
