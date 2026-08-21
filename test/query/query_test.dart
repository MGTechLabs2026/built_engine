import 'package:build_engine/build_engine.dart';
import 'package:test/test.dart';

class _Marker {
  const _Marker();
}

void main() {
  group('Query combinators', () {
    test('AndQuery matches only when every query matches', () {
      final components = ComponentStore();
      const id = EntityId(1);
      components.add(id, TagSet({'fire'}));
      final scope = QueryScope(components: components);

      final query = AndQuery([HasTagQuery('fire'), HasComponentQuery<TagSet>()]);

      expect(query.matches(id, scope), isTrue);
    });

    test('AndQuery fails when any query fails', () {
      final components = ComponentStore();
      const id = EntityId(1);
      components.add(id, TagSet({'fire'}));
      final scope = QueryScope(components: components);

      final query = AndQuery([HasTagQuery('fire'), HasTagQuery('ice')]);

      expect(query.matches(id, scope), isFalse);
    });

    test('OrQuery matches when any query matches', () {
      final components = ComponentStore();
      const id = EntityId(1);
      components.add(id, TagSet({'fire'}));
      final scope = QueryScope(components: components);

      final query = OrQuery([HasTagQuery('ice'), HasTagQuery('fire')]);

      expect(query.matches(id, scope), isTrue);
    });

    test('NotQuery inverts its wrapped query', () {
      final components = ComponentStore();
      const id = EntityId(1);
      final scope = QueryScope(components: components);

      final query = NotQuery(HasTagQuery('fire'));

      expect(query.matches(id, scope), isTrue);
    });

    test('Query.and/.or/.not fluent methods build the same combinators', () {
      final components = ComponentStore();
      const id = EntityId(1);
      components.add(id, TagSet({'fire', 'dragon'}));
      final scope = QueryScope(components: components);

      expect(
        HasTagQuery('fire').and(HasTagQuery('dragon')).matches(id, scope),
        isTrue,
      );
      expect(
        HasTagQuery('ice').or(HasTagQuery('fire')).matches(id, scope),
        isTrue,
      );
      expect(HasTagQuery('ice').not().matches(id, scope), isTrue);
    });
  });

  group('HasComponentQuery', () {
    test('matches when the entity has the component', () {
      final components = ComponentStore();
      const id = EntityId(1);
      components.add(id, const _Marker());
      final scope = QueryScope(components: components);

      expect(const HasComponentQuery<_Marker>().matches(id, scope), isTrue);
    });

    test('does not match when the entity lacks the component', () {
      final components = ComponentStore();
      const id = EntityId(1);
      final scope = QueryScope(components: components);

      expect(const HasComponentQuery<_Marker>().matches(id, scope), isFalse);
    });
  });

  group('HasTagQuery', () {
    test('matches when the tag is present', () {
      final components = ComponentStore();
      const id = EntityId(1);
      components.add(id, TagSet({'fire'}));
      final scope = QueryScope(components: components);

      expect(HasTagQuery('fire').matches(id, scope), isTrue);
    });

    test('does not match when the entity has no TagSet at all', () {
      final components = ComponentStore();
      const id = EntityId(1);
      final scope = QueryScope(components: components);

      expect(HasTagQuery('fire').matches(id, scope), isFalse);
    });
  });

  group('ResourceAboveQuery / ResourceBelowQuery', () {
    test('above matches strictly greater than the threshold', () {
      final components = ComponentStore();
      const id = EntityId(1);
      components.add(id, ResourceComponent({'stamina': 50}));
      final scope = QueryScope(components: components);

      expect(ResourceAboveQuery('stamina', 40).matches(id, scope), isTrue);
      expect(ResourceAboveQuery('stamina', 50).matches(id, scope), isFalse);
    });

    test('below matches strictly less than the threshold', () {
      final components = ComponentStore();
      const id = EntityId(1);
      components.add(id, ResourceComponent({'stamina': 50}));
      final scope = QueryScope(components: components);

      expect(ResourceBelowQuery('stamina', 60).matches(id, scope), isTrue);
      expect(ResourceBelowQuery('stamina', 50).matches(id, scope), isFalse);
    });

    test('a missing resource, or a missing ResourceComponent, is treated as zero', () {
      final components = ComponentStore();
      const withComponent = EntityId(1);
      const withoutComponent = EntityId(2);
      components.add(withComponent, ResourceComponent({}));
      final scope = QueryScope(components: components);

      expect(
        ResourceBelowQuery('stamina', 1).matches(withComponent, scope),
        isTrue,
      );
      expect(
        ResourceBelowQuery('stamina', 1).matches(withoutComponent, scope),
        isTrue,
      );
      expect(
        ResourceAboveQuery('stamina', -1).matches(withoutComponent, scope),
        isTrue,
      );
    });
  });

  group('HealthBelowQuery', () {
    test('matches strictly below the threshold', () {
      final components = ComponentStore();
      const id = EntityId(1);
      components.add(id, const HealthComponent(current: 30, max: 100));
      final scope = QueryScope(components: components);

      expect(const HealthBelowQuery(50).matches(id, scope), isTrue);
      expect(const HealthBelowQuery(30).matches(id, scope), isFalse);
    });

    test('an entity with no HealthComponent never matches', () {
      final components = ComponentStore();
      const id = EntityId(1);
      final scope = QueryScope(components: components);

      expect(const HealthBelowQuery(9999).matches(id, scope), isFalse);
    });
  });

  group('StatusActiveQuery', () {
    test('matches when the status is active', () {
      final components = ComponentStore();
      const id = EntityId(1);
      components.add(id, StatusComponent({'burning'}));
      final scope = QueryScope(components: components);

      expect(StatusActiveQuery('burning').matches(id, scope), isTrue);
    });

    test('does not match when the entity has no StatusComponent', () {
      final components = ComponentStore();
      const id = EntityId(1);
      final scope = QueryScope(components: components);

      expect(StatusActiveQuery('burning').matches(id, scope), isFalse);
    });
  });
}
