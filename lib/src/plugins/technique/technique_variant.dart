import 'package:build_engine/build_engine.dart';

/// Per-instance variant state for one technique an owner holds. Pure
/// data, no behaviour — the `ComponentStore` component attached to a
/// technique instance entity.
///
/// [owner] is the single authoritative "this owner has this instance"
/// relationship (rule 5), mirroring `ItemInstance.owner`. [axisProfile]
/// is the **stored** composed result (style centre ⊕ descriptor sum) at
/// mint time — not recomputed on read, so a later content change to a
/// descriptor does not silently restat existing instances.
class TechniqueVariant {
  const TechniqueVariant({
    required this.owner,
    required this.baseFamilyId,
    required this.descriptorIds,
    required this.axisProfile,
    this.styleId,
  });

  /// The entity that owns this variant instance.
  final EntityId owner;

  /// The base family this is a variant of, e.g. `'basic_punch'`.
  final String baseFamilyId;

  /// Thematic descriptor ids carried by this instance.
  final Set<String> descriptorIds;

  /// Composed axis contributions, e.g. `{'power': 13, 'speed': -1}`.
  final Map<String, num> axisProfile;

  /// The style this variant is tied to; `null` for a basic technique.
  final String? styleId;
}
