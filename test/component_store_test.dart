import 'package:build_engine/build_engine.dart';
import 'package:test/test.dart';

class _Position {
  const _Position(this.x, this.y);
  final int x;
  final int y;
}

class _Health {
  const _Health(this.hp);
  final int hp;
}

void main() {
  group('ComponentStore', () {
    test('a component can be added and retrieved', () {
      final store = ComponentStore();
      const id = EntityId(1);

      store.add(id, const _Position(3, 4));

      final position = store.get<_Position>(id);
      expect(position, isNotNull);
      expect(position!.x, equals(3));
      expect(position.y, equals(4));
    });

    test('get returns null when the entity has no such component', () {
      final store = ComponentStore();
      expect(store.get<_Position>(const EntityId(1)), isNull);
    });

    test('has reflects presence and absence', () {
      final store = ComponentStore();
      const id = EntityId(1);

      expect(store.has<_Position>(id), isFalse);
      store.add(id, const _Position(0, 0));
      expect(store.has<_Position>(id), isTrue);
    });

    test('remove clears only the given component type for that entity', () {
      final store = ComponentStore();
      const id = EntityId(1);
      store.add(id, const _Position(1, 1));
      store.add(id, const _Health(10));

      store.remove<_Position>(id);

      expect(store.has<_Position>(id), isFalse);
      expect(store.has<_Health>(id), isTrue);
    });

    test('different component types on the same entity do not collide', () {
      final store = ComponentStore();
      const id = EntityId(1);

      store.add(id, const _Position(2, 2));
      store.add(id, const _Health(50));

      expect(store.get<_Position>(id)!.x, equals(2));
      expect(store.get<_Health>(id)!.hp, equals(50));
    });

    test('entitiesWith returns exactly the entities carrying that component',
        () {
      final store = ComponentStore();
      const a = EntityId(1);
      const b = EntityId(2);
      const c = EntityId(3);

      store.add(a, const _Position(0, 0));
      store.add(b, const _Position(0, 0));
      store.add(c, const _Health(1));

      expect(store.entitiesWith<_Position>().toSet(), equals({a, b}));
      expect(store.entitiesWith<_Health>().toSet(), equals({c}));
    });

    test('entitiesWith returns empty for a component type never added', () {
      final store = ComponentStore();
      expect(store.entitiesWith<_Position>(), isEmpty);
    });

    test('re-adding a component for the same entity overwrites it', () {
      final store = ComponentStore();
      const id = EntityId(1);

      store.add(id, const _Position(1, 1));
      store.add(id, const _Position(2, 2));

      expect(store.get<_Position>(id)!.x, equals(2));
    });
  });
}
