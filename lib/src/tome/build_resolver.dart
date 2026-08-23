import '../entity/entity_id.dart';
import 'active_build.dart';
import 'tome_placement.dart';

/// A pure function transforming a Tome's current placements into an
/// [ActiveBuild] snapshot — no storage dependency, mirroring
/// `ModifierResolver`'s own "pure function, no storage" shape. Calling
/// [resolve] twice with the same [placements] (in the same order) always
/// yields the same [ActiveBuild], so build resolution stays deterministic
/// for free — no `RngService` involved anywhere in this class.
class BuildResolver {
  const BuildResolver();

  ActiveBuild resolve(EntityId owner, List<TomePlacement> placements) => ActiveBuild(
        owner: owner,
        components: [for (final placement in placements) placement.buildComponentRef],
      );
}
