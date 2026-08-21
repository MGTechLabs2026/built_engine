import '../entity/entity_id.dart';
import 'query.dart';

/// Evaluates a [Query] against a set of candidate entities, independent of
/// any particular source of candidates (typically `EntityRegistry.all`).
class QueryEngine {
  const QueryEngine(this.scope);

  final QueryScope scope;

  /// Every entity in [candidates] that [query] matches.
  Iterable<EntityId> evaluate(Iterable<EntityId> candidates, Query query) =>
      candidates.where((id) => query.matches(id, scope));
}
