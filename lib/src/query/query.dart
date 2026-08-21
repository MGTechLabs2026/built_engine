import '../component/component_store.dart';
import '../entity/entity_id.dart';

/// The read-only data a [Query] evaluates against.
class QueryScope {
  const QueryScope({required this.components});

  final ComponentStore components;
}

/// A composable predicate over a single entity. Independently useful on
/// its own via [QueryEngine] — "find every entity matching some
/// combination of tags/components/resources" — with no Rule Engine
/// involvement required.
abstract class Query {
  const Query();

  bool matches(EntityId id, QueryScope scope);

  /// A query that matches only when both this and [other] match.
  Query and(Query other) => AndQuery([this, other]);

  /// A query that matches when either this or [other] matches.
  Query or(Query other) => OrQuery([this, other]);

  /// A query that matches exactly when this query does not.
  Query not() => NotQuery(this);
}

/// Matches when every query in [queries] matches.
class AndQuery extends Query {
  const AndQuery(this.queries);

  final List<Query> queries;

  @override
  bool matches(EntityId id, QueryScope scope) =>
      queries.every((query) => query.matches(id, scope));
}

/// Matches when any query in [queries] matches.
class OrQuery extends Query {
  const OrQuery(this.queries);

  final List<Query> queries;

  @override
  bool matches(EntityId id, QueryScope scope) =>
      queries.any((query) => query.matches(id, scope));
}

/// Matches exactly when [query] does not.
class NotQuery extends Query {
  const NotQuery(this.query);

  final Query query;

  @override
  bool matches(EntityId id, QueryScope scope) => !query.matches(id, scope);
}
