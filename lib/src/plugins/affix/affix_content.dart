// lib/src/plugins/affix/affix_content.dart

/// The 33 reward affixes, ported verbatim (label / magnitude / lean)
/// from the client's `lib/core/engine/reward_affix.dart`. Ids are minted
/// `af_*` tokens; the two cross-pool labels (`Flowing`, `of Still
/// Water`) carry distinct ids. Item-pool affixes are all
/// `weapon_stat_bonus`; technique-pool affixes are `heal` or
/// `bank_progression`, per the source entry.
///
/// `final`, not `const` — the builders below keep 33 near-identical
/// entries DRY; `ContentRegistry` only needs `List<Map<String, dynamic>>`.
Map<String, dynamic> _affix(
  String id,
  String label,
  String category,
  String lean,
  Map<String, dynamic> mechanic,
) => {
      'id': id,
      'type': 'affix',
      'tags': ['affix', 'affix_pool:$category', 'lean:$lean'],
      'label': label,
      'category': category,
      'mechanic': mechanic,
    };

Map<String, dynamic> _stat(num a) => {'kind': 'weapon_stat_bonus', 'amount': a};
Map<String, dynamic> _heal(num a) => {'kind': 'heal', 'amount': a};
Map<String, dynamic> _bank(num a) => {'kind': 'bank_progression', 'amount': a};

final List<Map<String, dynamic>> affixContentDefinitions = <Map<String, dynamic>>[
  // ---- item prefixes (11) — weapon_stat_bonus ----
  _affix('af_plain', 'Plain', 'item_prefix', 'neutral', _stat(1)),
  _affix('af_sturdy', 'Sturdy', 'item_prefix', 'neutral', _stat(2)),
  _affix('af_keen', 'Keen', 'item_prefix', 'neutral', _stat(3)),
  _affix('af_tempered', 'Tempered', 'item_prefix', 'neutral', _stat(3)),
  _affix('af_masterwork', 'Masterwork', 'item_prefix', 'neutral', _stat(5)),
  _affix('af_heavy', 'Heavy', 'item_prefix', 'force', _stat(4)),
  _affix('af_brutal', 'Brutal', 'item_prefix', 'force', _stat(5)),
  _affix('af_ember_forged', 'Ember-Forged', 'item_prefix', 'force', _stat(6)),
  _affix('af_swift', 'Swift', 'item_prefix', 'flow', _stat(3)),
  _affix('af_flowing', 'Flowing', 'item_prefix', 'flow', _stat(4)),
  _affix('af_whispering', 'Whispering', 'item_prefix', 'flow', _stat(3)),

  // ---- item suffixes (9) — weapon_stat_bonus ----
  _affix('af_of_the_journeyman', 'of the Journeyman', 'item_suffix', 'neutral', _stat(2)),
  _affix('af_of_the_vanguard', 'of the Vanguard', 'item_suffix', 'neutral', _stat(3)),
  _affix('af_of_the_anvil', 'of the Anvil', 'item_suffix', 'neutral', _stat(4)),
  _affix('af_of_the_ember', 'of the Ember', 'item_suffix', 'force', _stat(4)),
  _affix('af_of_the_bear', 'of the Bear', 'item_suffix', 'force', _stat(5)),
  _affix('af_of_the_avalanche', 'of the Avalanche', 'item_suffix', 'force', _stat(7)),
  _affix('af_of_the_gale', 'of the Gale', 'item_suffix', 'flow', _stat(4)),
  _affix('af_of_still_water', 'of Still Water', 'item_suffix', 'flow', _stat(5)),
  _affix('af_of_the_reed', 'of the Reed', 'item_suffix', 'flow', _stat(3)),

  // ---- technique prefixes (7) — heal / bank_progression ----
  _affix('af_hard_won', 'Hard-Won', 'technique_prefix', 'neutral', _bank(1)),
  _affix('af_clean', 'Clean', 'technique_prefix', 'neutral', _bank(1)),
  _affix('af_drilled', 'Drilled', 'technique_prefix', 'neutral', _bank(2)),
  _affix('af_grounding', 'Grounding', 'technique_prefix', 'force', _heal(12)),
  _affix('af_iron_willed', 'Iron-Willed', 'technique_prefix', 'force', _bank(2)),
  _affix('af_serene', 'Serene', 'technique_prefix', 'flow', _heal(10)),
  _affix('af_flowing_technique', 'Flowing', 'technique_prefix', 'flow', _heal(14)),

  // ---- technique suffixes (6) — heal / bank_progression ----
  _affix('af_of_the_first_form', 'of the First Form', 'technique_suffix', 'neutral', _bank(1)),
  _affix('af_of_seven_stars', 'of Seven Stars', 'technique_suffix', 'neutral', _bank(2)),
  _affix('af_of_the_rising_sun', 'of the Rising Sun', 'technique_suffix', 'force', _heal(14)),
  _affix('af_of_the_iron_ox', 'of the Iron Ox', 'technique_suffix', 'force', _bank(2)),
  _affix('af_of_still_water_technique', 'of Still Water', 'technique_suffix', 'flow', _heal(16)),
  _affix('af_of_the_coiled_spring', 'of the Coiled Spring', 'technique_suffix', 'flow', _bank(2)),
];
