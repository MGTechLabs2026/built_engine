import 'package:build_engine/build_engine.dart';

/// Stable content ids for the Technique plugin's set
/// (`technique_content.dart`). Content Expansion V1 deepened the three
/// original families to `master` and added three new base families
/// (palm / finger / kick); a typo here is a compile error, not a silent
/// runtime string mismatch.
abstract final class TechniqueIds {
  // ── Punch family ──────────────────────────────────────────────────
  static const basicPunch = 'basic_punch';
  static const lightPunch = 'light_punch';
  static const heavyPunch = 'heavy_punch';
  static const fastPunch = 'fast_punch';
  static const counterPunch = 'counter_punch';
  static const preciseJab = 'precise_jab'; // advanced  (light line)
  static const lightningJab = 'lightning_jab'; // master
  static const hammerBlow = 'hammer_blow'; // advanced  (heavy line)
  static const mountainBreaker = 'mountain_breaker'; // master
  static const flashStrike = 'flash_strike'; // advanced  (fast line)
  static const thunderFlash = 'thunder_flash'; // master

  // ── Slash family ──────────────────────────────────────────────────
  static const basicSlash = 'basic_slash';
  static const quickSlash = 'quick_slash';
  static const heavySlash = 'heavy_slash';
  static const flashingSlash = 'flashing_slash'; // advanced (quick line)
  static const lightningSlash = 'lightning_slash'; // master
  static const cleavingSlash = 'cleaving_slash'; // advanced (heavy line)
  static const mountainCleave = 'mountain_cleave'; // master

  // ── Guard family ──────────────────────────────────────────────────
  static const basicGuard = 'basic_guard';
  static const fastGuard = 'fast_guard';
  static const counterGuard = 'counter_guard';
  static const rollingGuard = 'rolling_guard'; // advanced (fast line)
  static const turningGuard = 'turning_guard'; // advanced (counter line)
  static const stillWaterGuard = 'still_water_guard'; // master (control)

  // ── Palm family (new) ─────────────────────────────────────────────
  static const basicPalm = 'basic_palm';
  static const focusedPalm = 'focused_palm'; // intermediate (precision)
  static const pushingPalm = 'pushing_palm'; // intermediate (control)
  static const ironPalm = 'iron_palm'; // advanced (power)
  static const thunderPalm = 'thunder_palm'; // master
  static const stillPalm = 'still_palm'; // advanced (control)

  // ── Finger family (new) ───────────────────────────────────────────
  static const basicFinger = 'basic_finger';
  static const fingerStrike = 'finger_strike'; // intermediate (precision)
  static const needleFinger = 'needle_finger'; // intermediate (speed)
  static const piercingFinger = 'piercing_finger'; // advanced (precision)
  static const lightningFinger = 'lightning_finger'; // master

  // ── Kick family (new) ─────────────────────────────────────────────
  static const basicKick = 'basic_kick';
  static const snapKick = 'snap_kick'; // intermediate (speed)
  static const thrustKick = 'thrust_kick'; // intermediate (power)
  static const spinningKick = 'spinning_kick'; // advanced (power)
  static const whirlwindKick = 'whirlwind_kick'; // master
  static const crescentKick = 'crescent_kick'; // advanced (reaction)

  /// The base forms — the only ones with an independent LEARNING axis.
  /// Evolved branches are never "learned" separately.
  static const bases = [basicPunch, basicSlash, basicGuard, basicPalm, basicFinger, basicKick];
}

/// The single-tier LEARNING threshold registered per base technique.
const techniqueLearningThresholds = <num>[10];

/// The MASTERY rank thresholds registered for **every** technique — base
/// and evolved alike, so a rewarded or evolved form shows a rising rank
/// just like a base one. One source of truth; nothing outside this
/// plugin should restate these numbers.
const techniqueMasteryThresholds = <num>[5, 15, 30];

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

/// The per-instance Mastery subject for a technique variant entity —
/// `'technique:instance:<entityValue>'`. Distinct from
/// [techniqueSubject] (the base-family subject) so each variant a player
/// holds is drilled independently. `MasteryTracker` treats it like any
/// other subject string; it registers/reads it, never interprets it.
String techniqueInstanceSubject(EntityId instance) =>
    'technique:instance:${instance.value}';

/// The `BuildComponentRef.referenceType` every technique occupies a Tome
/// slot under — the canonical replacement for the bare `'technique'`
/// string literal already used ad hoc across test fixtures (e.g.
/// `test/tome/tome_service_test.dart`, `vertical_slice_runner.dart`).
const techniqueReferenceType = 'technique';

/// The [EffectProfile] axis key a technique variant reports its power
/// contribution under. This is a CONTRIBUTOR-LOCAL axis key, NOT a combat
/// stat key — `TechniqueActionInterpreter` reads it and applies the value
/// to whatever concrete `damageStat` it derives from the technique's tags.
/// A future generic per-stat modifier emitter must NOT treat this as a
/// stat combat reads.
const techniqueActivePowerKey = 'power';

// ── SP0b: technique inspiration / discovery tuning ───────────────────
// Placeholder magnitudes — tuned against `game_run` balance sweeps; each
// is a named constant, never inlined in the resolver.

/// Discovery probability at zero usage concentration.
const kInspirationBaseChance = 0.05;

/// How much a fully concentrated usage pattern (one dominant inspirer)
/// adds to the discovery probability. `p` tops out near `0.60` at `c == 1`.
const kInspirationConcentrationGain = 0.55;

/// An inspirer must be at least this per-instance mastery level.
const kMinMasteryToInspire = 1;

/// ...and must have performed at least this many combat actions this run.
const kMinUsageToInspire = 3;

/// The weighted draw re-rolls past an already-owned descriptor set at
/// most this many times before giving up.
const kInspirationExcludeRetries = 3;

/// Mean eligible-inspirer mastery at or above this makes a multi-source
/// blend "strong" (a candidate for a 3rd descriptor).
const kInspirationStrongMasteryBar = 2;

/// Minimum total damped inspirer weight for a "strong" (3-descriptor)
/// multi-source blend (spec §6.2 step 6). NOTE: with the current
/// `kMinUsageToInspire` (3) and `kInspirationStrongMasteryBar` (2), any
/// 2+-inspirer blend that clears the mastery bar already has
/// `Σ(mastery·√usage) ≥ 2·2·√3 ≈ 6.93`, so this bar does not currently
/// bind on its own — it is a floor the eligibility gates satisfy. Kept
/// as an explicit knob for future retuning of those gates.
const kInspirationStrongWeightBar = 6.0;

/// Descriptor tag prefix that restricts a descriptor to one base family,
/// e.g. `family:basic_kick`. A descriptor with no such tag is universal.
/// The suffix is the full base id (matches `techniqueFamilyOf`'s return).
const techniqueFamilyTagPrefix = 'family:';
