/// The per-style, per-base-family axis nudge applied to a technique
/// variant minted while practising that style — passed by a composition
/// layer into `resolveTechniqueInspirationAfterTraining` /
/// `mintTechniqueVariant`'s `styleCentre` parameter. Content-shaped: a
/// `const` table today, a `ContentRegistry` batch later if it grows.
///
/// The family keys are the six Technique-plugin base ids
/// (`basic_punch` … `basic_kick`) as bare strings — MartialArts does not
/// import the Technique plugin. An unlisted style or family pair yields
/// `const {}` (a legitimate "no nudge").
Map<String, num> styleCentre(String styleId, String familyId) =>
    _styleCentres[styleId]?[familyId] ?? const {};

/// Axis keys mirror `TechniqueAxes` (`power` / `speed` / `endurance` /
/// `precision`). Magnitudes are deliberately small (1–3): a starting
/// bias, not a defining trait. Roughly follows each style's
/// `styleAlignedFamilies` lane.
const _styleCentres = <String, Map<String, Map<String, num>>>{
  // ── western ───────────────────────────────────────────────────────
  'polearming': {
    'basic_punch': {'precision': 1},
    'basic_slash': {},
    'basic_guard': {'endurance': 1},
    'basic_palm': {},
    'basic_finger': {'precision': 2},
    'basic_kick': {'power': 2},
  },
  'wrestling': {
    'basic_punch': {'power': 3},
    'basic_slash': {},
    'basic_guard': {'endurance': 3},
    'basic_palm': {'power': 1},
    'basic_finger': {},
    'basic_kick': {'endurance': 1},
  },
  'fencing': {
    'basic_punch': {'speed': 2},
    'basic_slash': {'speed': 2, 'precision': 1},
    'basic_guard': {'speed': 1},
    'basic_palm': {},
    'basic_finger': {'precision': 3},
    'basic_kick': {},
  },
  // ── eastern ───────────────────────────────────────────────────────
  'shaolin': {
    'basic_punch': {'power': 2, 'endurance': 1},
    'basic_slash': {},
    'basic_guard': {'endurance': 2},
    'basic_palm': {'power': 3},
    'basic_finger': {'precision': 1},
    'basic_kick': {'power': 2},
  },
  'taiChi': {
    'basic_punch': {},
    'basic_slash': {},
    'basic_guard': {'endurance': 3},
    'basic_palm': {'endurance': 2, 'precision': 1},
    'basic_finger': {'precision': 2},
    'basic_kick': {},
  },
  'kunlun': {
    'basic_punch': {'speed': 2},
    'basic_slash': {'speed': 3},
    'basic_guard': {},
    'basic_palm': {},
    'basic_finger': {'speed': 2, 'precision': 2},
    'basic_kick': {'speed': 1},
  },
};
