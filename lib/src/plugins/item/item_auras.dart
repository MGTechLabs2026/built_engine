/// SP2 per-active aura rule definitions for the generic Item plugin —
/// loaded via `ContentRegistry.loadRule` in `ItemPlugin.initialize`, then
/// referenced by id from an item content entry's `auras` list. NOT
/// `RuleEngine.register`ed at load time: `AuraBinder` registers them per
/// hung ref, per fight. `scope` (`"self"` default, `"opponent"`) is read
/// by `ItemAuraContributor`; the DSL parser ignores it.
const itemAuraRuleDefinitions = <Map<String, dynamic>>[
  {
    'id': 'aura.regen_weave',
    'trigger': 'TurnStarted',
    'effects': [
      {'type': 'heal', 'amount': 1},
    ],
  },
  {
    'id': 'aura.braced',
    'trigger': 'TurnStarted',
    'effects': [
      {'type': 'applyStatus', 'status': 'status:braced'},
    ],
  },
  {
    'id': 'aura.quickstep',
    'trigger': 'TurnStarted',
    'effects': [
      {'type': 'applyStatus', 'status': 'status:quickstep'},
    ],
  },
  {
    'id': 'aura.bleed',
    'trigger': 'TurnStarted',
    'scope': 'opponent',
    'effects': [
      {'type': 'damage', 'amount': 1},
    ],
  },
  {
    'id': 'aura.thorns',
    'trigger': 'ActionCompleted',
    'scope': 'opponent',
    'effects': [
      {'type': 'damage', 'amount': 2},
    ],
  },
];
