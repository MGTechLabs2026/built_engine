import '../components/discovery_component.dart';
import '../components/health_component.dart';
import '../components/resource_component.dart';
import '../components/status_component.dart';
import '../components/tag_set.dart';
import '../discovery/discovery_state.dart';
import '../entity/entity_id.dart';
import 'query.dart';

/// Matches an entity that has a component of type `T`.
class HasComponentQuery<T extends Object> extends Query {
  const HasComponentQuery();

  @override
  bool matches(EntityId id, QueryScope scope) => scope.components.has<T>(id);
}

/// Matches an entity whose [TagSet] contains [tag].
class HasTagQuery extends Query {
  const HasTagQuery(this.tag);

  final String tag;

  @override
  bool matches(EntityId id, QueryScope scope) =>
      scope.components.get<TagSet>(id)?.tags.contains(tag) ?? false;
}

/// Matches an entity whose named [resource] is strictly greater than
/// [threshold]. An entity with no [ResourceComponent], or no entry for
/// [resource], is treated as if that resource were `0`.
class ResourceAboveQuery extends Query {
  const ResourceAboveQuery(this.resource, this.threshold);

  final String resource;
  final num threshold;

  @override
  bool matches(EntityId id, QueryScope scope) =>
      (scope.components.get<ResourceComponent>(id)?.resources[resource] ??
          0) >
      threshold;
}

/// Matches an entity whose named [resource] is strictly less than
/// [threshold]. Same zero-default as [ResourceAboveQuery].
class ResourceBelowQuery extends Query {
  const ResourceBelowQuery(this.resource, this.threshold);

  final String resource;
  final num threshold;

  @override
  bool matches(EntityId id, QueryScope scope) =>
      (scope.components.get<ResourceComponent>(id)?.resources[resource] ??
          0) <
      threshold;
}

/// Matches an entity whose [HealthComponent.current] is strictly less
/// than [threshold] (an absolute value, not a percentage of `max`). An
/// entity with no [HealthComponent] never matches — unlike
/// [ResourceBelowQuery]'s zero-default, "no health system at all" is
/// deliberately not the same as "health is low".
class HealthBelowQuery extends Query {
  const HealthBelowQuery(this.threshold);

  final num threshold;

  @override
  bool matches(EntityId id, QueryScope scope) {
    final health = scope.components.get<HealthComponent>(id);
    if (health == null) return false;
    return health.current < threshold;
  }
}

/// Matches an entity that has at least discovered [subject] — either
/// [DiscoveryState.discovered] or [DiscoveryState.unlocked]. An entity
/// with no [DiscoveryComponent], or no entry for [subject], reads as
/// [DiscoveryState.unknown] and never matches.
class DiscoveredQuery extends Query {
  const DiscoveredQuery(this.subject);

  final String subject;

  @override
  bool matches(EntityId id, QueryScope scope) {
    final state = scope.components.get<DiscoveryComponent>(id)?.states[subject] ??
        DiscoveryState.unknown;
    return state == DiscoveryState.discovered || state == DiscoveryState.unlocked;
  }
}

/// Matches an entity that has [subject] at [DiscoveryState.unlocked]
/// specifically — a discovered-but-not-yet-unlocked subject does not
/// match.
class UnlockedQuery extends Query {
  const UnlockedQuery(this.subject);

  final String subject;

  @override
  bool matches(EntityId id, QueryScope scope) =>
      (scope.components.get<DiscoveryComponent>(id)?.states[subject] ??
          DiscoveryState.unknown) ==
      DiscoveryState.unlocked;
}

/// Matches an entity whose [StatusComponent] has [status] active.
class StatusActiveQuery extends Query {
  const StatusActiveQuery(this.status);

  final String status;

  @override
  bool matches(EntityId id, QueryScope scope) =>
      scope.components
          .get<StatusComponent>(id)
          ?.activeStatuses
          .contains(status) ??
      false;
}
