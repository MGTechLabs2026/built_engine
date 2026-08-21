import 'package:build_engine/build_engine.dart';
import 'package:test/test.dart';

void main() {
  group('QueryEngine', () {
    test('evaluate returns only candidates matching the query', () {
      final components = ComponentStore();
      const a = EntityId(1);
      const b = EntityId(2);
      const c = EntityId(3);
      components.add(a, TagSet({'enemy'}));
      components.add(b, TagSet({'enemy'}));
      components.add(c, TagSet({'ally'}));
      final engine = QueryEngine(QueryScope(components: components));

      final matches = engine.evaluate([a, b, c], HasTagQuery('enemy'));

      expect(matches.toSet(), equals({a, b}));
    });

    test('evaluate returns empty when nothing matches', () {
      final components = ComponentStore();
      const a = EntityId(1);
      final engine = QueryEngine(QueryScope(components: components));

      final matches = engine.evaluate([a], HasTagQuery('enemy'));

      expect(matches, isEmpty);
    });

    test('evaluate composes with combinators for multi-criteria queries', () {
      final components = ComponentStore();
      const a = EntityId(1);
      const b = EntityId(2);
      components.add(a, TagSet({'enemy'}));
      components.add(a, const HealthComponent(current: 10, max: 100));
      components.add(b, TagSet({'enemy'}));
      components.add(b, const HealthComponent(current: 90, max: 100));
      final engine = QueryEngine(QueryScope(components: components));

      final query = HasTagQuery('enemy').and(const HealthBelowQuery(50));
      final matches = engine.evaluate([a, b], query);

      expect(matches.toSet(), equals({a}));
    });
  });
}
