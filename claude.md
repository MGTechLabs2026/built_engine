# BUILD ENGINE — ARCHITECTURE CONTRACT

You are building a modular, data-driven game Build Engine.

The engine is intended to support games where players collect, arrange,
combine, transform, and use modular gameplay components.

The first game will be a roguelike inventory/build game inspired by
Backpack Hero, themed around martial arts and cultivation.

However:

IMPORTANT:
The core engine MUST NOT contain martial-arts-specific, magic-specific,
cultivation-specific, weapon-specific, or game-world-specific logic.

The architecture must support future plugins such as:

- Martial Arts
- Magic
- Cultivation
- Alchemy
- Weapons
- Technology
- Divine Powers
- Demonic Powers
- Community Mods

The engine follows this principle:

    CORE PROVIDES VERBS.
    PLUGINS PROVIDE NOUNS.

The core knows how to:

- create entities
- attach components
- query state
- dispatch events
- evaluate rules
- execute effects
- calculate modifiers
- manage spatial relationships
- manage resources
- schedule actions
- save/load state
- load/unload plugins

The core must NOT know what:

- sword
- spell
- fireball
- qi
- mana
- boxing
- cultivation
- potion
- martial art

means.

Those belong to plugins.

==================================================
ARCHITECTURE
==================================================

Core services:

1. Entity Registry
2. Component Store
3. Event Bus
4. Query Engine
5. Rule Engine
6. Effect Engine
7. Modifier Engine
8. Spatial/Container Engine
9. Resource Engine
10. Scheduler
11. RNG Service
12. Asset/Data Registry
13. Serialization
14. Plugin Manager

Everything else is implemented as a plugin.

==================================================
ENTITY MODEL
==================================================

Use composition rather than inheritance.

Do NOT create giant classes such as:

- Player
- Sword
- Mage
- MartialArtist
- Enemy
- Potion

Instead use:

Entity + Components + Tags + Rules.

Example:

Entity:
    player_001

Components:
    Health
    Position
    Inventory
    Resources
    Combatant

Tags:
    player
    human

Items and abilities follow the same model.

==================================================
COMPONENT RULES
==================================================

Components are pure state/data.

Components should NOT contain complex gameplay logic.

Examples:

HealthComponent
ResourceComponent
PositionComponent
ItemComponent
SkillComponent
EquipmentComponent
StatusComponent
ContainerComponent
AttackComponent

Systems/plugins operate on components.

==================================================
EVENT SYSTEM
==================================================

Gameplay communication must use events wherever practical.

Examples:

EntityCreated
EntityDestroyed

ItemAdded
ItemRemoved
ItemMoved

TurnStarted
TurnEnded

ActionStarted
ActionCompleted

SkillUsed

EntityDamaged
EntityHealed
EntityKilled

ResourceChanged

StatusApplied
StatusRemoved

RoomEntered

BattleStarted
BattleWon
BattleLost

BreakthroughTriggered

Plugins subscribe to events.

Avoid direct coupling between plugins.

==================================================
RULE SYSTEM
==================================================

Rules use:

WHEN
IF
THEN

Conceptually:

Rule {
    trigger
    conditions[]
    effects[]
}

Example:

WHEN SkillUsed

IF:
    actor has tag "fire"
    actor has tag "dragon"

THEN:
    multiply damage by 1.25

Rules must be data-driven where possible.

Do not hardcode individual content combinations into the engine.

==================================================
CONDITIONS
==================================================

Conditions must be composable.

Core should support generic conditions such as:

HasTag
HasComponent
HasResource
ResourceAbove
ResourceBelow
StatAbove
StatBelow
HealthBelow
AdjacentTo
ContainedBy
DistanceFrom
StatusActive
EventCount
TurnNumber
RandomChance

Plugins may register additional conditions.

==================================================
EFFECTS
==================================================

Effects must be composable.

Core/general effects may include:

Damage
Heal
ModifyStat
ModifyResource
ApplyStatus
RemoveStatus
MoveEntity
AddItem
RemoveItem
TransformEntity
CreateEntity
DestroyEntity

Plugins may register custom effects.

The engine must execute effects through a common Effect interface.

==================================================
MODIFIER SYSTEM
==================================================

Never directly mutate final derived stats when a modifier is appropriate.

Use:

base value
+
modifiers
=
derived value

Modifiers contain:

source
target
stat
operation
value
priority
duration
condition

Support operations such as:

add
multiply
override
min
max

Modifier ordering must be deterministic.

==================================================
TAGS
==================================================

Tags are first-class.

Tags are the universal language for content interoperability.

Example martial item:

tags:
    skill
    attack
    fist
    martial
    fire
    dragon
    qi

Example magic item:

tags:
    spell
    attack
    magic
    fire
    dragon
    mana

The engine does not interpret these tags.

It only provides querying and matching.

==================================================
SPATIAL / CONTAINER SYSTEM
==================================================

Containers are generic.

Do NOT hardcode "Backpack".

Implement a generic Container abstraction.

A container can support:

- slots
- grid positions
- pages
- adjacency
- containment
- sockets
- equipment locations

Relationships should be queryable:

Adjacent
Above
Below
Left
Right
SameRow
SameColumn
Distance
ContainedBy
EquippedTo
ConnectedTo

This will later support:

- Backpack
- Tome
- Spellbook
- Weapon Rack
- Character Equipment
- Skill Board

==================================================
PLUGIN SYSTEM
==================================================

Every feature is a plugin.

Plugin interface conceptually:

GamePlugin {
    id
    version
    dependencies

    register(context)
    initialize(context)
    start(context)
    stop(context)
    unregister(context)
}

PluginContext provides controlled access to:

entities
components
events
rules
effects
conditions
modifiers
queries
spatial
resources
assets
localization
rng
save/load

Plugins must not directly reach into another plugin's private implementation.

Use public contracts/interfaces.

==================================================
PLUGIN TYPES
==================================================

Infrastructure plugins:

- Combat
- Container
- Status
- Progression
- Map
- Loot

Content plugins:

- MartialArts
- Magic
- Cultivation
- Weapons
- Potions
- Trinkets
- Enemies

Presentation plugins:

- UI
- Animation
- VFX
- Audio

Meta plugins:

- Save
- Localization
- Modding
- Analytics
- Debugging

==================================================
DEPENDENCY RULE
==================================================

Dependencies must point downward toward abstractions.

Example:

GOOD:

Magic -> Combat
Combat -> Core

BAD:

Combat -> Magic

Combat must never know that magic exists.

Similarly:

Cultivation -> Resource
Cultivation -> Rule
Cultivation -> Combat

But:

Combat must not depend on Cultivation.

==================================================
DATA DRIVEN CONTENT
==================================================

Content should preferably be represented as data.

Example:

{
    "id": "iron_sword",
    "type": "item",
    "tags": [
        "weapon",
        "sword",
        "physical"
    ],
    "components": {
        "attack": {
            "damage": 12
        }
    }
}

Do not create a new source-code class for every individual item.

==================================================
TESTING
==================================================

Every core service requires unit tests.

Every plugin requires:

- registration test
- initialization test
- behavior tests
- serialization test where applicable
- dependency test

Rules and effects must have isolated tests.

Create integration tests proving:

1. Core can run without content plugins.
2. Martial Arts can run without Magic.
3. Magic can run without Martial Arts.
4. Martial Arts + Magic can coexist.
5. Plugins can be loaded/unloaded.
6. Plugin state can be serialized.
7. Deterministic RNG produces reproducible results.

==================================================
DETERMINISM
==================================================

Gameplay RNG must be injectable.

Never call global/random APIs directly from gameplay systems.

All randomness must go through RNGService.

A run should be reproducible from:

seed + initial state + player actions.

==================================================
SERIALIZATION
==================================================

Save data must contain:

engine version
plugin versions
game state
entity state
component state
RNG state

Do not serialize implementation-specific runtime objects.

Use stable IDs.

==================================================
CODE QUALITY
==================================================

Prefer:

composition
interfaces
dependency injection
pure functions
data-driven definitions
small services
explicit dependencies

Avoid:

global state
singletons where unnecessary
deep inheritance
circular dependencies
god classes
hardcoded content
hardcoded item combinations
magic strings scattered throughout code

==================================================
ARCHITECTURAL ENFORCEMENT
==================================================

Before implementing a feature ask:

1. Is this generic engine behavior?
2. Is this plugin behavior?
3. Can this be represented as data?
4. Can this communicate through events?
5. Can this use a generic effect/condition/rule?
6. Does this create a dependency on a specific content domain?

If a feature introduces martial-arts or magic vocabulary into Core,
stop and redesign it.

==================================================
IMPLEMENTATION STYLE
==================================================

Work incrementally.

Before major implementation:

1. Inspect repository.
2. Inspect existing architecture.
3. Identify affected modules.
4. Propose the smallest implementation.
5. Implement.
6. Run tests.
7. Fix failures.
8. Update architecture documentation.

Never rewrite unrelated modules.

Never introduce speculative abstractions without a concrete use case.

Favor the smallest stable API that can support future plugins.

==================================================
SUCCESS CRITERIA
==================================================

The final architecture must allow this:

Core Engine
+
MartialArtsPlugin

to create a martial arts game.

And:

Core Engine
+
MagicPlugin

to create a magic game.

And:

Core Engine
+
MartialArtsPlugin
+
MagicPlugin
+
CultivationPlugin

to create a hybrid game.

WITHOUT modifying Core Engine.