/// Stable content ids for the Technique plugin's starter set
/// (`technique_content.dart`).
abstract final class TechniqueIds {
  static const basicPunch = 'basic_punch';
  static const basicSlash = 'basic_slash';
  static const basicGuard = 'basic_guard';
  static const lightPunch = 'light_punch';
  static const heavyPunch = 'heavy_punch';
  static const fastPunch = 'fast_punch';
  static const counterPunch = 'counter_punch';
  static const quickSlash = 'quick_slash';
  static const heavySlash = 'heavy_slash';
  static const fastGuard = 'fast_guard';
  static const counterGuard = 'counter_guard';
}

/// The canonical Discovery *and* Mastery subject for technique
/// [definitionId] — `'technique:<id>'`. Discovery and Mastery may safely
/// share this one string: they're stored in different component types
/// (`DiscoveryComponent` vs `MasteryComponent`), so there is no collision.
String techniqueSubject(String definitionId) => 'technique:$definitionId';

/// The canonical Learning (`ProgressionEngine`) subject for technique
/// [definitionId] — deliberately a *different* string from
/// [techniqueSubject], even though both are ultimately stored via
/// `MasteryTracker`/`MasteryComponent`: `ProgressionEngine.addExperience`
/// and `MasteryTracker.increase` would otherwise silently share one
/// number, collapsing Learning and Mastery into the same axis — exactly
/// what this milestone forbids ("Discovery != Learning != Mastery").
String techniqueKnowledgeSubject(String definitionId) =>
    'technique:$definitionId:knowledge';

/// The `BuildComponentRef.referenceType` every technique occupies a Tome
/// slot under — the canonical replacement for the bare `'technique'`
/// string literal already used ad hoc across test fixtures (e.g.
/// `test/tome/tome_service_test.dart`, `vertical_slice_runner.dart`).
const techniqueReferenceType = 'technique';
