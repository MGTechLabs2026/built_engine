import '../entity/entity_id.dart';
import 'active_build.dart';
import 'build_component_ref.dart';
import 'tome_placement.dart';

/// A Tome's current placements PLUS every component instance the owner
/// merely *has* — not just what's hung. [active] means currently hung
/// (what `ActiveBuild` used to mean, alone); [owned] means every owned
/// component instance, hung or loose. `active` is a subset of `owned`
/// by construction (see [BuildResolver.resolve] — the union guarantees
/// it); the constructor also asserts it, so a hand-built [ResolvedBuild]
/// that violated the invariant fails fast rather than silently dropping
/// the active ref from any owned-only iteration (e.g.
/// `ItemActionInterpreter`'s stat-key union).
class ResolvedBuild {
  // Non-`const`: the assert condition (`active ⊆ owned`) is not a
  // potentially-constant expression, so a `const` constructor would
  // reject it (`invalid_constant`). No `const ResolvedBuild(...)` call
  // exists in lib/ or test/ — every call site is already non-const — so
  // dropping `const` costs nothing and makes the doc-claimed invariant
  // structural: a hand-built ResolvedBuild that violates it fails fast
  // rather than silently dropping the active ref from the item
  // interpreter's owned-only stat-key union.
  ResolvedBuild({required this.owner, required this.active, required this.owned})
      : assert(
          _activeSubsetOfOwned(active, owned),
          'ResolvedBuild.active must be a subset of owned',
        );

  static bool _activeSubsetOfOwned(
          List<BuildComponentRef> active, List<BuildComponentRef> owned) =>
      active.every(owned.contains);

  final EntityId owner;

  /// Hung — what is on the Tome. Fed to Combat as today's `ActiveBuild`.
  final List<BuildComponentRef> active;

  /// Everything the owner has, hung or not. [active] is always a subset.
  final List<BuildComponentRef> owned;

  /// Backward-compat projection for callers that only ever wanted the
  /// hung set (today's `ActiveBuild` shape) — unchanged behaviour for
  /// every caller that doesn't yet care about ownership.
  ActiveBuild get asActiveBuild => ActiveBuild(owner: owner, components: active);
}

/// A pure function transforming a Tome's current placements (plus the
/// caller-supplied ownership roster) into a [ResolvedBuild] snapshot —
/// no storage dependency, mirroring `ModifierResolver`'s own "pure
/// function, no storage" shape. Calling [resolve] twice with the same
/// inputs (in the same order) always yields the same [ResolvedBuild].
///
/// Ownership is *passed in*, not fetched — `BuildResolver` (Core) never
/// imports `ItemInstance`/`TechniqueVariant` (plugin types). The caller
/// (the `build_interpretation` composition seam, which already holds a
/// `PluginContext`) derives [ownedRefs] from each instance entity's own
/// `owner` field — the single source of truth for "owner has this".
class BuildResolver {
  const BuildResolver();

  ResolvedBuild resolve(
    EntityId owner,
    List<TomePlacement> placements, {
    List<BuildComponentRef> ownedRefs = const [],
  }) {
    final active = [for (final placement in placements) placement.buildComponentRef];
    // Union, not a separate roster: every hung ref is automatically part
    // of `owned` even if the caller's ownedRefs forgot to list it — this
    // is what makes `active ⊆ owned` true by construction rather than by
    // an assert checked after the fact.
    final owned = <BuildComponentRef>[
      ...ownedRefs,
      for (final ref in active)
        if (!ownedRefs.contains(ref)) ref,
    ];
    return ResolvedBuild(owner: owner, active: active, owned: owned);
  }
}
