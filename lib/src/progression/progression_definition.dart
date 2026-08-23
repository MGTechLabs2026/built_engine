/// Generic tier thresholds for one named progression subject (e.g. a
/// content plugin's own "item:brass_knuckles" mastery or "technique:jab"
/// tier). The engine never hardcodes a subject name.
///
/// [thresholds] must be given in strictly increasing order — `thresholds[i]`
/// is the cumulative experience required to reach tier `i + 1`. Not
/// per-entity: every entity progressing the same [subject] shares the same
/// curve, the same scoping decision `ResourceDefinition.max` makes for
/// resources.
class ProgressionDefinition {
  const ProgressionDefinition({required this.subject, required this.thresholds});

  final String subject;
  final List<num> thresholds;
}
