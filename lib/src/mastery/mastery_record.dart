import '../entity/entity_id.dart';

/// A read-model identifying one owner's mastery of one subject — level is
/// always derived from progress + a registered `MasteryDefinition`'s
/// thresholds, never itself stored, so it can't desync from the progress
/// it's based on.
class MasteryRecord {
  const MasteryRecord({
    required this.owner,
    required this.subject,
    required this.level,
    required this.progress,
  });

  final EntityId owner;
  final String subject;
  final int level;
  final num progress;
}
