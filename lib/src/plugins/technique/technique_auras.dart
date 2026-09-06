/// SP2 per-active aura rule definitions for the generic Technique plugin.
/// See `item_auras.dart` for the loading/lifecycle contract.
const techniqueAuraRuleDefinitions = <Map<String, dynamic>>[
  {
    'id': 'aura.guard_regen',
    'trigger': 'TurnStarted',
    'conditions': [
      {'type': 'healthBelow', 'threshold': 20},
    ],
    'effects': [
      {'type': 'heal', 'amount': 2},
    ],
  },
  {
    'id': 'aura.venom',
    'trigger': 'TurnStarted',
    'scope': 'opponent',
    'conditions': [
      {'type': 'randomChance', 'probability': 0.5},
    ],
    'effects': [
      {'type': 'damage', 'amount': 2},
    ],
  },
];
