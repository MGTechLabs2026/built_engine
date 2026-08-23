/// The three elemental spells this example plugin's vertical slice
/// implements, as data — loaded via `PluginSdk.registerContentBatch` in
/// `ExampleElementalPlugin.initialize`. Each mixes a built-in
/// `ContentRegistry` factory (`damage`) with this plugin's own
/// (`applyElementalStatus`, `hasElementalAffinity`), demonstrating the
/// complete data pipeline end to end.
const elementalContentDefinitions = <Map<String, dynamic>>[
  {
    'id': 'fireball',
    'type': 'spell',
    'tags': ['element:fire', 'attack'],
    'components': {
      'cost': {'resource': 'mana', 'amount': 4},
    },
    'conditions': [
      {'type': 'hasElementalAffinity', 'element': 'fire', 'threshold': 1},
    ],
    'effects': [
      {'type': 'damage', 'amount': 12},
      {'type': 'applyElementalStatus', 'element': 'fire'},
    ],
  },
  {
    'id': 'tidal_wave',
    'type': 'spell',
    'tags': ['element:water', 'attack'],
    'components': {
      'cost': {'resource': 'mana', 'amount': 3},
    },
    'conditions': [
      {'type': 'hasElementalAffinity', 'element': 'water', 'threshold': 1},
    ],
    'effects': [
      {'type': 'damage', 'amount': 8},
      {'type': 'applyElementalStatus', 'element': 'water'},
    ],
  },
  {
    'id': 'spark_bolt',
    'type': 'spell',
    'tags': ['element:lightning', 'attack'],
    'components': {
      'cost': {'resource': 'mana', 'amount': 5},
    },
    'conditions': [
      {
        'type': 'hasElementalAffinity',
        'element': 'lightning',
        'threshold': 1,
      },
    ],
    'effects': [
      {'type': 'damage', 'amount': 10},
      {'type': 'applyElementalStatus', 'element': 'lightning'},
    ],
  },
];
