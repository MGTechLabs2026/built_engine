/// Centralized resource/stance name constants for MartialArts —
/// `ARCHITECTURE_AUDIT.md`'s observation B flagged these as raw string
/// literals repeated across several files, where a typo would be a
/// silent runtime mismatch (a rule that quietly never fires) rather
/// than a compile error. Purely a plugin-local naming convention — Core
/// still never interprets resource/tag values.
abstract final class MartialResources {
  static const qi = 'qi';
  static const momentum = 'momentum';
}

/// Stance tags granted by techniques (`martial_technique_action.dart`)
/// and read by conditions/rules/modifiers elsewhere in this plugin.
/// Content Expansion V1 added the three western/eastern style stances
/// (`sprawl`/`en_garde`/`swallow`) the new style-technique sets grant and
/// several style specialties gate on.
abstract final class MartialStances {
  static const guard = 'stance:guard';
  static const ironBody = 'stance:iron_body';
  static const taiChi = 'stance:tai_chi';
  static const sprawl = 'stance:sprawl'; // wrestling
  static const enGarde = 'stance:en_garde'; // fencing
  static const swallow = 'stance:swallow'; // kunlun
}

/// Style-specialty marker tags granted by `learnStyle` (Content Expansion
/// V1, matrix §E.1). Each style grants one or two. The parts a static
/// `Modifier` can express are registered by `learnStyle` directly; the
/// parts that only manifest during a fight (pre-emption, dodge-ignore,
/// riposte window, mitigation floor, reflect, free dodge, hit streak)
/// are read off these tags by the client's `CombatAdapter` — a generic
/// `spec:*` branch, never an `if styleId == …`.
abstract final class MartialSpecs {
  static const openingReach = 'spec:opening_reach'; // polearming
  static const spacing = 'spec:spacing'; // polearming
  static const clinch = 'spec:clinch'; // wrestling
  static const absorb = 'spec:absorb'; // wrestling
  static const firstBlood = 'spec:first_blood'; // fencing
  static const riposteWindow = 'spec:riposte_window'; // fencing
  static const conditioning = 'spec:conditioning'; // shaolin
  static const redirect = 'spec:redirect'; // taiChi
  static const flow = 'spec:flow'; // taiChi
  static const swallowDodge = 'spec:swallow_dodge'; // kunlun
  static const burstChain = 'spec:burst_chain'; // kunlun

  /// Which specialty tags each style grants — one source of truth for
  /// `learnStyle` and for the client `CombatAdapter`'s spec dispatch.
  static const byStyle = <String, List<String>>{
    'polearming': [openingReach, spacing],
    'wrestling': [clinch, absorb],
    'fencing': [firstBlood, riposteWindow],
    'shaolin': [conditioning],
    'taiChi': [redirect, flow],
    'kunlun': [swallowDodge, burstChain],
  };
}

/// The recognised weapon/technique **family** tags. Content outside a
/// style's aligned set (see [styleAlignedFamilies]) takes the −15%
/// off-specialty penalty; content with none of these tags is neutral and
/// never penalised. Matrix §E.2.
const recognisedFamilyTags = <String>{
  'fist', 'palm', 'finger', 'blade', 'reach', 'polearm', 'thrust',
  'staff', 'fan', 'grapple', 'internal', 'guard', 'kick', 'improvised',
  'cloth',
};

/// The family tags each style is "in its lane" for — a technique or item
/// whose family tag is **not** listed here is used at `×0.85` damage.
/// Exported so the one authority lives here; the client `CombatAdapter`
/// applies the multiplier (the headless sim honours styles through
/// `learnStyle`'s static modifiers only, in V1). Matrix §E.2.
const styleAlignedFamilies = <String, Set<String>>{
  'polearming': {'reach', 'polearm', 'thrust', 'staff', 'kick', 'guard', 'fist'},
  'wrestling': {'grapple', 'guard', 'fist', 'improvised', 'cloth'},
  'fencing': {'blade', 'thrust', 'fist', 'finger'},
  'shaolin': {'palm', 'fist', 'staff', 'kick'},
  'taiChi': {'internal', 'palm', 'guard', 'fan'},
  'kunlun': {'blade', 'finger', 'thrust', 'fist'},
};

/// The off-specialty damage multiplier applied when a component's family
/// tag falls outside the acting style's [styleAlignedFamilies] set.
const offSpecialtyDamageFactor = 0.85;

/// Stable content ids for MartialArts' items/trinkets
/// (`martial_item_content.dart`) — referenced by content definitions,
/// `martial_arts_rules.dart`'s passive-regen rules (`.momentumTrinket`/
/// `.qiPendant`), and by `martialItem(id, context)` call sites, so a
/// rename here propagates everywhere instead of silently breaking a
/// second, independently-typed string literal.
/// The two broad martial traditions `_traditionTagFor` (`martial_styles
/// .dart`) grants — `ARCHITECTURE_AUDIT.md`'s Observation A/C flagged
/// these as the one remaining pair of raw literals from the original
/// Observation B fix, carried over unaddressed until now. This is the
/// entire interoperability contract with Physique's own synergy
/// modifiers (`physique_content.dart`'s `PhysiqueTraditions`) — two
/// independent constant classes with matching *values*, not a shared
/// import, is deliberate: it keeps this plugin's zero-dependency-on-
/// Physique property intact (see `ARCHITECTURE.md`'s Physique section)
/// while still naming the literal once instead of nine times.
abstract final class MartialTraditions {
  static const western = 'western';
  static const eastern = 'eastern';
}

abstract final class MartialItemIds {
  static const brassKnuckles = 'brass_knuckles';
  static const ironPalmWraps = 'iron_palm_wraps';
  static const taiChiSilkSash = 'tai_chi_silk_sash';
  static const sparringGloves = 'sparring_gloves';
  static const weightedVest = 'weighted_vest';
  static const momentumTrinket = 'momentum_trinket';
  static const qiPendant = 'qi_pendant';
  static const counterstrikeRing = 'counterstrike_ring';
}
