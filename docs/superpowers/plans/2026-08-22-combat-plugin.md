# Combat Plugin Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement Combat as the first real plugin on Build Engine core: `CombatantComponent`/`CombatStateComponent`, a generic Action/Target model, turn/battle orchestration, damage/healing/defeat, and a concrete generic `AttackAction` — with zero martial-arts/magic/cultivation/weapon vocabulary, built entirely on core's existing generic services.

**Architecture:** `PluginContext` grows to expose `RngService`/`RuleEngine`/`QueryEngine`/`ModifierCollection` (already built in core, but not yet reachable from a plugin's lifecycle methods). Combat lives under `lib/src/plugins/combat/` in the same package, importing core only via its public `build_engine.dart` barrel. `CombatAction` is an abstract interface (mirroring `Condition`/`Effect`'s "implement directly, no registry" pattern) that `CombatSystem` executes by building `RuleContext`s and applying effects through the existing Effect Engine. Turn order and battle state live on a `CombatStateComponent` attached to a dedicated battle entity. Defeat/win/loss is derived by re-querying living participants via the Query Engine, batched exactly once per `executeAction` call (not once per individual kill), so a single action that kills members of multiple teams at once is judged correctly.

**Tech Stack:** Dart (SDK `^3.7.0`), `package:test`, existing `build_engine` core services (`EntityRegistry`, `ComponentStore`, `EventBus`, `RngService`, `Query`/`QueryEngine`, `Condition`/`Effect`/`Rule`/`RuleEngine`/`RuleContext`, `Modifier`/`ModifierCollection`/`ModifierResolver`, `GamePlugin`/`PluginContext`/`PluginManager`).

**Spec:** `docs/superpowers/specs/2026-08-22-combat-plugin-design.md`

All paths below are relative to the repo root: `/Users/m4maxpro/Projects/Tome:RougelikeGame`.

## Global Constraints

- No martial-arts, magic, cultivation, weapon, or other game-specific vocabulary anywhere in this package, including inside Combat itself.
- Combat imports core exclusively via `package:build_engine/build_engine.dart` — never `lib/src/...` internals directly.
- `PluginContext` gains `rng`, `rules`, `queries`, `modifiers`. Do **not** add anything to `RuleContext` or change `RuleEngine`'s constructor — the damage/Modifier-Engine design was specifically reworked during planning to avoid that cascade (see spec).
- `CombatAction` is abstract (mirrors `Condition`/`Effect`) — not a concrete data class. No dedicated `Target` class — targets are a plain `List<EntityId>`.
- No `HealAction` or other dedicated action class beyond `AttackAction` — "Healing" is demonstrated with a minimal test-only `CombatAction` implementation, not a new production class.
- Every participant passed to `CombatSystem.startBattle` must carry a `CombatantComponent` — required, not defaulted.
- Battle-end (team-elimination) checks batch exactly once per `executeAction` call via an in-flight suppression flag, never once per individual `EntityKilled` — see the spec's Defeat/battle end section for why.
- `TurnEnded` always publishes for the acting entity, even when that action ends the battle. `TurnStarted` for a next actor publishes only if the battle is still active afterward.
- No engine-wide Serialization integration — Combat's `toJson`/`fromJson` on its two components is module-local only, matching `Container`'s existing precedent.
- Every task ends with `dart analyze` reporting zero issues and `dart test` passing, before commit.

---

### Task 1: Extend `PluginContext` with `rng`/`rules`/`queries`/`modifiers`

**Files:**
- Modify: `lib/src/plugin/plugin_context.dart`
- Modify: `test/plugin_manager_test.dart:38-45` (the `_newContext()` helper)
- Modify: `test/integration/core_boots_without_plugins_test.dart:44-48` and `:79-83` (two inline `PluginContext(...)` constructions)
- Test: `test/plugin_context_test.dart`

**Interfaces:**
- Consumes: `EntityRegistry`, `ComponentStore`, `EventBus`, `RngService`, `RuleEngine`, `QueryEngine`, `QueryScope`, `ModifierCollection` (all existing, all already exported from `lib/build_engine.dart`).
- Produces: `PluginContext` now requires `rng: RngService`, `rules: RuleEngine`, `queries: QueryEngine`, `modifiers: ModifierCollection` in addition to its existing three fields. Every later task's tests construct `PluginContext` with all seven.

- [ ] **Step 1: Write the failing test**

Create `test/plugin_context_test.dart`:
```dart
import 'package:build_engine/build_engine.dart';
import 'package:test/test.dart';

void main() {
  test('PluginContext exposes every constructor argument unchanged', () {
    final events = EventBus();
    final entities = EntityRegistry(events);
    final components = ComponentStore();
    final rng = RngService(1);
    final rules = RuleEngine(
      entities: entities,
      components: components,
      events: events,
      rng: rng,
    );
    final queries = QueryEngine(QueryScope(components: components));
    final modifiers = ModifierCollection();

    final context = PluginContext(
      entities: entities,
      components: components,
      events: events,
      rng: rng,
      rules: rules,
      queries: queries,
      modifiers: modifiers,
    );

    expect(context.entities, same(entities));
    expect(context.components, same(components));
    expect(context.events, same(events));
    expect(context.rng, same(rng));
    expect(context.rules, same(rules));
    expect(context.queries, same(queries));
    expect(context.modifiers, same(modifiers));
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `dart test test/plugin_context_test.dart`
Expected: FAIL — `PluginContext` has no `rng`/`rules`/`queries`/`modifiers` named parameters yet.

- [ ] **Step 3: Extend `PluginContext` and fix the two existing call sites it breaks**

Replace the contents of `lib/src/plugin/plugin_context.dart` with:
```dart
import '../component/component_store.dart';
import '../entity/entity_registry.dart';
import '../event/event_bus.dart';
import '../modifier/modifier_collection.dart';
import '../query/query_engine.dart';
import '../rng/rng_service.dart';
import '../rule/rule_engine.dart';

/// The controlled access every plugin lifecycle method receives. Exposes
/// every core service that exists so far.
class PluginContext {
  const PluginContext({
    required this.entities,
    required this.components,
    required this.events,
    required this.rng,
    required this.rules,
    required this.queries,
    required this.modifiers,
  });

  final EntityRegistry entities;
  final ComponentStore components;
  final EventBus events;
  final RngService rng;
  final RuleEngine rules;
  final QueryEngine queries;
  final ModifierCollection modifiers;
}
```

In `test/plugin_manager_test.dart`, replace the existing `_newContext()` function (currently lines 38-45) with:
```dart
PluginContext _newContext() {
  final events = EventBus();
  final entities = EntityRegistry(events);
  final components = ComponentStore();
  final rng = RngService(1);
  return PluginContext(
    entities: entities,
    components: components,
    events: events,
    rng: rng,
    rules: RuleEngine(
      entities: entities,
      components: components,
      events: events,
      rng: rng,
    ),
    queries: QueryEngine(QueryScope(components: components)),
    modifiers: ModifierCollection(),
  );
}
```

In `test/integration/core_boots_without_plugins_test.dart`, add the same `_newContext()` helper (place it after the imports, before the `_MarkerComponent` class):
```dart
PluginContext _newContext() {
  final events = EventBus();
  final entities = EntityRegistry(events);
  final components = ComponentStore();
  final rng = RngService(1);
  return PluginContext(
    entities: entities,
    components: components,
    events: events,
    rng: rng,
    rules: RuleEngine(
      entities: entities,
      components: components,
      events: events,
      rng: rng,
    ),
    queries: QueryEngine(QueryScope(components: components)),
    modifiers: ModifierCollection(),
  );
}
```

Then replace both occurrences (in `'full lifecycle succeeds with zero plugins registered'` and in `'plugins load and unload in dependency order end-to-end'`) of:
```dart
      final events = EventBus();
      final context = PluginContext(
        entities: EntityRegistry(events),
        components: ComponentStore(),
        events: events,
      );
```
with:
```dart
      final context = _newContext();
```
(Neither test references the standalone `events` variable again after this point — confirm that by reading each test body before deleting it.)

- [ ] **Step 4: Run the whole suite and analyze**

Run:
```bash
dart test
dart analyze
```
Expected: every test across the whole package PASSes; `dart analyze` reports `No issues found!`.

- [ ] **Step 5: Commit**

```bash
git add lib/src/plugin/plugin_context.dart test/plugin_manager_test.dart test/integration/core_boots_without_plugins_test.dart test/plugin_context_test.dart
git commit -m "feat: expose RngService, RuleEngine, QueryEngine, and ModifierCollection on PluginContext"
```

---

### Task 2: `CombatantComponent`

**Files:**
- Create: `lib/src/plugins/combat/combatant_component.dart`
- Create: `lib/combat_plugin.dart` (new public export barrel for this plugin)
- Test: `test/plugins/combat/combatant_component_test.dart`

**Interfaces:**
- Consumes: nothing beyond Dart core types.
- Produces: `class CombatantComponent { const CombatantComponent({required String team, num initiative = 0}); final String team; final num initiative; Map<String, dynamic> toJson(); factory CombatantComponent.fromJson(Map<String, dynamic>); }`. `CombatSystem` (Task 5) reads `team` and `initiative` off this component for every battle participant.

- [ ] **Step 1: Write the failing test**

Create `test/plugins/combat/combatant_component_test.dart`:
```dart
import 'package:build_engine/combat_plugin.dart';
import 'package:test/test.dart';

void main() {
  group('CombatantComponent', () {
    test('stores team and initiative', () {
      const component = CombatantComponent(team: 'alpha', initiative: 5);
      expect(component.team, equals('alpha'));
      expect(component.initiative, equals(5));
    });

    test('initiative defaults to 0', () {
      const component = CombatantComponent(team: 'alpha');
      expect(component.initiative, equals(0));
    });

    test('round-trips through toJson/fromJson', () {
      const component = CombatantComponent(team: 'beta', initiative: 3);
      final restored = CombatantComponent.fromJson(component.toJson());
      expect(restored.team, equals('beta'));
      expect(restored.initiative, equals(3));
    });
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `dart test test/plugins/combat/combatant_component_test.dart`
Expected: FAIL — `Error: Not found: 'package:build_engine/combat_plugin.dart'`.

- [ ] **Step 3: Implement `CombatantComponent` and the barrel file**

Create `lib/src/plugins/combat/combatant_component.dart`:
```dart
/// Marks an entity as a participant in Combat and carries the data its
/// turn order and win/loss grouping need. `team` and `initiative` are
/// arbitrary values a caller/content plugin chooses — Combat never
/// interprets what a team name means beyond grouping and comparing it.
class CombatantComponent {
  const CombatantComponent({required this.team, this.initiative = 0});

  /// An arbitrary label used to group participants for win/loss
  /// determination. Combat never interprets its value.
  final String team;

  /// Turn order: a battle's participants act in descending order of this
  /// value; ties break by the order given to `CombatSystem.startBattle`.
  final num initiative;

  /// A plain, stable structure — no engine-wide Serialization
  /// integration, matching `Container.toJson`'s module-local precedent.
  Map<String, dynamic> toJson() => {'team': team, 'initiative': initiative};

  factory CombatantComponent.fromJson(Map<String, dynamic> json) =>
      CombatantComponent(
        team: json['team'] as String,
        initiative: json['initiative'] as num,
      );
}
```

Create `lib/combat_plugin.dart`:
```dart
/// Combat — a plugin built on Build Engine core. Turn-based combat
/// (combatants, actions, targets, damage, healing, defeat) with zero
/// martial-arts/magic/cultivation/weapon vocabulary — see `claude.md`'s
/// CORE PROVIDES VERBS / PLUGINS PROVIDE NOUNS contract. Depends only on
/// `package:build_engine/build_engine.dart`'s public core API.
library;

export 'src/plugins/combat/combatant_component.dart';
```

- [ ] **Step 4: Run the test to verify it passes, and analyze**

Run:
```bash
dart test test/plugins/combat/combatant_component_test.dart
dart analyze
```
Expected: all 3 tests PASS; `dart analyze` reports `No issues found!`.

- [ ] **Step 5: Commit**

```bash
git add lib/src/plugins/combat/combatant_component.dart lib/combat_plugin.dart test/plugins/combat/combatant_component_test.dart
git commit -m "feat: add CombatantComponent and the combat_plugin.dart barrel"
```

---

### Task 3: `CombatStateComponent`

**Files:**
- Create: `lib/src/plugins/combat/combat_state_component.dart`
- Modify: `lib/combat_plugin.dart`
- Test: `test/plugins/combat/combat_state_component_test.dart`

**Interfaces:**
- Consumes: `EntityId` (core, via `build_engine.dart`).
- Produces: `class CombatStateComponent { const CombatStateComponent({required List<EntityId> participants, required int currentTurnIndex, required int round, required bool active}); final List<EntityId> participants; final int currentTurnIndex; final int round; final bool active; Map<String, dynamic> toJson(); factory CombatStateComponent.fromJson(Map<String, dynamic>); }`. `CombatSystem` (Task 5) attaches this to a battle entity and reads/replaces it on every turn/action.

- [ ] **Step 1: Write the failing test**

Create `test/plugins/combat/combat_state_component_test.dart`:
```dart
import 'package:build_engine/build_engine.dart';
import 'package:build_engine/combat_plugin.dart';
import 'package:test/test.dart';

void main() {
  group('CombatStateComponent', () {
    test('stores all fields', () {
      const component = CombatStateComponent(
        participants: [EntityId(1), EntityId(2)],
        currentTurnIndex: 1,
        round: 3,
        active: true,
      );
      expect(
        component.participants,
        equals([const EntityId(1), const EntityId(2)]),
      );
      expect(component.currentTurnIndex, equals(1));
      expect(component.round, equals(3));
      expect(component.active, isTrue);
    });

    test('round-trips through toJson/fromJson', () {
      const component = CombatStateComponent(
        participants: [EntityId(1), EntityId(2), EntityId(3)],
        currentTurnIndex: 2,
        round: 5,
        active: false,
      );
      final restored = CombatStateComponent.fromJson(component.toJson());
      expect(restored.participants, equals(component.participants));
      expect(restored.currentTurnIndex, equals(2));
      expect(restored.round, equals(5));
      expect(restored.active, isFalse);
    });

    test('round-trips an empty participant list', () {
      const component = CombatStateComponent(
        participants: [],
        currentTurnIndex: 0,
        round: 1,
        active: true,
      );
      final restored = CombatStateComponent.fromJson(component.toJson());
      expect(restored.participants, isEmpty);
    });
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `dart test test/plugins/combat/combat_state_component_test.dart`
Expected: FAIL — `Error: Undefined class 'CombatStateComponent'`.

- [ ] **Step 3: Implement `CombatStateComponent`**

Create `lib/src/plugins/combat/combat_state_component.dart`:
```dart
import 'package:build_engine/build_engine.dart';

/// A battle's turn order and status, attached to a dedicated battle
/// entity (not to any participant) — a battle is itself an `EntityId`, so
/// multiple concurrent battles need no extra machinery.
class CombatStateComponent {
  const CombatStateComponent({
    required this.participants,
    required this.currentTurnIndex,
    required this.round,
    required this.active,
  });

  /// Fixed initiative order, set once by `CombatSystem.startBattle`.
  final List<EntityId> participants;

  /// Index into [participants] of whoever's turn it currently is.
  final int currentTurnIndex;

  /// Increments each time [currentTurnIndex] wraps back to 0.
  final int round;

  /// `false` once the battle has ended (a `BattleWon`/`BattleLost` pair
  /// has been published).
  final bool active;

  /// A plain, stable structure — no engine-wide Serialization
  /// integration, matching `Container.toJson`'s module-local precedent.
  Map<String, dynamic> toJson() => {
        'participants': [for (final id in participants) id.value],
        'currentTurnIndex': currentTurnIndex,
        'round': round,
        'active': active,
      };

  factory CombatStateComponent.fromJson(Map<String, dynamic> json) =>
      CombatStateComponent(
        participants: [
          for (final value in json['participants'] as List<dynamic>)
            EntityId(value as int),
        ],
        currentTurnIndex: json['currentTurnIndex'] as int,
        round: json['round'] as int,
        active: json['active'] as bool,
      );
}
```

Modify `lib/combat_plugin.dart` — `combat_state_component.dart` sorts before `combatant_component.dart` (`_` sorts before `a`), so the full file becomes:
```dart
/// Combat — a plugin built on Build Engine core. Turn-based combat
/// (combatants, actions, targets, damage, healing, defeat) with zero
/// martial-arts/magic/cultivation/weapon vocabulary — see `claude.md`'s
/// CORE PROVIDES VERBS / PLUGINS PROVIDE NOUNS contract. Depends only on
/// `package:build_engine/build_engine.dart`'s public core API.
library;

export 'src/plugins/combat/combat_state_component.dart';
export 'src/plugins/combat/combatant_component.dart';
```

- [ ] **Step 4: Run the test to verify it passes, and analyze**

Run:
```bash
dart test test/plugins/combat/combat_state_component_test.dart
dart analyze
```
Expected: all 3 tests PASS; `dart analyze` reports `No issues found!`.

- [ ] **Step 5: Commit**

```bash
git add lib/src/plugins/combat/combat_state_component.dart lib/combat_plugin.dart test/plugins/combat/combat_state_component_test.dart
git commit -m "feat: add CombatStateComponent"
```

---

### Task 4: `CombatAction` and `AttackAction`

**Files:**
- Create: `lib/src/plugins/combat/combat_action.dart`
- Modify: `lib/combat_plugin.dart`
- Test: `test/plugins/combat/combat_action_test.dart`

**Interfaces:**
- Consumes: `EntityId`, `Condition`, `Effect`, `Damage`, `Heal`, `PluginContext`, `Modifier`, `ModifierSource`, `ModifierOperation`, `ModifierResolver`, `RandomChance`, `ModifyResource` (all core, via `build_engine.dart`).
- Produces: `abstract class CombatAction { EntityId get actor; List<EntityId> get targets; List<Condition> get conditions => const []; List<Effect> get costEffects => const []; List<Effect> effectsFor(EntityId target, PluginContext context); }` and `class AttackAction extends CombatAction { const AttackAction({required EntityId actor, required List<EntityId> targets, required num baseDamage, required String damageStat, List<Condition> conditions = const [], List<Effect> costEffects = const []}); ... }`. Concrete actions use `extends`, not `implements` — `implements` would discard `conditions`/`costEffects`'s default `const []` bodies, since Dart only inherits a method's implementation through `extends` (the same reason `Query`'s own subclasses like `HasComponentQuery` already `extend Query` elsewhere in this codebase). `CombatSystem` (Task 5) consumes `CombatAction`'s full interface directly.

- [ ] **Step 1: Write the failing test**

Create `test/plugins/combat/combat_action_test.dart`:
```dart
import 'package:build_engine/build_engine.dart';
import 'package:build_engine/combat_plugin.dart';
import 'package:test/test.dart';

class _HealAction extends CombatAction {
  const _HealAction({
    required this.actor,
    required this.targets,
    required this.amount,
  });

  @override
  final EntityId actor;
  @override
  final List<EntityId> targets;
  final num amount;

  // conditions/costEffects are not overridden — CombatAction's own
  // `const []` defaults apply, since this class `extends CombatAction`.

  @override
  List<Effect> effectsFor(EntityId target, PluginContext context) =>
      [Heal(amount)];
}

PluginContext _newContext() {
  final events = EventBus();
  final entities = EntityRegistry(events);
  final components = ComponentStore();
  final rng = RngService(1);
  return PluginContext(
    entities: entities,
    components: components,
    events: events,
    rng: rng,
    rules: RuleEngine(
      entities: entities,
      components: components,
      events: events,
      rng: rng,
    ),
    queries: QueryEngine(QueryScope(components: components)),
    modifiers: ModifierCollection(),
  );
}

void main() {
  group('AttackAction', () {
    test('effectsFor applies flat base damage with no modifiers registered',
        () {
      final context = _newContext();
      final actor = context.entities.create();
      final target = context.entities.create();
      final action = AttackAction(
        actor: actor,
        targets: [target],
        baseDamage: 10,
        damageStat: 'attack',
      );

      final effects = action.effectsFor(target, context);

      expect(effects, hasLength(1));
      expect(effects.single, isA<Damage>());
      expect((effects.single as Damage).amount, equals(10));
    });

    test('effectsFor resolves damage through a registered modifier', () {
      final context = _newContext();
      final actor = context.entities.create();
      final target = context.entities.create();
      context.modifiers.add(Modifier(
        source: const ModifierSource('rage'),
        target: actor,
        stat: 'attack',
        operation: ModifierOperation.multiply,
        value: 2,
      ));
      final action = AttackAction(
        actor: actor,
        targets: [target],
        baseDamage: 10,
        damageStat: 'attack',
      );

      final effects = action.effectsFor(target, context);

      expect((effects.single as Damage).amount, equals(20));
    });

    test('a modifier registered for a different stat does not apply', () {
      final context = _newContext();
      final actor = context.entities.create();
      final target = context.entities.create();
      context.modifiers.add(Modifier(
        source: const ModifierSource('armor'),
        target: actor,
        stat: 'defense',
        operation: ModifierOperation.add,
        value: 100,
      ));
      final action = AttackAction(
        actor: actor,
        targets: [target],
        baseDamage: 10,
        damageStat: 'attack',
      );

      final effects = action.effectsFor(target, context);

      expect((effects.single as Damage).amount, equals(10));
    });

    test('conditions and costEffects default to empty', () {
      final action = AttackAction(
        actor: const EntityId(1),
        targets: const [EntityId(2)],
        baseDamage: 5,
        damageStat: 'attack',
      );
      expect(action.conditions, isEmpty);
      expect(action.costEffects, isEmpty);
    });

    test('conditions and costEffects can be supplied', () {
      final action = AttackAction(
        actor: const EntityId(1),
        targets: const [EntityId(2)],
        baseDamage: 5,
        damageStat: 'attack',
        conditions: [const RandomChance(0.9)],
        costEffects: const [ModifyResource('stamina', -5)],
      );
      expect(action.conditions, hasLength(1));
      expect(action.costEffects, hasLength(1));
    });
  });

  group('a custom CombatAction (Heal)', () {
    test(
        'effectsFor returns a Heal effect, proving the same interface '
        'handles healing without a dedicated HealAction class', () {
      final context = _newContext();
      final actor = context.entities.create();
      final target = context.entities.create();
      final action = _HealAction(actor: actor, targets: [target], amount: 15);

      final effects = action.effectsFor(target, context);

      expect(effects.single, isA<Heal>());
      expect((effects.single as Heal).amount, equals(15));
    });
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `dart test test/plugins/combat/combat_action_test.dart`
Expected: FAIL — `Error: Type 'CombatAction' not found`.

- [ ] **Step 3: Implement `CombatAction` and `AttackAction`**

Create `lib/src/plugins/combat/combat_action.dart`:
```dart
import 'package:build_engine/build_engine.dart';

/// A generic combat action: what an actor can do to zero or more targets
/// on their turn. Plugins compose their own actions by implementing this
/// directly — the same "no registry required" pattern `Condition`/`Effect`
/// already use in core.
abstract class CombatAction {
  /// The entity performing this action.
  EntityId get actor;

  /// The entities this action affects. A plain list, not a resolver
  /// strategy — whoever builds the action (AI, UI, a future plugin)
  /// decides who's targeted.
  List<EntityId> get targets;

  /// Checked against [actor] before anything else applies. Every
  /// condition must pass (AND) for [costEffects]/[effectsFor] to run.
  List<Condition> get conditions => const [];

  /// Applied once to [actor] if [conditions] all pass.
  List<Effect> get costEffects => const [];

  /// Applied once for each entry in [targets] if [conditions] all pass.
  /// [context] is the owning `PluginContext` — passed in at call time
  /// (rather than resolved once at construction) so an action can read
  /// execution-time state, e.g. Modifier Engine-derived values, exactly
  /// when it runs.
  List<Effect> effectsFor(EntityId target, PluginContext context);
}

/// A generic "deal damage to targets" action — no martial-arts/magic/
/// weapon vocabulary. [baseDamage] is resolved through the Modifier
/// Engine against [actor]'s [damageStat] before being applied via the
/// existing core `Damage` effect, so a future plugin can affect Combat's
/// damage purely by registering a `Modifier`, with zero Combat-side
/// knowledge that plugin exists.
class AttackAction extends CombatAction {
  const AttackAction({
    required this.actor,
    required this.targets,
    required this.baseDamage,
    required this.damageStat,
    this.conditions = const [],
    this.costEffects = const [],
  });

  @override
  final EntityId actor;
  @override
  final List<EntityId> targets;

  /// The un-modified damage value; see [effectsFor] for how modifiers
  /// adjust it.
  final num baseDamage;

  /// The `Modifier.stat` key this action reads on [actor] — an arbitrary,
  /// caller-chosen string. Combat never interprets its value.
  final String damageStat;

  @override
  final List<Condition> conditions;
  @override
  final List<Effect> costEffects;

  @override
  List<Effect> effectsFor(EntityId target, PluginContext context) {
    final resolved = const ModifierResolver().resolve(
      baseDamage,
      context.modifiers.activeModifiersFor(
        actor,
        damageStat,
        context.components,
      ),
    );
    return [Damage(resolved)];
  }
}
```

Modify `lib/combat_plugin.dart` — `combat_action.dart` sorts before `combat_state_component.dart` (`a` < `s`):
```dart
/// Combat — a plugin built on Build Engine core. Turn-based combat
/// (combatants, actions, targets, damage, healing, defeat) with zero
/// martial-arts/magic/cultivation/weapon vocabulary — see `claude.md`'s
/// CORE PROVIDES VERBS / PLUGINS PROVIDE NOUNS contract. Depends only on
/// `package:build_engine/build_engine.dart`'s public core API.
library;

export 'src/plugins/combat/combat_action.dart';
export 'src/plugins/combat/combat_state_component.dart';
export 'src/plugins/combat/combatant_component.dart';
```

- [ ] **Step 4: Run the test to verify it passes, and analyze**

Run:
```bash
dart test test/plugins/combat/combat_action_test.dart
dart analyze
```
Expected: all 6 tests PASS; `dart analyze` reports `No issues found!`.

- [ ] **Step 5: Commit**

```bash
git add lib/src/plugins/combat/combat_action.dart lib/combat_plugin.dart test/plugins/combat/combat_action_test.dart
git commit -m "feat: add CombatAction and AttackAction"
```

---

### Task 5: Combat events, `IllegalActionException`, and `CombatSystem`

**Files:**
- Create: `lib/src/plugins/combat/combat_events.dart`
- Create: `lib/src/plugins/combat/illegal_action_exception.dart`
- Create: `lib/src/plugins/combat/combat_system.dart`
- Modify: `lib/combat_plugin.dart`
- Test: `test/plugins/combat/combat_system_test.dart`

**Interfaces:**
- Consumes: `PluginContext`, `EntityId`, `EntityKilled`, `RuleContext`, `HealthBelowQuery`, `CombatantComponent` (Task 2), `CombatStateComponent` (Task 3), `CombatAction`/`AttackAction` (Task 4).
- Produces: events `ActionStarted`, `ActionCompleted`, `TurnStarted`, `TurnEnded`, `BattleStarted`, `BattleWon`, `BattleLost`; `class IllegalActionException implements Exception`; `class CombatSystem { CombatSystem(PluginContext context); EntityId startBattle(List<EntityId> participants); void executeAction(EntityId battle, CombatAction action); }`. `CombatPlugin` (Task 6) constructs one `CombatSystem`.

- [ ] **Step 1: Write the failing tests**

Create `test/plugins/combat/combat_system_test.dart`:
```dart
import 'package:build_engine/build_engine.dart';
import 'package:build_engine/combat_plugin.dart';
import 'package:test/test.dart';

PluginContext _newContext() {
  final events = EventBus();
  final entities = EntityRegistry(events);
  final components = ComponentStore();
  final rng = RngService(1);
  return PluginContext(
    entities: entities,
    components: components,
    events: events,
    rng: rng,
    rules: RuleEngine(
      entities: entities,
      components: components,
      events: events,
      rng: rng,
    ),
    queries: QueryEngine(QueryScope(components: components)),
    modifiers: ModifierCollection(),
  );
}

void main() {
  group('CombatSystem.startBattle', () {
    test(
        'orders participants by descending initiative, ties by input '
        'order, and publishes BattleStarted + the first TurnStarted', () {
      final context = _newContext();
      final system = CombatSystem(context);
      final a = context.entities.create();
      final b = context.entities.create();
      final c = context.entities.create();
      context.components
          .add(a, const CombatantComponent(team: 'alpha', initiative: 5));
      context.components
          .add(b, const CombatantComponent(team: 'beta', initiative: 10));
      context.components
          .add(c, const CombatantComponent(team: 'alpha', initiative: 5));
      final started = <BattleStarted>[];
      final turnsStarted = <TurnStarted>[];
      context.events.subscribe<BattleStarted>(started.add);
      context.events.subscribe<TurnStarted>(turnsStarted.add);

      final battle = system.startBattle([a, b, c]);

      final state = context.components.get<CombatStateComponent>(battle)!;
      expect(state.participants, equals([b, a, c]));
      expect(state.currentTurnIndex, equals(0));
      expect(state.round, equals(1));
      expect(state.active, isTrue);
      expect(started, hasLength(1));
      expect(started.single.participants, equals([b, a, c]));
      expect(turnsStarted, hasLength(1));
      expect(turnsStarted.single.actor, equals(b));
      expect(turnsStarted.single.round, equals(1));
    });
  });

  group('CombatSystem.executeAction — illegal use', () {
    test("throws IllegalActionException when it isn't the actor's turn", () {
      final context = _newContext();
      final system = CombatSystem(context);
      final a = context.entities.create();
      final b = context.entities.create();
      context.components
          .add(a, const CombatantComponent(team: 'alpha', initiative: 10));
      context.components
          .add(b, const CombatantComponent(team: 'beta', initiative: 5));
      context.components.add(a, const HealthComponent(current: 100, max: 100));
      context.components.add(b, const HealthComponent(current: 100, max: 100));
      final battle = system.startBattle([a, b]);
      final action =
          AttackAction(actor: b, targets: [a], baseDamage: 10, damageStat: 'attack');

      expect(
        () => system.executeAction(battle, action),
        throwsA(isA<IllegalActionException>()),
      );
    });

    test('throws IllegalActionException when the battle is inactive', () {
      final context = _newContext();
      final system = CombatSystem(context);
      final a = context.entities.create();
      final b = context.entities.create();
      final battle = context.entities.create();
      context.components.add(
        battle,
        const CombatStateComponent(
          participants: [],
          currentTurnIndex: 0,
          round: 1,
          active: false,
        ),
      );
      final action =
          AttackAction(actor: a, targets: [b], baseDamage: 10, damageStat: 'attack');

      expect(
        () => system.executeAction(battle, action),
        throwsA(isA<IllegalActionException>()),
      );
    });
  });

  group('CombatSystem.executeAction — successful action', () {
    test(
        'applies cost + damage, publishes events in order, and advances '
        'the turn', () {
      final context = _newContext();
      final system = CombatSystem(context);
      final a = context.entities.create();
      final b = context.entities.create();
      context.components
          .add(a, const CombatantComponent(team: 'alpha', initiative: 10));
      context.components
          .add(b, const CombatantComponent(team: 'beta', initiative: 5));
      context.components.add(a, const HealthComponent(current: 100, max: 100));
      context.components.add(b, const HealthComponent(current: 100, max: 100));
      context.components.add(a, ResourceComponent({'stamina': 20}));
      final battle = system.startBattle([a, b]);
      final log = <String>[];
      context.events.subscribe<ActionStarted>((_) => log.add('ActionStarted'));
      context.events.subscribe<EntityDamaged>((_) => log.add('EntityDamaged'));
      context.events
          .subscribe<ActionCompleted>((_) => log.add('ActionCompleted'));
      context.events.subscribe<TurnEnded>((_) => log.add('TurnEnded'));
      context.events.subscribe<TurnStarted>((_) => log.add('TurnStarted'));

      system.executeAction(
        battle,
        AttackAction(
          actor: a,
          targets: [b],
          baseDamage: 10,
          damageStat: 'attack',
          costEffects: const [ModifyResource('stamina', -5)],
        ),
      );

      expect(
        log,
        equals([
          'ActionStarted',
          'EntityDamaged',
          'ActionCompleted',
          'TurnEnded',
          'TurnStarted',
        ]),
      );
      expect(context.components.get<HealthComponent>(b)!.current, equals(90));
      expect(
        context.components.get<ResourceComponent>(a)!.resources['stamina'],
        equals(15),
      );
      final state = context.components.get<CombatStateComponent>(battle)!;
      expect(state.currentTurnIndex, equals(1));
      expect(state.participants[state.currentTurnIndex], equals(b));
    });

    test(
        'failed conditions skip cost and target effects but still '
        'advance the turn', () {
      final context = _newContext();
      final system = CombatSystem(context);
      final a = context.entities.create();
      final b = context.entities.create();
      context.components
          .add(a, const CombatantComponent(team: 'alpha', initiative: 10));
      context.components
          .add(b, const CombatantComponent(team: 'beta', initiative: 5));
      context.components.add(a, const HealthComponent(current: 100, max: 100));
      context.components.add(b, const HealthComponent(current: 100, max: 100));
      context.components.add(a, ResourceComponent({'stamina': 2}));
      final battle = system.startBattle([a, b]);
      final damaged = <EntityDamaged>[];
      context.events.subscribe<EntityDamaged>(damaged.add);

      system.executeAction(
        battle,
        AttackAction(
          actor: a,
          targets: [b],
          baseDamage: 10,
          damageStat: 'attack',
          conditions: const [ResourceAbove('stamina', 5)],
          costEffects: const [ModifyResource('stamina', -5)],
        ),
      );

      expect(damaged, isEmpty);
      expect(
        context.components.get<ResourceComponent>(a)!.resources['stamina'],
        equals(2),
      );
      final state = context.components.get<CombatStateComponent>(battle)!;
      expect(state.currentTurnIndex, equals(1));
    });

    test(
        'a RandomChance(0.0) condition always fails, demonstrating an '
        'RNG-gated action', () {
      final context = _newContext();
      final system = CombatSystem(context);
      final a = context.entities.create();
      final b = context.entities.create();
      context.components
          .add(a, const CombatantComponent(team: 'alpha', initiative: 10));
      context.components
          .add(b, const CombatantComponent(team: 'beta', initiative: 5));
      context.components.add(a, const HealthComponent(current: 100, max: 100));
      context.components.add(b, const HealthComponent(current: 100, max: 100));
      final battle = system.startBattle([a, b]);
      final damaged = <EntityDamaged>[];
      context.events.subscribe<EntityDamaged>(damaged.add);

      system.executeAction(
        battle,
        AttackAction(
          actor: a,
          targets: [b],
          baseDamage: 10,
          damageStat: 'attack',
          conditions: const [RandomChance(0.0)],
        ),
      );

      expect(damaged, isEmpty);
    });

    test('advancing the turn skips participants with 0 health', () {
      final context = _newContext();
      final system = CombatSystem(context);
      final a = context.entities.create();
      final b = context.entities.create();
      final c = context.entities.create();
      context.components
          .add(a, const CombatantComponent(team: 'alpha', initiative: 30));
      context.components
          .add(b, const CombatantComponent(team: 'alpha', initiative: 20));
      context.components
          .add(c, const CombatantComponent(team: 'beta', initiative: 10));
      context.components.add(a, const HealthComponent(current: 100, max: 100));
      context.components.add(b, const HealthComponent(current: 0, max: 100));
      context.components.add(c, const HealthComponent(current: 100, max: 100));
      final battle = system.startBattle([a, b, c]);

      system.executeAction(
        battle,
        AttackAction(actor: a, targets: [c], baseDamage: 5, damageStat: 'attack'),
      );

      final state = context.components.get<CombatStateComponent>(battle)!;
      expect(state.participants[state.currentTurnIndex], equals(c));
    });
  });

  group('CombatSystem — defeat and battle end', () {
    test(
        'reducing the last opposing team member to 0 health ends the '
        'battle: BattleWon/BattleLost fire, the battle goes inactive, and '
        'no further TurnStarted is published', () {
      final context = _newContext();
      final system = CombatSystem(context);
      final a = context.entities.create();
      final b = context.entities.create();
      context.components
          .add(a, const CombatantComponent(team: 'alpha', initiative: 10));
      context.components
          .add(b, const CombatantComponent(team: 'beta', initiative: 5));
      context.components.add(a, const HealthComponent(current: 100, max: 100));
      context.components.add(b, const HealthComponent(current: 10, max: 100));
      final battle = system.startBattle([a, b]);
      final won = <BattleWon>[];
      final lost = <BattleLost>[];
      final turnsEnded = <TurnEnded>[];
      final turnsStarted = <TurnStarted>[];
      context.events.subscribe<BattleWon>(won.add);
      context.events.subscribe<BattleLost>(lost.add);
      context.events.subscribe<TurnEnded>(turnsEnded.add);
      context.events.subscribe<TurnStarted>(turnsStarted.add);

      system.executeAction(
        battle,
        AttackAction(actor: a, targets: [b], baseDamage: 10, damageStat: 'attack'),
      );

      expect(won, hasLength(1));
      expect(won.single.team, equals('alpha'));
      expect(lost, hasLength(1));
      expect(lost.single.team, equals('beta'));
      expect(context.components.get<CombatStateComponent>(battle)!.active, isFalse);
      expect(turnsEnded, hasLength(1));
      expect(turnsEnded.single.actor, equals(a));
      expect(turnsStarted, hasLength(1)); // only startBattle's initial one
    });

    test('executeAction throws once the battle has ended', () {
      final context = _newContext();
      final system = CombatSystem(context);
      final a = context.entities.create();
      final b = context.entities.create();
      context.components
          .add(a, const CombatantComponent(team: 'alpha', initiative: 10));
      context.components
          .add(b, const CombatantComponent(team: 'beta', initiative: 5));
      context.components.add(a, const HealthComponent(current: 100, max: 100));
      context.components.add(b, const HealthComponent(current: 10, max: 100));
      final battle = system.startBattle([a, b]);
      system.executeAction(
        battle,
        AttackAction(actor: a, targets: [b], baseDamage: 10, damageStat: 'attack'),
      );

      expect(
        () => system.executeAction(
          battle,
          AttackAction(actor: a, targets: [b], baseDamage: 1, damageStat: 'attack'),
        ),
        throwsA(isA<IllegalActionException>()),
      );
    });

    test(
        'mutual annihilation (no living teams remain) publishes '
        'BattleLost for every team and no BattleWon', () {
      final context = _newContext();
      final system = CombatSystem(context);
      final a = context.entities.create();
      final b = context.entities.create();
      context.components
          .add(a, const CombatantComponent(team: 'alpha', initiative: 10));
      context.components
          .add(b, const CombatantComponent(team: 'beta', initiative: 5));
      context.components.add(a, const HealthComponent(current: 10, max: 100));
      context.components.add(b, const HealthComponent(current: 10, max: 100));
      final battle = system.startBattle([a, b]);
      final won = <BattleWon>[];
      final lost = <BattleLost>[];
      context.events.subscribe<BattleWon>(won.add);
      context.events.subscribe<BattleLost>(lost.add);

      system.executeAction(
        battle,
        AttackAction(actor: a, targets: [a, b], baseDamage: 10, damageStat: 'attack'),
      );

      expect(won, isEmpty);
      expect(lost.map((e) => e.team).toSet(), equals({'alpha', 'beta'}));
    });

    test(
        'a kill from outside executeAction (e.g. a different rule/plugin) '
        'still ends the battle', () {
      final context = _newContext();
      final system = CombatSystem(context);
      final a = context.entities.create();
      final b = context.entities.create();
      context.components
          .add(a, const CombatantComponent(team: 'alpha', initiative: 10));
      context.components
          .add(b, const CombatantComponent(team: 'beta', initiative: 5));
      context.components.add(a, const HealthComponent(current: 100, max: 100));
      context.components.add(b, const HealthComponent(current: 0, max: 100));
      final battle = system.startBattle([a, b]);
      final won = <BattleWon>[];
      context.events.subscribe<BattleWon>(won.add);

      context.events.publish(EntityKilled(b));

      expect(won, hasLength(1));
      expect(won.single.team, equals('alpha'));
      expect(context.components.get<CombatStateComponent>(battle)!.active, isFalse);
    });
  });
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `dart test test/plugins/combat/combat_system_test.dart`
Expected: FAIL — `Error: Undefined class 'CombatSystem'` (and `BattleStarted`, `IllegalActionException`, etc.).

- [ ] **Step 3: Implement the events, exception, and `CombatSystem`**

Create `lib/src/plugins/combat/combat_events.dart`:
```dart
import 'package:build_engine/build_engine.dart';

import 'combat_action.dart';

/// Published by `CombatSystem.executeAction` before evaluating [action]'s
/// conditions — always, whether or not they end up passing.
class ActionStarted {
  const ActionStarted(this.battle, this.actor, this.targets, this.action);
  final EntityId battle;
  final EntityId actor;
  final List<EntityId> targets;
  final CombatAction action;
}

/// Published by `CombatSystem.executeAction` after [action]'s effects (if
/// any applied) have run. Its presence with no `EntityDamaged`/etc. in
/// between marks an action whose conditions failed.
class ActionCompleted {
  const ActionCompleted(this.battle, this.actor, this.targets, this.action);
  final EntityId battle;
  final EntityId actor;
  final List<EntityId> targets;
  final CombatAction action;
}

/// Published by `CombatSystem` when [actor]'s turn in [battle] begins.
class TurnStarted {
  const TurnStarted(this.battle, this.actor, this.round);
  final EntityId battle;
  final EntityId actor;
  final int round;
}

/// Published by `CombatSystem` when [actor]'s turn in [battle] ends —
/// always, even if that same action also ended the battle.
class TurnEnded {
  const TurnEnded(this.battle, this.actor, this.round);
  final EntityId battle;
  final EntityId actor;
  final int round;
}

/// Published by `CombatSystem.startBattle`.
class BattleStarted {
  const BattleStarted(this.battle, this.participants);
  final EntityId battle;
  final List<EntityId> participants;
}

/// Published once per surviving team when [battle] ends with exactly one
/// team still standing.
class BattleWon {
  const BattleWon(this.battle, this.team);
  final EntityId battle;
  final String team;
}

/// Published once per eliminated team when [battle] ends — every starting
/// team, if the battle ends in mutual annihilation.
class BattleLost {
  const BattleLost(this.battle, this.team);
  final EntityId battle;
  final String team;
}
```

Create `lib/src/plugins/combat/illegal_action_exception.dart`:
```dart
/// Thrown by `CombatSystem.executeAction` when it's called on a battle
/// that isn't active, or with an action whose actor isn't the entity
/// whose turn it currently is — a programmer-error/caller-misuse case,
/// mirroring `Container`'s `InvalidPlacementException` convention:
/// illegal *use* throws; a legal-but-unsuccessful outcome (failed
/// conditions) does not.
class IllegalActionException implements Exception {
  const IllegalActionException(this.message);

  final String message;

  @override
  String toString() => 'IllegalActionException: $message';
}
```

Create `lib/src/plugins/combat/combat_system.dart`:
```dart
import 'package:build_engine/build_engine.dart';

import 'combat_action.dart';
import 'combat_events.dart';
import 'combat_state_component.dart';
import 'combatant_component.dart';
import 'illegal_action_exception.dart';

/// Combat's turn/battle orchestration: starts battles, executes actions
/// (validating turn order, evaluating conditions, applying costs/effects
/// through the existing Effect Engine), advances turns, and ends battles
/// on team elimination. No martial-arts/magic/cultivation/weapon
/// vocabulary anywhere in this class.
///
/// Every entity passed to [startBattle] must carry a [CombatantComponent]
/// — required for both initiative ordering and win/loss grouping.
class CombatSystem {
  CombatSystem(this._context) {
    _context.events.subscribe<EntityKilled>(_onEntityKilled);
  }

  final PluginContext _context;

  /// While an `executeAction` call is applying an action's effects, the
  /// per-kill battle-end check below is suppressed — `executeAction` runs
  /// one authoritative check itself, after all of the action's effects
  /// have landed. This matters because a single action can kill
  /// multiple different-team entities in one call; checking after each
  /// individual `EntityKilled` would let the first death's check run
  /// before the second has happened, misjudging a mutual kill as a
  /// normal win. A kill from outside `executeAction` (this flag `false`)
  /// isn't part of any such batch, so it's always checked immediately.
  bool _executingAction = false;

  /// Creates a battle entity, orders [participants] by descending
  /// `CombatantComponent.initiative` (ties broken by their position in
  /// [participants]), stores its `CombatStateComponent`, and publishes
  /// `BattleStarted` then the first `TurnStarted`.
  EntityId startBattle(List<EntityId> participants) {
    final battle = _context.entities.create();
    final ordered = _byInitiative(participants);
    _context.components.add(
      battle,
      CombatStateComponent(
        participants: ordered,
        currentTurnIndex: 0,
        round: 1,
        active: true,
      ),
    );
    _context.events.publish(BattleStarted(battle, ordered));
    if (ordered.isNotEmpty) {
      _context.events.publish(TurnStarted(battle, ordered.first, 1));
    }
    return battle;
  }

  /// Runs [action] against [battle]. Throws [IllegalActionException] if
  /// [battle] isn't active or it isn't `action.actor`'s turn. If
  /// `action.conditions` don't all pass, no cost/target effects apply,
  /// but `ActionStarted`/`ActionCompleted` still publish and the turn
  /// still advances.
  void executeAction(EntityId battle, CombatAction action) {
    final initialState = _context.components.get<CombatStateComponent>(battle);
    if (initialState == null || !initialState.active) {
      throw const IllegalActionException('battle is not active');
    }
    if (initialState.participants.isEmpty ||
        initialState.participants[initialState.currentTurnIndex] !=
            action.actor) {
      throw const IllegalActionException("it is not this actor's turn");
    }

    _context.events.publish(
      ActionStarted(battle, action.actor, action.targets, action),
    );

    final actorContext = _ruleContextFor(action.actor, action);
    final conditionsPass = action.conditions
        .every((condition) => condition.evaluate(actorContext));

    _executingAction = true;
    try {
      if (conditionsPass) {
        for (final effect in action.costEffects) {
          effect.apply(actorContext);
        }
        for (final target in action.targets) {
          final targetContext = _ruleContextFor(target, action);
          for (final effect in action.effectsFor(target, _context)) {
            effect.apply(targetContext);
          }
        }
      }
    } finally {
      _executingAction = false;
    }

    _checkBattleEndFor(battle);

    _context.events.publish(
      ActionCompleted(battle, action.actor, action.targets, action),
    );

    _advanceTurn(battle);
  }

  RuleContext _ruleContextFor(EntityId subject, Object triggerEvent) =>
      RuleContext(
        subject: subject,
        triggerEvent: triggerEvent,
        entities: _context.entities,
        components: _context.components,
        events: _context.events,
        rng: _context.rng,
        eventCounts: _context.rules.eventCounts,
      );

  void _advanceTurn(EntityId battle) {
    final state = _context.components.get<CombatStateComponent>(battle);
    if (state == null) return;
    _context.events.publish(
      TurnEnded(
        battle,
        state.participants[state.currentTurnIndex],
        state.round,
      ),
    );
    if (!state.active) return;

    final living = _livingParticipants(state.participants).toSet();
    if (living.isEmpty) return;

    var nextIndex = state.currentTurnIndex;
    var round = state.round;
    EntityId next;
    do {
      nextIndex = (nextIndex + 1) % state.participants.length;
      if (nextIndex == 0) round += 1;
      next = state.participants[nextIndex];
    } while (!living.contains(next));

    _context.components.add(
      battle,
      CombatStateComponent(
        participants: state.participants,
        currentTurnIndex: nextIndex,
        round: round,
        active: true,
      ),
    );
    _context.events.publish(TurnStarted(battle, next, round));
  }

  void _onEntityKilled(EntityKilled event) {
    if (_executingAction) return;
    for (final battle
        in _context.components.entitiesWith<CombatStateComponent>()) {
      final state = _context.components.get<CombatStateComponent>(battle)!;
      if (state.active && state.participants.contains(event.id)) {
        _checkBattleEnd(battle, state);
      }
    }
  }

  void _checkBattleEndFor(EntityId battle) {
    final state = _context.components.get<CombatStateComponent>(battle);
    if (state != null && state.active) {
      _checkBattleEnd(battle, state);
    }
  }

  void _checkBattleEnd(EntityId battle, CombatStateComponent state) {
    final living = _livingParticipants(state.participants);
    final livingTeams = <String>{
      for (final id in living)
        _context.components.get<CombatantComponent>(id)!.team,
    };
    if (livingTeams.length > 1) return;

    final allTeams = <String>{
      for (final id in state.participants)
        _context.components.get<CombatantComponent>(id)!.team,
    };

    _context.components.add(
      battle,
      CombatStateComponent(
        participants: state.participants,
        currentTurnIndex: state.currentTurnIndex,
        round: state.round,
        active: false,
      ),
    );

    for (final team in allTeams) {
      if (livingTeams.contains(team)) {
        _context.events.publish(BattleWon(battle, team));
      } else {
        _context.events.publish(BattleLost(battle, team));
      }
    }
  }

  Iterable<EntityId> _livingParticipants(List<EntityId> participants) =>
      _context.queries.evaluate(participants, HealthBelowQuery(1).not());

  List<EntityId> _byInitiative(List<EntityId> participants) {
    final indexed = participants.asMap().entries.toList();
    indexed.sort((a, b) {
      final initiativeA =
          _context.components.get<CombatantComponent>(a.value)!.initiative;
      final initiativeB =
          _context.components.get<CombatantComponent>(b.value)!.initiative;
      final byInitiative = initiativeB.compareTo(initiativeA);
      if (byInitiative != 0) return byInitiative;
      return a.key.compareTo(b.key);
    });
    return [for (final entry in indexed) entry.value];
  }
}
```

Modify `lib/combat_plugin.dart` — `combat_events.dart` sorts before `combat_state_component.dart` (`e` < `s`), and `illegal_action_exception.dart` sorts last (`i` > `c`):
```dart
/// Combat — a plugin built on Build Engine core. Turn-based combat
/// (combatants, actions, targets, damage, healing, defeat) with zero
/// martial-arts/magic/cultivation/weapon vocabulary — see `claude.md`'s
/// CORE PROVIDES VERBS / PLUGINS PROVIDE NOUNS contract. Depends only on
/// `package:build_engine/build_engine.dart`'s public core API.
library;

export 'src/plugins/combat/combat_action.dart';
export 'src/plugins/combat/combat_events.dart';
export 'src/plugins/combat/combat_state_component.dart';
export 'src/plugins/combat/combat_system.dart';
export 'src/plugins/combat/combatant_component.dart';
export 'src/plugins/combat/illegal_action_exception.dart';
```

- [ ] **Step 4: Run the tests to verify they pass, and analyze**

Run:
```bash
dart test test/plugins/combat/combat_system_test.dart
dart analyze
```
Expected: all 12 tests PASS; `dart analyze` reports `No issues found!`.

- [ ] **Step 5: Commit**

```bash
git add lib/src/plugins/combat/combat_events.dart lib/src/plugins/combat/illegal_action_exception.dart lib/src/plugins/combat/combat_system.dart lib/combat_plugin.dart test/plugins/combat/combat_system_test.dart
git commit -m "feat: add Combat events, IllegalActionException, and CombatSystem"
```

---

### Task 6: `CombatPlugin`

**Files:**
- Create: `lib/src/plugins/combat/combat_plugin.dart`
- Modify: `lib/combat_plugin.dart`
- Test: `test/plugins/combat/combat_plugin_test.dart`

**Interfaces:**
- Consumes: `GamePlugin`, `PluginContext`, `PluginManager` (core); `CombatSystem` (Task 5).
- Produces: `class CombatPlugin extends GamePlugin { String get id; String get version; late final CombatSystem system; void initialize(PluginContext context); }`. Task 7's integration test consumes `CombatPlugin` directly.

- [ ] **Step 1: Write the failing test**

Create `test/plugins/combat/combat_plugin_test.dart`:
```dart
import 'package:build_engine/build_engine.dart';
import 'package:build_engine/combat_plugin.dart';
import 'package:test/test.dart';

PluginContext _newContext() {
  final events = EventBus();
  final entities = EntityRegistry(events);
  final components = ComponentStore();
  final rng = RngService(1);
  return PluginContext(
    entities: entities,
    components: components,
    events: events,
    rng: rng,
    rules: RuleEngine(
      entities: entities,
      components: components,
      events: events,
      rng: rng,
    ),
    queries: QueryEngine(QueryScope(components: components)),
    modifiers: ModifierCollection(),
  );
}

void main() {
  group('CombatPlugin', () {
    test('has id "combat", a version, and no dependencies', () {
      final plugin = CombatPlugin();
      expect(plugin.id, equals('combat'));
      expect(plugin.version, isNotEmpty);
      expect(plugin.dependencies, isEmpty);
    });

    test('initialize constructs a usable CombatSystem', () {
      final plugin = CombatPlugin();
      final context = _newContext();

      plugin.initialize(context);

      final a = context.entities.create();
      final b = context.entities.create();
      context.components.add(a, const CombatantComponent(team: 'alpha'));
      context.components.add(b, const CombatantComponent(team: 'beta'));

      final battle = plugin.system.startBattle([a, b]);

      expect(context.components.has<CombatStateComponent>(battle), isTrue);
    });

    test(
        'registers, initializes, starts, stops, and unregisters through '
        'PluginManager with no other plugin present', () {
      final context = _newContext();
      final manager = PluginManager();
      final plugin = CombatPlugin();
      manager.register(plugin);

      manager.initialize(context);
      manager.start(context);

      final a = context.entities.create();
      final b = context.entities.create();
      context.components.add(a, const CombatantComponent(team: 'alpha'));
      context.components.add(b, const CombatantComponent(team: 'beta'));
      context.components.add(a, const HealthComponent(current: 100, max: 100));
      context.components.add(b, const HealthComponent(current: 100, max: 100));
      final battle = plugin.system.startBattle([a, b]);
      plugin.system.executeAction(
        battle,
        AttackAction(actor: a, targets: [b], baseDamage: 10, damageStat: 'attack'),
      );

      expect(context.components.get<HealthComponent>(b)!.current, equals(90));
      expect(() => manager.stop(context), returnsNormally);
      expect(() => manager.unregister(context), returnsNormally);
    });
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `dart test test/plugins/combat/combat_plugin_test.dart`
Expected: FAIL — `Error: Undefined class 'CombatPlugin'`.

- [ ] **Step 3: Implement `CombatPlugin`**

Create `lib/src/plugins/combat/combat_plugin.dart`:
```dart
import 'package:build_engine/build_engine.dart';

import 'combat_system.dart';

/// Turn-based combat as an ordinary plugin: combatants, actions, targets,
/// damage, healing, and defeat, expressed entirely through core's generic
/// services (entities, components, events, conditions, effects, queries,
/// modifiers, RNG). No martial-arts/magic/cultivation/weapon vocabulary —
/// those are separate future plugins that depend on this one, never the
/// reverse (`claude.md`'s DEPENDENCY RULE).
class CombatPlugin extends GamePlugin {
  @override
  String get id => 'combat';

  @override
  String get version => '0.1.0';

  /// Constructed in [initialize]; the only way calling code reaches
  /// Combat's behavior — there's no service-locator in core, so whoever
  /// holds this [CombatPlugin] instance holds `system` too.
  late final CombatSystem system;

  @override
  void initialize(PluginContext context) {
    system = CombatSystem(context);
  }
}
```

Modify `lib/combat_plugin.dart` — `combat_plugin.dart` sorts after `combat_events.dart` and before `combat_state_component.dart` (`p` between `e` and `s`):
```dart
/// Combat — a plugin built on Build Engine core. Turn-based combat
/// (combatants, actions, targets, damage, healing, defeat) with zero
/// martial-arts/magic/cultivation/weapon vocabulary — see `claude.md`'s
/// CORE PROVIDES VERBS / PLUGINS PROVIDE NOUNS contract. Depends only on
/// `package:build_engine/build_engine.dart`'s public core API.
library;

export 'src/plugins/combat/combat_action.dart';
export 'src/plugins/combat/combat_events.dart';
export 'src/plugins/combat/combat_plugin.dart';
export 'src/plugins/combat/combat_state_component.dart';
export 'src/plugins/combat/combat_system.dart';
export 'src/plugins/combat/combatant_component.dart';
export 'src/plugins/combat/illegal_action_exception.dart';
```

- [ ] **Step 4: Run the test to verify it passes, and analyze**

Run:
```bash
dart test test/plugins/combat/combat_plugin_test.dart
dart analyze
```
Expected: all 3 tests PASS; `dart analyze` reports `No issues found!`.

- [ ] **Step 5: Commit**

```bash
git add lib/src/plugins/combat/combat_plugin.dart lib/combat_plugin.dart test/plugins/combat/combat_plugin_test.dart
git commit -m "feat: add CombatPlugin"
```

---

### Task 7: Integration test — Combat end to end, generic components only

**Files:**
- Create: `test/integration/combat_plugin_end_to_end_test.dart`

**Interfaces:**
- Consumes: `CombatPlugin`, `CombatSystem`, `CombatantComponent`, `CombatStateComponent`, `AttackAction`, `CombatAction`, all Combat events, `IllegalActionException` (Tasks 1–6); `HealthComponent`, `Heal`, and the full core stack (existing).
- Produces: nothing new — verification-only, proving the full stack composes correctly with real (non-fake) services and exclusively generic vocabulary (no Sword/Punch/Fireball, no player/enemy — only `team: 'alpha'`/`'beta'`).

- [ ] **Step 1: Write the integration test**

Create `test/integration/combat_plugin_end_to_end_test.dart`:
```dart
import 'package:build_engine/build_engine.dart';
import 'package:build_engine/combat_plugin.dart';
import 'package:test/test.dart';

/// A minimal custom CombatAction — proves Combat's execution pipeline
/// handles healing without a dedicated "HealAction" class, and that a
/// future content plugin can add its own actions the same way.
class _DrinkAction extends CombatAction {
  const _DrinkAction({required this.actor, required this.amount});

  @override
  final EntityId actor;
  final num amount;

  @override
  List<EntityId> get targets => [actor];

  // conditions/costEffects are not overridden — CombatAction's own
  // `const []` defaults apply, since this class `extends CombatAction`.

  @override
  List<Effect> effectsFor(EntityId target, PluginContext context) =>
      [Heal(amount)];
}

PluginContext _newContext() {
  final events = EventBus();
  final entities = EntityRegistry(events);
  final components = ComponentStore();
  final rng = RngService(7);
  return PluginContext(
    entities: entities,
    components: components,
    events: events,
    rng: rng,
    rules: RuleEngine(
      entities: entities,
      components: components,
      events: events,
      rng: rng,
    ),
    queries: QueryEngine(QueryScope(components: components)),
    modifiers: ModifierCollection(),
  );
}

void main() {
  test(
      'AttackAction and a custom healing CombatAction both run through '
      'CombatSystem, using only generic components', () {
    final context = _newContext();
    final plugin = CombatPlugin();
    plugin.initialize(context);
    final system = plugin.system;

    final alpha = context.entities.create();
    final beta = context.entities.create();
    context.components
        .add(alpha, const CombatantComponent(team: 'alpha', initiative: 10));
    context.components
        .add(beta, const CombatantComponent(team: 'beta', initiative: 5));
    context.components.add(alpha, const HealthComponent(current: 30, max: 30));
    context.components.add(beta, const HealthComponent(current: 30, max: 30));

    final turnsStarted = <TurnStarted>[];
    context.events.subscribe<TurnStarted>(turnsStarted.add);

    final battle = system.startBattle([alpha, beta]);
    expect(turnsStarted.single.actor, equals(alpha));

    system.executeAction(
      battle,
      AttackAction(
        actor: alpha,
        targets: [beta],
        baseDamage: 12,
        damageStat: 'attack',
      ),
    );
    expect(context.components.get<HealthComponent>(beta)!.current, equals(18));

    system.executeAction(battle, _DrinkAction(actor: beta, amount: 5));
    expect(context.components.get<HealthComponent>(beta)!.current, equals(23));

    expect(
      turnsStarted.map((e) => e.actor).toList(),
      equals([alpha, beta, alpha]),
    );
  });

  test(
      'reducing a combatant to 0 health ends the battle with a decisive '
      'win/loss, using only generic components', () {
    final context = _newContext();
    final plugin = CombatPlugin();
    plugin.initialize(context);
    final system = plugin.system;

    final alpha = context.entities.create();
    final beta = context.entities.create();
    context.components
        .add(alpha, const CombatantComponent(team: 'alpha', initiative: 10));
    context.components
        .add(beta, const CombatantComponent(team: 'beta', initiative: 5));
    context.components.add(alpha, const HealthComponent(current: 30, max: 30));
    context.components.add(beta, const HealthComponent(current: 12, max: 30));

    final won = <BattleWon>[];
    final lost = <BattleLost>[];
    context.events.subscribe<BattleWon>(won.add);
    context.events.subscribe<BattleLost>(lost.add);

    final battle = system.startBattle([alpha, beta]);
    system.executeAction(
      battle,
      AttackAction(
        actor: alpha,
        targets: [beta],
        baseDamage: 12,
        damageStat: 'attack',
      ),
    );

    expect(context.components.get<HealthComponent>(beta)!.current, equals(0));
    expect(won.single.team, equals('alpha'));
    expect(lost.single.team, equals('beta'));
    expect(context.components.get<CombatStateComponent>(battle)!.active, isFalse);
    expect(
      () => system.executeAction(
        battle,
        AttackAction(
          actor: alpha,
          targets: [beta],
          baseDamage: 1,
          damageStat: 'attack',
        ),
      ),
      throwsA(isA<IllegalActionException>()),
    );
  });
}
```

- [ ] **Step 2: Run it and confirm it passes on the first try**

Run: `dart test test/integration/combat_plugin_end_to_end_test.dart`
Expected: both tests PASS. (No implementation step needed — every service under test was already implemented in Tasks 1–6. If it fails, that's a bug in an earlier task; stop and fix the earlier task's implementation, don't patch around it here.)

- [ ] **Step 3: Run the whole suite and analyze**

Run:
```bash
dart test
dart analyze
```
Expected: every test across the whole package PASSes; `dart analyze` reports `No issues found!`.

- [ ] **Step 4: Commit**

```bash
git add test/integration/combat_plugin_end_to_end_test.dart
git commit -m "test: add Combat plugin end-to-end integration coverage"
```

---

### Task 8: Documentation

**Files:**
- Modify: `ARCHITECTURE.md`

**Interfaces:**
- Consumes: the finished implementation from Tasks 1–7 (this task only documents it).
- Produces: nothing new in `lib/` — this is the plan's final task.

- [ ] **Step 1: Amend `ARCHITECTURE.md`**

Read the current `ARCHITECTURE.md` first to confirm its exact present content — leave every existing section untouched except the two edits below.

1. In the `PluginContext` description (inside "### Plugin system (`lib/src/plugin/`)"), update the sentence that currently says `PluginContext` exposes `entities`/`components`/`events` only, to also mention it now exposes `rng`/`rules`/`queries`/`modifiers`.

2. Add a new top-level section after "## What's deliberately not here yet", documenting the Combat plugin:

```markdown
## Combat — the first plugin (`lib/src/plugins/combat/`, `lib/combat_plugin.dart`)

Combat is the first real `GamePlugin` built on this engine — proof that
the core/plugin boundary CLAUDE.md describes actually holds. It lives in
the same package (no workspace/multi-package tooling exists yet) but
imports core exclusively through `package:build_engine/build_engine.dart`,
never `lib/src/...` directly, and is exported through its own barrel,
`lib/combat_plugin.dart`.

`CombatantComponent` (`team`, `initiative`) and `CombatStateComponent`
(`participants`, `currentTurnIndex`, `round`, `active` — attached to a
dedicated battle entity, not to a participant) are the only new component
types. `CombatAction` is abstract, mirroring `Condition`/`Effect`'s
"implement directly, no registry" pattern; `AttackAction` is the one
concrete implementation, resolving its damage through the Modifier Engine
(`ModifierResolver().resolve(baseDamage, ...)`) before delegating to the
existing core `Damage` effect. "Healing" needed no dedicated action class
— any `CombatAction` whose `effectsFor` returns a `Heal` runs through the
identical pipeline.

`CombatSystem.executeAction` validates turn order (throwing
`IllegalActionException` on caller misuse), evaluates an action's
`Condition`s via a manually-built `RuleContext` (the same public type
`RuleEngine` itself uses — no new machinery), and applies its
`Effect`s the same way. Team-elimination (defeat/win/loss) is checked via
`QueryEngine` once per `executeAction` call — not once per individual
`EntityKilled` — because a single action can kill members of multiple
teams at once; checking per-kill would let an early check run before a
simultaneous second kill has landed, misjudging a mutual kill as a normal
win. A kill from outside `executeAction` (e.g. a future plugin's
independent rule) is still checked immediately, since by construction it
isn't part of any such batch.

This pass also grew `PluginContext` to expose `rng`/`rules`/`queries`/
`modifiers` (previously entities/components/events only) — the four core
services that existed but weren't yet reachable from a plugin's lifecycle
methods. `RuleContext`/`RuleEngine` were deliberately left unchanged; an
earlier version of this design routed `AttackAction`'s modifier
resolution through a `RuleContext`-carried `ModifierCollection`, which
would have cascaded into extending `RuleEngine`'s constructor too — the
final design resolves modifiers directly against `PluginContext` instead,
inside `CombatAction.effectsFor`, avoiding that cascade entirely.
```

- [ ] **Step 2: Final full verification**

Run:
```bash
dart pub get
dart test
dart analyze
```
Expected: `dart pub get` succeeds; every test in the package PASSes; `dart analyze` reports `No issues found!`.

- [ ] **Step 3: Commit**

```bash
git add ARCHITECTURE.md
git commit -m "docs: describe the Combat plugin in ARCHITECTURE.md"
```

---

## Self-Review Notes

- **Spec coverage:** every concept the spec (and the original CLAUDE.md request) asks for maps to a task above — `CombatantComponent`/`CombatStateComponent` (Tasks 2–3), Action/Target model (Task 4), Turn/Combat state/Action execution (Task 5's `CombatSystem`), Damage/Healing (Task 4's `AttackAction` + Task 7's `_DrinkAction` demo), Defeat (Task 5's battle-end logic), the generic `AttackAction` demonstration with no Sword/Punch/Fireball (Tasks 4 and 7), and integration tests proving Combat works with generic components only (Task 7). CLAUDE.md's per-plugin testing checklist is covered across tasks: registration/initialization/dependency tests (Task 6), behavior tests (Tasks 2–7), serialization tests where applicable (Tasks 2–3's `toJson`/`fromJson` round-trips).
- **Placeholder scan:** no "TBD"/"TODO" — every step carries complete, runnable code.
- **Type consistency checked:** `CombatAction`'s interface (`actor`, `targets`, `conditions`, `costEffects`, `effectsFor(EntityId, PluginContext)`) is defined once in Task 4 and consumed identically by `AttackAction` (Task 4), `CombatSystem` (Task 5), and both the plugin lifecycle test (Task 6) and integration test's `_DrinkAction` (Task 7). `PluginContext`'s seven fields (Task 1) are constructed identically (same `_newContext()` shape) in every subsequent test file. `CombatStateComponent`'s field names (`participants`, `currentTurnIndex`, `round`, `active`) are used identically in Tasks 3, 5, 6, and 7.
- **The RuleContext/RuleEngine cascade was caught and designed around, not left in:** the spec's first draft had `AttackAction` reading modifiers off `RuleContext`, which doesn't carry a `ModifierCollection` and would have forced extending `RuleEngine`'s constructor too. The spec (and this plan) were corrected before implementation to resolve modifiers directly against `PluginContext.modifiers` inside `CombatAction.effectsFor` instead — zero changes to `RuleContext`/`RuleEngine`.
- **The per-kill battle-end race was caught and designed around:** an initial mutual-annihilation scenario (a single action lethally hitting two different-team entities) would have let the first entity's death declare a winner before the second death landed. Task 5's `_executingAction` suppression flag defers the check to run exactly once, after `executeAction` finishes applying an action's effects — covered explicitly by the mutual-annihilation test in Task 5 and exercised again in Task 7's integration coverage.
- **Barrel-file ordering:** six new files under `lib/src/plugins/combat/`, added incrementally across Tasks 2–6 — each task's Step 3 shows the barrel's exact resulting content, so there's nothing to compute at execution time.
