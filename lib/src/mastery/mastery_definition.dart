/// Generic level thresholds for one named mastery subject (e.g. a content
/// plugin's own "item:iron_sword" or "technique:jab"). The engine never
/// hardcodes a subject name.
///
/// [thresholds] must be given in strictly increasing order —
/// `thresholds[i]` is the cumulative progress required to reach level
/// `i + 1`. Not per-owner: every owner mastering the same [subject] shares
/// the same curve.
class MasteryDefinition {
  const MasteryDefinition({required this.subject, required this.thresholds});

  final String subject;
  final List<num> thresholds;
}
