/// The abstract attribute axes a technique variant's descriptors sum
/// onto. Open set — a plugin adds one by authoring descriptors for it,
/// no code change. These four ship at launch.
abstract final class TechniqueAxes {
  static const power = 'power';
  static const speed = 'speed';
  static const endurance = 'endurance';
  static const precision = 'precision';

  static const all = [power, speed, endurance, precision];
}

/// Launch descriptor set. Each maps a thematic id to an `axes` map of
/// one or more `axisKey: signedMagnitude` (rule 1). The dominant axis is
/// the theme; a secondary, usually-negative axis is the trade-off
/// (`bear`: heavy but a touch slower).
const techniqueDescriptorContentDefinitions = <Map<String, dynamic>>[
  // ── power-leaning ────────────────────────────────────────────────
  {'id': 'bear', 'type': 'technique_descriptor', 'tags': ['technique_descriptor', 'beast'], 'axes': {'power': 6, 'speed': -1}},
  {'id': 'elephant', 'type': 'technique_descriptor', 'tags': ['technique_descriptor', 'beast'], 'axes': {'power': 8, 'speed': -2}},
  {'id': 'strong', 'type': 'technique_descriptor', 'tags': ['technique_descriptor'], 'axes': {'power': 4}},
  {'id': 'destruction', 'type': 'technique_descriptor', 'tags': ['technique_descriptor'], 'axes': {'power': 9, 'precision': -2}},
  {'id': 'thunder', 'type': 'technique_descriptor', 'tags': ['technique_descriptor', 'weather'], 'axes': {'power': 7}},
  {'id': 'iron', 'type': 'technique_descriptor', 'tags': ['technique_descriptor', 'material'], 'axes': {'power': 5, 'endurance': 2}},

  // ── speed-leaning ───────────────────────────────────────────────
  {'id': 'swift', 'type': 'technique_descriptor', 'tags': ['technique_descriptor'], 'axes': {'speed': 5}},
  {'id': 'fast', 'type': 'technique_descriptor', 'tags': ['technique_descriptor'], 'axes': {'speed': 4}},
  {'id': 'lightning', 'type': 'technique_descriptor', 'tags': ['technique_descriptor', 'weather'], 'axes': {'speed': 8, 'power': -1}},
  {'id': 'light', 'type': 'technique_descriptor', 'tags': ['technique_descriptor'], 'axes': {'speed': 6, 'power': -2}},
  {'id': 'flash', 'type': 'technique_descriptor', 'tags': ['technique_descriptor'], 'axes': {'speed': 7, 'endurance': -1}},

  // ── endurance-leaning ──────────────────────────────────────────
  {'id': 'immortal', 'type': 'technique_descriptor', 'tags': ['technique_descriptor'], 'axes': {'endurance': 9, 'speed': -2}},
  {'id': 'wall', 'type': 'technique_descriptor', 'tags': ['technique_descriptor'], 'axes': {'endurance': 5}},
  {'id': 'mountain', 'type': 'technique_descriptor', 'tags': ['technique_descriptor'], 'axes': {'endurance': 7, 'speed': -1}},
  {'id': 'undead', 'type': 'technique_descriptor', 'tags': ['technique_descriptor'], 'axes': {'endurance': 6}},
  {'id': 'rooted', 'type': 'technique_descriptor', 'tags': ['technique_descriptor'], 'axes': {'endurance': 4, 'speed': -1}},

  // ── precision-leaning ──────────────────────────────────────────
  {'id': 'bullseye', 'type': 'technique_descriptor', 'tags': ['technique_descriptor'], 'axes': {'precision': 6}},
  {'id': 'hawkseye', 'type': 'technique_descriptor', 'tags': ['technique_descriptor', 'beast'], 'axes': {'precision': 7}},
  {'id': 'one_hit', 'type': 'technique_descriptor', 'tags': ['technique_descriptor'], 'axes': {'precision': 9, 'power': 2}},
  {'id': 'needle', 'type': 'technique_descriptor', 'tags': ['technique_descriptor'], 'axes': {'precision': 5, 'power': -1}},
  {'id': 'focused', 'type': 'technique_descriptor', 'tags': ['technique_descriptor'], 'axes': {'precision': 4}},
];
