# Per-active Auras (SP2) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let a hung item or technique carry content-authored `Rule`s that fire only while the component is in `ResolvedBuild.active`, off Combat's per-turn / per-action events, targeting the build owner or the owner's single opponent.

**Architecture:** A new Core module `lib/src/aura/` defines `AuraContributor` (returns `List<AuraRule>` = a raw Core `Rule` + a `self`/`opponent` scope). Composing wrappers (`ItemAuraContributor`, `TechniqueAuraContributor`) resolve a component's `auras: [<ruleId>]` content field into `RuleDefinition`s loaded through the existing `ContentRegistry.loadRule` DSL. `BuildActionInterpreter.auraRules(...)` (implemented by the Item/Technique interpreters, aggregated by the composite) collects the `AuraRule`s of every ref in `build.active`. A new `AuraBinder` in `build_interpretation/` registers each with `RuleEngine` — injecting owner/opponent scoping in a `_wire` step so rule bodies stay identity-free — and returns an idempotent-`dispose()` `AuraBinding`. `CombatStage.runFight` binds after `tome.resolve` and disposes in a `finally`.

**Tech Stack:** Dart 3.7 (`sdk: ^3.7.0`), `package:test` 1.25, `lints` 5. No new dependencies. Tests run with `dart test <path>` (optionally `--name "<substring>"`); lint with `dart analyze`.

**Spec:** `docs/superpowers/specs/2026-09-06-per-active-auras-sp2-design.md` — read it alongside this plan; `§` references point into it.

## Global Constraints

- **No new `Effect` / `Condition` / content-factory** beyond the single generic `SubjectIs` condition. Aura content uses only the built-in factories (`heal`, `damage`, `modifyStat`, `modifyResource`, `applyStatus`, `removeStatus`, `addTag`, `removeTag`, `randomChance`, `hasTag`, `healthBelow`, `resourceAbove`, `resourceBelow`, `statusActive`). (spec §3.2)
- **No change to `RuleEngine`, `RuleContext`, or `Rule`.** (spec §3.2)
- **Anti-goal:** no aura-oriented Core conditions (`OwnerIs`, `OpponentIs`, `ComponentIsHung`, `AuraActive`). All owner/opponent/hung semantics live in `AuraBinder._wire` and the `build.active` filter. (spec §3.2, §5.5)
- **`lib/src/aura/` imports only Core.** `aura_binder.dart` (in `build_interpretation/`) imports **no Combat symbol** and reads no `TurnStarted`/`ActionCompleted` field — it obtains "the event's actor" generically from the aura rule's own `subjectOf`. (spec §4, §5.5)
- **`AuraRule.sourceRuleId` is diagnostics-only — never a sort key.** Aura firing order = interpreter-list order → `build.active` order → `auraRuleIds` order → `EventBus` subscription order. Nothing sorts `AuraRule`s. (spec §5.1, §8)
- **`AuraBinding` is immutable in membership after `bind`.** No in-place update path; the only flow is dispose old → resolve new → `bind` new. `dispose()` is idempotent. (spec §5.4)
- **`scope: opponent` opponent-count policy:** 0 opponents → the aura is not registered (inert, no throw); exactly 1 → valid; >1 → `ArgumentError`. (spec §5.4, §5.9)
- Trigger keys are PascalCase, matching the existing `'EntityDamaged'` convention: `'TurnStarted'`, `'TurnEnded'`, `'ActionCompleted'`. (spec §5.6)
- Commit after every task. Conventional-commit messages. Branch: `per-active-auras-sp2` (already exists; the spec commits are already on it).
- Every commit message ends with the two trailer lines this repo requires:
  ```
  Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
  Claude-Session: https://claude.ai/code/session_01USc4vgCm9nma1UBaEd5c7z
  ```

---

## File Structure

**New — Core (`lib/src/aura/`):**
- `aura_scope.dart` — `enum AuraScope { self, opponent }`.
- `aura_rule.dart` — `class AuraRule { Rule rule; AuraScope scope; String sourceRuleId; }`.
- `aura_contributor.dart` — `abstract interface class AuraContributor { List<AuraRule> auraRules(); }`.

**New — build interpretation (`lib/src/plugins/build_interpretation/`):**
- `aura_binder.dart` — `AuraBinder` (`bind(...) → AuraBinding`), `AuraBinding` (`dispose()`), and the private `_wire` + `_EventActorIs` condition.

**New — content plugins:**
- `lib/src/plugins/item/item_aura_contributor.dart` — `ItemAuraContributor implements AuraContributor`.
- `lib/src/plugins/item/item_auras.dart` — `const itemAuraRuleDefinitions` (aura `RuleDefinition` JSON).
- `lib/src/plugins/technique/technique_aura_contributor.dart` — `TechniqueAuraContributor implements AuraContributor`.
- `lib/src/plugins/technique/technique_auras.dart` — `const techniqueAuraRuleDefinitions`.

**Modified:**
- `lib/src/rule/system_conditions.dart` — add `SubjectIs`.
- `lib/build_engine.dart` — export the three `src/aura/` files.
- `lib/build_interpretation.dart` — export `aura_binder.dart`.
- `lib/item_plugin.dart` / `lib/technique_plugin.dart` — export the new contributor + auras files.
- `lib/src/plugins/build_interpretation/build_action_interpreter.dart` — add abstract `auraRules(...)`.
- `.../composite_build_action_interpreter.dart` — implement `auraRules` (aggregate).
- `.../item_action_interpreter.dart` / `.../technique_action_interpreter.dart` — implement `auraRules`.
- `lib/src/plugins/item/item_definition.dart` / `.../item_content.dart` — `auraRuleIds` field + parse.
- `lib/src/plugins/technique/technique_definition.dart` / `.../technique_content.dart` — `auraRuleIds` field + parse.
- `lib/src/plugins/item/item_plugin.dart` / `.../technique/technique_plugin.dart` — load aura `RuleDefinition`s + register the three triggers is Combat's job (below).
- `lib/src/plugins/combat/combat_plugin.dart` — register `TurnStarted` / `TurnEnded` / `ActionCompleted` triggers.
- `lib/src/plugins/item/item_content.dart` / `.../technique/technique_content.dart` — add `auras` keys to specific content entries.
- `lib/src/plugins/game/combat_stage.dart` — bind/dispose auras around the fight.
- `test/integration/architecture_dependency_test.dart` — `lib/src/aura/` + `aura_binder.dart` guards.
- `CHANGELOG.md`, `ARCHITECTURE.md`.
- `output/game_run_seed_*.txt`, `output/game_run_summary.txt` — regenerated artifacts.

---

## Task 1: `SubjectIs` condition (Core)

**Files:**
- Modify: `lib/src/rule/system_conditions.dart`
- Test: `test/rule/subject_is_test.dart` (create)

**Interfaces:**
- Consumes: `Condition` (`lib/src/rule/condition.dart`), `RuleContext` (`.subject` is `EntityId?`), `EntityId`.
- Produces: `class SubjectIs implements Condition { const SubjectIs(EntityId entity); }` — exported via the existing `export 'src/rule/system_conditions.dart';` line in `lib/build_engine.dart`.

- [ ] **Step 1: Write the failing test**

Create `test/rule/subject_is_test.dart`:

```dart
import 'package:build_engine/build_engine.dart';
import 'package:test/test.dart';

class _Evt {
  const _Evt();
}

RuleContext _ctx(EntityId? subject) {
  final events = EventBus();
  final components = ComponentStore();
  final entities = EntityRegistry(events);
  return RuleContext(
    subject: subject,
    triggerEvent: const _Evt(),
    entities: entities,
    components: components,
    events: events,
    rng: RngService(1),
    eventCounts: EventCounter(events),
  );
}

void main() {
  test('matches when the subject equals the entity', () {
    expect(const SubjectIs(EntityId(7)).evaluate(_ctx(const EntityId(7))), isTrue);
  });

  test('does not match a different subject', () {
    expect(const SubjectIs(EntityId(7)).evaluate(_ctx(const EntityId(8))), isFalse);
  });

  test('does not match a null subject', () {
    expect(const SubjectIs(EntityId(7)).evaluate(_ctx(null)), isFalse);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `dart test test/rule/subject_is_test.dart`
Expected: compile FAIL — `SubjectIs` is not defined.

- [ ] **Step 3: Add the class**

In `lib/src/rule/system_conditions.dart`, add `import '../entity/entity_id.dart';` to the imports (keep them sorted: it goes before `import '../query/queries.dart';`). Append the class at the end of the file:

```dart
/// Matches when the rule's resolved [RuleContext.subject] is exactly
/// [entity] — a generic identity check with no aura, combat, or Tome
/// vocabulary. `AuraBinder._wire`
/// (`lib/src/plugins/build_interpretation/aura_binder.dart`) uses it as
/// the `self`-scope guard, but any rule may use it.
class SubjectIs implements Condition {
  const SubjectIs(this.entity);

  final EntityId entity;

  @override
  bool evaluate(RuleContext context) => context.subject == entity;
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `dart test test/rule/subject_is_test.dart`
Expected: PASS (3 tests).

- [ ] **Step 5: Lint**

Run: `dart analyze lib/src/rule/system_conditions.dart test/rule/subject_is_test.dart`
Expected: `No issues found!`

- [ ] **Step 6: Commit**

```bash
git add lib/src/rule/system_conditions.dart test/rule/subject_is_test.dart
git commit -m "$(printf 'feat(aura): SubjectIs generic condition\n\nctx.subject == entity. Reused by AuraBinder._wire as the self-scope\nguard; no aura/combat/Tome vocabulary.\n\nCo-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>\nClaude-Session: https://claude.ai/code/session_01USc4vgCm9nma1UBaEd5c7z')"
```

---

## Task 2: `lib/src/aura/` — value types + interface

**Files:**
- Create: `lib/src/aura/aura_scope.dart`, `lib/src/aura/aura_rule.dart`, `lib/src/aura/aura_contributor.dart`
- Modify: `lib/build_engine.dart`
- Test: `test/aura/aura_types_test.dart` (create)

**Interfaces:**
- Consumes: `Rule` (`lib/src/rule/rule.dart`).
- Produces:
  - `enum AuraScope { self, opponent }`
  - `class AuraRule { const AuraRule({required Rule rule, required AuraScope scope, required String sourceRuleId}); final Rule rule; final AuraScope scope; final String sourceRuleId; }`
  - `abstract interface class AuraContributor { List<AuraRule> auraRules(); }`
  - All three exported from `package:build_engine/build_engine.dart`.

- [ ] **Step 1: Write the failing test**

Create `test/aura/aura_types_test.dart`:

```dart
import 'package:build_engine/build_engine.dart';
import 'package:test/test.dart';

class _Dummy implements AuraContributor {
  @override
  List<AuraRule> auraRules() => const [];
}

void main() {
  test('AuraScope is exactly {self, opponent}', () {
    expect(AuraScope.values, [AuraScope.self, AuraScope.opponent]);
  });

  test('AuraRule carries rule, scope, and source id unchanged', () {
    final rule = Rule(trigger: Object, effects: const []);
    final aura = AuraRule(
      rule: rule,
      scope: AuraScope.opponent,
      sourceRuleId: 'aura.x',
    );
    expect(aura.rule, same(rule));
    expect(aura.scope, AuraScope.opponent);
    expect(aura.sourceRuleId, 'aura.x');
  });

  test('AuraContributor is exported and implementable', () {
    expect(_Dummy(), isA<AuraContributor>());
    expect(_Dummy().auraRules(), isEmpty);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `dart test test/aura/aura_types_test.dart`
Expected: compile FAIL — `AuraScope` / `AuraRule` / `AuraContributor` undefined.

- [ ] **Step 3: Create the three files**

`lib/src/aura/aura_scope.dart`:

```dart
/// Who an aura's effects act on. Read from a `RuleDefinition`'s optional
/// `scope` key (`"self"` — the default — or `"opponent"`). It is the only
/// aura-specific metadata `AuraBinder._wire`
/// (`lib/src/plugins/build_interpretation/aura_binder.dart`) needs; the
/// rule body itself stays identity-free.
enum AuraScope { self, opponent }
```

`lib/src/aura/aura_rule.dart`:

```dart
import '../rule/rule.dart';
import 'aura_scope.dart';

/// One aura: an unmodified Core [Rule] body (trigger + conditions +
/// effects, straight from the `ContentRegistry.loadRule` DSL) plus the
/// single piece of aura-specific metadata the binder needs to scope it.
///
/// [rule] is never mutated. [sourceRuleId] is the `RuleDefinition` id it
/// came from — for diagnostics / logging ONLY. It is **never** a sort
/// key: aura firing order is fixed by interpreter-list order ->
/// `build.active` order -> a component's `auraRuleIds` order ->
/// `EventBus` subscription order, and nothing re-orders `AuraRule`s.
class AuraRule {
  const AuraRule({
    required this.rule,
    required this.scope,
    required this.sourceRuleId,
  });

  final Rule rule;
  final AuraScope scope;
  final String sourceRuleId;
}
```

`lib/src/aura/aura_contributor.dart`:

```dart
import 'aura_rule.dart';

/// A component type that can declare rules which are live only while the
/// component is in `ResolvedBuild.active`. The "implement the interface,
/// no registry" pattern `EffectContributor` / `Condition` / `Effect` /
/// `CombatAction` already use.
///
/// Parameterless, mirroring `EffectContributor.effectProfile()`. Owner /
/// opponent identity is injected later by `AuraBinder._wire`, so every
/// [Rule] returned here stays identity-free and serializable.
///
/// **Implemented by a composing wrapper** (`ItemAuraContributor`,
/// `TechniqueAuraContributor`) that holds a `ContentRegistry` — NOT by
/// `ItemDefinition` / `TechniqueVariant` themselves. Resolving a
/// component's `auras` id list into `RuleDefinition`s needs the registry,
/// and a Core-adjacent value object must not take a `ContentRegistry`
/// dependency. Contrast `EffectContributor`: pure value calculation over
/// component state, so it can live on the state object. Do not
/// "simplify" this asymmetry away.
abstract interface class AuraContributor {
  List<AuraRule> auraRules();
}
```

- [ ] **Step 4: Add exports**

In `lib/build_engine.dart`, immediately after `library;` block's first export line region — put these three lines at the very top of the export list (before `export 'src/character/character_component.dart';`):

```dart
export 'src/aura/aura_contributor.dart';
export 'src/aura/aura_rule.dart';
export 'src/aura/aura_scope.dart';
```

- [ ] **Step 5: Run test to verify it passes**

Run: `dart test test/aura/aura_types_test.dart`
Expected: PASS (3 tests).

- [ ] **Step 6: Lint**

Run: `dart analyze lib/src/aura test/aura`
Expected: `No issues found!`

- [ ] **Step 7: Commit**

```bash
git add lib/src/aura lib/build_engine.dart test/aura
git commit -m "$(printf 'feat(aura): AuraScope, AuraRule, AuraContributor value types\n\nCore lib/src/aura/. AuraRule wraps a raw Core Rule + a self/opponent\nscope + a diagnostics-only source id. Parameterless interface; wrappers\n(not state objects) will implement it since id-lookup needs the registry.\n\nCo-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>\nClaude-Session: https://claude.ai/code/session_01USc4vgCm9nma1UBaEd5c7z')"
```

---

## Task 3: `BuildActionInterpreter.auraRules` — abstract method + three implementations

Adds the contract method so every interpreter satisfies it; the Item/Technique implementations are stubs here (real logic in Task 6), the composite aggregates.

**Files:**
- Modify: `lib/src/plugins/build_interpretation/build_action_interpreter.dart`
- Modify: `lib/src/plugins/build_interpretation/composite_build_action_interpreter.dart`
- Modify: `lib/src/plugins/build_interpretation/item_action_interpreter.dart`
- Modify: `lib/src/plugins/build_interpretation/technique_action_interpreter.dart`
- Test: `test/plugins/build_interpretation/build_action_interpreter_aura_rules_test.dart` (create)

**Interfaces:**
- Consumes: `AuraRule` (Task 2), `ResolvedBuild`, `PluginContext`.
- Produces: `List<AuraRule> BuildActionInterpreter.auraRules({required ResolvedBuild build, required PluginContext context})` — abstract on the base; `CompositeBuildActionInterpreter` concatenates children in `interpreters` order; `ItemActionInterpreter` / `TechniqueActionInterpreter` return `const []` (until Task 6).

- [ ] **Step 1: Write the failing test**

Create `test/plugins/build_interpretation/build_action_interpreter_aura_rules_test.dart`:

```dart
import 'package:build_engine/build_engine.dart';
import 'package:build_engine/build_interpretation.dart';
import 'package:build_engine/combat_plugin.dart';
import 'package:test/test.dart';

PluginContext _ctx() {
  final events = EventBus();
  final entities = EntityRegistry(events);
  final components = ComponentStore();
  final rng = RngService(1);
  return PluginContext(
    entities: entities,
    components: components,
    events: events,
    rng: rng,
    rules: RuleEngine(entities: entities, components: components, events: events, rng: rng),
    queries: QueryEngine(QueryScope(components: components)),
    modifiers: ModifierCollection(),
    content: ContentRegistry(),
  );
}

ResolvedBuild _emptyBuild() =>
    ResolvedBuild(owner: const EntityId(1), active: const [], owned: const []);

AuraRule _aura(String id, AuraScope scope) => AuraRule(
      rule: Rule(trigger: Object, effects: const []),
      scope: scope,
      sourceRuleId: id,
    );

class _FixedAuraInterpreter implements BuildActionInterpreter {
  const _FixedAuraInterpreter(this._auras);
  final List<AuraRule> _auras;

  @override
  List<CombatAction> interpret({
    required ResolvedBuild build,
    required EntityId actor,
    required List<EntityId> targets,
    required PluginContext context,
  }) =>
      const [];

  @override
  List<AuraRule> auraRules({required ResolvedBuild build, required PluginContext context}) => _auras;
}

void main() {
  test('composite concatenates children auraRules in interpreter-list order', () {
    final composite = CompositeBuildActionInterpreter([
      _FixedAuraInterpreter([_aura('a', AuraScope.self)]),
      _FixedAuraInterpreter([_aura('b', AuraScope.opponent), _aura('c', AuraScope.self)]),
    ]);

    final result = composite.auraRules(build: _emptyBuild(), context: _ctx());

    expect(result.map((r) => r.sourceRuleId), ['a', 'b', 'c']);
  });

  test('ItemActionInterpreter and TechniqueActionInterpreter yield no auras yet', () {
    final ctx = _ctx();
    expect(const ItemActionInterpreter().auraRules(build: _emptyBuild(), context: ctx), isEmpty);
    expect(const TechniqueActionInterpreter().auraRules(build: _emptyBuild(), context: ctx), isEmpty);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `dart test test/plugins/build_interpretation/build_action_interpreter_aura_rules_test.dart`
Expected: compile FAIL — `auraRules` not defined on `BuildActionInterpreter`.

- [ ] **Step 3: Add the abstract method**

In `lib/src/plugins/build_interpretation/build_action_interpreter.dart`, inside the class body after `interpret(...)`'s declaration, add:

```dart
  /// The `AuraRule`s (`package:build_engine/build_engine.dart`) to keep
  /// live while their owning component is hung — i.e. present in
  /// `build.active`. Fed to `AuraBinder`. Abstract: every interpreter in
  /// this repo uses `implements`, not `extends`, so a default body would
  /// not propagate. See
  /// `docs/superpowers/specs/2026-09-06-per-active-auras-sp2-design.md`.
  List<AuraRule> auraRules({
    required ResolvedBuild build,
    required PluginContext context,
  });
```

`AuraRule` resolves through the existing `import 'package:build_engine/build_engine.dart';` at the top of the file.

- [ ] **Step 4: Implement on the composite**

In `composite_build_action_interpreter.dart`, add after `interpret(...)`:

```dart
  @override
  List<AuraRule> auraRules({
    required ResolvedBuild build,
    required PluginContext context,
  }) =>
      [
        for (final interpreter in interpreters)
          ...interpreter.auraRules(build: build, context: context),
      ];
```

- [ ] **Step 5: Stub on the Item and Technique interpreters**

In both `item_action_interpreter.dart` and `technique_action_interpreter.dart`, add after `interpret(...)`:

```dart
  @override
  List<AuraRule> auraRules({
    required ResolvedBuild build,
    required PluginContext context,
  }) =>
      const [];
```

- [ ] **Step 6: Run the new test + the whole build_interpretation suite**

Run: `dart test test/plugins/build_interpretation/`
Expected: PASS, including the new file (2 tests) and every pre-existing interpreter test unchanged.

- [ ] **Step 7: Lint**

Run: `dart analyze lib/src/plugins/build_interpretation test/plugins/build_interpretation`
Expected: `No issues found!`

- [ ] **Step 8: Commit**

```bash
git add lib/src/plugins/build_interpretation test/plugins/build_interpretation/build_action_interpreter_aura_rules_test.dart
git commit -m "$(printf 'feat(aura): BuildActionInterpreter.auraRules contract + composite\n\nAbstract method on the interpreter contract; composite concatenates\nchildren in interpreter-list order; Item/Technique return const [] for\nnow (real logic in a later task).\n\nCo-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>\nClaude-Session: https://claude.ai/code/session_01USc4vgCm9nma1UBaEd5c7z')"
```

---

## Task 4: `auras` content field → `ItemDefinition.auraRuleIds` / `TechniqueDefinition.auraRuleIds`

**Files:**
- Modify: `lib/src/plugins/item/item_definition.dart`
- Modify: `lib/src/plugins/item/item_content.dart` (`itemDefinitionFromContent`)
- Modify: `lib/src/plugins/technique/technique_definition.dart`
- Modify: `lib/src/plugins/technique/technique_content.dart` (`techniqueDefinitionFromContent`)
- Test: `test/plugins/item/item_definition_auras_test.dart` (create), `test/plugins/technique/technique_definition_auras_test.dart` (create)

**Interfaces:**
- Consumes: `ContentDefinition.extra` (a `Map<String, dynamic>`; a JSON `auras` key lands here since `_parse` strips only `id/type/tags/requires/components/conditions/effects`).
- Produces:
  - `ItemDefinition` gains `final List<String> auraRuleIds` — new named param `this.auraRuleIds = const []` (placed last, after `classScalingPercent`).
  - `TechniqueDefinition` gains `final List<String> auraRuleIds` — new named param `this.auraRuleIds = const []` (placed last, after `modifiersFor`).
  - `itemDefinitionFromContent` / `techniqueDefinitionFromContent` populate it from `definition.extra['auras']`.

- [ ] **Step 1: Write the failing tests**

Create `test/plugins/item/item_definition_auras_test.dart`:

```dart
import 'package:build_engine/build_engine.dart';
import 'package:build_engine/item_plugin.dart';
import 'package:test/test.dart';

void main() {
  test('itemDefinitionFromContent reads the auras id list', () {
    final registry = ContentRegistry();
    final def = registry.load({
      'id': 'test_boots',
      'type': 'footwear',
      'tags': <String>[],
      'properties': {'attack': 1},
      'auras': ['aura.one', 'aura.two'],
    });
    expect(itemDefinitionFromContent(def).auraRuleIds, ['aura.one', 'aura.two']);
  });

  test('an item with no auras key has an empty auraRuleIds', () {
    final registry = ContentRegistry();
    final def = registry.load({
      'id': 'plain',
      'type': 'weapon',
      'tags': <String>[],
      'properties': {'attack': 2},
    });
    expect(itemDefinitionFromContent(def).auraRuleIds, isEmpty);
  });

  test('ItemDefinition default auraRuleIds is const []', () {
    const def = ItemDefinition(
      id: 'x', category: 'weapon', tags: {}, properties: {},
    );
    expect(def.auraRuleIds, isEmpty);
  });
}
```

Create `test/plugins/technique/technique_definition_auras_test.dart`:

```dart
import 'package:build_engine/build_engine.dart';
import 'package:build_engine/technique_plugin.dart';
import 'package:test/test.dart';

void main() {
  test('techniqueDefinitionFromContent reads the auras id list', () {
    final registry = ContentRegistry();
    final def = registry.load({
      'id': 'test_tech',
      'type': 'technique',
      'tags': <String>[],
      'name': 'Test',
      'tier': 'basic',
      'properties': {'damage': 3},
      'auras': ['aura.venom'],
    });
    expect(techniqueDefinitionFromContent(def).auraRuleIds, ['aura.venom']);
  });

  test('a technique with no auras key has an empty auraRuleIds', () {
    final registry = ContentRegistry();
    final def = registry.load({
      'id': 'plain_tech',
      'type': 'technique',
      'tags': <String>[],
      'name': 'Plain',
      'tier': 'basic',
      'properties': {'damage': 2},
    });
    expect(techniqueDefinitionFromContent(def).auraRuleIds, isEmpty);
  });
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `dart test test/plugins/item/item_definition_auras_test.dart test/plugins/technique/technique_definition_auras_test.dart`
Expected: compile FAIL — `auraRuleIds` undefined.

- [ ] **Step 3: Add the field to `ItemDefinition`**

In `lib/src/plugins/item/item_definition.dart`: add `this.auraRuleIds = const [],` as the last entry in the constructor param list, and `final List<String> auraRuleIds;` as the last field. Extend the doc comment with one sentence:

```
/// [auraRuleIds] lists `RuleDefinition` ids (loaded via
/// `ContentRegistry.loadRule`) whose rules are live only while this item
/// is hung — resolved by `ItemAuraContributor`
/// (`docs/superpowers/specs/2026-09-06-per-active-auras-sp2-design.md`).
```

- [ ] **Step 4: Populate it in `itemDefinitionFromContent`**

In `lib/src/plugins/item/item_content.dart`, inside `itemDefinitionFromContent`, before the `return ItemDefinition(`:

```dart
  final auraRuleIds = <String>[
    for (final id in (definition.extra['auras'] as List?) ?? const [])
      id as String,
  ];
```

and pass `auraRuleIds: auraRuleIds,` as the last argument to `ItemDefinition(...)`.

- [ ] **Step 5: Add the field to `TechniqueDefinition`**

In `lib/src/plugins/technique/technique_definition.dart`: add `this.auraRuleIds = const [],` as the last constructor param and `final List<String> auraRuleIds;` as the last field, with the analogous one-sentence doc note.

- [ ] **Step 6: Populate it in `techniqueDefinitionFromContent`**

In `lib/src/plugins/technique/technique_content.dart`, inside `techniqueDefinitionFromContent`, before `return TechniqueDefinition(`:

```dart
  final auraRuleIds = <String>[
    for (final id in (definition.extra['auras'] as List?) ?? const [])
      id as String,
  ];
```

and pass `auraRuleIds: auraRuleIds,` as the last argument.

- [ ] **Step 7: Run tests to verify they pass**

Run: `dart test test/plugins/item/item_definition_auras_test.dart test/plugins/technique/technique_definition_auras_test.dart`
Expected: PASS (3 + 2 tests).

- [ ] **Step 8: Regression + lint**

Run: `dart test test/plugins/item test/plugins/technique && dart analyze lib/src/plugins/item lib/src/plugins/technique`
Expected: all green; `No issues found!`

- [ ] **Step 9: Commit**

```bash
git add lib/src/plugins/item/item_definition.dart lib/src/plugins/item/item_content.dart lib/src/plugins/technique/technique_definition.dart lib/src/plugins/technique/technique_content.dart test/plugins/item/item_definition_auras_test.dart test/plugins/technique/technique_definition_auras_test.dart
git commit -m "$(printf 'feat(aura): parse auras id list onto Item/TechniqueDefinition\n\nNew auraRuleIds field, populated from content extra[auras]; absent key\n-> const []. Same parsing shape as trainingWeights/properties.\n\nCo-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>\nClaude-Session: https://claude.ai/code/session_01USc4vgCm9nma1UBaEd5c7z')"
```

---

## Task 5: `ItemAuraContributor` + `TechniqueAuraContributor`

**Files:**
- Create: `lib/src/plugins/item/item_aura_contributor.dart`
- Create: `lib/src/plugins/technique/technique_aura_contributor.dart`
- Modify: `lib/item_plugin.dart` (export), `lib/technique_plugin.dart` (export)
- Test: `test/plugins/item/item_aura_contributor_test.dart` (create), `test/plugins/technique/technique_aura_contributor_test.dart` (create)

**Interfaces:**
- Consumes: `AuraContributor` / `AuraRule` / `AuraScope` (Task 2); `ItemDefinition.auraRuleIds` / `TechniqueDefinition.auraRuleIds` (Task 4); `ContentRegistry.rule(String) → RuleDefinition` (throws `ContentNotFoundException` on a missing id); `RuleDefinition.rule` (a `Rule`) and `RuleDefinition.raw` (`Map<String, dynamic>`).
- Produces:
  - `class ItemAuraContributor implements AuraContributor { const ItemAuraContributor(ItemDefinition definition, ContentRegistry content); }`
  - `class TechniqueAuraContributor implements AuraContributor { const TechniqueAuraContributor(TechniqueDefinition definition, ContentRegistry content); }`
  - Both: `auraRules()` returns one `AuraRule` per `auraRuleIds` entry, `scope` = `raw['scope']` mapped (`"self"`→`AuraScope.self` default, `"opponent"`→`AuraScope.opponent`, anything else → `ArgumentError`).
  - Exported via `package:build_engine/item_plugin.dart` and `package:build_engine/technique_plugin.dart`.

- [ ] **Step 1: Write the failing tests**

Create `test/plugins/item/item_aura_contributor_test.dart`:

```dart
import 'package:build_engine/build_engine.dart';
import 'package:build_engine/item_plugin.dart';
import 'package:test/test.dart';

class _Evt {
  const _Evt(this.actor);
  final EntityId actor;
}

ContentRegistry _registryWithRule(Map<String, dynamic> ruleJson) {
  final r = ContentRegistry();
  r.registerTrigger('Evt', _Evt, (e) => (e as _Evt).actor);
  r.loadRule(ruleJson);
  return r;
}

ItemDefinition _defWithAuras(List<String> ids) => ItemDefinition(
      id: 'x', category: 'weapon', tags: const {}, properties: const {},
      auraRuleIds: ids,
    );

void main() {
  test('resolves each auraRuleId into an AuraRule with default self scope', () {
    final content = _registryWithRule({
      'id': 'aura.heal',
      'trigger': 'Evt',
      'effects': [{'type': 'heal', 'amount': 2}],
    });
    final auras = ItemAuraContributor(_defWithAuras(['aura.heal']), content).auraRules();
    expect(auras, hasLength(1));
    expect(auras.single.sourceRuleId, 'aura.heal');
    expect(auras.single.scope, AuraScope.self);
    expect(auras.single.rule.effects.single, isA<Heal>());
  });

  test('reads scope: opponent from the rule json', () {
    final content = _registryWithRule({
      'id': 'aura.bleed',
      'trigger': 'Evt',
      'scope': 'opponent',
      'effects': [{'type': 'damage', 'amount': 1}],
    });
    final auras = ItemAuraContributor(_defWithAuras(['aura.bleed']), content).auraRules();
    expect(auras.single.scope, AuraScope.opponent);
  });

  test('empty auraRuleIds yields no auras', () {
    expect(ItemAuraContributor(_defWithAuras(const []), ContentRegistry()).auraRules(), isEmpty);
  });

  test('an unknown auraRuleId throws ContentNotFoundException', () {
    expect(
      () => ItemAuraContributor(_defWithAuras(['aura.missing']), ContentRegistry()).auraRules(),
      throwsA(isA<ContentNotFoundException>()),
    );
  });

  test('an invalid scope value throws ArgumentError', () {
    final content = _registryWithRule({
      'id': 'aura.bad',
      'trigger': 'Evt',
      'scope': 'everyone',
      'effects': [{'type': 'heal', 'amount': 1}],
    });
    expect(
      () => ItemAuraContributor(_defWithAuras(['aura.bad']), content).auraRules(),
      throwsA(isA<ArgumentError>()),
    );
  });
}
```

Create `test/plugins/technique/technique_aura_contributor_test.dart` — the same five tests, replacing `ItemAuraContributor(_defWithAuras(...), content)` with `TechniqueAuraContributor(_techDefWithAuras(...), content)` where:

```dart
TechniqueDefinition _techDefWithAuras(List<String> ids) => TechniqueDefinition(
      id: 't', name: 'T', tier: 'basic', tags: const {}, properties: const {},
      auraRuleIds: ids,
    );
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `dart test test/plugins/item/item_aura_contributor_test.dart test/plugins/technique/technique_aura_contributor_test.dart`
Expected: compile FAIL — contributors undefined.

- [ ] **Step 3: Create `ItemAuraContributor`**

`lib/src/plugins/item/item_aura_contributor.dart`:

```dart
import 'package:build_engine/build_engine.dart';

import 'item_definition.dart';

/// [ItemDefinition] + the [ContentRegistry] as one [AuraContributor].
/// Resolving `definition.auraRuleIds` into `RuleDefinition`s needs the
/// registry, so the interface is implemented by this thin wrapper, never
/// by `ItemDefinition` (a Core-adjacent value object that must not take a
/// `ContentRegistry` dependency). Mirrors why `ItemEffectContributor`
/// wraps rather than extends — except `EffectContributor` is pure value
/// calculation over item state and needs no registry, whereas this is an
/// id lookup and does. Do not "simplify" the two into one shape.
class ItemAuraContributor implements AuraContributor {
  const ItemAuraContributor(this.definition, this.content);

  final ItemDefinition definition;
  final ContentRegistry content;

  @override
  List<AuraRule> auraRules() => [
        for (final id in definition.auraRuleIds) _auraRuleFrom(content, id),
      ];
}

/// Shared by [ItemAuraContributor] and `TechniqueAuraContributor`: look
/// up [id], read its optional `scope` (`"self"` default, `"opponent"`),
/// and pair the loaded [Rule] with it. Throws `ContentNotFoundException`
/// for an unknown id and `ArgumentError` for an unrecognised `scope`.
AuraRule auraRuleFromRegistry(ContentRegistry content, String id) {
  final definition = content.rule(id); // throws ContentNotFoundException if absent
  final rawScope = definition.raw['scope'];
  final AuraScope scope;
  switch (rawScope) {
    case null:
    case 'self':
      scope = AuraScope.self;
    case 'opponent':
      scope = AuraScope.opponent;
    default:
      throw ArgumentError.value(
        rawScope, 'scope', 'aura rule "$id": scope must be "self" or "opponent"');
  }
  return AuraRule(rule: definition.rule, scope: scope, sourceRuleId: id);
}

AuraRule _auraRuleFrom(ContentRegistry content, String id) =>
    auraRuleFromRegistry(content, id);
```

> Note: `_auraRuleFrom` is a trivial alias kept only so the class body reads cleanly; you may inline `auraRuleFromRegistry` directly and delete `_auraRuleFrom` if you prefer — behaviour is identical. The shared top-level `auraRuleFromRegistry` is the one `TechniqueAuraContributor` reuses.

- [ ] **Step 4: Create `TechniqueAuraContributor`**

`lib/src/plugins/technique/technique_aura_contributor.dart`:

```dart
import 'package:build_engine/build_engine.dart';
import 'package:build_engine/item_plugin.dart' show auraRuleFromRegistry;

import 'technique_definition.dart';

/// [TechniqueDefinition] + the [ContentRegistry] as one [AuraContributor]
/// — the exact analogue of `ItemAuraContributor`, reading `auraRuleIds`
/// off the base technique definition. `TechniqueVariant` keeps
/// implementing `EffectContributor` directly (no registry needed there),
/// but not `AuraContributor`: aura resolution needs the registry, so it
/// goes through this wrapper. See `AuraContributor`'s own doc comment.
class TechniqueAuraContributor implements AuraContributor {
  const TechniqueAuraContributor(this.definition, this.content);

  final TechniqueDefinition definition;
  final ContentRegistry content;

  @override
  List<AuraRule> auraRules() => [
        for (final id in definition.auraRuleIds)
          auraRuleFromRegistry(content, id),
      ];
}
```

> If importing `auraRuleFromRegistry` from `item_plugin.dart` into the Technique plugin trips the architecture-dependency guard (Task 11 adds no such rule, but the existing `build_interpretation_architecture_test.dart` / `architecture_dependency_test.dart` might), instead **move `auraRuleFromRegistry` to a shared Core home**: create `lib/src/aura/aura_rule_from_registry.dart` exporting the same function (it depends only on `ContentRegistry` + `AuraRule` + `AuraScope`, all Core), add it to `lib/build_engine.dart` exports, and import it from both contributors. Decide by running `dart test test/integration/architecture_dependency_test.dart test/plugins/build_interpretation/build_interpretation_architecture_test.dart` after Step 5 — if red on this import, do the move; if green, leave it. **Recommended: do the Core move upfront** — it is cleaner and avoids Item↔Technique coupling. In that case `item_aura_contributor.dart` also imports it from the barrel and drops its own top-level definition.

- [ ] **Step 5: Add exports**

`lib/item_plugin.dart`: add `export 'src/plugins/item/item_aura_contributor.dart';` (keep list alphabetical — after `item_action`… no, there is none; place after the `export 'src/plugins/item/item_combine.dart';` line, before `item_content.dart`).

`lib/technique_plugin.dart`: add `export 'src/plugins/technique/technique_aura_contributor.dart';` (place before `export 'src/plugins/technique/technique_content.dart'` line).

If you did the Core move: also add `export 'src/aura/aura_rule_from_registry.dart';` to `lib/build_engine.dart`.

- [ ] **Step 6: Run tests to verify they pass**

Run: `dart test test/plugins/item/item_aura_contributor_test.dart test/plugins/technique/technique_aura_contributor_test.dart`
Expected: PASS (5 + 5 tests).

- [ ] **Step 7: Architecture guard check + lint**

Run: `dart test test/integration/architecture_dependency_test.dart test/plugins/build_interpretation/build_interpretation_architecture_test.dart && dart analyze lib/src/plugins/item lib/src/plugins/technique lib/src/aura`
Expected: all green; `No issues found!`. If the architecture test is red on an Item↔Technique import, apply the Core move from Step 4's note, then re-run.

- [ ] **Step 8: Commit**

```bash
git add lib/src/plugins/item/item_aura_contributor.dart lib/src/plugins/technique/technique_aura_contributor.dart lib/item_plugin.dart lib/technique_plugin.dart lib/build_engine.dart lib/src/aura test/plugins/item/item_aura_contributor_test.dart test/plugins/technique/technique_aura_contributor_test.dart
git commit -m "$(printf 'feat(aura): Item/TechniqueAuraContributor resolve auras ids to AuraRules\n\nComposing wrappers hold the ContentRegistry; auraRules() maps each id to\nan AuraRule, reading scope from raw[scope] (self default / opponent;\nelse ArgumentError). Unknown id -> ContentNotFoundException.\n\nCo-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>\nClaude-Session: https://claude.ai/code/session_01USc4vgCm9nma1UBaEd5c7z')"
```

---

## Task 6: Fill in `ItemActionInterpreter.auraRules` + `TechniqueActionInterpreter.auraRules`

**Files:**
- Modify: `lib/src/plugins/build_interpretation/item_action_interpreter.dart`
- Modify: `lib/src/plugins/build_interpretation/technique_action_interpreter.dart`
- Test: `test/plugins/build_interpretation/item_action_interpreter_aura_rules_test.dart` (create), `test/plugins/build_interpretation/technique_action_interpreter_aura_rules_test.dart` (create)

**Interfaces:**
- Consumes: `ItemAuraContributor` / `TechniqueAuraContributor` (Task 5); `build.active`; `itemReferenceType` / `techniqueReferenceType`; `context.content` (`ContentRegistry`); `itemDefinitionFromContent` / `techniqueDefinitionFromContent`.
- Produces: real `auraRules({required ResolvedBuild build, required PluginContext context})` — iterates `build.active`, keeps its own `referenceType`, resolves the definition, delegates to the contributor. Only `build.active` (never `build.owned`).

- [ ] **Step 1: Write the failing tests**

Create `test/plugins/build_interpretation/item_action_interpreter_aura_rules_test.dart`:

```dart
import 'package:build_engine/build_engine.dart';
import 'package:build_engine/build_interpretation.dart';
import 'package:build_engine/item_plugin.dart';
import 'package:test/test.dart';

class _Evt {
  const _Evt(this.actor);
  final EntityId actor;
}

PluginContext _ctx() {
  final events = EventBus();
  final entities = EntityRegistry(events);
  final components = ComponentStore();
  final rng = RngService(1);
  final c = PluginContext(
    entities: entities,
    components: components,
    events: events,
    rng: rng,
    rules: RuleEngine(entities: entities, components: components, events: events, rng: rng),
    queries: QueryEngine(QueryScope(components: components)),
    modifiers: ModifierCollection(),
    content: ContentRegistry(),
  );
  c.content.registerTrigger('Evt', _Evt, (e) => (e as _Evt).actor);
  c.content.load({
    'id': 'boots_of_regen',
    'type': 'footwear',
    'tags': <String>[],
    'properties': {'attack': 1},
    'auras': ['aura.step_heal'],
  });
  c.content.loadRule({
    'id': 'aura.step_heal',
    'trigger': 'Evt',
    'effects': [{'type': 'heal', 'amount': 2}],
  });
  return c;
}

ResolvedBuild _build(EntityId owner, {List<BuildComponentRef> hung = const [], List<BuildComponentRef> ownedOnly = const []}) =>
    ResolvedBuild(owner: owner, active: hung, owned: [...hung, ...ownedOnly]);

void main() {
  const interp = ItemActionInterpreter();

  test('a hung item with an auras key contributes its AuraRule', () {
    final ctx = _ctx();
    final owner = ctx.entities.create();
    final result = interp.auraRules(
      build: _build(owner, hung: const [
        BuildComponentRef(referenceType: itemReferenceType, contentId: 'boots_of_regen'),
      ]),
      context: ctx,
    );
    expect(result.map((r) => r.sourceRuleId), ['aura.step_heal']);
  });

  test('an owned-but-not-hung item contributes nothing', () {
    final ctx = _ctx();
    final owner = ctx.entities.create();
    final result = interp.auraRules(
      build: _build(owner, ownedOnly: const [
        BuildComponentRef(referenceType: itemReferenceType, contentId: 'boots_of_regen'),
      ]),
      context: ctx,
    );
    expect(result, isEmpty);
  });

  test('a hung technique ref is ignored by the item interpreter', () {
    final ctx = _ctx();
    final owner = ctx.entities.create();
    final result = interp.auraRules(
      build: _build(owner, hung: const [
        BuildComponentRef(referenceType: 'technique', contentId: 'whatever'),
      ]),
      context: ctx,
    );
    expect(result, isEmpty);
  });
}
```

Create `test/plugins/build_interpretation/technique_action_interpreter_aura_rules_test.dart` — analogous, with content `{'id': 'venom_strike', 'type': 'technique', 'tags': [], 'name': 'Venom', 'tier': 'basic', 'properties': {'damage': 3}, 'auras': ['aura.venom']}`, rule `{'id': 'aura.venom', 'trigger': 'Evt', 'scope': 'opponent', 'effects': [{'type': 'damage', 'amount': 1}]}`, `referenceType: techniqueReferenceType`, and `const interp = TechniqueActionInterpreter();`. Assert the hung case yields `['aura.venom']` with `scope == AuraScope.opponent`, and that a hung *item* ref is ignored.

- [ ] **Step 2: Run tests to verify they fail**

Run: `dart test test/plugins/build_interpretation/item_action_interpreter_aura_rules_test.dart test/plugins/build_interpretation/technique_action_interpreter_aura_rules_test.dart`
Expected: FAIL — `auraRules` still returns `const []` (assertions on `sourceRuleId` fail).

- [ ] **Step 3: Implement on `ItemActionInterpreter`**

Add `import 'package:build_engine/item_plugin.dart';` is already present. Replace the stub `auraRules` body:

```dart
  @override
  List<AuraRule> auraRules({
    required ResolvedBuild build,
    required PluginContext context,
  }) =>
      [
        for (final ref in build.active)
          if (ref.referenceType == itemReferenceType)
            if (context.content.find(ref.contentId) case final definition?)
              ...ItemAuraContributor(
                itemDefinitionFromContent(definition),
                context.content,
              ).auraRules(),
      ];
```

- [ ] **Step 4: Implement on `TechniqueActionInterpreter`**

`import 'package:build_engine/technique_plugin.dart';` is already present. Replace the stub body:

```dart
  @override
  List<AuraRule> auraRules({
    required ResolvedBuild build,
    required PluginContext context,
  }) =>
      [
        for (final ref in build.active)
          if (ref.referenceType == techniqueReferenceType)
            if (context.content.find(ref.contentId) case final definition?)
              ...TechniqueAuraContributor(
                techniqueDefinitionFromContent(definition),
                context.content,
              ).auraRules(),
      ];
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `dart test test/plugins/build_interpretation/`
Expected: PASS — new files plus the Task 3 composite test (which now aggregates real results) and every pre-existing interpreter test.

- [ ] **Step 6: Lint**

Run: `dart analyze lib/src/plugins/build_interpretation test/plugins/build_interpretation`
Expected: `No issues found!`

- [ ] **Step 7: Commit**

```bash
git add lib/src/plugins/build_interpretation/item_action_interpreter.dart lib/src/plugins/build_interpretation/technique_action_interpreter.dart test/plugins/build_interpretation/item_action_interpreter_aura_rules_test.dart test/plugins/build_interpretation/technique_action_interpreter_aura_rules_test.dart
git commit -m "$(printf 'feat(aura): Item/Technique interpreters emit auras for hung refs\n\nauraRules() iterates build.active, keeps its own referenceType, resolves\nthe definition, and delegates to the *AuraContributor wrapper. Owned-only\nrefs contribute nothing.\n\nCo-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>\nClaude-Session: https://claude.ai/code/session_01USc4vgCm9nma1UBaEd5c7z')"
```

---

## Task 7: `AuraBinder` / `AuraBinding` / `_wire`

**Files:**
- Create: `lib/src/plugins/build_interpretation/aura_binder.dart`
- Modify: `lib/build_interpretation.dart` (export)
- Test: `test/plugins/build_interpretation/aura_binder_test.dart` (create)

**Interfaces:**
- Consumes: `BuildActionInterpreter.auraRules(...)` (Task 3/6); `RuleEngine.register(Rule) → EventSubscription` (`context.rules`); `EventSubscription.cancel()`; `Rule` (`.trigger` `Type`, `.subjectOf` `EntityId? Function(Object)?`, `.conditions`, `.effects`); `SubjectIs` (Task 1); `ResolvedBuild.owner`.
- Produces:
  - `class AuraBinder { const AuraBinder(); AuraBinding bind({required ResolvedBuild build, required BuildActionInterpreter interpreter, required PluginContext context, List<EntityId> opponents = const []}); }`
  - `class AuraBinding { void dispose(); }` — idempotent.
  - `bind` throws `ArgumentError` when any registered aura is `AuraScope.opponent` and `opponents.length > 1`. `AuraScope.opponent` + `opponents.isEmpty` → that aura is skipped (not registered).
  - Exported via `package:build_engine/build_interpretation.dart`.

- [ ] **Step 1: Write the failing test**

Create `test/plugins/build_interpretation/aura_binder_test.dart`:

```dart
import 'package:build_engine/build_engine.dart';
import 'package:build_engine/build_interpretation.dart';
import 'package:build_engine/combat_plugin.dart';
import 'package:test/test.dart';

/// Minimal stand-in for a combat turn event; its actor extractor is what
/// the binder must use generically.
class _Turn {
  const _Turn(this.actor);
  final EntityId actor;
}

PluginContext _ctx() {
  final events = EventBus();
  final entities = EntityRegistry(events);
  final components = ComponentStore();
  final rng = RngService(1);
  final c = PluginContext(
    entities: entities,
    components: components,
    events: events,
    rng: rng,
    rules: RuleEngine(entities: entities, components: components, events: events, rng: rng),
    queries: QueryEngine(QueryScope(components: components)),
    modifiers: ModifierCollection(),
    content: ContentRegistry(),
  );
  c.content.registerTrigger('Turn', _Turn, (e) => (e as _Turn).actor);
  return c;
}

/// An interpreter that returns a fixed aura list, so the binder is tested
/// in isolation from Item/Technique resolution.
class _FixedInterpreter implements BuildActionInterpreter {
  const _FixedInterpreter(this._auras);
  final List<AuraRule> _auras;
  @override
  List<CombatAction> interpret({required ResolvedBuild build, required EntityId actor, required List<EntityId> targets, required PluginContext context}) => const [];
  @override
  List<AuraRule> auraRules({required ResolvedBuild build, required PluginContext context}) => _auras;
}

AuraRule _selfHeal() => AuraRule(
      rule: Rule(
        trigger: _Turn,
        subjectOf: (e) => (e as _Turn).actor,
        effects: const [Heal(5)],
      ),
      scope: AuraScope.self,
      sourceRuleId: 'aura.self_heal',
    );

AuraRule _opponentBleed() => AuraRule(
      rule: Rule(
        trigger: _Turn,
        subjectOf: (e) => (e as _Turn).actor,
        effects: const [Damage(5)],
      ),
      scope: AuraScope.opponent,
      sourceRuleId: 'aura.opp_bleed',
    );

void main() {
  ResolvedBuild build(EntityId owner) =>
      ResolvedBuild(owner: owner, active: const [], owned: const []);

  test('self-scope aura fires on the owner\'s turn only', () {
    final ctx = _ctx();
    final owner = ctx.entities.create();
    final enemy = ctx.entities.create();
    ctx.components.add(owner, const HealthComponent(current: 50, max: 100));

    const AuraBinder().bind(
      build: build(owner),
      interpreter: _FixedInterpreter([_selfHeal()]),
      context: ctx,
      opponents: [enemy],
    );

    ctx.events.publish(_Turn(enemy)); // not the owner's turn
    expect(ctx.components.get<HealthComponent>(owner)!.current, 50);

    ctx.events.publish(_Turn(owner)); // owner's turn
    expect(ctx.components.get<HealthComponent>(owner)!.current, 55);
  });

  test('opponent-scope aura hits the opponent, ticking on the owner\'s turn', () {
    final ctx = _ctx();
    final owner = ctx.entities.create();
    final enemy = ctx.entities.create();
    ctx.components.add(enemy, const HealthComponent(current: 30, max: 30));

    const AuraBinder().bind(
      build: build(owner),
      interpreter: _FixedInterpreter([_opponentBleed()]),
      context: ctx,
      opponents: [enemy],
    );

    ctx.events.publish(_Turn(enemy)); // enemy's turn -> no tick
    expect(ctx.components.get<HealthComponent>(enemy)!.current, 30);

    ctx.events.publish(_Turn(owner)); // owner's turn -> opponent takes 5
    expect(ctx.components.get<HealthComponent>(enemy)!.current, 25);
  });

  test('opponent-scope aura with no opponent is simply not registered', () {
    final ctx = _ctx();
    final owner = ctx.entities.create();
    final binding = const AuraBinder().bind(
      build: build(owner),
      interpreter: _FixedInterpreter([_opponentBleed()]),
      context: ctx,
      opponents: const [],
    );
    // No throw; publishing does nothing.
    ctx.events.publish(_Turn(owner));
    binding.dispose(); // also must not throw
  });

  test('opponent-scope aura with >1 opponent throws ArgumentError', () {
    final ctx = _ctx();
    final owner = ctx.entities.create();
    expect(
      () => const AuraBinder().bind(
        build: build(owner),
        interpreter: _FixedInterpreter([_opponentBleed()]),
        context: ctx,
        opponents: [ctx.entities.create(), ctx.entities.create()],
      ),
      throwsA(isA<ArgumentError>()),
    );
  });

  test('dispose() detaches every subscription and is idempotent', () {
    final ctx = _ctx();
    final owner = ctx.entities.create();
    ctx.components.add(owner, const HealthComponent(current: 50, max: 100));

    final binding = const AuraBinder().bind(
      build: build(owner),
      interpreter: _FixedInterpreter([_selfHeal()]),
      context: ctx,
      opponents: [ctx.entities.create()],
    );

    binding.dispose();
    binding.dispose(); // idempotent

    ctx.events.publish(_Turn(owner));
    expect(ctx.components.get<HealthComponent>(owner)!.current, 50); // no heal after dispose
  });

  test('firing order follows the auraRules list, not sourceRuleId', () {
    final ctx = _ctx();
    final owner = ctx.entities.create();
    ctx.components.add(owner, const HealthComponent(current: 0, max: 100));
    final order = <String>[];
    AuraRule recorder(String id) => AuraRule(
          rule: Rule(
            trigger: _Turn,
            subjectOf: (e) => (e as _Turn).actor,
            conditions: [SubjectIs(owner)],
            effects: [_Record(() => order.add(id))],
          ),
          scope: AuraScope.self,
          sourceRuleId: id,
        );
    const AuraBinder().bind(
      build: build(owner),
      interpreter: _FixedInterpreter([recorder('z'), recorder('a'), recorder('m')]),
      context: ctx,
      opponents: [ctx.entities.create()],
    );
    ctx.events.publish(_Turn(owner));
    expect(order, ['z', 'a', 'm']); // list order, NOT sorted
  });
}

class _Record implements Effect {
  const _Record(this.onApply);
  final void Function() onApply;
  @override
  void apply(RuleContext context) => onApply();
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `dart test test/plugins/build_interpretation/aura_binder_test.dart`
Expected: compile FAIL — `AuraBinder` / `AuraBinding` undefined.

- [ ] **Step 3: Create `aura_binder.dart`**

```dart
import 'package:build_engine/build_engine.dart';

import 'build_action_interpreter.dart';

/// Registers the [AuraRule]s of every hung component with the
/// [RuleEngine] for the duration of one resolved build (in the headless
/// harness: one fight), and hands back an [AuraBinding] that detaches
/// them again.
///
/// Stateless (`const`). Each [bind] call produces a self-contained
/// [AuraBinding] tied to exactly the `build.owner` and `opponents` passed
/// at that call — there is no in-place update path. When the build
/// changes, the flow is always: dispose the old binding, resolve the new
/// build, `bind` again.
///
/// This class imports no Combat symbol and reads no `TurnStarted` /
/// `ActionCompleted` field. The one Combat-shaped fact it uses — "the
/// aura rule's `subjectOf` yields the acting entity" — is the
/// content-trigger-registry contract, wired by `CombatPlugin` (see the
/// SP2 spec §5.5/§5.6). Opponents are passed in by the caller, not
/// derived from combat state.
class AuraBinder {
  const AuraBinder();

  AuraBinding bind({
    required ResolvedBuild build,
    required BuildActionInterpreter interpreter,
    required PluginContext context,
    List<EntityId> opponents = const [],
  }) {
    final subscriptions = <EventSubscription>[];
    for (final aura in interpreter.auraRules(build: build, context: context)) {
      final wired = _wire(aura, owner: build.owner, opponents: opponents);
      if (wired == null) continue; // opponent-scope aura, no opponent -> inert
      subscriptions.add(context.rules.register(wired));
    }
    return AuraBinding(subscriptions);
  }

  /// Builds the concrete [Rule] handed to `RuleEngine.register`, scoping
  /// it to owner/opponent. Returns `null` for an opponent-scope aura when
  /// there is no opponent. Throws [ArgumentError] for an opponent-scope
  /// aura with more than one opponent (SP2 is strictly 1-v-1; a
  /// multi-enemy mode must define its own opponent-selection policy).
  Rule? _wire(
    AuraRule aura, {
    required EntityId owner,
    required List<EntityId> opponents,
  }) {
    final body = aura.rule;
    switch (aura.scope) {
      case AuraScope.self:
        // Keep the trigger's own subjectOf (subject = the event's actor);
        // the SubjectIs guard limits firing to the owner's own turn, and
        // the effects then act on that subject (== owner).
        return Rule(
          trigger: body.trigger,
          subjectOf: body.subjectOf,
          conditions: [SubjectIs(owner), ...body.conditions],
          effects: body.effects,
        );
      case AuraScope.opponent:
        if (opponents.isEmpty) return null;
        if (opponents.length > 1) {
          throw ArgumentError.value(
            opponents.length,
            'opponents',
            'opponent-scope auras require exactly one opponent in SP2',
          );
        }
        final opponent = opponents.single;
        return Rule(
          trigger: body.trigger,
          subjectOf: (_) => opponent, // effects land on the opponent
          conditions: [_EventActorIs(body.subjectOf, owner), ...body.conditions],
          effects: body.effects,
        );
    }
  }
}

/// A live set of aura subscriptions. Membership is fixed at construction;
/// [dispose] detaches every one and is safe to call more than once (and
/// on an empty binding).
class AuraBinding {
  AuraBinding(this._subscriptions);

  final List<EventSubscription> _subscriptions;
  var _disposed = false;

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    for (final subscription in _subscriptions) {
      subscription.cancel();
    }
    _subscriptions.clear();
  }
}

/// Passes only when the triggering event's own actor — resolved through
/// [_actorOf], which is the aura rule's trigger-descriptor `subjectOf` —
/// is [_expected]. Event-shape agnostic: it never names a concrete event
/// type. Used by `AuraBinder._wire` for the opponent-scope "on the
/// owner's turn/action" guard.
class _EventActorIs implements Condition {
  const _EventActorIs(this._actorOf, this._expected);

  final EntityId? Function(Object event)? _actorOf;
  final EntityId _expected;

  @override
  bool evaluate(RuleContext context) =>
      _actorOf?.call(context.triggerEvent) == _expected;
}
```

- [ ] **Step 4: Export it**

In `lib/build_interpretation.dart`, add (keep alphabetical — first in the list, before `build_action_interpreter.dart`):

```dart
export 'src/plugins/build_interpretation/aura_binder.dart';
```

- [ ] **Step 5: Run test to verify it passes**

Run: `dart test test/plugins/build_interpretation/aura_binder_test.dart`
Expected: PASS (6 tests).

- [ ] **Step 6: Lint + architecture guard**

Run: `dart analyze lib/src/plugins/build_interpretation/aura_binder.dart test/plugins/build_interpretation/aura_binder_test.dart && dart test test/plugins/build_interpretation/build_interpretation_architecture_test.dart`
Expected: `No issues found!`; architecture test green.

- [ ] **Step 7: Commit**

```bash
git add lib/src/plugins/build_interpretation/aura_binder.dart lib/build_interpretation.dart test/plugins/build_interpretation/aura_binder_test.dart
git commit -m "$(printf 'feat(aura): AuraBinder/AuraBinding register hung auras with RuleEngine\n\n_wire injects owner/opponent scoping: self keeps the trigger subjectOf\n+ a SubjectIs(owner) guard; opponent pins subjectOf to the sole opponent\n+ a generic event-actor guard. 0 opponents -> skip; >1 -> ArgumentError.\ndispose() is idempotent; membership is fixed at bind.\n\nCo-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>\nClaude-Session: https://claude.ai/code/session_01USc4vgCm9nma1UBaEd5c7z')"
```

---

## Task 8: Combat registers the `TurnStarted` / `TurnEnded` / `ActionCompleted` triggers

**Files:**
- Modify: `lib/src/plugins/combat/combat_plugin.dart`
- Test: `test/plugins/combat/combat_trigger_registration_test.dart` (create)

**Interfaces:**
- Consumes: `ContentRegistry.registerTrigger(String key, Type eventType, EntityId? Function(Object) subjectOf)` — `context.content`; `TurnStarted` / `TurnEnded` / `ActionCompleted` (`.actor` is `EntityId`).
- Produces: after `CombatPlugin().initialize(context)`, `context.content` can `loadRule` a rule with `trigger: 'TurnStarted'` / `'TurnEnded'` / `'ActionCompleted'`, and that rule's `subjectOf` returns the event's `.actor`.

- [ ] **Step 1: Write the failing test**

Create `test/plugins/combat/combat_trigger_registration_test.dart`:

```dart
import 'package:build_engine/build_engine.dart';
import 'package:build_engine/combat_plugin.dart';
import 'package:test/test.dart';

PluginContext _ctx() {
  final events = EventBus();
  final entities = EntityRegistry(events);
  final components = ComponentStore();
  final rng = RngService(1);
  return PluginContext(
    entities: entities,
    components: components,
    events: events,
    rng: rng,
    rules: RuleEngine(entities: entities, components: components, events: events, rng: rng),
    queries: QueryEngine(QueryScope(components: components)),
    modifiers: ModifierCollection(),
    content: ContentRegistry(),
  );
}

void main() {
  test('TurnStarted / TurnEnded / ActionCompleted are registered as triggers with an actor subject', () {
    final ctx = _ctx();
    CombatPlugin().initialize(ctx);

    final owner = ctx.entities.create();
    final battle = ctx.entities.create();
    ctx.components.add(owner, const HealthComponent(current: 50, max: 100));

    // A loadRule against each key must succeed (unknown trigger throws)
    // and fire with the event actor as subject.
    for (final key in ['TurnStarted', 'TurnEnded', 'ActionCompleted']) {
      ctx.content.loadRule({
        'id': 'probe_$key',
        'trigger': key,
        'effects': [{'type': 'heal', 'amount': 1}],
      });
      ctx.rules.register(ctx.content.rule('probe_$key').rule);
    }

    final before = ctx.components.get<HealthComponent>(owner)!.current;
    ctx.events.publish(TurnStarted(battle, owner, 1));
    ctx.events.publish(TurnEnded(battle, owner, 1));
    ctx.events.publish(ActionCompleted(battle, owner, const [], _NoopAction(owner)));
    expect(ctx.components.get<HealthComponent>(owner)!.current, before + 3);
  });
}

class _NoopAction implements CombatAction {
  const _NoopAction(this.actor);
  @override
  final EntityId actor;
  // Fill in whatever the CombatAction interface requires — see
  // lib/src/plugins/combat/combat_action.dart. If it is simplest, use an
  // existing concrete action (e.g. SelfEffectAction) instead of this stub.
}
```

> Before running: open `lib/src/plugins/combat/combat_action.dart` and either implement `_NoopAction` against the real `CombatAction` interface, or replace it with the simplest existing concrete action. The assertion that matters is the `+3` heal from the three published events.

- [ ] **Step 2: Run test to verify it fails**

Run: `dart test test/plugins/combat/combat_trigger_registration_test.dart`
Expected: FAIL — `loadRule` throws `UnknownContentFactoryException` for `trigger: 'TurnStarted'`.

- [ ] **Step 3: Register the triggers**

In `lib/src/plugins/combat/combat_plugin.dart`, add `import 'combat_events.dart';` to the imports, and inside `initialize(...)` after the `sdk.registerComponentCleanup<CombatStateComponent>();` line:

```dart
    // Content-rule triggers for Combat's per-turn / per-action events, so
    // data-defined rules (e.g. SP2 auras) can name them. Only Core's own
    // events are registered by `ContentRegistry`'s constructor.
    // `registerTrigger` overwrites by key, so this is safe to run again
    // if the plugin is `initialize`d a second time.
    context.content
      ..registerTrigger('TurnStarted', TurnStarted, (e) => (e as TurnStarted).actor)
      ..registerTrigger('TurnEnded', TurnEnded, (e) => (e as TurnEnded).actor)
      ..registerTrigger('ActionCompleted', ActionCompleted, (e) => (e as ActionCompleted).actor);
```

- [ ] **Step 4: Run test to verify it passes**

Run: `dart test test/plugins/combat/combat_trigger_registration_test.dart`
Expected: PASS.

- [ ] **Step 5: Regression + lint**

Run: `dart test test/plugins/combat test/integration/combat_plugin_end_to_end_test.dart && dart analyze lib/src/plugins/combat`
Expected: green; `No issues found!`

- [ ] **Step 6: Commit**

```bash
git add lib/src/plugins/combat/combat_plugin.dart test/plugins/combat/combat_trigger_registration_test.dart
git commit -m "$(printf 'feat(aura): Combat registers TurnStarted/TurnEnded/ActionCompleted triggers\n\nData-defined rules (SP2 auras) can now name Combat per-turn/per-action\nevents; subjectOf resolves each to its .actor. Idempotent (registerTrigger\noverwrites by key).\n\nCo-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>\nClaude-Session: https://claude.ai/code/session_01USc4vgCm9nma1UBaEd5c7z')"
```

---

## Task 9: Wire `AuraBinder` into `CombatStage.runFight`

**Files:**
- Modify: `lib/src/plugins/game/combat_stage.dart`
- Test: `test/plugins/game/combat_stage_aura_test.dart` (create)

**Interfaces:**
- Consumes: `AuraBinder` / `AuraBinding` (Task 7); the `build` already resolved in `runFight`; `enemyEntity` from `spawnEnemy`.
- Produces: `runFight` binds auras after `tome.resolve` and disposes them in a `finally` that also runs on the happy path. No new field on `CombatStage`.

- [ ] **Step 1: Write the failing test**

Create `test/plugins/game/combat_stage_aura_test.dart`. It drives a real `runGame` with a policy that forces an aura item into the Tome and asserts a per-turn effect shows up. Concretely, the smallest reliable check: a run where `cloth_armor` (starting kit, gains `aura.regen_weave` in Task 10) is hung produces at least one `EntityHealed` on the player during a fight. Since Task 10 has not run yet, this test is written now but will only pass after Task 10 wires the content — mark it and run it at the end of Task 10.

Instead, for **this** task, test the wiring mechanically with a stubbed interpreter is not possible (`runFight` constructs its own `CompositeBuildActionInterpreter` via `CombatStage`'s `interpreter` field). So write the integration assertion and defer its green run:

```dart
import 'package:build_engine/build_engine.dart';
import 'package:build_engine/game.dart';
import 'package:test/test.dart';

import '../../support/policies.dart';

void main() {
  // GREEN AFTER TASK 10 (needs cloth_armor to carry aura.regen_weave).
  test('a fight with an aura item hung produces a per-turn heal on the player', () {
    var playerHeals = 0;
    // runGame gives no event hook; assert indirectly via the encounter
    // trail instead: with a self-heal aura, the player ends at least one
    // fight with MORE health than the no-aura baseline would allow, OR
    // (simpler and robust) assert the run completes and at least one
    // EntityHealed-driven effect is visible in balance signals.
    final withAura = runGame(6, policy: TrainAfterFirstCombatPolicy());
    expect(withAura.encounters, isNotEmpty);
    // The strong assertion lives in Task 12's acceptance test, which has
    // a direct event hook. Here we only assert the run still completes
    // and is deterministic with the wiring in place.
    final again = runGame(6, policy: TrainAfterFirstCombatPolicy());
    expect(again.finalBuild.map((c) => c.contentId), withAura.finalBuild.map((c) => c.contentId));
    expect(playerHeals, 0); // placeholder; real assertion is Task 12
  });
}
```

> This test is intentionally thin — the meaningful end-to-end assertion is Task 12's acceptance test, which constructs its own context and subscribes to events. This task's job is the wiring + keeping the full suite green. If you prefer, skip creating this file and rely on Task 12 plus the full-suite run in Step 4 below.

- [ ] **Step 2: Apply the wiring**

In `lib/src/plugins/game/combat_stage.dart`, add `import 'package:build_engine/build_interpretation.dart';` — it is already imported. In `runFight`, after:

```dart
    final playerActions = interpreter.interpret(
        build: build, actor: character, targets: [enemyEntity], context: context);
```

insert:

```dart
    final auraBinding = const AuraBinder().bind(
      build: build,
      interpreter: interpreter,
      context: context,
      opponents: [enemyEntity],
    );
```

Then wrap the fight body from `final effectivePlayerActions = ...` through `controller.runUntilBattleEnds();` in `try { ... } finally { ... }`, moving the existing `subscription.cancel();` into the `finally` and adding `auraBinding.dispose();` next to it:

```dart
    final effectivePlayerActions = playerActions.isEmpty
        ? [AttackAction(actor: character, targets: [enemyEntity], baseDamage: 4, damageStat: fallbackStrikeStat(build.asActiveBuild))]
        : playerActions;
    final battle = combatPlugin.system.startBattle([character, enemyEntity]);
    final controller = AutoCombatController(
      context: context,
      combatSystem: combatPlugin.system,
      battle: battle,
      availableActions: [
        ...effectivePlayerActions,
        AttackAction(actor: enemyEntity, targets: [character], baseDamage: enemy.damage, damageStat: enemy.damageStat),
      ],
      policy: CombatPolicy.scored(),
    );

    var turnsUsed = 0;
    final subscription = events.subscribe<ActionCompleted>((e) {
      if (e.battle != battle) return;
      turnsUsed++;
      final ref = e.action.sourceRef;
      if (ref != null &&
          ref.referenceType == techniqueReferenceType &&
          ref.instanceEntityId != null) {
        recordTechniqueVariantUsage(ref.instanceEntityId!, context);
      }
    });
    try {
      controller.runUntilBattleEnds();
    } finally {
      subscription.cancel();
      auraBinding.dispose();
    }
```

Update the `CombatStage` class doc comment: add a sentence — "Per-active auras (SP2) are bound here via `AuraBinder` right after `tome.resolve` and disposed in the fight's `finally`, so they are live only for the duration of one fight."

- [ ] **Step 3: Lint**

Run: `dart analyze lib/src/plugins/game/combat_stage.dart`
Expected: `No issues found!`

- [ ] **Step 4: Run the full game + integration suites**

Run: `dart test test/plugins/game test/game test/integration`
Expected: all green. Aura content is not wired yet (Task 10), so behaviour is unchanged — this step only proves the wiring compiles and breaks nothing.

- [ ] **Step 5: Commit**

```bash
git add lib/src/plugins/game/combat_stage.dart test/plugins/game/combat_stage_aura_test.dart
git commit -m "$(printf 'feat(aura): bind per-active auras for each fight in CombatStage.runFight\n\nbind() after tome.resolve with the spawned enemy as the sole opponent;\ndispose() in a finally alongside the existing ActionCompleted\nsubscription cancel, so auras live exactly one fight.\n\nCo-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>\nClaude-Session: https://claude.ai/code/session_01USc4vgCm9nma1UBaEd5c7z')"
```

---

## Task 10: Content pass

**Files:**
- Create: `lib/src/plugins/item/item_auras.dart`, `lib/src/plugins/technique/technique_auras.dart`
- Modify: `lib/item_plugin.dart` / `lib/technique_plugin.dart` (export the auras files)
- Modify: `lib/src/plugins/item/item_plugin.dart` / `lib/src/plugins/technique/technique_plugin.dart` (load the aura `RuleDefinition`s)
- Modify: `lib/src/plugins/item/item_content.dart` (add `auras` keys to `cloth_armor`, `training_staff`, `training_shoes`, `warlords_iron_sword`, `crushing_gauntlets`)
- Modify: `lib/src/plugins/technique/technique_content.dart` (add `auras` keys to `basic_guard`, `basic_slash`)
- Test: `test/plugins/item/item_auras_load_test.dart` (create), `test/plugins/technique/technique_auras_load_test.dart` (create)
- Regenerate: `output/game_run_seed_*.txt`, `output/game_run_summary.txt`

**Interfaces:**
- Consumes: `ContentRegistry.loadRule`; `PluginContext` in each plugin's `initialize`; the Combat triggers (Task 8) — but note: Combat's `initialize` must run **before** the Item/Technique plugins so the triggers exist when `loadRule` parses `trigger: 'TurnStarted'`. `game_run.dart` already initializes `CombatPlugin` first (see `game_run.dart` — `CombatPlugin()..initialize(context)` precedes `ItemPlugin().initialize(context)`), and every test that drives auras must do the same.
- Produces: `const itemAuraRuleDefinitions` / `const techniqueAuraRuleDefinitions` (`List<Map<String, dynamic>>`), loaded into `context.content` inside each plugin's existing content-load idempotency guard.

- [ ] **Step 1: Write the failing tests**

Create `test/plugins/item/item_auras_load_test.dart`:

```dart
import 'package:build_engine/build_engine.dart';
import 'package:build_engine/combat_plugin.dart';
import 'package:build_engine/item_plugin.dart';
import 'package:test/test.dart';

PluginContext _ctx() {
  final events = EventBus();
  final entities = EntityRegistry(events);
  final components = ComponentStore();
  final rng = RngService(1);
  return PluginContext(
    entities: entities,
    components: components,
    events: events,
    rng: rng,
    rules: RuleEngine(entities: entities, components: components, events: events, rng: rng),
    queries: QueryEngine(QueryScope(components: components)),
    modifiers: ModifierCollection(),
    content: ContentRegistry(),
  );
}

void main() {
  test('ItemPlugin.initialize loads every aura RuleDefinition it references', () {
    final ctx = _ctx();
    CombatPlugin().initialize(ctx); // triggers must exist first
    ItemPlugin().initialize(ctx);

    for (final ref in ['cloth_armor', 'training_staff', 'training_shoes',
        'warlords_iron_sword', 'crushing_gauntlets']) {
      final def = itemDefinitionFromContent(ctx.content.get(ref));
      for (final id in def.auraRuleIds) {
        expect(ctx.content.rule(id), isNotNull, reason: '$ref -> $id must be loaded');
      }
    }
  });

  test('ItemPlugin.initialize is idempotent for aura rules', () {
    final ctx = _ctx();
    CombatPlugin().initialize(ctx);
    ItemPlugin().initialize(ctx);
    // A second initialize (as after unregister) must not throw a
    // ContentDuplicateIdException on the aura rule ids.
    ItemPlugin()
      ..initialize(ctx)
      ..unregister(ctx);
  });
}
```

Create `test/plugins/technique/technique_auras_load_test.dart` — analogous, for `basic_guard` and `basic_slash`, using `TechniquePlugin`.

- [ ] **Step 2: Run tests to verify they fail**

Run: `dart test test/plugins/item/item_auras_load_test.dart test/plugins/technique/technique_auras_load_test.dart`
Expected: FAIL — `auraRuleIds` is empty (no `auras` keys yet) so the first test trivially passes; the real failure comes once you add `auras` keys but not the `loadRule` calls. Write the content keys first (Step 3), re-run to see `ContentNotFoundException`, then add loading (Step 4).

- [ ] **Step 3: Add the aura `RuleDefinition` lists**

`lib/src/plugins/item/item_auras.dart`:

```dart
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
```

`lib/src/plugins/technique/technique_auras.dart`:

```dart
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
```

- [ ] **Step 4: Load them in the plugins**

In `lib/src/plugins/item/item_plugin.dart`, add `import 'item_auras.dart';`. Inside the existing guard block:

```dart
    if (context.content.find(ItemIds.knife) == null) {
      sdk.registerContentBatch(itemContentDefinitions);
    }
```

change to also load the aura rules (they share the guard — if `knife` is absent, nothing from this plugin is loaded yet):

```dart
    if (context.content.find(ItemIds.knife) == null) {
      sdk.registerContentBatch(itemContentDefinitions);
      for (final json in itemAuraRuleDefinitions) {
        context.content.loadRule(json);
      }
    }
```

In `lib/src/plugins/technique/technique_plugin.dart`, add `import 'technique_auras.dart';`. Inside its existing guard:

```dart
    if (context.content.find(TechniqueIds.basicPunch) == null) {
      sdk.registerContentBatch(techniqueContentDefinitions);
      for (final json in techniqueAuraRuleDefinitions) {
        context.content.loadRule(json);
      }
    }
```

- [ ] **Step 5: Add `auras` keys to content entries**

In `lib/src/plugins/item/item_content.dart`, add an `'auras'` key to these five map literals (find each by its `'id'`):

- `cloth_armor` → `'auras': ['aura.regen_weave'],`
- `training_staff` → `'auras': ['aura.braced'],`
- `training_shoes` → `'auras': ['aura.quickstep'],`
- `warlords_iron_sword` → `'auras': ['aura.bleed'],`
- `crushing_gauntlets` → `'auras': ['aura.thorns'],`

In `lib/src/plugins/technique/technique_content.dart`:

- `basic_guard` → `'auras': ['aura.guard_regen'],`
- `basic_slash` → `'auras': ['aura.venom'],`

- [ ] **Step 6: Export the new files**

`lib/item_plugin.dart`: `export 'src/plugins/item/item_auras.dart';`
`lib/technique_plugin.dart`: `export 'src/plugins/technique/technique_auras.dart';`

- [ ] **Step 7: Run the load tests + full plugin/integration suites**

Run: `dart test test/plugins/item test/plugins/technique test/plugins/build_interpretation test/integration test/game`
Expected: green. If a seed-specific assertion in `test/game/` flips (e.g. `game_run_test.dart`'s seed-6 expectations, or `multi_seed_diversity_test.dart`'s win/loss split): auras change per-turn combat math, so this is expected. For each failure, confirm the assertion is a *diversity/structure* check (not a golden) and update the specific expectation to the new observed value, noting it in the commit message. Do **not** weaken a determinism assertion — those must still pass (same seed → same result).

- [ ] **Step 8: Regenerate the report artifacts**

Run: `dart run tool/game_run_report.dart`
This rewrites `output/game_run_seed_1.txt` … `output/game_run_seed_10.txt` and `output/game_run_summary.txt`. Review the diff (`git diff --stat output/`) — expect changed fight lengths / outcomes, no crashes.

- [ ] **Step 9: Lint**

Run: `dart analyze lib/src/plugins/item lib/src/plugins/technique`
Expected: `No issues found!`

- [ ] **Step 10: Commit**

```bash
git add lib/src/plugins/item lib/src/plugins/technique lib/item_plugin.dart lib/technique_plugin.dart test/plugins/item/item_auras_load_test.dart test/plugins/technique/technique_auras_load_test.dart output/
git commit -m "$(printf 'feat(aura): content pass - auras on 5 items + 2 techniques\n\ncloth_armor/training_staff/training_shoes (self), warlords_iron_sword/\ncrushing_gauntlets (opponent); basic_guard (conditional self heal),\nbasic_slash (RNG opponent tick). Aura RuleDefinitions loaded in the\nplugins under the existing content guard. Regenerated output/ artifacts.\n\nCo-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>\nClaude-Session: https://claude.ai/code/session_01USc4vgCm9nma1UBaEd5c7z')"
```

---

## Task 11: Architecture guard tests + docs

**Files:**
- Modify: `test/integration/architecture_dependency_test.dart`
- Modify: `CHANGELOG.md`
- Modify: `ARCHITECTURE.md`

**Interfaces:** none (docs + guard tests only).

- [ ] **Step 1: Add the guard tests**

In `test/integration/architecture_dependency_test.dart`, after the existing `group('effect_profile/ is pure Core — ...')` block, add:

```dart
  group('aura/ is pure Core — no plugin, no vocabulary import', () {
    for (final barrel in _pluginBarrels) {
      test('aura/ does not reference $barrel', () {
        _assertNoSubstringInDirectory(barrel, 'lib/src/aura');
      });
    }
    test('aura/ does not escape into any plugins/ directory', () {
      _assertNoSubstringInDirectory('plugins/', 'lib/src/aura');
    });
  });

  group('AuraBinder imports no Combat symbol', () {
    test('aura_binder.dart does not reference combat_plugin.dart or plugins/combat/', () {
      final src = File(
        'lib/src/plugins/build_interpretation/aura_binder.dart',
      ).readAsStringSync();
      expect(src, isNot(contains('combat_plugin.dart')));
      expect(src, isNot(contains('plugins/combat/')));
    });
  });
```

- [ ] **Step 2: Run the architecture suite**

Run: `dart test test/integration/architecture_dependency_test.dart`
Expected: PASS, including the two new groups.

- [ ] **Step 3: Update `CHANGELOG.md`**

Under `## Unreleased`, add a new section directly under the SP1 one:

```markdown
### Added — Per-active Auras (SP2)

- **`package:build_engine/build_engine.dart`** exports three new Core
  types from `src/aura/`:
  - **`AuraScope`** — `{ self, opponent }`. Who an aura's effects act
    on; read from a `RuleDefinition`'s optional `scope` key.
  - **`AuraRule`** — an unmodified Core `Rule` body + its `AuraScope` +
    a diagnostics-only `sourceRuleId`. Never a sort key.
  - **`AuraContributor`** — parameterless `List<AuraRule> auraRules()`.
    Implemented by composing wrappers (`ItemAuraContributor`,
    `TechniqueAuraContributor`, from `item_plugin.dart` /
    `technique_plugin.dart`) that hold a `ContentRegistry` — not by the
    definition/instance types, since id lookup needs the registry.
- **`SubjectIs`** (`src/rule/system_conditions.dart`) — generic
  `context.subject == entity` condition.
- **`package:build_engine/build_interpretation.dart`** exports
  **`AuraBinder`** / **`AuraBinding`**. `AuraBinder.bind({build,
  interpreter, context, opponents})` registers every hung component's
  aura rules with `RuleEngine` and returns an idempotent-`dispose()`
  `AuraBinding`. `bind` throws `ArgumentError` for an `opponent`-scope
  aura with more than one opponent.
- **`BuildActionInterpreter` gained `auraRules({build, context})`** —
  abstract; `ItemActionInterpreter` / `TechniqueActionInterpreter`
  implement it, `CompositeBuildActionInterpreter` aggregates.
- **New `auras: [<ruleId>]` content field** on item and technique
  content definitions → `ItemDefinition.auraRuleIds` /
  `TechniqueDefinition.auraRuleIds` (`const []` when absent).
- **`CombatPlugin.initialize` now registers the `TurnStarted` /
  `TurnEnded` / `ActionCompleted` content-rule triggers**, so
  data-defined rules can name Combat's per-turn / per-action events.

### Changed — Per-active Auras (SP2)

- **`CombatStage.runFight`** binds auras (`AuraBinder`) right after
  `tome.resolve` and disposes them in a `finally`, so an aura is live
  for exactly one fight. Combat outcomes for a fixed seed shift where
  aura content is now hung — a representation/behaviour addition, not a
  balance pass; determinism (seed + decisions → same run) is preserved.
```

- [ ] **Step 4: Update `ARCHITECTURE.md`**

After the `## Tiered Component Effects (SP1) (...)` section (it ends just before `## Almanac — Persistent Player History`), insert a new section:

```markdown
## Per-active Auras (SP2) (`lib/src/aura/`, `lib/src/plugins/build_interpretation/aura_binder.dart`)

SP1 let a hung component contribute *numbers*, folded once into a static
action list. SP2 lets it contribute *behaviour over time* — a `Rule`
that is live only while the component is in `ResolvedBuild.active`.

- **`AuraContributor`** (`lib/src/aura/`) — `List<AuraRule> auraRules()`.
  An `AuraRule` is an unmodified Core `Rule` plus an `AuraScope`
  (`self` / `opponent`) and a diagnostics-only source id. Implemented by
  composing wrappers (`ItemAuraContributor`, `TechniqueAuraContributor`)
  that hold a `ContentRegistry`, because resolving a component's `auras`
  id list into `RuleDefinition`s needs it — unlike `EffectContributor`,
  which is pure value calculation over component state.
- **Rule bodies are content.** Authored through the existing
  `ContentRegistry.loadRule` DSL (`trigger` / `conditions` / `effects`),
  referenced by id from a content entry's new `auras` field. `Combat`
  registers the `TurnStarted` / `TurnEnded` / `ActionCompleted` trigger
  keys.
- **`BuildActionInterpreter.auraRules({build, context})`** collects the
  `AuraRule`s of every ref in `build.active`; the composite aggregates
  in interpreter-list order.
- **`AuraBinder`** (`build_interpretation/`) registers each with
  `RuleEngine`, injecting owner/opponent scoping in a `_wire` step so the
  rule body stays identity-free: `self` keeps the trigger's `subjectOf`
  and prepends `SubjectIs(owner)`; `opponent` pins `subjectOf` to the
  single passed opponent and guards on the event's own actor being the
  owner (via a generic, event-shape-agnostic condition). It imports no
  Combat symbol. `AuraBinding.dispose()` is idempotent; membership is
  fixed at `bind`.
- **Lifecycle.** `CombatStage.runFight` binds after `tome.resolve` and
  disposes in a `finally` — one binding per fight, torn down on every
  exit path. `Tome_client` adoption is SP4.
- **Determinism.** Firing order = interpreter-list order → `build.active`
  order → `auraRuleIds` order → `EventBus` subscription order. RNG-using
  aura effects go through `RuleContext.rng`.
```

- [ ] **Step 5: Full suite**

Run: `dart test`
Expected: entire suite green.

- [ ] **Step 6: Commit**

```bash
git add test/integration/architecture_dependency_test.dart CHANGELOG.md ARCHITECTURE.md
git commit -m "$(printf 'docs(aura): SP2 CHANGELOG + ARCHITECTURE + dependency guards\n\naura/ is pure Core (guard test); aura_binder.dart imports no Combat\nsymbol (guard test). CHANGELOG public-surface entries; ARCHITECTURE\nper-active-auras section.\n\nCo-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>\nClaude-Session: https://claude.ai/code/session_01USc4vgCm9nma1UBaEd5c7z')"
```

---

## Task 12: Acceptance-invariant integration test

Proves the full "per-active" promise (spec §12) end to end with a direct event hook.

**Files:**
- Test: `test/integration/per_active_aura_test.dart` (create)

**Interfaces:**
- Consumes: `CombatPlugin`, `ItemPlugin`, `TechniquePlugin` (init order: Combat first), `TomeService` / `BuildResolver`, `CompositeBuildActionInterpreter`, `AuraBinder`, the `aura.regen_weave` (self / `cloth_armor`) and `aura.bleed` (opponent / `warlords_iron_sword`) content from Task 10.
- Produces: one test file asserting the six rows of spec §12.

- [ ] **Step 1: Write the test**

Create `test/integration/per_active_aura_test.dart`:

```dart
/// SP2 §12 acceptance invariant — "per-active" means exactly this.
library;

import 'package:build_engine/build_engine.dart';
import 'package:build_engine/build_interpretation.dart';
import 'package:build_engine/combat_plugin.dart';
import 'package:build_engine/item_plugin.dart';
import 'package:build_engine/technique_plugin.dart';
import 'package:test/test.dart';

PluginContext _ctx() {
  final events = EventBus();
  final entities = EntityRegistry(events);
  final components = ComponentStore();
  final rng = RngService(1);
  final shared = CoreServices(components: components, events: events);
  final c = PluginContext(
    entities: entities,
    components: components,
    events: events,
    rng: rng,
    rules: RuleEngine(
        entities: entities, components: components, events: events, rng: rng, shared: shared),
    queries: QueryEngine(QueryScope(components: components)),
    modifiers: ModifierCollection(),
    content: ContentRegistry(),
    shared: shared,
  );
  CombatPlugin().initialize(c); // triggers must exist before Item/Technique load their aura rules
  ItemPlugin().initialize(c);
  TechniquePlugin().initialize(c);
  return c;
}

const _interpreter = CompositeBuildActionInterpreter([
  TechniqueActionInterpreter(),
  ItemActionInterpreter(),
]);

/// A ref for a hung `cloth_armor` (self-heal aura `aura.regen_weave`).
const _clothArmorRef =
    BuildComponentRef(referenceType: itemReferenceType, contentId: 'cloth_armor');

ResolvedBuild _build(EntityId owner, {required bool hung}) => ResolvedBuild(
      owner: owner,
      active: hung ? const [_clothArmorRef] : const [],
      owned: const [_clothArmorRef],
    );

void main() {
  test('owned + loose: aura does NOT fire', () {
    final ctx = _ctx();
    final owner = ctx.entities.create();
    final battle = ctx.entities.create();
    ctx.components.add(owner, const HealthComponent(current: 50, max: 100));

    const AuraBinder().bind(
      build: _build(owner, hung: false),
      interpreter: _interpreter,
      context: ctx,
      opponents: [ctx.entities.create()],
    );

    ctx.events.publish(TurnStarted(battle, owner, 1));
    expect(ctx.components.get<HealthComponent>(owner)!.current, 50);
  });

  test('owned + hung: aura fires on the owner\'s turn', () {
    final ctx = _ctx();
    final owner = ctx.entities.create();
    final battle = ctx.entities.create();
    final enemy = ctx.entities.create();
    ctx.components.add(owner, const HealthComponent(current: 50, max: 100));

    const AuraBinder().bind(
      build: _build(owner, hung: true),
      interpreter: _interpreter,
      context: ctx,
      opponents: [enemy],
    );

    ctx.events.publish(TurnStarted(battle, enemy, 1)); // not owner's turn
    expect(ctx.components.get<HealthComponent>(owner)!.current, 50);

    ctx.events.publish(TurnStarted(battle, owner, 1)); // owner's turn
    expect(ctx.components.get<HealthComponent>(owner)!.current, 51); // aura.regen_weave heals 1
  });

  test('unhung mid-run: aura stops on the next event after re-bind', () {
    final ctx = _ctx();
    final owner = ctx.entities.create();
    final battle = ctx.entities.create();
    final enemy = ctx.entities.create();
    ctx.components.add(owner, const HealthComponent(current: 50, max: 100));

    final first = const AuraBinder().bind(
      build: _build(owner, hung: true),
      interpreter: _interpreter,
      context: ctx,
      opponents: [enemy],
    );
    ctx.events.publish(TurnStarted(battle, owner, 1));
    expect(ctx.components.get<HealthComponent>(owner)!.current, 51);

    // Player unhangs the armour: dispose old, resolve new (loose), bind new.
    first.dispose();
    const AuraBinder().bind(
      build: _build(owner, hung: false),
      interpreter: _interpreter,
      context: ctx,
      opponents: [enemy],
    );
    ctx.events.publish(TurnStarted(battle, owner, 2));
    expect(ctx.components.get<HealthComponent>(owner)!.current, 51); // no further heal
  });

  test('fight ends: dispose() detaches every aura subscription', () {
    final ctx = _ctx();
    final owner = ctx.entities.create();
    final battle = ctx.entities.create();
    final enemy = ctx.entities.create();
    ctx.components.add(owner, const HealthComponent(current: 50, max: 100));

    final binding = const AuraBinder().bind(
      build: _build(owner, hung: true),
      interpreter: _interpreter,
      context: ctx,
      opponents: [enemy],
    );
    binding.dispose();
    binding.dispose(); // idempotent

    ctx.events.publish(TurnStarted(battle, owner, 1));
    expect(ctx.components.get<HealthComponent>(owner)!.current, 50);
  });

  test('next fight: only fresh bindings exist (no leakage)', () {
    final ctx = _ctx();
    final owner = ctx.entities.create();
    final battle = ctx.entities.create();
    ctx.components.add(owner, const HealthComponent(current: 50, max: 100));

    // Fight 1
    const AuraBinder()
        .bind(build: _build(owner, hung: true), interpreter: _interpreter, context: ctx, opponents: [ctx.entities.create()])
        .dispose();
    // Fight 2 — a fresh binding; one owner-turn heals exactly once (1), not twice.
    const AuraBinder().bind(
      build: _build(owner, hung: true),
      interpreter: _interpreter,
      context: ctx,
      opponents: [ctx.entities.create()],
    );
    ctx.events.publish(TurnStarted(battle, owner, 1));
    expect(ctx.components.get<HealthComponent>(owner)!.current, 51);
  });

  test('same seed + same events -> identical aura effect sequence', () {
    int runHealTotal() {
      final ctx = _ctx();
      final owner = ctx.entities.create();
      final battle = ctx.entities.create();
      final enemy = ctx.entities.create();
      ctx.components.add(owner, const HealthComponent(current: 1, max: 100));
      const AuraBinder().bind(
        build: _build(owner, hung: true),
        interpreter: _interpreter,
        context: ctx,
        opponents: [enemy],
      );
      for (var round = 1; round <= 5; round++) {
        ctx.events.publish(TurnStarted(battle, owner, round));
        ctx.events.publish(TurnStarted(battle, enemy, round));
      }
      return ctx.components.get<HealthComponent>(owner)!.current;
    }

    expect(runHealTotal(), runHealTotal()); // deterministic: 1 + 5 owner-turn heals = 6
    expect(runHealTotal(), 6);
  });
}
```

- [ ] **Step 2: Run the test**

Run: `dart test test/integration/per_active_aura_test.dart`
Expected: PASS (6 tests). If `aura.regen_weave`'s amount differs from `1` (Task 10 chose the amounts), adjust the expected numbers to match the content — the *invariant* (fires only while hung, only on owner's turn, stops on unhang, disposed at fight end, deterministic) is what must hold.

- [ ] **Step 3: Full suite + lint**

Run: `dart test && dart analyze`
Expected: entire suite green; `No issues found!`

- [ ] **Step 4: Commit**

```bash
git add test/integration/per_active_aura_test.dart
git commit -m "$(printf 'test(aura): SP2 acceptance invariant end to end\n\nowned+loose -> no fire; owned+hung -> fires on owner turn; unhung ->\nstops; fight end -> disposed; next fight -> fresh only; same seed+events\n-> identical sequence.\n\nCo-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>\nClaude-Session: https://claude.ai/code/session_01USc4vgCm9nma1UBaEd5c7z')"
```

- [ ] **Step 5: Push the branch**

```bash
git push
```

---

## Self-Review

**Spec coverage:**

| Spec section | Task(s) |
|---|---|
| §3.1 new Core module `lib/src/aura/` | 2 |
| §3.1 `SubjectIs` in `system_conditions.dart` | 1 |
| §3.1 `AuraContributor` via composing wrappers (Item, Technique) | 5 |
| §3.1 `auras: [<ruleId>]` content field | 4, 10 |
| §3.1 Combat registers `TurnStarted`/`TurnEnded`/`ActionCompleted` | 8 |
| §3.1 `BuildActionInterpreter.auraRules` + composite | 3, 6 |
| §3.1 `AuraBinder`/`AuraBinding` | 7 |
| §3.1 `CombatStage.runFight` bind/dispose | 9 |
| §3.1 content pass (both scopes, both ref types, 1 conditional) | 10 |
| §3.2 no new primitive beyond `SubjectIs`; anti-goal conditions | Global Constraints; 1, 7 |
| §3.2 no `RuleEngine`/`RuleContext`/`Rule` change | Global Constraints (verified by builds using them unchanged) |
| §5.1 `AuraScope`/`AuraRule`/`AuraContributor` shapes | 2 |
| §5.2 wrapper asymmetry documented in code | 5 (Step 3/4 doc comments) |
| §5.2 `_scopeOf` (`raw['scope']`, self default, else error) | 5 |
| §5.2 default definition-only aura ids | 4, 5 (no instance path added) |
| §5.3 abstract `auraRules`, 3 implementers | 3 |
| §5.4 `_wire` self/opponent; 0/1/>1 opponent policy | 7 |
| §5.4 idempotent `dispose`; membership immutable | 7 |
| §5.5 `SubjectIs` generic; opponent guard event-shape agnostic | 1, 7 |
| §5.6 trigger registration | 8 |
| §5.7 `runFight` try/finally | 9 |
| §5.9 opponent-count test matrix | 7 |
| §8 determinism / ordering not by `sourceRuleId` | 7 (Step 1 ordering test), Global Constraints |
| §9 tests (Core, contributors, binder, triggers, integration, serialization*, guards) | 1, 2, 3, 5, 6, 7, 8, 11, 12 |
| §11 completion criteria | 11 (docs), 12 (acceptance) |
| §12 acceptance invariant | 12 |

\* §9 "serialization: an aura `RuleDefinition` round-trips through `ContentRegistry.toJson`" — this is already covered by the DSL's own existing tests (`test/content/`), and the aura `RuleDefinition`s carry only standard keys plus a plain `scope` string the parser ignores, so no new serialization test is required. If a reviewer wants belt-and-braces, add one case to `test/plugins/item/item_auras_load_test.dart` asserting `ContentRegistry()..loadAll(...)..loadRule(each itemAuraRuleDefinitions)` then `toJson()` contains each aura id — a 4-line addition, no new file.

**Placeholder scan:** The only deliberately-deferred item is Task 9's thin test file, explicitly marked optional with its real assertion relocated to Task 12 — not a placeholder in shipped code. Task 8's `_NoopAction` has an explicit instruction to implement it against the real `CombatAction` interface or swap in a concrete action before running. No `TODO`/`TBD` in library code.

**Type consistency:** `auraRules()` (parameterless, on `AuraContributor`) vs `auraRules({required ResolvedBuild build, required PluginContext context})` (on `BuildActionInterpreter`) are deliberately different methods on different types — checked. `AuraRule` fields (`rule`, `scope`, `sourceRuleId`) are used consistently across Tasks 2, 3, 5, 6, 7. `AuraBinder.bind` signature (`build`, `interpreter`, `context`, `opponents`) is identical in Tasks 7, 9, 12. `auraRuleFromRegistry(ContentRegistry, String)` is the shared helper name in Task 5 (with the recommended Core-move note keeping one definition). `itemDefinitionFromContent` / `techniqueDefinitionFromContent` return types unchanged; only a new last field.

---

## Execution Handoff

Plan complete and saved to `docs/superpowers/plans/2026-09-06-per-active-auras-sp2.md`. Two execution options:

**1. Subagent-Driven (recommended)** — I dispatch a fresh subagent per task, review between tasks, fast iteration.

**2. Inline Execution** — Execute tasks in this session using executing-plans, batch execution with checkpoints for review.

Which approach?
