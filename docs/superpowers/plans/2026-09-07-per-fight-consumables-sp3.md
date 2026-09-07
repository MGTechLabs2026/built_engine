# Per-fight Consumables (SP3) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A hung `consumable` component produces a `CombatAction` the headless auto-combat can choose, limited to N per-fight charges (refreshed each battle), with the AI choosing *when* by the effect's shape — reusing `ConsumeResource` / `ScoredActionSelector` / `CombatSystem`.

**Architecture:** A new Core-only `ConsumablePlugin` (mirrors `ItemPlugin`) owns `referenceType: 'consumable'`. Charges are a per-fight `ResourcePool` resource (`consumable:<id>`, defined `max: double.infinity`): the consumable's action carries `costEffects: [ConsumeResource('consumable:<id>', 1)]` and the existing `ScoredActionSelector._isAvailable` / `CombatSystem.executeAction` do the filter + spend. `ConsumableActionInterpreter` (in `build_interpretation/`, added to `game_run`'s composite) turns each hung consumable into a `SelfEffectAction` / `AttackAction`. `ConsumableBinder`/`ConsumableCharges` (sibling of SP2's `AuraBinder`) sums per-copy charges at fight start and zeroes pools + removes `consumable:*` modifiers at fight end. `ConsumableAwareActionScorer` (`auto_combat/`) composes `DefaultActionScorer` and adds a missing-HP-scaled bonus per `Heal` and a flat bonus per `ApplyStatus` found in `action.effectsFor(...)`. Two new generic Core `Effect`s — `RemoveAllStatuses` and `GrantModifier` — the latter requiring one new field, `RuleContext.modifiers`.

**Tech Stack:** Dart 3.7 (`sdk: ^3.7.0`), `package:test` 1.25, `lints` 5. No new dependencies. `dart test <path>` / `dart analyze <paths>`.

**Spec:** `docs/superpowers/specs/2026-09-07-per-fight-consumables-sp3-design.md` — read it alongside this plan; `§` references point into it.

## Global Constraints

- **New Core surface is exactly**: `RemoveAllStatuses` (`Effect`), `GrantModifier` (`Effect`), `RuleContext.modifiers` (one field), `'removeAllStatuses'` content factory. Nothing else. No new `CombatAction` subclass. (spec §3, §11)
- **No `RuleEngine` change. No `Rule` change. No `CombatSystem` change.** `RuleEngine._fire` keeps building its `RuleContext` without a real `ModifierCollection` (default empty). (spec §3.2, §5.4)
- **`GrantModifier` must never appear in `Rule` / `loadRule` / SP2-aura content** — in a `RuleEngine._fire` context its `context.modifiers` is unobserved and it silently no-ops. There is deliberately **no `'grantModifier'` content factory**. (spec §5.4 callout)
- **Charge resource `max` is `double.infinity`.** `ConsumableDefinition.charges` is per-copy capacity; the `consumable:<id>` pool holds the aggregate (Σ over hung copies). A finite `max` would clamp the sum. `ResourcePool.set(owner, key, 3)` must leave the value at `3`. (spec §5.1.1)
- **Content validation is strict and at parse time.** `consumableDefinitionFromContent` produces **exactly one** `ConsumableEffectSpec` or throws `ContentFieldException`; `ConsumablePlugin.initialize` wraps per-entry as `ContentValidationException(id, e)` — byte-for-byte `ContentRegistry._parse`'s pattern. Zero/multiple variants, unknown keys, malformed nested objects, wrong types, negative amounts, and any `effect` × `target` pairing outside §5.1.2 all throw. No "first key wins". (spec §5.1.2, §5.1.3)
- **`effect` × `target`**: `heal` / `grantModifier` / `removeAllStatuses` → `self` only; `attack` → `enemy` only. `ConsumableDefinition.target` has no blanket default — the parser resolves it (from content `target` if present, validated; else the effect's only legal value). (spec §5.1.2)
- **`grant()` is not in-place reconciliation.** A placement change is applied by `dispose()` old `ConsumableCharges` → resolve new build → `grant()` again. `grant()` twice without an intervening `dispose()` is unsupported. (spec §5.5)
- **`runFight` per-fight setup is exception-safe as a unit** — every binder call inside one `try`, nullable locals, reverse-order disposal in `finally`; a throw in `ConsumableBinder.grant` after `AuraBinder.bind` still disposes the aura binding. (spec §5.7)
- **Consumables**: reward-pool only (not starting kit); no `EffectProfile` passive tier; not `AuraContributor`s; player-only (no enemy consumables). (spec §3.2)
- **Determinism is mandatory.** No new randomness. `test/game/` determinism assertions (same seed twice / seed + replayed decisions → identical result) must still pass — a failure there is a real bug, STOP. Diversity/structure assertions updated to observed values if they flip. (spec §8)
- Commit after every task. Conventional-commit messages. Branch: `per-fight-consumables-sp3` (exists; spec commits already on it).
- Every commit message ends with:
  ```
  Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
  Claude-Session: https://claude.ai/code/session_01USc4vgCm9nma1UBaEd5c7z
  ```

## Spec deviations found during planning (apply as written here)

1. **Spec §5.2 says "`AttackAction` / `SelfEffectAction` … already carry … `priority`".** They do **not** — `CombatAction.priority` is a getter defaulting to `0`, not a constructor parameter, and neither concrete action overrides it. **Task 5 adds an optional `this.priority = 0` constructor param + `@override final num priority;` to both `AttackAction` and `SelfEffectAction`** (behaviour-neutral: default `0`; every existing call site is unaffected). The consumable interpreter then passes `priority: consumable.priority`.
2. **`swift_draught` is dropped** — the spec's own §7 note allows a 4-consumable set; a second grant-modifier consumable adds no mechanism coverage (heal / attack / grantModifier / removeAllStatuses is complete at 4) and only reintroduces the "which stat does it touch" ambiguity. Shipped set: `heal_potion`, `firebomb`, `power_tonic`, `cleanse_tonic`.
3. **`ConsumableEffectSpec` is a Dart 3 `sealed class`** (four subclasses) — chosen from the spec's "sealed class hierarchy or a tagged value object" so the interpreter's `switch` is exhaustive.

---

## File Structure

**New — Core:**
- `lib/src/rule/effect.dart` — MODIFY: add `RemoveAllStatuses` and `GrantModifier` classes (+ imports).
- `lib/src/rule/rule_context.dart` — MODIFY: `modifiers` field (optional factory param, default `ModifierCollection()`).
- `lib/src/plugin/plugin_context.dart` — MODIFY: `ruleContextFor` passes `modifiers: modifiers`.
- `lib/src/content/built_in_content_factories.dart` — MODIFY: register `'removeAllStatuses'`.

**New — consumable plugin (`lib/src/plugins/consumable/`):**
- `consumable_vocabulary.dart` — `consumableReferenceType`, `consumableChargeResource(String)`, `ConsumableIds`.
- `consumable_definition.dart` — `ConsumableDefinition`, `ConsumableTarget`, sealed `ConsumableEffectSpec` + 4 subclasses.
- `consumable_content.dart` — `consumableContentDefinitions`, `consumableDefinitionFromContent`, `consumableDefinition(id, context)`.
- `consumable_plugin.dart` — `ConsumablePlugin`.
- `lib/consumable_plugin.dart` — barrel.

**New — build_interpretation:**
- `lib/src/plugins/build_interpretation/consumable_action_interpreter.dart` — `ConsumableActionInterpreter`.
- `lib/src/plugins/build_interpretation/consumable_binder.dart` — `ConsumableBinder`, `ConsumableCharges`.
- `lib/build_interpretation.dart` — MODIFY: export both.

**New — auto_combat:**
- `lib/src/plugins/auto_combat/consumable_aware_action_scorer.dart` — `ConsumableAwareActionScorer`.
- `lib/auto_combat_plugin.dart` — MODIFY: export it.

**New — combat_action `priority` param:**
- `lib/src/plugins/combat/combat_action.dart` — MODIFY: `AttackAction` gains `priority`.
- `lib/src/plugins/build_interpretation/self_effect_action.dart` — MODIFY: `SelfEffectAction` gains `priority`.

**Modified — game composition:**
- `lib/src/plugins/game/game_run.dart` — init `ConsumablePlugin`; composite `+ ConsumableActionInterpreter()`; `rewardPool` `+ consumables`.
- `lib/src/plugins/game/combat_stage.dart` — exception-safe `runFight`; `CombatPolicy.scored(scorer: const ConsumableAwareActionScorer())`.
- `lib/src/plugins/game/reward_stage.dart` — `consumable` branch in `resolveReward`.
- `lib/src/plugins/game/tome_manager.dart` — `placeConsumable`.
- `lib/src/plugins/game/run_content.dart` — `rewardPoolConsumableIds`.

**Modified — guards/docs/artifacts:**
- `test/integration/architecture_dependency_test.dart` — `consumable/` guard.
- `CHANGELOG.md`, `ARCHITECTURE.md`.
- `output/game_run_seed_*.txt`, `output/game_run_summary.txt` — regenerated (gitignored; regeneration confirms the run + measures effect, nothing to commit).

---

## Task 1: `RemoveAllStatuses` Effect + `'removeAllStatuses'` factory

**Files:**
- Modify: `lib/src/rule/effect.dart`
- Modify: `lib/src/content/built_in_content_factories.dart`
- Test: `test/rule/remove_all_statuses_test.dart` (create)

**Interfaces:**
- Consumes: `Effect`, `RuleContext` (`.subject`, `.components`), `StatusComponent`, `ComponentStore.remove<T>`.
- Produces: `class RemoveAllStatuses implements Effect { const RemoveAllStatuses(); }` — exported via the existing `export 'src/rule/effect.dart';` in `lib/build_engine.dart`. Content factory key `'removeAllStatuses'` (no params).

- [ ] **Step 1: Write the failing test**

Create `test/rule/remove_all_statuses_test.dart`:

```dart
import 'package:build_engine/build_engine.dart';
import 'package:test/test.dart';

class _Evt {
  const _Evt();
}

RuleContext _ctx(EntityId? subject, ComponentStore components) {
  final events = EventBus();
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
  test('clears a multi-status StatusComponent', () {
    final components = ComponentStore();
    const owner = EntityId(1);
    components.add(owner, StatusComponent({'status:poison', 'status:burn'}));

    const RemoveAllStatuses().apply(_ctx(owner, components));

    expect(components.get<StatusComponent>(owner), isNull);
  });

  test('no-op when the subject has no StatusComponent', () {
    final components = ComponentStore();
    const owner = EntityId(1);
    expect(() => const RemoveAllStatuses().apply(_ctx(owner, components)),
        returnsNormally);
    expect(components.get<StatusComponent>(owner), isNull);
  });

  test('no-op on a null subject', () {
    final components = ComponentStore();
    expect(() => const RemoveAllStatuses().apply(_ctx(null, components)),
        returnsNormally);
  });

  test("the 'removeAllStatuses' content factory parses a bare entry", () {
    final registry = ContentRegistry();
    registry.registerTrigger('Evt', _Evt, (e) => const EntityId(1));
    final rule = registry.loadRule({
      'id': 'r.clear',
      'trigger': 'Evt',
      'effects': [
        {'type': 'removeAllStatuses'},
      ],
    });
    expect(rule.rule.effects.single, isA<RemoveAllStatuses>());
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `dart test test/rule/remove_all_statuses_test.dart`
Expected: compile FAIL — `RemoveAllStatuses` undefined.

- [ ] **Step 3: Add the class**

In `lib/src/rule/effect.dart`, after the `RemoveStatus` class (it ends around line 146, before `class AddTag`), add:

```dart
/// Clears every active status on the subject — removes its
/// [StatusComponent] outright. No-op if the subject has none, or if there
/// is no subject. The wholesale counterpart to [RemoveStatus]'s
/// single-key removal, for a "cleanse" / "dispel all" action with no need
/// to enumerate names.
class RemoveAllStatuses implements Effect {
  const RemoveAllStatuses();

  @override
  void apply(RuleContext context) {
    final subject = context.subject;
    if (subject == null) return;
    context.components.remove<StatusComponent>(subject);
  }
}
```

(`status_component.dart` is already imported at the top of `effect.dart`.)

- [ ] **Step 4: Register the content factory**

In `lib/src/content/built_in_content_factories.dart`, in `_registerBuiltInEffectFactories`, after the `'transformEntity'` line add:

```dart
  registry.registerEffectFactory(
      'removeAllStatuses', (p) => const RemoveAllStatuses());
```

(`effect.dart` is already imported there.)

- [ ] **Step 5: Run test to verify it passes**

Run: `dart test test/rule/remove_all_statuses_test.dart`
Expected: PASS (4 tests).

- [ ] **Step 6: Regression + lint**

Run: `dart test test/rule test/content && dart analyze lib/src/rule/effect.dart lib/src/content/built_in_content_factories.dart test/rule/remove_all_statuses_test.dart`
Expected: green; `No issues found!`

- [ ] **Step 7: Commit**

```bash
git add lib/src/rule/effect.dart lib/src/content/built_in_content_factories.dart test/rule/remove_all_statuses_test.dart
git commit -m "$(printf 'feat(consumable): RemoveAllStatuses effect + removeAllStatuses factory\n\nClears the subject StatusComponent. Generic Core Effect, no-op on\nabsent component / null subject. Registered as a content factory too.\n\nCo-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>\nClaude-Session: https://claude.ai/code/session_01USc4vgCm9nma1UBaEd5c7z')"
```

---

## Task 2: `RuleContext.modifiers` field

Behaviour-neutral: an optional factory param defaulting to a fresh `ModifierCollection`; `ruleContextFor` supplies the real one. `RuleEngine._fire` unchanged.

**Files:**
- Modify: `lib/src/rule/rule_context.dart`
- Modify: `lib/src/plugin/plugin_context.dart`
- Test: `test/rule/rule_context_modifiers_test.dart` (create)

**Interfaces:**
- Consumes: `ModifierCollection` (`lib/src/modifier/modifier_collection.dart`).
- Produces: `RuleContext.modifiers` (non-null `ModifierCollection`); factory param `ModifierCollection? modifiers` (default `ModifierCollection()`); `PluginContextRuleContext.ruleContextFor(...)` passes the `PluginContext`'s own `modifiers`.

- [ ] **Step 1: Write the failing test**

Create `test/rule/rule_context_modifiers_test.dart`:

```dart
import 'package:build_engine/build_engine.dart';
import 'package:test/test.dart';

class _Evt {
  const _Evt();
}

void main() {
  test('RuleContext.modifiers defaults to a fresh ModifierCollection when unsupplied', () {
    final events = EventBus();
    final ctx = RuleContext(
      subject: null,
      triggerEvent: const _Evt(),
      entities: EntityRegistry(events),
      components: ComponentStore(),
      events: events,
      rng: RngService(1),
      eventCounts: EventCounter(events),
    );
    expect(ctx.modifiers, isA<ModifierCollection>());
  });

  test('ruleContextFor supplies the PluginContext own ModifierCollection (identity)', () {
    final events = EventBus();
    final entities = EntityRegistry(events);
    final components = ComponentStore();
    final rng = RngService(1);
    final modifiers = ModifierCollection();
    final context = PluginContext(
      entities: entities,
      components: components,
      events: events,
      rng: rng,
      rules: RuleEngine(entities: entities, components: components, events: events, rng: rng),
      queries: QueryEngine(QueryScope(components: components)),
      modifiers: modifiers,
      content: ContentRegistry(),
    );
    final ruleContext = context.ruleContextFor(const EntityId(1));
    expect(identical(ruleContext.modifiers, modifiers), isTrue);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `dart test test/rule/rule_context_modifiers_test.dart`
Expected: compile FAIL — `RuleContext.modifiers` / factory param undefined.

- [ ] **Step 3: Add the field**

In `lib/src/rule/rule_context.dart`:

Add the import (keep sorted — after `import '../mastery/mastery_tracker.dart';`):
```dart
import '../modifier/modifier_collection.dart';
```

In the `factory RuleContext({...})` param list, add `ModifierCollection? modifiers,` (place it after `required EventCounter eventCounts,`, before `ResourcePool? resources,`).

In the factory body's `return RuleContext._(...)`, add `modifiers: modifiers ?? ModifierCollection(),` (place after `eventCounts: eventCounts,`).

In the `RuleContext._({...})` private constructor param list, add `required this.modifiers,` (after `required this.eventCounts,`).

In the fields block, add after `final EventCounter eventCounts;`:
```dart

  /// The Modifier Engine. Supplied real by `PluginContext.ruleContextFor`
  /// (so a `CombatAction`'s effects, run by `CombatSystem`, can grant
  /// modifiers — see `GrantModifier`). A `RuleContext` built without one
  /// — including `RuleEngine._fire`'s — gets a fresh, unobserved
  /// `ModifierCollection`: do not rely on `GrantModifier` inside a
  /// `RuleEngine`-dispatched `Rule` (SP3 spec §5.4).
  final ModifierCollection modifiers;
```

- [ ] **Step 4: Wire `ruleContextFor`**

In `lib/src/plugin/plugin_context.dart`, in the `ruleContextFor` extension method's `RuleContext(...)` call, add `modifiers: modifiers,` (place after `eventCounts: rules.eventCounts,`).

- [ ] **Step 5: Run test + regression**

Run: `dart test test/rule test/plugin_context_test.dart && dart analyze lib/src/rule/rule_context.dart lib/src/plugin/plugin_context.dart`
Expected: new test PASS (2); every existing `RuleContext` / `ruleContextFor` test still green (the param is optional); `No issues found!`

- [ ] **Step 6: Full suite (this touches a central type)**

Run: `dart test`
Expected: entire suite green — no behaviour change.

- [ ] **Step 7: Commit**

```bash
git add lib/src/rule/rule_context.dart lib/src/plugin/plugin_context.dart test/rule/rule_context_modifiers_test.dart
git commit -m "$(printf 'feat(consumable): RuleContext.modifiers field\n\nOptional factory param, defaults to a fresh ModifierCollection;\nruleContextFor supplies the PluginContext own. RuleEngine._fire\nunchanged (gets the empty default). Behaviour-neutral.\n\nCo-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>\nClaude-Session: https://claude.ai/code/session_01USc4vgCm9nma1UBaEd5c7z')"
```

---

## Task 3: `GrantModifier` Effect

**Files:**
- Modify: `lib/src/rule/effect.dart`
- Test: `test/rule/grant_modifier_test.dart` (create)

**Interfaces:**
- Consumes: `Effect`, `RuleContext` (`.subject`, `.modifiers`), `Modifier`, `ModifierSource`, `ModifierOperation`, `ModifierCollection` (`removeBySource`, `add`, `activeModifiersFor`).
- Produces: `class GrantModifier implements Effect { const GrantModifier(String stat, ModifierOperation operation, num value, {int priority = 0, String sourceKey = 'grantmodifier'}); }` — exported via `effect.dart`. **Not** a content factory.

- [ ] **Step 1: Write the failing test**

Create `test/rule/grant_modifier_test.dart`:

```dart
import 'package:build_engine/build_engine.dart';
import 'package:test/test.dart';

class _Evt {
  const _Evt();
}

RuleContext _ctx(EntityId? subject, {ModifierCollection? modifiers}) {
  final events = EventBus();
  return RuleContext(
    subject: subject,
    triggerEvent: const _Evt(),
    entities: EntityRegistry(events),
    components: ComponentStore(),
    events: events,
    rng: RngService(1),
    eventCounts: EventCounter(events),
    modifiers: modifiers,
  );
}

void main() {
  test('apply adds one source-scoped Modifier on the subject', () {
    final modifiers = ModifierCollection();
    const owner = EntityId(7);
    const GrantModifier('thrown', ModifierOperation.add, 6, sourceKey: 'consumable:power_tonic')
        .apply(_ctx(owner, modifiers: modifiers));

    final active = modifiers
        .activeModifiersFor(owner, 'thrown', ComponentStore())
        .toList();
    expect(active, hasLength(1));
    expect(active.single.value, 6);
    expect(active.single.source, const ModifierSource('consumable:power_tonic:7'));
  });

  test('re-apply with the same subject + sourceKey replaces, never stacks', () {
    final modifiers = ModifierCollection();
    const owner = EntityId(7);
    const g = GrantModifier('thrown', ModifierOperation.add, 6, sourceKey: 'consumable:power_tonic');
    g.apply(_ctx(owner, modifiers: modifiers));
    g.apply(_ctx(owner, modifiers: modifiers));

    expect(modifiers.activeModifiersFor(owner, 'thrown', ComponentStore()).length, 1);
  });

  test('no-op on a null subject', () {
    final modifiers = ModifierCollection();
    expect(
      () => const GrantModifier('x', ModifierOperation.add, 1).apply(_ctx(null, modifiers: modifiers)),
      returnsNormally,
    );
    expect(modifiers.activeModifiersFor(const EntityId(1), 'x', ComponentStore()), isEmpty);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `dart test test/rule/grant_modifier_test.dart`
Expected: compile FAIL — `GrantModifier` undefined.

- [ ] **Step 3: Add the class**

In `lib/src/rule/effect.dart`:

Add imports (keep sorted — after `import '../components/tag_set.dart';`):
```dart
import '../modifier/modifier.dart';
import '../modifier/modifier_source.dart';
```

After the `RemoveAllStatuses` class (Task 1), add:

```dart
/// Adds one source-scoped [Modifier] on the subject via the Modifier
/// Engine. [sourceKey] namespaces the modifier so a caller can later
/// remove exactly this contribution with
/// `modifiers.removeBySource(ModifierSource('$sourceKey:${subject.value}'))`.
/// Re-applying with the same subject + [sourceKey] replaces (never
/// stacks): [apply] does `removeBySource` before `add`.
///
/// LIMITATION: requires `RuleContext.modifiers` to be the run's real
/// collection. That holds when the context comes from
/// `PluginContext.ruleContextFor` — e.g. a `CombatAction`'s effects run
/// by `CombatSystem`, the ONLY sanctioned path. Inside a
/// `RuleEngine`-dispatched `Rule` (`ContentRegistry.loadRule`, an SP2
/// aura) `context.modifiers` is a fresh, unobserved `ModifierCollection`:
/// the effect silently no-ops. Do NOT use `GrantModifier` in `Rule`
/// content until `RuleEngine` threads a real `ModifierCollection`. There
/// is deliberately no `'grantModifier'` content factory.
class GrantModifier implements Effect {
  const GrantModifier(
    this.stat,
    this.operation,
    this.value, {
    this.priority = 0,
    this.sourceKey = 'grantmodifier',
  });

  final String stat;
  final ModifierOperation operation;
  final num value;
  final int priority;
  final String sourceKey;

  @override
  void apply(RuleContext context) {
    final subject = context.subject;
    if (subject == null) return;
    final source = ModifierSource('$sourceKey:${subject.value}');
    context.modifiers
      ..removeBySource(source)
      ..add(Modifier(
        source: source,
        target: subject,
        stat: stat,
        operation: operation,
        value: value,
        priority: priority,
      ));
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `dart test test/rule/grant_modifier_test.dart`
Expected: PASS (3 tests).

> If `ModifierCollection.activeModifiersFor`'s signature differs from `(EntityId, String, ComponentStore)`, adjust the test's read calls to match — open `lib/src/modifier/modifier_collection.dart`. The assertions that matter: one modifier, value 6, source `consumable:power_tonic:7`, and no stacking on re-apply.

- [ ] **Step 5: Regression + lint**

Run: `dart test test/rule && dart analyze lib/src/rule/effect.dart test/rule/grant_modifier_test.dart`
Expected: green; `No issues found!`

- [ ] **Step 6: Commit**

```bash
git add lib/src/rule/effect.dart test/rule/grant_modifier_test.dart
git commit -m "$(printf 'feat(consumable): GrantModifier effect\n\nSource-scoped Modifier grant on the subject; removeBySource-before-add so\nre-apply replaces. Doc callout: CombatAction/PluginContext path only,\nnever Rule content (no grantModifier factory).\n\nCo-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>\nClaude-Session: https://claude.ai/code/session_01USc4vgCm9nma1UBaEd5c7z')"
```

---

## Task 4: `consumable` plugin — vocabulary, definition, strict parser, plugin, barrel

**Files:**
- Create: `lib/src/plugins/consumable/consumable_vocabulary.dart`
- Create: `lib/src/plugins/consumable/consumable_definition.dart`
- Create: `lib/src/plugins/consumable/consumable_content.dart`
- Create: `lib/src/plugins/consumable/consumable_plugin.dart`
- Create: `lib/consumable_plugin.dart` (barrel)
- Test: `test/plugins/consumable/consumable_definition_test.dart` (create), `test/plugins/consumable/consumable_plugin_test.dart` (create)

**Interfaces:**
- Consumes: `ContentDefinition` (`.extra`, `.id`), `ContentField` (`requireString`/`requireNum`/`requireMap`), `ContentFieldException`, `ContentValidationException`, `modifierOperationFromString`, `ModifierOperation`, `GamePlugin`, `PluginSdk`, `ResourceDefinition`, `PluginContext` (`.content`, `.resources`).
- Produces:
  - `const consumableReferenceType = 'consumable';`
  - `String consumableChargeResource(String contentId) => 'consumable:$contentId';`
  - `abstract final class ConsumableIds { static const healPotion = 'heal_potion'; static const firebomb = 'firebomb'; static const powerTonic = 'power_tonic'; static const cleanseTonic = 'cleanse_tonic'; }`
  - `enum ConsumableTarget { self, enemy }`
  - `sealed class ConsumableEffectSpec {}` with `ConsumableHeal(num amount)`, `ConsumableAttack(num damage, String stat)`, `ConsumableGrantModifier(String stat, ModifierOperation operation, num value)`, `ConsumableRemoveAllStatuses()`.
  - `class ConsumableDefinition { const ConsumableDefinition({required String id, required Set<String> tags, int charges = 1, num priority = 0, required ConsumableTarget target, required ConsumableEffectSpec effect}); }`
  - `ConsumableDefinition consumableDefinitionFromContent(ContentDefinition definition)` — strict; throws `ContentFieldException`.
  - `ConsumableDefinition consumableDefinition(String id, PluginContext context) => consumableDefinitionFromContent(context.content.get(id));`
  - `const consumableContentDefinitions = <Map<String, dynamic>>[ … ]` — **1 entry** here (`heal_potion`); Task 9 adds the rest.
  - `class ConsumablePlugin extends GamePlugin { id = 'consumable'; version = '0.1.0'; }`
  - Barrel `package:build_engine/consumable_plugin.dart` re-exports all of the above.

- [ ] **Step 1: Write the failing tests**

Create `test/plugins/consumable/consumable_definition_test.dart`:

```dart
import 'package:build_engine/build_engine.dart';
import 'package:build_engine/consumable_plugin.dart';
import 'package:test/test.dart';

ContentDefinition _load(Map<String, dynamic> json) =>
    (ContentRegistry()..load(json)).get(json['id'] as String);

void main() {
  group('valid parses', () {
    test('heal → ConsumableHeal, target self', () {
      final d = consumableDefinitionFromContent(_load({
        'id': 'p', 'type': 'consumable', 'tags': <String>[],
        'charges': 2, 'priority': 8, 'effect': {'heal': 20},
      }));
      expect(d.charges, 2);
      expect(d.priority, 8);
      expect(d.target, ConsumableTarget.self);
      expect(d.effect, isA<ConsumableHeal>());
      expect((d.effect as ConsumableHeal).amount, 20);
    });

    test('attack → ConsumableAttack, target enemy; defaults apply', () {
      final d = consumableDefinitionFromContent(_load({
        'id': 'b', 'type': 'consumable', 'tags': <String>[],
        'effect': {'attack': {'damage': 15, 'stat': 'thrown'}},
      }));
      expect(d.charges, 1);
      expect(d.priority, 0);
      expect(d.target, ConsumableTarget.enemy);
      final e = d.effect as ConsumableAttack;
      expect(e.damage, 15);
      expect(e.stat, 'thrown');
    });

    test('grant → ConsumableGrantModifier, target self', () {
      final d = consumableDefinitionFromContent(_load({
        'id': 'g', 'type': 'consumable', 'tags': <String>[],
        'effect': {'grant': {'stat': 'thrown', 'op': 'add', 'value': 6}},
      }));
      final e = d.effect as ConsumableGrantModifier;
      expect(e.stat, 'thrown');
      expect(e.operation, ModifierOperation.add);
      expect(e.value, 6);
      expect(d.target, ConsumableTarget.self);
    });

    test('removeAllStatuses → ConsumableRemoveAllStatuses, target self', () {
      final d = consumableDefinitionFromContent(_load({
        'id': 'c', 'type': 'consumable', 'tags': <String>[],
        'effect': {'removeAllStatuses': true},
      }));
      expect(d.effect, isA<ConsumableRemoveAllStatuses>());
      expect(d.target, ConsumableTarget.self);
    });

    test('explicit matching target is accepted', () {
      final d = consumableDefinitionFromContent(_load({
        'id': 'x', 'type': 'consumable', 'tags': <String>[],
        'target': 'enemy', 'effect': {'attack': {'damage': 5, 'stat': 's'}},
      }));
      expect(d.target, ConsumableTarget.enemy);
    });
  });

  group('rejected — every one throws ContentFieldException', () {
    Matcher throwsField() => throwsA(isA<ContentFieldException>());

    for (final bad in <Map<String, dynamic>>[
      {'id': 'z1', 'type': 'consumable', 'tags': <String>[]},                                   // effect absent
      {'id': 'z2', 'type': 'consumable', 'tags': <String>[], 'effect': <String, dynamic>{}},    // {}
      {'id': 'z3', 'type': 'consumable', 'tags': <String>[], 'effect': {'heal': 20, 'attack': {'damage': 1, 'stat': 's'}}}, // two variants
      {'id': 'z4', 'type': 'consumable', 'tags': <String>[], 'effect': {'attack': <String, dynamic>{}}},                    // missing damage/stat
      {'id': 'z5', 'type': 'consumable', 'tags': <String>[], 'effect': {'attack': {'damage': 15}}},                         // missing stat
      {'id': 'z6', 'type': 'consumable', 'tags': <String>[], 'effect': {'grant': {'stat': 'x'}}},                           // missing op/value
      {'id': 'z7', 'type': 'consumable', 'tags': <String>[], 'effect': {'grant': {'stat': 'x', 'op': 'bogus', 'value': 1}}}, // bad op
      {'id': 'z8', 'type': 'consumable', 'tags': <String>[], 'effect': {'heal': '20'}},          // wrong type
      {'id': 'z9', 'type': 'consumable', 'tags': <String>[], 'effect': {'heal': -5}},            // negative
      {'id': 'z10', 'type': 'consumable', 'tags': <String>[], 'effect': {'unknownKey': 1}},      // unknown key only
      {'id': 'z11', 'type': 'consumable', 'tags': <String>[], 'effect': {'heal': 20, 'junk': 1}}, // unknown key alongside valid
      {'id': 'z12', 'type': 'consumable', 'tags': <String>[], 'target': 'enemy', 'effect': {'heal': 20}},                   // heal + enemy
      {'id': 'z13', 'type': 'consumable', 'tags': <String>[], 'target': 'self', 'effect': {'attack': {'damage': 5, 'stat': 's'}}}, // attack + self
      {'id': 'z14', 'type': 'consumable', 'tags': <String>[], 'target': 'enemy', 'effect': {'grant': {'stat': 'x', 'op': 'add', 'value': 1}}}, // grant + enemy
      {'id': 'z15', 'type': 'consumable', 'tags': <String>[], 'target': 'enemy', 'effect': {'removeAllStatuses': true}},    // cleanse + enemy
    ]) {
      test('${bad['id']}: ${bad['effect'] ?? '(no effect)'} target=${bad['target']}', () {
        expect(() => consumableDefinitionFromContent(_load(bad)), throwsField());
      });
    }
  });
}
```

Create `test/plugins/consumable/consumable_plugin_test.dart`:

```dart
import 'package:build_engine/build_engine.dart';
import 'package:build_engine/consumable_plugin.dart';
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
  test('initialize loads content, registers the tag, and defines an unbounded charge resource per consumable', () {
    final ctx = _ctx();
    ConsumablePlugin().initialize(ctx);

    expect(ctx.content.find(ConsumableIds.healPotion), isNotNull);
    final def = ctx.resources.definitionOf(consumableChargeResource(ConsumableIds.healPotion));
    expect(def, isNotNull);
    expect(def!.max, double.infinity);
    expect(def.min, 0);
  });

  test('initialize is idempotent (second call, e.g. after unregister, does not throw)', () {
    final ctx = _ctx();
    ConsumablePlugin().initialize(ctx);
    expect(() => ConsumablePlugin()..initialize(ctx)..unregister(ctx), returnsNormally);
  });

  test('runs standalone with no Combat plugin', () {
    final ctx = _ctx();
    expect(() => ConsumablePlugin().initialize(ctx), returnsNormally);
  });

  test('a malformed consumableContentDefinitions entry surfaces as ContentValidationException', () {
    // white-box: feed a bad entry through the same parse+wrap path the
    // plugin uses. If the shipped content is all valid, assert the shape
    // by parsing a bad map directly and confirming the plugin would wrap
    // it — see consumable_plugin.dart's try/catch.
    final registry = ContentRegistry()
      ..load({'id': 'bad', 'type': 'consumable', 'tags': <String>[], 'effect': <String, dynamic>{}});
    expect(
      () {
        try {
          consumableDefinitionFromContent(registry.get('bad'));
        } on ContentFieldException catch (e) {
          throw ContentValidationException('bad', e);
        }
      },
      throwsA(isA<ContentValidationException>()),
    );
  });
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `dart test test/plugins/consumable/`
Expected: compile FAIL — nothing defined.

- [ ] **Step 3: `consumable_vocabulary.dart`**

```dart
/// Stable ids + keys for the Consumable plugin — a typo is a compile
/// error, not a silent string mismatch (same rationale as `ItemIds`).
const consumableReferenceType = 'consumable';

/// The per-fight charge pool key on the build owner — one per content id.
/// Every hung copy of the same consumable sums into this one pool
/// (`ConsumableBinder.grant`). Defined `max: double.infinity` (SP3 §5.1.1):
/// the value is an aggregate, not a single copy's capacity.
String consumableChargeResource(String contentId) => 'consumable:$contentId';

abstract final class ConsumableIds {
  static const healPotion = 'heal_potion';
  static const firebomb = 'firebomb';
  static const powerTonic = 'power_tonic';
  static const cleanseTonic = 'cleanse_tonic';
}
```

- [ ] **Step 4: `consumable_definition.dart`**

```dart
import 'package:build_engine/build_engine.dart';

/// Who a consumable's effect acts on. Fixed per effect variant
/// (SP3 §5.1.2): `heal` / `grantModifier` / `removeAllStatuses` are
/// `self`; `attack` is `enemy`.
enum ConsumableTarget { self, enemy }

/// A consumable's effect — a closed set, one variant per
/// `ConsumableDefinition`. Parsing yields exactly one of these or throws
/// (SP3 §5.1.3). The interpreter maps each to a fixed `CombatAction`.
sealed class ConsumableEffectSpec {
  const ConsumableEffectSpec();
}

class ConsumableHeal extends ConsumableEffectSpec {
  const ConsumableHeal(this.amount);
  final num amount;
}

class ConsumableAttack extends ConsumableEffectSpec {
  const ConsumableAttack(this.damage, this.stat);
  final num damage;
  final String stat;
}

class ConsumableGrantModifier extends ConsumableEffectSpec {
  const ConsumableGrantModifier(this.stat, this.operation, this.value);
  final String stat;
  final ModifierOperation operation;
  final num value;
}

class ConsumableRemoveAllStatuses extends ConsumableEffectSpec {
  const ConsumableRemoveAllStatuses();
}

/// Immutable, content-derived — mirrors `ItemDefinition`'s shape.
/// [charges] is PER-COPY capacity (SP3 §5.1.1). [target] is always
/// consistent with [effect] — the parser guarantees it.
class ConsumableDefinition {
  const ConsumableDefinition({
    required this.id,
    required this.tags,
    this.charges = 1,
    this.priority = 0,
    required this.target,
    required this.effect,
  });

  final String id;
  final Set<String> tags;
  final int charges;
  final num priority;
  final ConsumableTarget target;
  final ConsumableEffectSpec effect;
}
```

- [ ] **Step 5: `consumable_content.dart` (parser + 1 content entry)**

```dart
import 'package:build_engine/build_engine.dart';

import 'consumable_definition.dart';
import 'consumable_vocabulary.dart';

/// SP3 consumables as data — loaded into `PluginContext.content` via
/// `PluginSdk.registerContentBatch` in `ConsumablePlugin.initialize`.
/// Task 9 fills this out; this is the minimal single entry.
const consumableContentDefinitions = <Map<String, dynamic>>[
  {
    'id': ConsumableIds.healPotion,
    'type': 'consumable',
    'tags': <String>['consumable'],
    'charges': 1,
    'priority': 8,
    'effect': {'heal': 20},
  },
];

const _selfEffectKeys = {'heal', 'grant', 'removeAllStatuses'};
const _enemyEffectKeys = {'attack'};
const _allEffectKeys = {..._selfEffectKeys, ..._enemyEffectKeys};

/// Builds a [ConsumableDefinition] from a loaded [ContentDefinition].
/// STRICT (SP3 §5.1.2 / §5.1.3): exactly one recognized `effect` variant
/// and a `target` consistent with it, or a [ContentFieldException]
/// (which `ConsumablePlugin.initialize` wraps as
/// [ContentValidationException]).
ConsumableDefinition consumableDefinitionFromContent(ContentDefinition definition) {
  final extra = definition.extra;

  final charges = _optionalNonNegativeInt(extra, 'charges', 1);
  final priority = (extra['priority'] as num?) ?? 0;

  final effectRaw = extra['effect'];
  if (effectRaw is! Map) {
    throw ContentFieldException('effect', 'required object field missing');
  }
  final effect = Map<String, dynamic>.of(effectRaw.map((k, v) => MapEntry(k as String, v)));

  final present = effect.keys.toSet();
  final recognized = present.intersection(_allEffectKeys);
  final unknown = present.difference(_allEffectKeys);
  if (recognized.isEmpty) {
    throw ContentFieldException('effect', 'no recognized variant (one of ${_allEffectKeys.join('/')})');
  }
  if (recognized.length > 1) {
    throw ContentFieldException('effect', 'more than one variant: ${recognized.join(', ')}');
  }
  if (unknown.isNotEmpty) {
    throw ContentFieldException('effect.${unknown.first}', 'unknown key');
  }
  final key = recognized.single;

  final ConsumableEffectSpec spec;
  final ConsumableTarget legalTarget;
  switch (key) {
    case 'heal':
      spec = ConsumableHeal(_nonNegativeNum(effect, 'heal'));
      legalTarget = ConsumableTarget.self;
    case 'attack':
      final a = ContentField.requireMap(effect, 'attack');
      spec = ConsumableAttack(
        _nonNegativeNum(a, 'damage'),
        ContentField.requireString(a, 'stat'),
      );
      legalTarget = ConsumableTarget.enemy;
    case 'grant':
      final g = ContentField.requireMap(effect, 'grant');
      final opName = ContentField.requireString(g, 'op');
      const knownOps = {'add', 'multiply', 'override', 'min', 'max'};
      if (!knownOps.contains(opName)) {
        throw ContentFieldException('effect.grant.op', 'unknown modifier operation "$opName"');
      }
      final value = ContentField.requireNum(g, 'value');
      if (opName == 'add' && value < 0) {
        throw ContentFieldException('effect.grant.value', 'must be >= 0 for op "add"');
      }
      spec = ConsumableGrantModifier(
        ContentField.requireString(g, 'stat'),
        modifierOperationFromString(opName),
        value,
      );
      legalTarget = ConsumableTarget.self;
    case 'removeAllStatuses':
      if (effect['removeAllStatuses'] != true) {
        throw ContentFieldException('effect.removeAllStatuses', 'must be the literal true');
      }
      spec = const ConsumableRemoveAllStatuses();
      legalTarget = ConsumableTarget.self;
    default:
      throw StateError('unreachable: $key');
  }

  final targetRaw = extra['target'];
  final ConsumableTarget target;
  if (targetRaw == null) {
    target = legalTarget;
  } else {
    final parsed = switch (targetRaw) {
      'self' => ConsumableTarget.self,
      'enemy' => ConsumableTarget.enemy,
      _ => throw ContentFieldException('target', 'must be "self" or "enemy"'),
    };
    if (parsed != legalTarget) {
      throw ContentFieldException(
        'target', 'effect "$key" requires target ${legalTarget.name}, got ${parsed.name}');
    }
    target = parsed;
  }

  return ConsumableDefinition(
    id: definition.id,
    tags: definition.tags,
    charges: charges,
    priority: priority,
    target: target,
    effect: spec,
  );
}

num _nonNegativeNum(Map<String, dynamic> json, String key) {
  final v = ContentField.requireNum(json, key);
  if (v < 0) throw ContentFieldException(key, 'must be >= 0');
  return v;
}

int _optionalNonNegativeInt(Map<String, dynamic> json, String key, int fallback) {
  final v = json[key];
  if (v == null) return fallback;
  if (v is! int || v < 0) throw ContentFieldException(key, 'must be a non-negative int');
  return v;
}

/// Resolves + parses consumable [id] from [context]'s loaded content.
ConsumableDefinition consumableDefinition(String id, PluginContext context) =>
    consumableDefinitionFromContent(context.content.get(id));
```

> `ContentField.requireMap` returns `Map<String, dynamic>` and throws `ContentFieldException` on a non-object — that already covers `{"attack": []}` etc. `ContentField.requireNum` / `requireString` throw `ContentFieldException` on wrong type / absent, covering the `z5`/`z6`/`z8` cases without extra code.

- [ ] **Step 6: `consumable_plugin.dart`**

```dart
import 'package:build_engine/build_engine.dart';

import 'consumable_content.dart';
import 'consumable_definition.dart';
import 'consumable_vocabulary.dart';

/// The Consumable plugin: per-fight limited-use items (heal potion,
/// firebomb, tonics), built with `PluginSdk`, depending on nothing but
/// Core — a fourth proof after Elemental / Item / Technique. Owns
/// `referenceType: 'consumable'`. No Combat dependency, no trigger
/// registration, no plugin-order constraint.
///
/// Charge pools (`consumable:<id>`) are defined `max: double.infinity`
/// (SP3 §5.1.1): the stored value is the aggregate over every hung copy,
/// written authoritatively by `ConsumableBinder.grant` each fight, not a
/// single copy's `charges`.
class ConsumablePlugin extends GamePlugin {
  @override
  String get id => 'consumable';

  @override
  String get version => '0.1.0';

  late PluginSdk sdk;

  @override
  void initialize(PluginContext context) {
    sdk = PluginSdk(context);
    sdk.registerTag('consumable', description: 'A per-fight limited-use item.');

    // ContentRegistry has no unload — guard against a second load.
    if (context.content.find(ConsumableIds.healPotion) == null) {
      sdk.registerContentBatch(consumableContentDefinitions);
    }

    for (final json in consumableContentDefinitions) {
      final id = json['id'] as String;
      final ConsumableDefinition def;
      try {
        def = consumableDefinitionFromContent(context.content.get(id));
      } on ContentFieldException catch (e) {
        throw ContentValidationException(id, e); // same as ContentRegistry._parse
      }
      context.resources.define(ResourceDefinition(
        id: consumableChargeResource(def.id),
        min: 0,
        max: double.infinity,
      ));
    }
  }

  @override
  void unregister(PluginContext context) {
    sdk.disposeAll();
  }
}
```

- [ ] **Step 7: Barrel `lib/consumable_plugin.dart`**

```dart
/// The Consumable plugin's public surface — import this, never
/// `package:build_engine/src/plugins/consumable/...` directly.
library;

export 'src/plugins/consumable/consumable_content.dart'
    show consumableContentDefinitions, consumableDefinition, consumableDefinitionFromContent;
export 'src/plugins/consumable/consumable_definition.dart';
export 'src/plugins/consumable/consumable_plugin.dart';
export 'src/plugins/consumable/consumable_vocabulary.dart';
```

- [ ] **Step 8: Run tests to verify they pass**

Run: `dart test test/plugins/consumable/`
Expected: PASS (definition: 5 valid + 15 rejected = 20; plugin: 4).

- [ ] **Step 9: Lint + full suite**

Run: `dart analyze lib/src/plugins/consumable lib/consumable_plugin.dart test/plugins/consumable && dart test`
Expected: `No issues found!`; entire suite green (nothing wired into a run yet).

- [ ] **Step 10: Commit**

```bash
git add lib/src/plugins/consumable lib/consumable_plugin.dart test/plugins/consumable
git commit -m "$(printf 'feat(consumable): ConsumablePlugin + strict parser + sealed ConsumableEffectSpec\n\nreferenceType consumable; consumableChargeResource key; ConsumableDefinition\n/ ConsumableTarget / sealed ConsumableEffectSpec (heal/attack/grant/\nremoveAllStatuses). consumableDefinitionFromContent is strict: exactly one\nvariant + a target consistent with it, else ContentFieldException, wrapped\nby the plugin as ContentValidationException. Charge resources defined\nmax: double.infinity. One content entry (heal_potion); full set in a\nlater task.\n\nCo-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>\nClaude-Session: https://claude.ai/code/session_01USc4vgCm9nma1UBaEd5c7z')"
```

---

## Task 5: `AttackAction` / `SelfEffectAction` gain `priority`; `ConsumableActionInterpreter`

**Files:**
- Modify: `lib/src/plugins/combat/combat_action.dart` (`AttackAction` + `priority`)
- Modify: `lib/src/plugins/build_interpretation/self_effect_action.dart` (`SelfEffectAction` + `priority`)
- Create: `lib/src/plugins/build_interpretation/consumable_action_interpreter.dart`
- Modify: `lib/build_interpretation.dart` (export)
- Test: `test/plugins/combat/combat_action_priority_test.dart` (create), `test/plugins/build_interpretation/consumable_action_interpreter_test.dart` (create)

**Interfaces:**
- Consumes: `BuildActionInterpreter` (abstract `interpret` + `auraRules`), `ResolvedBuild.active`, `consumableReferenceType`, `consumableChargeResource`, `consumableDefinitionFromContent`, the sealed `ConsumableEffectSpec`, `SelfEffectAction` / `AttackAction` (now with `priority`), `Heal` / `GrantModifier` / `RemoveAllStatuses` / `ConsumeResource`.
- Produces:
  - `AttackAction({..., num priority = 0})` + `@override final num priority;`
  - `SelfEffectAction({..., num priority = 0})` + `@override final num priority;`
  - `class ConsumableActionInterpreter implements BuildActionInterpreter { const ConsumableActionInterpreter(); }` — `interpret` returns one `CombatAction` per hung consumable ref; `auraRules` returns `const []`. Exported via `build_interpretation.dart`.

- [ ] **Step 1: Write the failing tests**

Create `test/plugins/combat/combat_action_priority_test.dart`:

```dart
import 'package:build_engine/build_engine.dart';
import 'package:build_engine/build_interpretation.dart';
import 'package:build_engine/combat_plugin.dart';
import 'package:test/test.dart';

void main() {
  test('AttackAction.priority defaults to 0 and is settable', () {
    expect(const AttackAction(actor: EntityId(1), targets: [], baseDamage: 1, damageStat: 's').priority, 0);
    expect(
      const AttackAction(actor: EntityId(1), targets: [], baseDamage: 1, damageStat: 's', priority: 7).priority,
      7,
    );
  });

  test('SelfEffectAction.priority defaults to 0 and is settable', () {
    expect(const SelfEffectAction(actor: EntityId(1)).priority, 0);
    expect(const SelfEffectAction(actor: EntityId(1), priority: 5).priority, 5);
  });
}
```

Create `test/plugins/build_interpretation/consumable_action_interpreter_test.dart`:

```dart
import 'package:build_engine/build_engine.dart';
import 'package:build_engine/build_interpretation.dart';
import 'package:build_engine/combat_plugin.dart';
import 'package:build_engine/consumable_plugin.dart';
import 'package:test/test.dart';

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
  c.content.loadAll([
    {'id': 'hp', 'type': 'consumable', 'tags': <String>[], 'priority': 8, 'effect': {'heal': 20}},
    {'id': 'fb', 'type': 'consumable', 'tags': <String>[], 'priority': 4, 'effect': {'attack': {'damage': 15, 'stat': 'thrown'}}},
    {'id': 'pt', 'type': 'consumable', 'tags': <String>[], 'priority': 6, 'effect': {'grant': {'stat': 'thrown', 'op': 'add', 'value': 6}}},
    {'id': 'ct', 'type': 'consumable', 'tags': <String>[], 'priority': 5, 'effect': {'removeAllStatuses': true}},
  ]);
  return c;
}

ResolvedBuild _build(EntityId owner, {List<BuildComponentRef> hung = const [], List<BuildComponentRef> ownedOnly = const []}) =>
    ResolvedBuild(owner: owner, active: hung, owned: [...hung, ...ownedOnly]);

BuildComponentRef _ref(String id) => BuildComponentRef(referenceType: consumableReferenceType, contentId: id);

void main() {
  const interp = ConsumableActionInterpreter();

  test('heal → SelfEffectAction with Heal + ConsumeResource + priority + sourceRef', () {
    final ctx = _ctx();
    final owner = ctx.entities.create();
    final enemy = ctx.entities.create();
    final actions = interp.interpret(build: _build(owner, hung: [_ref('hp')]), actor: owner, targets: [enemy], context: ctx);
    final a = actions.single as SelfEffectAction;
    expect(a.selfEffects.single, isA<Heal>());
    expect(a.priority, 8);
    expect(a.sourceRef, _ref('hp'));
    expect(a.costEffects.single, isA<ConsumeResource>());
    expect((a.costEffects.single as ConsumeResource).resource, consumableChargeResource('hp'));
  });

  test('attack → AttackAction targeting the passed enemy; empty targets → no action', () {
    final ctx = _ctx();
    final owner = ctx.entities.create();
    final enemy = ctx.entities.create();
    final withEnemy = interp.interpret(build: _build(owner, hung: [_ref('fb')]), actor: owner, targets: [enemy], context: ctx);
    final a = withEnemy.single as AttackAction;
    expect(a.baseDamage, 15);
    expect(a.damageStat, 'thrown');
    expect(a.targets, [enemy]);
    expect(a.priority, 4);

    final noTargets = interp.interpret(build: _build(owner, hung: [_ref('fb')]), actor: owner, targets: const [], context: ctx);
    expect(noTargets, isEmpty);
  });

  test('grant → SelfEffectAction carrying a GrantModifier with the consumable sourceKey', () {
    final ctx = _ctx();
    final owner = ctx.entities.create();
    final actions = interp.interpret(build: _build(owner, hung: [_ref('pt')]), actor: owner, targets: const [], context: ctx);
    final g = (actions.single as SelfEffectAction).selfEffects.single as GrantModifier;
    expect(g.stat, 'thrown');
    expect(g.operation, ModifierOperation.add);
    expect(g.value, 6);
    expect(g.sourceKey, 'consumable:pt');
  });

  test('removeAllStatuses → SelfEffectAction with RemoveAllStatuses', () {
    final ctx = _ctx();
    final owner = ctx.entities.create();
    final actions = interp.interpret(build: _build(owner, hung: [_ref('ct')]), actor: owner, targets: const [], context: ctx);
    expect((actions.single as SelfEffectAction).selfEffects.single, isA<RemoveAllStatuses>());
  });

  test('owned-but-not-hung consumable → no action; hung item/technique ref ignored', () {
    final ctx = _ctx();
    final owner = ctx.entities.create();
    expect(interp.interpret(build: _build(owner, ownedOnly: [_ref('hp')]), actor: owner, targets: const [], context: ctx), isEmpty);
    expect(
      interp.interpret(
        build: _build(owner, hung: [const BuildComponentRef(referenceType: 'item', contentId: 'x')]),
        actor: owner, targets: const [], context: ctx),
      isEmpty,
    );
  });

  test('auraRules returns const []', () {
    final ctx = _ctx();
    final owner = ctx.entities.create();
    expect(interp.auraRules(build: _build(owner, hung: [_ref('hp')]), context: ctx), isEmpty);
  });
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `dart test test/plugins/combat/combat_action_priority_test.dart test/plugins/build_interpretation/consumable_action_interpreter_test.dart`
Expected: compile FAIL — `priority` param / `ConsumableActionInterpreter` undefined.

- [ ] **Step 3: Add `priority` to `AttackAction`**

In `lib/src/plugins/combat/combat_action.dart`, `AttackAction`:
- constructor: add `this.priority = 0,` (place after `this.sourceRef,`).
- fields: add `@override\n  final num priority;` (place after `final BuildComponentRef? sourceRef;`).

- [ ] **Step 4: Add `priority` to `SelfEffectAction`**

In `lib/src/plugins/build_interpretation/self_effect_action.dart`, `SelfEffectAction`:
- constructor: add `this.priority = 0,` (after `this.sourceRef,`).
- fields: add `@override\n  final num priority;` (after `final BuildComponentRef? sourceRef;`).

- [ ] **Step 5: Create `consumable_action_interpreter.dart`**

```dart
import 'package:build_engine/build_engine.dart';
import 'package:build_engine/combat_plugin.dart';
import 'package:build_engine/consumable_plugin.dart';

import 'build_action_interpreter.dart';
import 'self_effect_action.dart';

/// Translates `consumable`-typed [ResolvedBuild] components into
/// [CombatAction]s. Lives here (not in `lib/src/plugins/consumable/`) so
/// the Consumable plugin's own content/resource lifecycle stays
/// Combat-free — only this bridging interpreter needs both, exactly like
/// `Item`/`Technique`.
///
/// One action per hung consumable ref, mapped 1:1 from its
/// `ConsumableEffectSpec` (SP3 §5.2). Every action carries
/// `costEffects: [ConsumeResource(consumable:<id>, 1)]` (the per-fight
/// charge — `ConsumableBinder` grants the pool, `ScoredActionSelector`
/// filters when it is empty), the content `priority`, and `sourceRef`.
/// An `attack` consumable with no `targets` yields no action, mirroring
/// `TechniqueActionInterpreter`.
class ConsumableActionInterpreter implements BuildActionInterpreter {
  const ConsumableActionInterpreter();

  @override
  List<CombatAction> interpret({
    required ResolvedBuild build,
    required EntityId actor,
    required List<EntityId> targets,
    required PluginContext context,
  }) {
    final actions = <CombatAction>[];
    for (final ref in build.active) {
      if (ref.referenceType != consumableReferenceType) continue;
      final definition = context.content.find(ref.contentId);
      if (definition == null) continue;
      final consumable = consumableDefinitionFromContent(definition);
      final action = _actionFor(consumable, actor, targets, ref);
      if (action != null) actions.add(action);
    }
    return actions;
  }

  @override
  List<AuraRule> auraRules({
    required ResolvedBuild build,
    required PluginContext context,
  }) =>
      const [];

  CombatAction? _actionFor(
    ConsumableDefinition c,
    EntityId actor,
    List<EntityId> targets,
    BuildComponentRef ref,
  ) {
    final cost = [ConsumeResource(consumableChargeResource(c.id), 1)];
    switch (c.effect) {
      case ConsumableHeal(:final amount):
        return SelfEffectAction(
          actor: actor,
          selfEffects: [Heal(amount)],
          costEffects: cost,
          priority: c.priority,
          sourceRef: ref,
        );
      case ConsumableAttack(:final damage, :final stat):
        if (targets.isEmpty) return null;
        return AttackAction(
          actor: actor,
          targets: targets,
          baseDamage: damage,
          damageStat: stat,
          costEffects: cost,
          priority: c.priority,
          sourceRef: ref,
        );
      case ConsumableGrantModifier(:final stat, :final operation, :final value):
        return SelfEffectAction(
          actor: actor,
          selfEffects: [
            GrantModifier(stat, operation, value, sourceKey: 'consumable:${c.id}'),
          ],
          costEffects: cost,
          priority: c.priority,
          sourceRef: ref,
        );
      case ConsumableRemoveAllStatuses():
        return SelfEffectAction(
          actor: actor,
          selfEffects: const [RemoveAllStatuses()],
          costEffects: cost,
          priority: c.priority,
          sourceRef: ref,
        );
    }
  }
}
```

- [ ] **Step 6: Export it**

In `lib/build_interpretation.dart`, add (alphabetical — after `composite_build_action_interpreter.dart`):
```dart
export 'src/plugins/build_interpretation/consumable_action_interpreter.dart';
```

- [ ] **Step 7: Run tests to verify they pass**

Run: `dart test test/plugins/combat/combat_action_priority_test.dart test/plugins/build_interpretation/`
Expected: PASS — priority tests (2), consumable interpreter (6), and every pre-existing `build_interpretation` / combat test unchanged.

- [ ] **Step 8: Lint + full suite**

Run: `dart analyze lib/src/plugins/combat/combat_action.dart lib/src/plugins/build_interpretation && dart test`
Expected: `No issues found!`; entire suite green (`priority` default `0` is behaviour-neutral; the interpreter is not in any composite yet).

- [ ] **Step 9: Commit**

```bash
git add lib/src/plugins/combat/combat_action.dart lib/src/plugins/build_interpretation/self_effect_action.dart lib/src/plugins/build_interpretation/consumable_action_interpreter.dart lib/build_interpretation.dart test/plugins/combat/combat_action_priority_test.dart test/plugins/build_interpretation/consumable_action_interpreter_test.dart
git commit -m "$(printf 'feat(consumable): ConsumableActionInterpreter + priority on Attack/SelfEffect actions\n\nAttackAction/SelfEffectAction gain an optional priority param (default 0,\nbehaviour-neutral) so a consumable priority hint reaches DefaultActionScorer.\nInterpreter maps each hung consumable 1:1: heal/grant/removeAllStatuses ->\nSelfEffectAction, attack -> AttackAction (null if no targets); every action\ncarries ConsumeResource(consumable:<id>,1). auraRules() => const [].\n\nCo-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>\nClaude-Session: https://claude.ai/code/session_01USc4vgCm9nma1UBaEd5c7z')"
```

---

## Task 6: `ConsumableBinder` / `ConsumableCharges`

**Files:**
- Create: `lib/src/plugins/build_interpretation/consumable_binder.dart`
- Modify: `lib/build_interpretation.dart` (export)
- Test: `test/plugins/build_interpretation/consumable_binder_test.dart` (create)

**Interfaces:**
- Consumes: `ResolvedBuild` (`.active`, `.owner`), `PluginContext` (`.content`, `.resources`, `.modifiers`), `consumableReferenceType`, `consumableChargeResource`, `consumableDefinitionFromContent` (`.charges`), `ResourcePool.set`, `ModifierCollection.removeBySource`, `ModifierSource`.
- Produces:
  - `class ConsumableBinder { const ConsumableBinder(); ConsumableCharges grant({required ResolvedBuild build, required PluginContext context}); }`
  - `class ConsumableCharges { void dispose(); }` — idempotent.

- [ ] **Step 1: Write the failing test**

Create `test/plugins/build_interpretation/consumable_binder_test.dart`:

```dart
import 'package:build_engine/build_engine.dart';
import 'package:build_engine/build_interpretation.dart';
import 'package:build_engine/consumable_plugin.dart';
import 'package:test/test.dart';

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
  // charges: heal_potion 1, big_potion 3
  c.content.loadAll([
    {'id': 'heal_potion', 'type': 'consumable', 'tags': <String>[], 'charges': 1, 'effect': {'heal': 5}},
    {'id': 'big_potion', 'type': 'consumable', 'tags': <String>[], 'charges': 3, 'effect': {'heal': 5}},
  ]);
  for (final id in ['heal_potion', 'big_potion']) {
    c.resources.define(ResourceDefinition(id: consumableChargeResource(id), min: 0, max: double.infinity));
  }
  return c;
}

BuildComponentRef _ref(String id) => BuildComponentRef(referenceType: consumableReferenceType, contentId: id);

ResolvedBuild _build(EntityId owner, {List<BuildComponentRef> hung = const [], List<BuildComponentRef> ownedOnly = const []}) =>
    ResolvedBuild(owner: owner, active: hung, owned: [...hung, ...ownedOnly]);

void main() {
  test('grant sums per-copy charges into one pool per content id; 3 refs → 3 (no clamp)', () {
    final ctx = _ctx();
    final owner = ctx.entities.create();
    const AuraBinderIgnored = null; // (documentation: this task is the consumable binder only)
    const ConsumableBinder().grant(
      build: _build(owner, hung: [_ref('heal_potion'), _ref('heal_potion'), _ref('heal_potion')]),
      context: ctx,
    );
    expect(ctx.resources.currentOf(owner, consumableChargeResource('heal_potion')), 3);
  });

  test('different consumables → independent pools; charges honoured', () {
    final ctx = _ctx();
    final owner = ctx.entities.create();
    const ConsumableBinder().grant(
      build: _build(owner, hung: [_ref('heal_potion'), _ref('big_potion')]),
      context: ctx,
    );
    expect(ctx.resources.currentOf(owner, consumableChargeResource('heal_potion')), 1);
    expect(ctx.resources.currentOf(owner, consumableChargeResource('big_potion')), 3);
  });

  test('only build.active consumables count', () {
    final ctx = _ctx();
    final owner = ctx.entities.create();
    const ConsumableBinder().grant(
      build: _build(owner, ownedOnly: [_ref('heal_potion')]),
      context: ctx,
    );
    expect(ctx.resources.currentOf(owner, consumableChargeResource('heal_potion')), 0);
  });

  test('dispose zeroes granted pools and removes consumable:<id>:<owner> modifiers; idempotent', () {
    final ctx = _ctx();
    final owner = ctx.entities.create();
    // simulate a GrantModifier having run this fight
    ctx.modifiers.add(Modifier(
      source: ModifierSource('consumable:heal_potion:${owner.value}'),
      target: owner, stat: 'thrown', operation: ModifierOperation.add, value: 6));

    final charges = const ConsumableBinder().grant(build: _build(owner, hung: [_ref('heal_potion')]), context: ctx);
    expect(ctx.resources.currentOf(owner, consumableChargeResource('heal_potion')), 1);

    charges.dispose();
    charges.dispose(); // idempotent

    expect(ctx.resources.currentOf(owner, consumableChargeResource('heal_potion')), 0);
    expect(ctx.modifiers.activeModifiersFor(owner, 'thrown', ctx.components), isEmpty);
  });

  test('lifecycle: dispose old → resolve new → grant new applies a placement change', () {
    final ctx = _ctx();
    final owner = ctx.entities.create();
    final first = const ConsumableBinder().grant(
      build: _build(owner, hung: [_ref('heal_potion'), _ref('heal_potion')]), context: ctx);
    expect(ctx.resources.currentOf(owner, consumableChargeResource('heal_potion')), 2);

    first.dispose(); // pool → 0
    const ConsumableBinder().grant(build: _build(owner, hung: [_ref('heal_potion')]), context: ctx);
    expect(ctx.resources.currentOf(owner, consumableChargeResource('heal_potion')), 1);
  });

  test('dispose on an empty binding does not throw', () {
    final ctx = _ctx();
    final owner = ctx.entities.create();
    expect(() => const ConsumableBinder().grant(build: _build(owner), context: ctx).dispose(), returnsNormally);
  });
}
```

> Remove the stray `const AuraBinderIgnored` line if `dart analyze` flags it — it's a no-op comment marker; drop it.

- [ ] **Step 2: Run test to verify it fails**

Run: `dart test test/plugins/build_interpretation/consumable_binder_test.dart`
Expected: compile FAIL — `ConsumableBinder` undefined.

- [ ] **Step 3: Create `consumable_binder.dart`**

```dart
import 'package:build_engine/build_engine.dart';
import 'package:build_engine/consumable_plugin.dart';

/// Grants each hung consumable's per-fight charges as a `ResourcePool`
/// value on the build owner, and — on `dispose()` — zeroes those pools
/// and removes any `consumable:*` `Modifier` a `GrantModifier` effect
/// added this fight. Sibling of `AuraBinder`: created per resolved build
/// (per fight in the harness), disposed at fight end.
///
/// `grant()` is NOT an in-place reconciliation mechanism (SP3 §5.5): a
/// placement change is applied by `dispose()` old → resolve new build →
/// `grant()` again. `grant()` only `set`s the keys present in ITS
/// `build.active`; `dispose()` is what zeroes the key of a consumable
/// that dropped out. Calling `grant()` twice without an intervening
/// `dispose()` is unsupported.
class ConsumableBinder {
  const ConsumableBinder();

  ConsumableCharges grant({
    required ResolvedBuild build,
    required PluginContext context,
  }) {
    final byContent = <String, int>{};
    for (final ref in build.active) {
      if (ref.referenceType != consumableReferenceType) continue;
      final def = context.content.find(ref.contentId);
      if (def == null) continue;
      final charges = consumableDefinitionFromContent(def).charges;
      byContent[ref.contentId] = (byContent[ref.contentId] ?? 0) + charges;
    }
    for (final entry in byContent.entries) {
      // Authoritative aggregate write. The resource is defined
      // `max: double.infinity`, so `set` is a plain assignment — 3 hung
      // copies → 3, never clamped to one copy's `charges`.
      context.resources.set(build.owner, consumableChargeResource(entry.key), entry.value);
    }
    return ConsumableCharges._(
      owner: build.owner,
      contentIds: byContent.keys.toList(growable: false),
      resources: context.resources,
      modifiers: context.modifiers,
    );
  }
}

/// The disposable handle from [ConsumableBinder.grant]. Membership is
/// fixed at construction (no update path). [dispose] is idempotent.
class ConsumableCharges {
  ConsumableCharges._({
    required this.owner,
    required this.contentIds,
    required this.resources,
    required this.modifiers,
  });

  final EntityId owner;
  final List<String> contentIds;
  final ResourcePool resources;
  final ModifierCollection modifiers;
  var _disposed = false;

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    for (final id in contentIds) {
      resources.set(owner, consumableChargeResource(id), 0);
      modifiers.removeBySource(ModifierSource('consumable:$id:${owner.value}'));
    }
  }
}
```

- [ ] **Step 4: Export it**

In `lib/build_interpretation.dart`, add (after `consumable_action_interpreter.dart`):
```dart
export 'src/plugins/build_interpretation/consumable_binder.dart';
```

- [ ] **Step 5: Run test to verify it passes**

Run: `dart test test/plugins/build_interpretation/consumable_binder_test.dart`
Expected: PASS (6 tests).

- [ ] **Step 6: Lint + build_interpretation suite**

Run: `dart analyze lib/src/plugins/build_interpretation/consumable_binder.dart test/plugins/build_interpretation/consumable_binder_test.dart && dart test test/plugins/build_interpretation`
Expected: green; `No issues found!`

- [ ] **Step 7: Commit**

```bash
git add lib/src/plugins/build_interpretation/consumable_binder.dart lib/build_interpretation.dart test/plugins/build_interpretation/consumable_binder_test.dart
git commit -m "$(printf 'feat(consumable): ConsumableBinder / ConsumableCharges per-fight lifecycle\n\ngrant() sums per-copy charges per content id and set()s one pool each\n(unbounded resource, no clamp). dispose() zeroes those pools and\nremoveBySource()es consumable:<id>:<owner> modifiers; idempotent. Not an\nin-place reconciliation mechanism.\n\nCo-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>\nClaude-Session: https://claude.ai/code/session_01USc4vgCm9nma1UBaEd5c7z')"
```

---

## Task 7: `ConsumableAwareActionScorer`

**Files:**
- Create: `lib/src/plugins/auto_combat/consumable_aware_action_scorer.dart`
- Modify: `lib/auto_combat_plugin.dart` (export)
- Test: `test/plugins/auto_combat/consumable_aware_action_scorer_test.dart` (create)

**Interfaces:**
- Consumes: `ActionScorer`, `DefaultActionScorer`, `CombatAction` (`.effectsFor`, `.actor`), `HealthComponent`, `Heal` / `ApplyStatus`, `PluginContext`.
- Produces: `class ConsumableAwareActionScorer implements ActionScorer { const ConsumableAwareActionScorer({ActionScorer base = const DefaultActionScorer(), num missingHealthWeight = 40, num buffBonus = 6}); }` — exported via `auto_combat_plugin.dart`.

- [ ] **Step 1: Write the failing test**

Create `test/plugins/auto_combat/consumable_aware_action_scorer_test.dart`:

```dart
import 'package:build_engine/auto_combat_plugin.dart';
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

void main() {
  const scorer = ConsumableAwareActionScorer();
  const base = DefaultActionScorer();

  test('a Heal action scores base + missingHealthWeight * missingFraction', () {
    final ctx = _ctx();
    final actor = ctx.entities.create();
    ctx.components.add(actor, const HealthComponent(current: 25, max: 100)); // missing 0.75
    final heal = SelfEffectAction(actor: actor, selfEffects: const [Heal(20)], priority: 8);

    expect(scorer.score(heal, actor, null, ctx), base.score(heal, actor, null, ctx) + 40 * 0.75);
  });

  test('at full HP the Heal bonus is 0', () {
    final ctx = _ctx();
    final actor = ctx.entities.create();
    ctx.components.add(actor, const HealthComponent(current: 100, max: 100));
    final heal = SelfEffectAction(actor: actor, selfEffects: const [Heal(20)], priority: 8);
    expect(scorer.score(heal, actor, null, ctx), base.score(heal, actor, null, ctx));
  });

  test('an ApplyStatus action scores base + buffBonus', () {
    final ctx = _ctx();
    final actor = ctx.entities.create();
    ctx.components.add(actor, const HealthComponent(current: 50, max: 100));
    final buff = SelfEffectAction(actor: actor, selfEffects: [ApplyStatus('status:x')], priority: 3);
    expect(scorer.score(buff, actor, null, ctx), base.score(buff, actor, null, ctx) + 6);
  });

  test('a plain AttackAction is scored identically to DefaultActionScorer (regression)', () {
    final ctx = _ctx();
    final actor = ctx.entities.create();
    final target = ctx.entities.create();
    final atk = AttackAction(actor: actor, targets: [target], baseDamage: 12, damageStat: 'fist');
    expect(scorer.score(atk, actor, target, ctx), base.score(atk, actor, target, ctx));
  });

  test('a GrantModifier-carrying SelfEffectAction gets no bonus and applies no modifier', () {
    final ctx = _ctx();
    final actor = ctx.entities.create();
    ctx.components.add(actor, const HealthComponent(current: 50, max: 100));
    final buff = SelfEffectAction(
      actor: actor,
      selfEffects: const [GrantModifier('thrown', ModifierOperation.add, 6, sourceKey: 'consumable:pt')],
      priority: 6,
    );
    expect(scorer.score(buff, actor, null, ctx), base.score(buff, actor, null, ctx));
    expect(ctx.modifiers.activeModifiersFor(actor, 'thrown', ctx.components), isEmpty);
  });

  test('no HealthComponent → Heal bonus is 0 (missing fraction treated as 0)', () {
    final ctx = _ctx();
    final actor = ctx.entities.create();
    final heal = SelfEffectAction(actor: actor, selfEffects: const [Heal(20)]);
    expect(scorer.score(heal, actor, null, ctx), base.score(heal, actor, null, ctx));
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `dart test test/plugins/auto_combat/consumable_aware_action_scorer_test.dart`
Expected: compile FAIL — `ConsumableAwareActionScorer` undefined.

- [ ] **Step 3: Create the scorer**

```dart
import 'package:build_engine/build_engine.dart';
import 'package:build_engine/combat_plugin.dart';

import 'action_scorer.dart';

/// `DefaultActionScorer` plus consumable-shaped intent, read from the
/// action's own Core effect types (SP3 §5.6) — the same category as the
/// base scorer's `action is AttackAction` check, no domain vocabulary:
///
/// - each `Heal` effect adds `missingHealthWeight * (1 - actorHpFraction)`
///   — near-worthless at full HP, top value near death;
/// - each `ApplyStatus` effect adds a flat `buffBonus` (an early-use buff).
///
/// Offensive consumables are `AttackAction` and are already scored by
/// resolved damage in the composed base. `GrantModifier` matches neither
/// branch (priority-gated). Applies to ANY heal/buff action, not only
/// consumables (a healing guard technique gets smarter too).
class ConsumableAwareActionScorer implements ActionScorer {
  const ConsumableAwareActionScorer({
    this.base = const DefaultActionScorer(),
    this.missingHealthWeight = 40,
    this.buffBonus = 6,
  });

  final ActionScorer base;
  final num missingHealthWeight;
  final num buffBonus;

  @override
  num score(
    CombatAction action,
    EntityId actor,
    EntityId? preferredTarget,
    PluginContext context,
  ) {
    var total = base.score(action, actor, preferredTarget, context);
    final hp = context.components.get<HealthComponent>(actor);
    final missing = (hp == null || hp.max <= 0)
        ? 0.0
        : (1 - hp.current / hp.max).clamp(0.0, 1.0);
    for (final effect in action.effectsFor(action.actor, context)) {
      if (effect is Heal) total += missingHealthWeight * missing;
      if (effect is ApplyStatus) total += buffBonus;
    }
    return total;
  }
}
```

- [ ] **Step 4: Export it**

In `lib/auto_combat_plugin.dart`, add (alphabetical — after `combat_policy.dart`):
```dart
export 'src/plugins/auto_combat/consumable_aware_action_scorer.dart';
```

- [ ] **Step 5: Run test + regression**

Run: `dart test test/plugins/auto_combat && dart analyze lib/src/plugins/auto_combat/consumable_aware_action_scorer.dart test/plugins/auto_combat/consumable_aware_action_scorer_test.dart`
Expected: PASS (6 new + every pre-existing auto_combat test); `No issues found!`

- [ ] **Step 6: Commit**

```bash
git add lib/src/plugins/auto_combat/consumable_aware_action_scorer.dart lib/auto_combat_plugin.dart test/plugins/auto_combat/consumable_aware_action_scorer_test.dart
git commit -m "$(printf 'feat(consumable): ConsumableAwareActionScorer\n\nComposes DefaultActionScorer; adds missingHealthWeight*(1-hpFrac) per Heal\neffect and a flat buffBonus per ApplyStatus effect, read from\naction.effectsFor. Never calls Effect.apply. Plain AttackActions and\nGrantModifier-carrying actions are unaffected.\n\nCo-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>\nClaude-Session: https://claude.ai/code/session_01USc4vgCm9nma1UBaEd5c7z')"
```

---

## Task 8: harness wiring — `game_run.dart` + exception-safe `combat_stage.dart`

**Files:**
- Modify: `lib/src/plugins/game/game_run.dart`
- Modify: `lib/src/plugins/game/combat_stage.dart`
- Test: `test/integration/consumable_combat_stage_test.dart` (create)

**Interfaces:**
- Consumes: `ConsumablePlugin`, `ConsumableActionInterpreter`, `ConsumableBinder` / `ConsumableCharges`, `ConsumableAwareActionScorer`, existing `AuraBinder`, `CombatPolicy.scored`.
- Produces: `game_run` initializes `ConsumablePlugin` and its composite includes `ConsumableActionInterpreter()`; `CombatStage.runFight` is exception-safe (both binders inside one `try`, nullable locals, reverse-order `finally`) and uses `CombatPolicy.scored(scorer: const ConsumableAwareActionScorer())`.

- [ ] **Step 1: Write the failing test**

Create `test/integration/consumable_combat_stage_test.dart`. It drives a real `runGame` with `heal_potion` reachable and asserts the player is healed by the consumable during a fight, then that the aura/charge lifecycle survives a `grant` throw.

```dart
/// SP3 §5.7 / §9 — the headless run exercises the consumable path, and
/// per-fight setup is exception-safe.
library;

import 'package:build_engine/build_engine.dart';
import 'package:build_engine/consumable_plugin.dart';
import 'package:build_engine/game.dart';
import 'package:test/test.dart';

// GREEN AFTER TASK 9 (needs heal_potion in the reward pool + a policy
// that takes it). Task 8 keeps this file present but its run-level
// asserts are marked skip until Task 9; the exception-safety unit-style
// assert (below) is live now.
void main() {
  test('CombatStage.runFight: partial setup (aura ok, consumable grant throws) still disposes the aura binding',
      () {
    // Build a minimal CombatStage-like harness is heavy; instead assert
    // the contract at the seam Task 8 introduces: see combat_stage.dart —
    // the finally must run consumableCharges?.dispose() then
    // auraBinding?.dispose() with both as nullable locals assigned inside
    // the try. A dedicated harness test is added in Task 11's acceptance
    // file which constructs CombatStage directly with a stub interpreter
    // whose consumable path throws.
  }, skip: 'covered by Task 11 acceptance test (needs a throwing stub interpreter)');

  test('a run with heal_potion hung shows a consumable Heal(20) on the player', () {
    // Filled in / un-skipped by Task 9 once heal_potion is reward-pool
    // reachable. Placeholder asserts the run still completes.
    final r = runGame(6);
    expect(r.encounters, isNotEmpty);
  });
}
```

> This task's real deliverable is the **wiring compiling and the full suite staying green** (consumables aren't in the reward pool until Task 9, so behaviour is unchanged). The meaningful end-to-end asserts land in Task 9 (run-level) and Task 11 (acceptance, incl. the throwing-stub `CombatStage` test).

- [ ] **Step 2: Wire `game_run.dart`**

Add the import (with the other plugin barrels near the top):
```dart
import 'package:build_engine/consumable_plugin.dart';
```

After `TechniquePlugin().initialize(context);` add:
```dart
  ConsumablePlugin().initialize(context);
```

Change the composite from:
```dart
  const interpreter =
      CompositeBuildActionInterpreter([TechniqueActionInterpreter(), ItemActionInterpreter()]);
```
to:
```dart
  const interpreter = CompositeBuildActionInterpreter([
    TechniqueActionInterpreter(),
    ItemActionInterpreter(),
    ConsumableActionInterpreter(),
  ]);
```
(`ConsumableActionInterpreter` comes from `package:build_engine/build_interpretation.dart`, already imported.)

- [ ] **Step 3: Restructure `combat_stage.dart` `runFight` (exception-safe)**

Add the import: `import 'package:build_engine/consumable_plugin.dart';` — actually `ConsumableBinder`/`ConsumableCharges`/`ConsumableAwareActionScorer` come from `build_interpretation` and `auto_combat_plugin`, both already imported. No new import needed.

Replace the body of `runFight` from the `final auraBinding = ...` line through the existing `try { … } finally { … }` with this shape (keep `events.publish(EncounterStarted…)`, `spawnEnemy`, `tome.resolve`, `ActiveBuildResolved`, `interpreter.interpret`, `fallbackStrikeStat`, and the post-`finally` bookkeeping exactly as they are):

```dart
    final playerActions = interpreter.interpret(
        build: build, actor: character, targets: [enemyEntity], context: context);

    AuraBinding? auraBinding;
    ConsumableCharges? consumableCharges;
    EventSubscription? subscription;
    AutoCombatController? controller;
    var turnsUsed = 0;
    try {
      auraBinding = const AuraBinder().bind(
        build: build, interpreter: interpreter, context: context, opponents: [enemyEntity]);
      consumableCharges = const ConsumableBinder().grant(build: build, context: context);

      final effectivePlayerActions = playerActions.isEmpty
          ? [AttackAction(actor: character, targets: [enemyEntity], baseDamage: 4, damageStat: fallbackStrikeStat(build.asActiveBuild))]
          : playerActions;
      final battle = combatPlugin.system.startBattle([character, enemyEntity]);
      controller = AutoCombatController(
        context: context,
        combatSystem: combatPlugin.system,
        battle: battle,
        availableActions: [
          ...effectivePlayerActions,
          AttackAction(actor: enemyEntity, targets: [character], baseDamage: enemy.damage, damageStat: enemy.damageStat),
        ],
        policy: CombatPolicy.scored(scorer: const ConsumableAwareActionScorer()),
      );
      subscription = events.subscribe<ActionCompleted>((e) {
        if (e.battle != battle) return;
        turnsUsed++;
        final ref = e.action.sourceRef;
        if (ref != null &&
            ref.referenceType == techniqueReferenceType &&
            ref.instanceEntityId != null) {
          recordTechniqueVariantUsage(ref.instanceEntityId!, context);
        }
      });
      controller.runUntilBattleEnds();
    } finally {
      subscription?.cancel();
      consumableCharges?.dispose();
      auraBinding?.dispose();
    }

    final playerHealth = context.components.get<HealthComponent>(character)!.current;
    final won = playerHealth > 0 && !controller!.isActive;
```

(Everything after `final won = …` — `encounters.add(...)`, `EncounterResolved`, `return won;` — is unchanged. `controller!` is safe: if the `try` threw before assigning it, the exception has already propagated out of `runFight`.)

Update the `CombatStage` class doc comment's SP2 paragraph to also mention: "Per-fight consumable charges (SP3) are granted here alongside the aura binding, inside the same `try`, and disposed (reverse order) in the `finally` — so a throw between the two binder calls leaves neither live."

- [ ] **Step 4: `dart analyze` + targeted suites**

Run: `dart analyze lib/src/plugins/game/game_run.dart lib/src/plugins/game/combat_stage.dart && dart test test/plugins/game test/integration`
Expected: `No issues found!`; green. Behaviour-neutral (no consumable in the reward pool yet).

- [ ] **Step 5: Full suite**

Run: `dart test`
Expected: entire suite green.

- [ ] **Step 6: Commit**

```bash
git add lib/src/plugins/game/game_run.dart lib/src/plugins/game/combat_stage.dart test/integration/consumable_combat_stage_test.dart
git commit -m "$(printf 'feat(consumable): wire ConsumablePlugin + exception-safe CombatStage.runFight\n\ngame_run inits ConsumablePlugin and adds ConsumableActionInterpreter to\nthe composite. runFight restructured: AuraBinder.bind + ConsumableBinder\n.grant inside one try behind nullable locals, disposed reverse-order in\nfinally (a grant() throw after bind() still disposes the aura binding).\nScored policy now uses ConsumableAwareActionScorer. Behaviour-neutral\nuntil the content pass.\n\nCo-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>\nClaude-Session: https://claude.ai/code/session_01USc4vgCm9nma1UBaEd5c7z')"
```

---

## Task 9: content pass + reward/placement wiring + artifact regen

**Files:**
- Modify: `lib/src/plugins/consumable/consumable_content.dart` (full 4-consumable set)
- Modify: `lib/src/plugins/consumable/consumable_vocabulary.dart` (ids already present from Task 4 — verify)
- Modify: `lib/src/plugins/game/run_content.dart` (`rewardPoolConsumableIds`)
- Modify: `lib/src/plugins/game/game_run.dart` (`rewardPool` list)
- Modify: `lib/src/plugins/game/reward_stage.dart` (`consumable` branch)
- Modify: `lib/src/plugins/game/tome_manager.dart` (`placeConsumable`)
- Test: `test/plugins/consumable/consumable_content_test.dart` (create); un-skip / fill `test/integration/consumable_combat_stage_test.dart`
- Regenerate: `output/game_run_seed_*.txt`

**Interfaces:**
- Consumes: `TomeManager` (`orderedUnlockedSlots`, `snapshot`, `recordingPolicy`), `context.tome.insert`, `consumableReferenceType`, `consumableDefinition`.
- Produces: `const rewardPoolConsumableIds`; `RewardStage.resolveReward` handles `entry.referenceType == consumableReferenceType`; `TomeManager.placeConsumable(ConsumableDefinition, String)`.

- [ ] **Step 1: Write the failing content test**

Create `test/plugins/consumable/consumable_content_test.dart`:

```dart
import 'package:build_engine/build_engine.dart';
import 'package:build_engine/consumable_plugin.dart';
import 'package:test/test.dart';

void main() {
  test('all shipped consumables load and parse to the expected shapes', () {
    final registry = ContentRegistry()..loadAll(consumableContentDefinitions);

    final heal = consumableDefinitionFromContent(registry.get(ConsumableIds.healPotion));
    expect(heal.effect, isA<ConsumableHeal>());
    expect((heal.effect as ConsumableHeal).amount, 20);
    expect(heal.target, ConsumableTarget.self);
    expect(heal.priority, 8);

    final bomb = consumableDefinitionFromContent(registry.get(ConsumableIds.firebomb));
    final ba = bomb.effect as ConsumableAttack;
    expect(ba.damage, 15);
    expect(ba.stat, 'thrown');
    expect(bomb.target, ConsumableTarget.enemy);

    final tonic = consumableDefinitionFromContent(registry.get(ConsumableIds.powerTonic));
    final tg = tonic.effect as ConsumableGrantModifier;
    expect(tg.stat, 'thrown');
    expect(tg.operation, ModifierOperation.add);
    expect(tg.value, 6);
    expect(tonic.target, ConsumableTarget.self);

    final cleanse = consumableDefinitionFromContent(registry.get(ConsumableIds.cleanseTonic));
    expect(cleanse.effect, isA<ConsumableRemoveAllStatuses>());
    expect(cleanse.target, ConsumableTarget.self);
  });

  test('ConsumablePlugin.initialize defines an unbounded charge resource for every shipped consumable', () {
    final events = EventBus();
    final entities = EntityRegistry(events);
    final components = ComponentStore();
    final rng = RngService(1);
    final ctx = PluginContext(
      entities: entities, components: components, events: events, rng: rng,
      rules: RuleEngine(entities: entities, components: components, events: events, rng: rng),
      queries: QueryEngine(QueryScope(components: components)),
      modifiers: ModifierCollection(), content: ContentRegistry(),
    );
    ConsumablePlugin().initialize(ctx);
    for (final id in [ConsumableIds.healPotion, ConsumableIds.firebomb, ConsumableIds.powerTonic, ConsumableIds.cleanseTonic]) {
      final def = ctx.resources.definitionOf(consumableChargeResource(id));
      expect(def, isNotNull, reason: id);
      expect(def!.max, double.infinity, reason: id);
    }
  });
}
```

- [ ] **Step 2: Run it (fails — only heal_potion exists)**

Run: `dart test test/plugins/consumable/consumable_content_test.dart`
Expected: FAIL — `registry.get('firebomb')` throws `ContentNotFoundException`.

- [ ] **Step 3: Fill `consumableContentDefinitions`**

In `lib/src/plugins/consumable/consumable_content.dart`, replace the single-entry list with:

```dart
const consumableContentDefinitions = <Map<String, dynamic>>[
  {
    'id': ConsumableIds.healPotion,
    'type': 'consumable',
    'tags': <String>['consumable'],
    'charges': 1,
    'priority': 8,
    'effect': {'heal': 20},
  },
  {
    'id': ConsumableIds.firebomb,
    'type': 'consumable',
    'tags': <String>['consumable'],
    'charges': 1,
    'priority': 4,
    'target': 'enemy',
    'effect': {'attack': {'damage': 15, 'stat': 'thrown'}},
  },
  {
    'id': ConsumableIds.powerTonic,
    'type': 'consumable',
    'tags': <String>['consumable'],
    'charges': 1,
    'priority': 6,
    'effect': {'grant': {'stat': 'thrown', 'op': 'add', 'value': 6}},
  },
  {
    'id': ConsumableIds.cleanseTonic,
    'type': 'consumable',
    'tags': <String>['consumable'],
    'charges': 1,
    'priority': 5,
    'effect': {'removeAllStatuses': true},
  },
];
```

- [ ] **Step 4: `run_content.dart` — reward pool ids**

In `lib/src/plugins/game/run_content.dart`, add near `rewardPoolItemIds`:
```dart
const rewardPoolConsumableIds = [
  ConsumableIds.healPotion,
  ConsumableIds.firebomb,
  ConsumableIds.powerTonic,
  ConsumableIds.cleanseTonic,
];
```
Add `import 'package:build_engine/consumable_plugin.dart';` at the top.

- [ ] **Step 5: `game_run.dart` — `rewardPool` list**

In `lib/src/plugins/game/game_run.dart`, the `rewardPool = seededShuffle([ ... ], rng)` literal — add a third comprehension:
```dart
      for (final id in rewardPoolConsumableIds)
        (referenceType: consumableReferenceType, contentId: id),
```

- [ ] **Step 6: `tome_manager.dart` — `placeConsumable`**

Add `import 'package:build_engine/consumable_plugin.dart';` (with the other plugin barrels). After `placeTechnique`, add — mirroring `placeTechnique`'s slot/replace flow but with a direct `insert` (no learned/usable gate):

```dart
  void placeConsumable(ConsumableDefinition consumable, String stepName) {
    final ref = BuildComponentRef(
        referenceType: consumableReferenceType, contentId: consumable.id);
    final slot = recordingPolicy.chooseSlot(ref, orderedUnlockedSlots());
    final existing = context.tome.inspect(character).where((p) => p.slot == slot);
    if (existing.isNotEmpty) {
      if (!recordingPolicy.chooseReplace(slot, existing.single.buildComponentRef, ref)) return;
      context.tome.remove(character, slot);
    }
    context.tome.insert(character, slot, ref);
    snapshot(stepName);
  }
```

- [ ] **Step 7: `reward_stage.dart` — `consumable` branch**

Add `import 'package:build_engine/consumable_plugin.dart';`. In `resolveReward`'s `RewardKind.itemOrTechnique` case, change the `if (entry.referenceType == itemReferenceType) { … } else { … technique … }` to a three-way:

```dart
        if (entry.referenceType == itemReferenceType) {
          final item = itemDefinition(entry.contentId, context);
          ownItem(character, item.id, context);
          discoverItem(character, item, context);
          itemsDiscovered.add(item.id);
          if (isItemUsable(character, item, context)) tomeManager.placeItem(item, '$stepName reward');
          return 'item:${item.id}';
        } else if (entry.referenceType == consumableReferenceType) {
          final consumable = consumableDefinition(entry.contentId, context);
          tomeManager.placeConsumable(consumable, '$stepName reward');
          return 'consumable:${consumable.id}';
        } else {
          final technique = techniqueDefinition(entry.contentId, context);
          discoverTechnique(character, technique, context);
          return 'technique:${technique.id}';
        }
```

- [ ] **Step 8: Un-skip / finish the integration test**

In `test/integration/consumable_combat_stage_test.dart`, replace the placeholder run-level test with a real assertion — subscribe an `EventBus` to `EntityHealed` before `runGame(seed, eventBus: bus)` (see `game_run.dart`'s doc comment ~line 120), and assert at least one in-fight `EntityHealed` of amount `20` occurs (that is `heal_potion`; the between-cycle rest heal is a different, larger amount and lands outside `EncounterStarted`/`EncounterResolved`). Pick a fight-heavy policy from `test/support/policies.dart` and, if needed, a policy that prefers `RewardKind.itemOrTechnique` so consumables actually enter the Tome; scan a handful of seeds (`for (seed in 1..20)`) for one where a `heal_potion` is granted and used, mirroring `technique_variant_run_test.dart`'s seed-sweep convention. Also add the determinism assertion (two `runGame(seed, ...)` with the same policy → identical `RunResult` fields). Keep the exception-safety `skip` pointing at Task 11.

- [ ] **Step 9: Run the consumable + game + integration suites; triage flips**

Run: `dart test test/plugins/consumable test/plugins/build_interpretation test/plugins/auto_combat test/plugins/game test/integration`
Expected: consumable content + integration green. `test/game/` may flip: `ConsumableAwareActionScorer` + consumables in the reward pool change fixed-seed fight outcomes.
- For each `test/game/` failure: if it is a **diversity / structure** assertion (`> 1` distinct X, `isNotEmpty`, `survived + died == 10`), update the specific expected value to the new observed value and note it in the commit body.
- If a **determinism** assertion fails (`decision_log_replay_test.dart`; `multi_seed_diversity_test.dart`'s "same seed twice" checks; two `runGame(seed)` compared), that is a real bug — **STOP and report `BLOCKED`** with the failing test + output. Do not weaken it.

- [ ] **Step 10: Full suite**

Run: `dart test`
Expected: entire suite green.

- [ ] **Step 11: Regenerate artifacts**

Run: `dart run tool/game_run_report.dart`
Rewrites `output/game_run_seed_*.txt` + `output/game_run_summary.txt` (gitignored — nothing to stage). Review `git status` shows no `output/` changes to commit; note the observed balance shift (avg cycles, elite win rate) in the commit body.

- [ ] **Step 12: Lint + commit**

Run: `dart analyze lib test`
Expected: `No issues found!`

```bash
git add lib/src/plugins/consumable lib/src/plugins/game test/plugins/consumable/consumable_content_test.dart test/integration/consumable_combat_stage_test.dart <any updated test/game files>
git commit -m "$(printf 'feat(consumable): content pass (heal_potion, firebomb, power_tonic, cleanse_tonic) + reward/placement wiring\n\nswift_draught dropped (spec §7 fallback; coverage complete at 4).\nrewardPoolConsumableIds + a consumable branch in resolveReward +\nTomeManager.placeConsumable (direct tome.insert, no usability gate).\nRegenerated output/ (gitignored). test/game flips: <list each: name,\nold->new, diversity/structure not determinism>.\n\nCo-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>\nClaude-Session: https://claude.ai/code/session_01USc4vgCm9nma1UBaEd5c7z')"
```

---

## Task 10: architecture guard + CHANGELOG + ARCHITECTURE

**Files:**
- Modify: `test/integration/architecture_dependency_test.dart`
- Modify: `CHANGELOG.md`, `ARCHITECTURE.md`

- [ ] **Step 1: Add the guard test**

In `test/integration/architecture_dependency_test.dart`, after the `aura/`-guard group (SP2), add:

```dart
  group('Consumable plugin is fully decoupled from every other plugin', () {
    for (final barrel in _pluginBarrels) {
      if (barrel == 'combat_plugin.dart') continue; // consumable/ never imports Combat either, but state it positively below
      test('Consumable does not reference $barrel', () {
        _assertNoSubstringInDirectory(barrel, 'lib/src/plugins/consumable');
      });
    }
    test('Consumable does not reference Combat', () {
      _assertNoSubstringInDirectory('combat_plugin.dart', 'lib/src/plugins/consumable');
      _assertNoSubstringInDirectory('plugins/combat/', 'lib/src/plugins/consumable');
    });
    test('Consumable does not escape into any other plugins/ directory', () {
      final src = Directory('lib/src/plugins/consumable')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))
          .map((f) => f.readAsStringSync())
          .join('\n');
      for (final other in ['item', 'technique', 'combat', 'auto_combat', 'martial_arts', 'elemental', 'physique', 'build_interpretation', 'game']) {
        expect(src, isNot(contains('plugins/$other/')), reason: 'consumable/ imports plugins/$other/');
      }
    });
  });
```

> Match the exact helper names in the file (`_assertNoSubstringInDirectory`, `_pluginBarrels`); adapt if the SP2 additions renamed anything. The intent: `lib/src/plugins/consumable/` imports only `package:build_engine/build_engine.dart`.

- [ ] **Step 2: Run the architecture suite**

Run: `dart test test/integration/architecture_dependency_test.dart`
Expected: PASS incl. the new group. (`consumable_definition.dart` imports `build_engine.dart` for `ModifierOperation`; `consumable_content.dart` for `ContentField`/`modifierOperationFromString`; `consumable_plugin.dart` for the SDK — all Core barrel, no plugin barrel.)

- [ ] **Step 3: `CHANGELOG.md`**

Under `## Unreleased`, after the SP2 sections, add:

```markdown
### Added — Per-fight Consumables (SP3)

- **`package:build_engine/consumable_plugin.dart`** — new Core-only content
  plugin barrel: `ConsumablePlugin`, `ConsumableDefinition`,
  `ConsumableTarget`, the sealed `ConsumableEffectSpec` (`ConsumableHeal` /
  `ConsumableAttack` / `ConsumableGrantModifier` /
  `ConsumableRemoveAllStatuses`), `consumableDefinitionFromContent` /
  `consumableDefinition`, `consumableContentDefinitions`,
  `consumableReferenceType` (`'consumable'`), `consumableChargeResource`,
  `ConsumableIds`.
- **`RemoveAllStatuses`** (`Effect`, `src/rule/effect.dart`) — clears the
  subject's `StatusComponent`. Also a `'removeAllStatuses'` content
  factory.
- **`GrantModifier`** (`Effect`, `src/rule/effect.dart`) — adds one
  source-scoped `Modifier` on the subject. **`CombatAction` /
  `PluginContext` execution path only** — no `'grantModifier'` content
  factory; a `RuleEngine`-dispatched `GrantModifier` silently no-ops
  (its `RuleContext.modifiers` is an unobserved default).
- **`RuleContext.modifiers`** — the Modifier Engine is now on
  `RuleContext` (optional factory param, defaults to a fresh
  `ModifierCollection`). `PluginContext.ruleContextFor` supplies the real
  one; `RuleEngine._fire` is unchanged (empty default).
- **`AttackAction` / `SelfEffectAction` gained an optional `priority`**
  constructor parameter (`num`, default `0`) — overrides the
  `CombatAction.priority` scoring hint.
- **`package:build_engine/build_interpretation.dart`** exports
  `ConsumableActionInterpreter` and `ConsumableBinder` /
  `ConsumableCharges`.
- **`package:build_engine/auto_combat_plugin.dart`** exports
  `ConsumableAwareActionScorer`.

### Changed — Per-fight Consumables (SP3)

- **`CombatStage.runFight`** now also binds per-fight consumable charges
  (`ConsumableBinder.grant`) alongside the aura binding, inside one
  exception-safe `try` (nullable locals, reverse-order disposal in
  `finally`), and its `CombatPolicy.scored` uses
  `ConsumableAwareActionScorer`. Fixed-seed headless outcomes shift where
  a consumable is now reachable/used — representation + AI, not a balance
  pass; determinism preserved. `output/` artifacts regenerated.
- **Headless run reward pool** gains `rewardPoolConsumableIds`
  (`heal_potion`, `firebomb`, `power_tonic`, `cleanse_tonic`);
  `RewardStage.resolveReward` and `TomeManager.placeConsumable` handle the
  third `referenceType`.
```

- [ ] **Step 4: `ARCHITECTURE.md`**

After the SP2 "Per-active Auras" section, add a "## Per-fight consumables (SP3)" section summarising: `referenceType: 'consumable'`; charges = a per-fight `ResourcePool` resource (`consumable:<id>`, `max: double.infinity`, aggregate over hung copies) spent via `ConsumeResource` + the existing `ScoredActionSelector._isAvailable`; `ConsumableActionInterpreter` (composite) → `SelfEffectAction`/`AttackAction`; `ConsumableBinder`/`ConsumableCharges` per-fight lifecycle (grant Σcharges, `dispose` zeroes pools + `removeBySource`es `consumable:*` modifiers; not in-place reconciliation); `ConsumableAwareActionScorer` (effect-shape bonuses); `RemoveAllStatuses` + `GrantModifier` effects; `RuleContext.modifiers` + the `RuleEngine._fire` caveat. Also add one line to the Rule/Effect section noting `RuleContext.modifiers` and that `RuleEngine._fire` gets the empty default.

- [ ] **Step 5: Full suite + commit**

Run: `dart test && dart analyze lib test`
Expected: entire suite green; `No issues found!`

```bash
git add test/integration/architecture_dependency_test.dart CHANGELOG.md ARCHITECTURE.md
git commit -m "$(printf 'docs(consumable): SP3 CHANGELOG + ARCHITECTURE + dependency guard\n\nlib/src/plugins/consumable/ imports only the Core barrel (guard test).\nCHANGELOG public-surface entries; ARCHITECTURE per-fight-consumables\nsection + RuleContext.modifiers note.\n\nCo-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>\nClaude-Session: https://claude.ai/code/session_01USc4vgCm9nma1UBaEd5c7z')"
```

---

## Task 11: acceptance-invariant integration test (spec §12)

**Files:**
- Test: `test/integration/per_fight_consumable_test.dart` (create)

**Interfaces:**
- Consumes: `CombatPlugin`, `ItemPlugin`, `TechniquePlugin`, `ConsumablePlugin`, `TomeService`, `BuildResolver`, `CompositeBuildActionInterpreter([TechniqueActionInterpreter(), ItemActionInterpreter(), ConsumableActionInterpreter()])`, `ConsumableBinder`, `AuraBinder`, `ScoredActionSelector` / `ConsumableAwareActionScorer`, the shipped `heal_potion` / `firebomb` / `power_tonic` / `cleanse_tonic` content.
- Produces: one test file proving every row of spec §12.

- [ ] **Step 1: Write the test**

Create `test/integration/per_fight_consumable_test.dart`. Build a `PluginContext` (Combat + Item + Technique + Consumable initialized), a `_interpreter` = the 3-interpreter composite, and small helpers. Cover each §12 row via observable state — no reliance on `ConsumableCharges` internals:

1. **owned but not hung** — a `consumable:heal_potion` ref in `owned` only: `_interpreter.interpret(...)` yields no consumable action; `ConsumableBinder().grant(...)` leaves the pool at `0`.
2. **hung, fight starts** — one hung `heal_potion` ref: after `grant`, `resources.currentOf(owner, consumableChargeResource('heal_potion')) == 1`; the interpreter yields a `SelfEffectAction` whose `costEffects` is `[ConsumeResource('consumable:heal_potion', 1)]`.
3. **2 identical hung** — two `heal_potion` refs → pool `2` (`2 × per-copy charges`).
4. **resource cap** — set the pool to `3` via `grant` (3 refs) and assert `resources.currentOf(...) == 3` (not clamped to 1); also `resources.definitionOf(key)!.max == double.infinity`.
5. **used N times then filtered** — with the pool at `1`, run the `heal_potion` action through `CombatSystem.executeAction` once (spends the charge → pool `0`); then `ScoredActionSelector().selectAction(...)` over `[healAction, aFallbackAttack]` with a HealthComponent low enough that the heal would otherwise score highest does **not** return the heal action (its `_isAvailable` is false at `0`); executing it anyway `CombatSystem`-side heals nothing (cost can't be afforded).
6. **fight ends (incl. a throw)** — `grant` a `power_tonic` (self, `GrantModifier` on `'thrown'`), execute its action so a `consumable:power_tonic:<owner>` modifier is live, then `ConsumableCharges.dispose()`: pool → `0` and `activeModifiersFor(owner, 'thrown', components)` is empty. Call `dispose()` twice — no throw, no change.
7. **partial fight setup** — construct a `CombatStage` directly with a **stub `CompositeBuildActionInterpreter`** whose `interpret` returns normally but which makes `ConsumableBinder.grant` throw (e.g. a consumable ref whose content id is registered but `consumableDefinitionFromContent` throws — feed a deliberately malformed consumable into `context.content` and hang it). Assert: `runFight` propagates the throw, AND afterward the aura's trigger produces no effect (the `AuraBinding` was disposed by the `finally`), AND no `consumable:*` resource is non-zero. *(If wiring a throwing stub through `CombatStage` proves too heavy, assert the equivalent directly: `AuraBinder().bind` succeeds, then a `try { ConsumableBinder().grant(throwing build) } finally { auraBinding.dispose() }` — and confirm the aura no longer fires. Name whichever form you used in the report.)*
8. **next fight refreshed** — dispose the fight-1 `ConsumableCharges`, `grant` a fresh one from the same build → pool back to the full aggregate.
9. **determinism** — run the whole §12-row-2/5 sequence twice from a fresh `_ctx()` each time (fixed `RngService(1)`), asserting identical resulting health / pool / modifier state; and (for `cleanse_tonic`) apply a synthetic `status:poison`, execute the cleanse action, assert the `StatusComponent` is gone — twice, identically.

- [ ] **Step 2: Run it**

Run: `dart test test/integration/per_fight_consumable_test.dart`
Expected: PASS (one test per §12 row). Adjust magnitudes only to match the shipped content (`heal_potion` = 20, `power_tonic` = +6 on `'thrown'`); the invariants are what must hold.

- [ ] **Step 3: Full suite + lint + push**

Run: `dart test && dart analyze`
Expected: entire suite green; `No issues found!`

```bash
git add test/integration/per_fight_consumable_test.dart
git commit -m "$(printf 'test(consumable): SP3 acceptance invariant end to end\n\nowned+loose -> no action/charge; hung -> pool = per-copy sum; 2 copies\n-> 2; unbounded resource not clamped; N uses then _isAvailable false;\nfight end (incl. throw) zeroes pools + removes consumable modifiers,\nidempotent; partial setup disposes the aura binding; next fight\nrefreshed; deterministic.\n\nCo-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>\nClaude-Session: https://claude.ai/code/session_01USc4vgCm9nma1UBaEd5c7z')"
git push
```

---

## Self-Review

**Spec coverage:**

| Spec section | Task(s) |
|---|---|
| §3.1 `consumable` plugin (unbounded charge resources) | 4 |
| §3.1 strict validation in `consumableDefinitionFromContent` | 4 |
| §3.1 `ConsumableActionInterpreter` (+ composite) | 5, 8 |
| §3.1 `ConsumableBinder`/`ConsumableCharges` | 6 |
| §3.1 `RemoveAllStatuses`, `GrantModifier`, `RuleContext.modifiers`, `'removeAllStatuses'` factory | 1, 2, 3 |
| §3.1 `ConsumableAwareActionScorer` | 7 |
| §3.1 `CombatStage.runFight` exception-safe + scorer | 8 |
| §3.1 run content (reward pool, `resolveReward`, `placeConsumable`) | 9 |
| §3.1 5→4 consumable content pass | 9 (deviation #2) |
| §5.1.1 `max: double.infinity`, aggregate pool, invariant | 4 (define), 6 (grant), 11 (rows 3-4) |
| §5.1.2 target/effect matrix, parser-time | 4 |
| §5.1.3 exactly-one-variant, all malformed cases, `ContentFieldException` → `ContentValidationException` | 4 |
| §5.2 interpreter mapping; `attack` + empty `targets` → null | 5 |
| §5.3 `RemoveAllStatuses` | 1 |
| §5.4 `GrantModifier` + `RuleContext.modifiers`; `RuleEngine._fire` unchanged; no factory | 2, 3 |
| §5.5 `ConsumableBinder`; grant ≠ reconciliation | 6, 11 (row 8) |
| §5.6 scorer; `effectsFor` safe; plain-`AttackAction` regression | 7 |
| §5.7 exception-safe setup; grant-throws-after-bind test | 8, 11 (row 7) |
| §5.8 reward/placement wiring; reward-pool-only | 9 |
| §8 determinism; golden regen; flip triage | 9 |
| §9 tests | 1,2,3,4,5,6,7,9,11 |
| §11 completion criteria | 10 (docs), 11 (acceptance) |
| §12 acceptance invariant table | 11 |

**Placeholder scan:** Task 8's integration test file is intentionally thin with `skip`/placeholder asserts that Task 9 fills and Task 11 completes — flagged in-task, not silent. Task 9 Step 8 and Task 11 Step 1 describe test *shape* rather than full code because they are seed-sweep / multi-row integration tests whose exact seed and magnitudes must be discovered against the built content — each lists the concrete assertions required and the observable signal. Every library-code step contains full code. No `TODO`/`TBD` in shipped code.

**Type consistency:** `consumableChargeResource(String) → String` used identically in Tasks 4/5/6/9/11. `ConsumableEffectSpec` sealed subclasses (`ConsumableHeal.amount`, `ConsumableAttack.damage/stat`, `ConsumableGrantModifier.stat/operation/value`, `ConsumableRemoveAllStatuses`) match between the definition (Task 4) and the interpreter `switch` (Task 5). `ConsumableBinder.grant({build, context}) → ConsumableCharges` / `ConsumableCharges.dispose()` identical in Tasks 6/8/11. `GrantModifier(stat, operation, value, {priority, sourceKey})` identical in Tasks 3/5. `ConsumableAwareActionScorer({base, missingHealthWeight, buffBonus})` identical in Tasks 7/8. `AttackAction`/`SelfEffectAction` `priority` param added in Task 5, consumed there and in Task 7's tests. `RuleContext.modifiers` added in Task 2, consumed in Task 3.

**Ordering:** Tasks 1→2→3 build the Core primitives (2 before 3: `GrantModifier` needs `RuleContext.modifiers`). 4 needs 3 (`ModifierOperation` for the parser — actually only `build_engine` barrel; but the interpreter Task 5 needs `GrantModifier` from Task 3). 5 needs 4 (`ConsumableEffectSpec`) + 3 (`GrantModifier`) + 1 (`RemoveAllStatuses`). 6 needs 4. 7 needs 5 (`SelfEffectAction.priority` for its tests) + nothing else. 8 needs 5+6+7. 9 needs 8. 10/11 last. Chain is sound.

---

## Execution Handoff

Plan complete and saved to `docs/superpowers/plans/2026-09-07-per-fight-consumables-sp3.md`. Two execution options:

**1. Subagent-Driven (recommended)** — I dispatch a fresh subagent per task, review between tasks (spec + quality), broad whole-branch review at the end.

**2. Inline Execution** — I execute tasks in this session using executing-plans, with checkpoints for review.

Which approach?
