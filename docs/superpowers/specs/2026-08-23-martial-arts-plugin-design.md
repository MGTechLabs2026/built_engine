# MartialArts Plugin — Design

## Purpose

Implement MartialArts as the first **content** plugin — a plugin that
depends on Combat (per `claude.md`'s DEPENDENCY RULE: `MartialArts ->
Combat -> Core`) but contributes zero martial-arts vocabulary to either
Combat or Core. It uses only Combat's and Core's already-public APIs
(`package:build_engine/build_engine.dart`, `package:build_engine/combat_plugin.dart`)
— no file under `lib/src/` outside `lib/src/plugins/martial_arts/` is
touched by this work.

A minimal vertical slice: 3 styles (Boxing, Shaolin, Tai Chi), 2 resources
(Qi, Momentum), the 11 given tags, 6 techniques, 3 stances, 5 items, 3
trinkets, and the three named interactions (Boxing momentum generation,
Shaolin defensive synergy, Tai Chi counter/redirect) — each implemented
through components, tags, rules, conditions, effects, modifiers, and
events already provided by Core/Combat, never by modifying either.

## The core problem, and why it can't be solved the "obvious" way

"Shaolin defensive synergy" (mitigate incoming damage) and "Tai Chi
counter" (redirect damage to the attacker) both sound like they need to
intercept an *incoming* attack. But `AttackAction.effectsFor` (Combat)
only resolves the *attacker's* modifiers for its own `damageStat` — it
never looks at the *target's* modifiers — and `EntityDamaged` (published
by core's `Damage` effect) carries only `(id, amount)`, no attacker
reference. Neither gap can be closed without editing `AttackAction` or
`Damage`, which this task forbids.

**Solution: react to Combat's existing events instead of intercepting
Combat's existing effects.**

- Shaolin's mitigation reacts to `EntityDamaged` (subject = the damaged
  entity) — a heal-back after the fact, not a block. This needs no
  attacker reference at all.
- Shaolin's "synergy" half (defense empowering offense) is a **permanent
  conditional `Modifier`** — `condition: HasTagQuery('stance:iron_body')`
  — registered once when the entity learns Shaolin, boosting their own
  `palm` stat only while that stance tag is active. Pure Modifier Engine
  composition, no Rule involved.
- Tai Chi's counter reacts to `ActionCompleted` — which Combat already
  publishes carrying `actor` **and** `targets` for every action, regardless
  of who the attacker is (a plain core `AttackAction` from a
  martial-arts-unaware "Generic Combatant" included). A custom `Condition`
  inspects `event.targets` for the `stance:tai_chi` tag; if found, the
  rule's effect (`Damage`) applies to `event.actor` — the attacker.
  **Known, documented simplification:** `ActionCompleted` fires whether or
  not the triggering action's own conditions passed (a miss included) —
  Combat exposes no "did it land" flag on the event, and adding one would
  violate the no-Core-changes constraint. The counter therefore fires on
  any completed attack targeting a Tai Chi stance, landed or not —
  thematically defensible ("redirect on contact"), not a bug to fix later
  without touching Combat.
- Boxing's momentum generation needs neither of the above — it's a flat
  `costEffects: [ModifyResource('momentum', +N)]` on the attacking
  technique itself, applied (like any `CombatAction`'s `costEffects`)
  whenever that technique's own conditions pass.

This is the one genuinely non-obvious design decision in this plugin;
everything else below is mechanical composition of existing primitives.

## File layout

```
lib/src/plugins/martial_arts/
  martial_styles.dart            # style id constants + learnStyle()
  martial_loadout_component.dart # MartialLoadoutComponent
  martial_conditions.dart        # TaiChiCounterCondition
  martial_item.dart              # MartialItemDefinition, equipItem(), 5 items, 3 trinkets
  martial_technique_action.dart  # MartialTechniqueAction, 6 techniques, 3 stances
  martial_arts_rules.dart        # buildMartialArtsRules() — the 4 registered Rules
  martial_arts_plugin.dart       # MartialArtsPlugin (GamePlugin)
lib/martial_arts_plugin.dart     # public export barrel
```

Every file imports Combat/Core exclusively via
`package:build_engine/build_engine.dart` and
`package:build_engine/combat_plugin.dart` — never `lib/src/...` directly,
matching Combat's own established convention for depending on Core.

## Styles (`martial_styles.dart`)

No component, no entity — a style is a marker tag. `learnStyle` uses the
existing `AddTag` effect (via a standalone `RuleContext`, the same pattern
`CombatSystem` itself uses to apply effects outside a rule firing):

```dart
abstract final class MartialStyles {
  static const boxing = 'boxing';
  static const shaolin = 'shaolin';
  static const taiChi = 'taiChi';
}

void learnStyle(EntityId entity, String styleId, PluginContext context) {
  final ctx = _standaloneContext(entity, context);
  const AddTag('martial').apply(ctx);
  AddTag('style:$styleId').apply(ctx);
  if (styleId == MartialStyles.shaolin) {
    context.modifiers.add(Modifier(
      source: ModifierSource('style:shaolin:synergy:${entity.value}'),
      target: entity,
      stat: 'palm',
      operation: ModifierOperation.add,
      value: 4,
      condition: HasTagQuery('stance:iron_body'),
    ));
  }
}
```

Branching on `styleId` inside `learnStyle` for Shaolin's synergy modifier
is content-specific logic — which is exactly what belongs inside a content
plugin, not Core or Combat. `HasTagQuery`/`Modifier`/`ModifierSource` are
all existing public core types.

## `MartialLoadoutComponent` (`martial_loadout_component.dart`)

Tracks which item entities are currently equipped on a combatant — genuine
state this plugin needs (not speculative): it's what a future query or UI
would read to answer "what is this combatant wearing."

```dart
class MartialLoadoutComponent {
  const MartialLoadoutComponent({required this.equippedItems});
  final List<EntityId> equippedItems;

  Map<String, dynamic> toJson() =>
      {'equippedItems': [for (final id in equippedItems) id.value]};

  factory MartialLoadoutComponent.fromJson(Map<String, dynamic> json) =>
      MartialLoadoutComponent(
        equippedItems: [
          for (final value in json['equippedItems'] as List<dynamic>)
            EntityId(value as int),
        ],
      );
}
```

`toJson`/`fromJson` follow `Container`/`CombatantComponent`'s established
module-local serialization precedent.

## Items and trinkets (`martial_item.dart`)

One class covers both — trinkets are simply the items whose behavior comes
from a Rule (see below) rather than a static `Modifier`:

```dart
class MartialItemDefinition {
  const MartialItemDefinition({
    required this.id,
    required this.tags,
    this.modifiersFor = _noModifiers,
  });

  final String id;
  final Set<String> tags;
  final List<Modifier> Function(EntityId wearer) modifiersFor;

  static List<Modifier> _noModifiers(EntityId wearer) => const [];
}

EntityId equipItem(
  MartialItemDefinition item,
  EntityId wearer,
  PluginContext context,
) {
  final itemEntity = context.entities.create();
  context.components.add(itemEntity, TagSet(item.tags));
  for (final modifier in item.modifiersFor(wearer)) {
    context.modifiers.add(modifier);
  }
  final ctx = _standaloneContext(wearer, context);
  AddTag('equipped:${item.id}').apply(ctx);
  final loadout = context.components.get<MartialLoadoutComponent>(wearer);
  context.components.add(
    wearer,
    MartialLoadoutComponent(
      equippedItems: [...?loadout?.equippedItems, itemEntity],
    ),
  );
  return itemEntity;
}
```

Each item's `modifiersFor` is a small top-level function (a top-level
function tear-off is a compile-time constant in Dart, so item constants
stay `const`):

| Item | id | tags | effect |
|---|---|---|---|
| Brass Knuckles | `brass_knuckles` | martial, fist, western | `+6 add` to `punch` |
| Iron Palm Wraps | `iron_palm_wraps` | martial, palm, eastern | `+6 add` to `palm` |
| Tai Chi Silk Sash | `tai_chi_silk_sash` | martial, internal, eastern, qi | `+5 add` to `internal` |
| Sparring Gloves | `sparring_gloves` | martial, fist, western | `+3 add` to `punch` |
| Weighted Vest | `weighted_vest` | martial, fist, western, external | `×1.1 multiply` on `punch` (stacks with Brass Knuckles' `add`, demonstrating the resolver's add-then-multiply pipeline) |

```dart
const martialItems = [
  brassKnuckles, ironPalmWraps, taiChiSilkSash, sparringGloves, weightedVest,
];
```

Trinkets — two are pure Rule-driven passives (`modifiersFor` returns
`[]`; their behavior comes entirely from `martial_arts_rules.dart`
checking their `equipped:<id>` tag), one is a conditional synergy
`Modifier` on Tai Chi's own damage while their stance is active (mirroring
Shaolin's synergy pattern, not the fixed counter-damage number, since that
number is a static `Rule` effect, not modifier-resolvable without
inventing a new Effect type Combat doesn't have):

| Trinket | id | tags | effect |
|---|---|---|---|
| Momentum Trinket | `momentum_trinket` | martial, western | none (drives Rule below) |
| Qi Pendant | `qi_pendant` | martial, qi, eastern | none (drives Rule below) |
| Counterstrike Ring | `counterstrike_ring` | martial, eastern, counter | `+3 add` to `internal`, `condition: HasTagQuery('stance:tai_chi')` |

```dart
const martialTrinkets = [momentumTrinket, qiPendant, counterstrikeRing];
```

## `TaiChiCounterCondition` (`martial_conditions.dart`)

```dart
class TaiChiCounterCondition implements Condition {
  const TaiChiCounterCondition();

  @override
  bool evaluate(RuleContext context) {
    final event = context.triggerEvent;
    if (event is! ActionCompleted) return false;
    final scope = QueryScope(components: context.components);
    return event.targets
        .any((target) => HasTagQuery('stance:tai_chi').matches(target, scope));
  }
}
```

A plugin-local `Condition` implementation — exactly the "implement
directly, no registry" extension point Core's `Condition` interface is
designed for.

## `MartialTechniqueAction` (`martial_technique_action.dart`)

One class for all 6 techniques and 3 stances — the same "don't create a
new source-code class per content item" principle `AttackAction` already
demonstrates. A technique with `baseDamage`/`damageStat` set is an attack
(damage resolved through the Modifier Engine, identical mechanism to
`AttackAction`); one with `selfEffects` set instead (and `targets: [actor]`
at the call site) is a stance:

```dart
class MartialTechniqueAction extends CombatAction {
  const MartialTechniqueAction({
    required this.actor,
    required this.targets,
    required this.tags,
    this.conditions = const [],
    this.costEffects = const [],
    this.baseDamage,
    this.damageStat,
    this.selfEffects = const [],
  });

  @override final EntityId actor;
  @override final List<EntityId> targets;

  /// This technique's own tags (fist/palm/internal/etc) — content
  /// metadata, not currently read by any Condition; kept for the same
  /// reason `AttackAction`-adjacent items carry tags in `claude.md`'s own
  /// example.
  final Set<String> tags;

  @override final List<Condition> conditions;
  @override final List<Effect> costEffects;

  /// Set together with [damageStat] for an attack technique. Leave both
  /// null and set [selfEffects] instead for a stance/utility technique —
  /// never set both kinds on the same instance.
  final num? baseDamage;
  final String? damageStat;
  final List<Effect> selfEffects;

  @override
  List<Effect> effectsFor(EntityId target, PluginContext context) {
    if (baseDamage != null) {
      final resolved = const ModifierResolver().resolve(
        baseDamage!,
        context.modifiers.activeModifiersFor(actor, damageStat!, context.components),
      );
      return [Damage(resolved)];
    }
    return selfEffects;
  }
}
```

Content (factory functions taking `actor`/`targets`, everything else
fixed data):

| # | Name | Style | Tags | Conditions | Cost | Damage (stat) |
|---|---|---|---|---|---|---|
| 1 | Jab | Boxing | martial, fist, western, external | style:boxing | `momentum +8` | 6 (`punch`) |
| 2 | Power Cross | Boxing | martial, fist, western, external | style:boxing, momentum > 19 | `momentum -20` | 18 (`punch`) |
| 3 | Palm Strike | Shaolin | martial, palm, eastern, external | style:shaolin, qi > 2 | `qi -3` | 8 (`palm`) |
| 4 | Blazing Palm | Shaolin | martial, palm, eastern, fire, qi | style:shaolin, qi > 7 | `qi -8` | 14 (`palm`) |
| 5 | Push Hands | Tai Chi | martial, internal, eastern, qi | style:taiChi, qi > 3 | `qi -4` | 7 (`internal`) |
| 6 | Whirling Palm | Tai Chi | martial, internal, eastern, qi, yang | style:taiChi, qi > 5 | `qi -6` | 10 (`internal`) |

Stances (self-targeted, `selfEffects` grants the stance tag):

| Name | Style | Tags | Conditions | Cost | Grants |
|---|---|---|---|---|---|
| Guard Stance | Boxing | martial, fist, western | style:boxing | — | `AddTag('stance:guard')`, `ModifyResource('momentum', 5)` |
| Iron Body Stance | Shaolin | martial, qi, internal, eastern | style:shaolin, qi > 4 | `qi -5` | `AddTag('stance:iron_body')` |
| Yielding Stance | Tai Chi | martial, internal, eastern, qi, counter | style:taiChi, qi > 2 | `qi -3` | `AddTag('stance:tai_chi')` |

All 11 required tags appear at least once across this table:
martial/fist/palm/internal/external/qi/yang/fire/counter/western/eastern.

## `MartialArtsRules` (`martial_arts_rules.dart`)

Four `Rule`s, built by one function, registered by the plugin:

```dart
List<Rule> buildMartialArtsRules() => [
  _shaolinDefensiveSynergyRule(),
  _taiChiCounterRule(),
  _passiveResourceRegenRule(
    requiresTag: 'equipped:momentum_trinket', resource: 'momentum', amount: 3,
  ),
  _passiveResourceRegenRule(
    requiresTag: 'equipped:qi_pendant', resource: 'qi', amount: 2,
  ),
];

Rule _shaolinDefensiveSynergyRule() => Rule(
  trigger: EntityDamaged,
  subjectOf: (event) => (event as EntityDamaged).id,
  conditions: const [HasTag('stance:iron_body')],
  effects: const [Heal(2)],
);

Rule _taiChiCounterRule() => Rule(
  trigger: ActionCompleted,
  subjectOf: (event) => (event as ActionCompleted).actor,
  conditions: const [TaiChiCounterCondition()],
  effects: const [Damage(3)],
);

Rule _passiveResourceRegenRule({
  required String requiresTag,
  required String resource,
  required num amount,
}) => Rule(
  trigger: TurnStarted,
  subjectOf: (event) => (event as TurnStarted).actor,
  conditions: [HasTag(requiresTag)],
  effects: [ModifyResource(resource, amount)],
);
```

The two trinket-regen rules are one data-driven factory called twice, not
two near-duplicate rules — DRY without a new abstraction beyond what
`Rule` already provides.

## `MartialArtsPlugin` (`martial_arts_plugin.dart`)

```dart
class MartialArtsPlugin extends GamePlugin {
  @override
  String get id => 'martial_arts';

  @override
  String get version => '0.1.0';

  @override
  List<String> get dependencies => const ['combat'];

  final List<EventSubscription> _subscriptions = [];

  @override
  void initialize(PluginContext context) {
    for (final rule in buildMartialArtsRules()) {
      _subscriptions.add(context.rules.register(rule));
    }
  }

  /// Mirrors [initialize]: cancels every rule subscription taken out
  /// there, so an unregistered `MartialArtsPlugin` stops reacting to
  /// events entirely — the same teardown discipline `CombatPlugin`
  /// established for its own `EntityKilled` subscription.
  @override
  void unregister(PluginContext context) {
    for (final subscription in _subscriptions) {
      subscription.cancel();
    }
    _subscriptions.clear();
  }
}
```

`dependencies => ['combat']` declares load order (and documents intent);
`MartialArtsPlugin` never holds a reference to `CombatPlugin`/`CombatSystem`
— it only depends on Combat's public event *vocabulary*
(`TurnStarted`/`EntityDamaged`/`ActionCompleted`), reached through the
shared `RuleEngine`/`EventBus` every plugin already gets via
`PluginContext`. This is what makes "Combat has zero knowledge MartialArts
exists" concretely true rather than just a comment: nothing in Combat's
source references MartialArts, and nothing in MartialArts needs a live
Combat object reference either — only its events.

## `lib/martial_arts_plugin.dart` (barrel)

Exports every public type above, alphabetically, mirroring
`lib/combat_plugin.dart`'s own convention.

## Testing plan

- Unit tests per file: `learnStyle` (tag grants, Shaolin's synergy modifier
  registered correctly), `MartialLoadoutComponent` (including
  `toJson`/`fromJson` round-trip), `equipItem` (item entity created,
  modifiers registered and resolve correctly including the add+multiply
  stack on `punch`, `equipped:` tag granted, loadout recorded and
  accumulates across multiple equips), `TaiChiCounterCondition` (matches
  only on `ActionCompleted` with a tagged target, not other event types,
  not untagged targets), `MartialTechniqueAction` (each of the 9
  factories: conditions gate correctly, costs apply, attack damage
  resolves through modifiers identically to `AttackAction`, stance
  variants grant their tag and no damage effect), the 4 rules in isolation
  (each fires only under its own condition, with a bare `PluginContext` —
  no full battle needed to prove a single rule's mechanics).
- Plugin lifecycle tests: registration/initialization,
  `dependencies == ['combat']`, all 4 rule subscriptions captured, and —
  critically — `unregister` actually stops them (publish a triggering
  event after `unregister` and assert no effect).
- Integration tests (`test/integration/martial_arts_end_to_end_test.dart`):
  1. **The required scenario** — Player learns Boxing, equips Brass
     Knuckles + Momentum Trinket; Enemy is a bare `CombatantComponent` +
     `HealthComponent` entity with zero martial-arts components, attacking
     via plain core `AttackAction`. Battle runs multiple turns: Jab lands
     for `6 + 6 = 12` and grows momentum via both its own `costEffects`
     and the trinket's passive `TurnStarted` regen; once momentum crosses
     19, Power Cross lands for 18 and drains momentum back down; the
     enemy's plain attacks land on the player throughout with no martial
     interaction at all. Asserts health/resource values at each step and
     that the battle concludes normally (a decisive win/loss once one
     side is reduced to 0 health).
  2. **Shaolin defensive synergy**, in isolation: entity learns Shaolin,
     takes damage, `EntityDamaged`'s mitigation `Heal` applies only while
     `stance:iron_body` is active; separately, Palm Strike's `palm` damage
     is measurably higher while that stance is active than while it isn't
     (proving the synergy `Modifier`, not just the regen Rule).
  3. **Tai Chi counter**, in isolation: entity learns Tai Chi, activates
     Yielding Stance, a plain core `AttackAction` (simulating a
     martial-arts-unaware attacker) targets them — asserts the counter
     `Damage` lands on the attacker, proving the mechanic works against an
     attacker with zero martial-arts awareness, not just against another
     `MartialTechniqueAction`.
  4. **Removability**: register `CombatPlugin` + `MartialArtsPlugin`,
     run a scenario exercising at least one Rule (e.g. Shaolin's
     mitigation), then `unregister` `MartialArtsPlugin` only — assert a
     subsequent battle using plain `AttackAction`s (no `MartialArtsPlugin`
     rules registered any more) runs to a normal conclusion, and that
     re-triggering what used to fire a MartialArts rule (e.g. publishing
     `EntityDamaged` for a still-`stance:iron_body`-tagged entity) now has
     no effect — Combat's own mechanics are completely unaffected by
     MartialArts' presence or absence.

## Explicitly out of scope

- Any change to `lib/src/` outside `lib/src/plugins/martial_arts/`.
- Slot-limited equipment (spatial `Container` usage) — the user's own
  "Use:" list names components/tags/rules/conditions/effects/
  modifiers/events, not the Spatial/Container Engine; equip is unlimited
  for this vertical slice.
- Unequip / toggle-off stances, style un-learning, item removal —
  nothing here asks for it, and `ModifierCollection.removeBySource` +
  `RemoveTag` already provide the primitives for a future pass if needed.
- Any AI/decision-making for which technique to use — the test scenario
  drives specific technique choices explicitly, matching how Combat's own
  integration test drives specific actions explicitly.
