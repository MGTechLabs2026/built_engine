import 'package:build_engine/build_engine.dart';

import 'technique_vocabulary.dart';

/// Per-instance variant state for one technique an owner holds. Pure
/// data, no behaviour — the `ComponentStore` component attached to a
/// technique instance entity.
///
/// [owner] is the single authoritative "this owner has this instance"
/// relationship (rule 5), mirroring `ItemInstance.owner`. [axisProfile]
/// is the **stored** composed result (style centre ⊕ descriptor sum) at
/// mint time — not recomputed on read, so a later content change to a
/// descriptor does not silently restat existing instances.
class TechniqueVariant implements EffectContributor {
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

  /// This variant's tiered contribution. SP1 (tiered effects) maps only
  /// the `power` axis, to the `active` tier, under the generic
  /// [techniqueActivePowerKey] — the caller (`TechniqueActionInterpreter`)
  /// already knows which
  /// concrete combat stat (`damageStat`) that power applies to; this
  /// profile deliberately doesn't guess it, keeping `EffectContributor`
  /// parameterless. `speed`/`precision`/`endurance` are not surfaced —
  /// no new stat keys in this migration (spec §14.2).
  @override
  EffectProfile effectProfile() {
    final power = axisProfile['power'];
    if (power == null || power == 0) return EffectProfile.empty;
    return EffectProfile.of({
      EffectTier.active: {techniqueActivePowerKey: power},
    });
  }
}
