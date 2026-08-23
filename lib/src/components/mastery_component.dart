/// An owner's accumulated progress toward arbitrary named mastery subjects
/// (e.g. a content plugin's own "item:iron_sword" or "technique:jab"). The
/// engine never hardcodes a subject name.
///
/// `ProgressionEngine` reads and writes through this same storage (via
/// `MasteryTracker`) rather than keeping its own — Mastery is the
/// authoritative store; Progression is a thin adapter preserving its own
/// `tier`/`experience` naming and event vocabulary on top of it.
class MasteryComponent {
  MasteryComponent(Map<String, num> progress)
      : progress = Map.unmodifiable(progress);

  final Map<String, num> progress;
}
