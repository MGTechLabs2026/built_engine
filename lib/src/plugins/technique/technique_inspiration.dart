import 'package:build_engine/build_engine.dart';

/// One of an owner's technique-variant instances, offered to
/// [TechniqueInspirationResolver] as raw material. The caller does **not**
/// pre-filter — the resolver applies the eligibility test itself.
class Inspirer {
  const Inspirer({
    required this.instanceId,
    required this.axisProfile,
    required this.masteryLevel,
    required this.usage,
  });

  /// The variant entity — reported back in [InspirationResult] and the
  /// event, never used in the resolver's arithmetic.
  final EntityId instanceId;

  /// The variant's stored `TechniqueVariant.axisProfile` (signed).
  final Map<String, num> axisProfile;

  /// Per-instance mastery level, `0..3`.
  final int masteryLevel;

  /// Combat actions performed this run, `>= 0`.
  final int usage;
}

/// The outcome of one discovery roll. `discovered == false` ⇒ every other
/// field is empty ([none]).
class InspirationResult {
  const InspirationResult({
    required this.discovered,
    required this.familyId,
    required this.descriptorIds,
    required this.inspirerInstanceIds,
  });

  final bool discovered;

  /// `== trainedFamilyId` on a hit; `''` otherwise.
  final String familyId;

  /// `1..3` descriptor ids on a hit; empty otherwise.
  final Set<String> descriptorIds;

  /// The eligible inspirers the resolver actually used; `[]` on a miss.
  final List<EntityId> inspirerInstanceIds;

  static const none = InspirationResult(
    discovered: false,
    familyId: '',
    descriptorIds: {},
    inspirerInstanceIds: [],
  );
}
