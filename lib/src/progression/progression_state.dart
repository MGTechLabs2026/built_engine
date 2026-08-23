/// A read-model pairing an entity's accumulated experience for a
/// progression subject with the tier that experience currently reaches —
/// computed on demand by [ProgressionEngine], never itself stored. Tier is
/// always derived from experience + a registered [ProgressionDefinition]'s
/// thresholds, so it can never desync from the experience it's based on.
class ProgressionState {
  const ProgressionState({required this.experience, required this.tier});

  final num experience;
  final int tier;
}
