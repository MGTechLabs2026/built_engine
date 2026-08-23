import 'package:build_engine/build_engine.dart';

/// Published by `initializePhysique` once a character's physique has
/// been selected and its `PhysiqueComponent` attached.
class PhysiqueAssigned {
  const PhysiqueAssigned(this.character, this.physiqueId);

  final EntityId character;
  final String physiqueId;
}
