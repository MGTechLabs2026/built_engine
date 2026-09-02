# Technique Inspiration / Discovery (SP0b) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** New technique variants are generated from how the player actually fights — a post-training discovery roll that blends the descriptors of their high-mastery, heavily-used variants onto the trained family.

**Architecture:** A new optional `CombatAction.sourceRef` field (set by `TechniqueActionInterpreter`) lets the composition layer attribute each performed action to a technique-variant instance, accumulated in a `TechniqueUsageComponent`. A pure `TechniqueInspirationResolver` turns (inspirers + descriptor pool + `RngService`) into an `InspirationResult`; `resolveTechniqueInspirationAfterTraining` is the one authoritative post-training hook that gathers inspirers, runs the resolver, mints on a hit, and publishes `TechniqueVariantInspired`. The `technique/` plugin stays Combat-free — the `ActionCompleted` → usage bridge lives in the harness's existing subscription.

**Tech Stack:** Dart, `package:build_engine` (Core → Combat → BuildInterpretation → Technique / MartialArts), `dart test`, `dart analyze`.

**Spec:** `docs/superpowers/specs/2026-09-03-technique-inspiration-design.md`

## Global Constraints

- **Contract (`claude.md`):** Core provides verbs, plugins provide nouns; no giant classes; no speculative abstraction; RNG only through `RngService` (`context.rng`); dependencies point downward; one authoritative publisher per domain event.
- **`lib/src/plugins/technique/` must name neither `combat` nor `martial_arts`** — `test/integration/architecture_dependency_test.dart` greps for `combat_plugin.dart` / `combat/` / `martial_arts_plugin.dart` / `martial_arts/` under that directory and fails on any match. No new import there.
- **`sourceRef` is behaviour-neutral:** set once at interpretation, read-only after; never enters damage math, modifier resolution, action ordering, or RNG. Combat outcomes must be byte-identical with and without it populated.
- **Descriptor content type string is `'technique_descriptor'`** (load-bearing: `martial_technique_content_test.dart` / `content_expansion_audit_test.dart` assert counts).
- **Negative axes are preserved:** the resolver's emphasis/selection math uses positive axis contributions only, but the minted variant's `axisProfile` (built by `TechniqueVariantResolver` over the drawn descriptors) keeps every axis, negatives included. SP0b strips nothing.
- **New variants start `masteryLevel 0` / `usage 0`** and therefore cannot inspire until they independently cross the thresholds — no `canInspire` flag; the behaviour falls out of the eligibility filter.
- **At most one discovery per training session** — enforced by the single resolver roll in the one hook call; no cooldown, no persistent state.
- **Real style ids** are `MartialStyles.polearming` / `wrestling` / `fencing` / `shaolin` / `taiChi` / `kunlun`. There is no `boxing` / `wing_chun`.
- **Tuning constant values (copy verbatim):** `kInspirationBaseChance = 0.05`, `kInspirationConcentrationGain = 0.55`, `kMinMasteryToInspire = 1`, `kMinUsageToInspire = 3`, `kInspirationExcludeRetries = 3`, `kInspirationStrongMasteryBar = 2`, `kInspirationStrongWeightBar = 6.0`.
- **Do not** implement SP1 (tiered `EffectProfile`), retire the evolution path, touch `ItemActionInterpreter`, or modify `Tome_client`.
- After every task: `dart test test/plugins/technique/ test/plugins/build_interpretation/ test/plugins/martial_arts/` + `dart analyze`. Before completion: full `dart test` + `dart analyze` + `dart test test/integration/architecture_dependency_test.dart`.
- Commits (in order, with trailers per repo convention):
  1. `feat(technique): implement inspiration weighting and eligibility`
  2. `feat(technique): add descriptor compatibility to inspiration`
  3. `test(technique): lock SP0b discovery invariants`
  Tasks below map onto these three; group task commits under the closest message, or use the task-scoped message shown in the task's commit step.

## File Structure

**New**

- `lib/src/plugins/technique/technique_usage.dart` — `TechniqueUsageComponent` (one `Map<EntityId,int>`), `recordTechniqueVariantUsage`, `forgetTechniqueVariantUsage`, `techniqueVariantUsage`. Core-only imports.
- `lib/src/plugins/technique/technique_inspiration.dart` — `Inspirer`, `InspirationResult`, `TechniqueInspirationResolver`, `descriptorCompatibleWithFamily`, `resolveTechniqueInspirationAfterTraining`. Imports Core + sibling `technique/` files only.
- `lib/src/plugins/martial_arts/style_centre.dart` — `styleCentre(styleId, familyId)` + a `const` table.
- Tests: `test/plugins/combat/combat_action_source_ref_test.dart`, `test/plugins/build_interpretation/technique_action_interpreter_source_ref_test.dart`, `test/plugins/technique/technique_usage_test.dart`, `test/plugins/technique/technique_inspiration_resolver_test.dart`, `test/plugins/technique/technique_inspiration_flow_test.dart`, `test/plugins/martial_arts/style_centre_test.dart`, `test/plugins/game/combat_stage_usage_test.dart`.

**Modified**

- `lib/src/plugins/combat/combat_action.dart` — `sourceRef` getter on `CombatAction` (default `=> null`); `sourceRef` param + `@override` field on `AttackAction` (same file).
- `lib/src/plugins/build_interpretation/self_effect_action.dart` — `sourceRef` param + `@override` field.
- `lib/src/plugins/build_interpretation/technique_action_interpreter.dart` — pass `sourceRef: ref` on every built action.
- `lib/src/plugins/technique/technique_events.dart` — `TechniqueVariantInspired`.
- `lib/src/plugins/technique/technique_vocabulary.dart` — 7 tuning constants + `techniqueFamilyTagPrefix`.
- `lib/src/plugins/technique/technique_variant_lifecycle.dart` — rename `_requireVariant` → `requireTechniqueVariant`, `_familyOf` → `techniqueFamilyOf` (visibility only); `removeTechniqueVariant` calls `forgetTechniqueVariantUsage`.
- `lib/technique_plugin.dart` — export `technique_usage.dart`, `technique_inspiration.dart`.
- `lib/martial_arts_plugin.dart` — export `style_centre.dart`.
- `lib/src/plugins/game/combat_stage.dart` — extend the existing `ActionCompleted` subscription.
- `lib/src/plugins/game/training_stage.dart` — new `styleId` field; one hook call after the evolution block.
- `lib/src/plugins/game/game_run.dart` — pass `styleId` to `TrainingStage`.
- `CHANGELOG.md`, `ARCHITECTURE.md`.

---

### Task 1: `CombatAction.sourceRef` seam

**Files:**
- Modify: `lib/src/plugins/combat/combat_action.dart`
- Modify: `lib/src/plugins/build_interpretation/self_effect_action.dart`
- Test: `test/plugins/combat/combat_action_source_ref_test.dart`

**Interfaces:**
- Produces:
  - `BuildComponentRef? get sourceRef` on `abstract class CombatAction`, default implementation `=> null` (so `MartialTechniqueAction` and every test action keep compiling untouched).
  - `AttackAction({..., BuildComponentRef? sourceRef})` → `@override final BuildComponentRef? sourceRef;`
  - `SelfEffectAction({..., BuildComponentRef? sourceRef})` → `@override final BuildComponentRef? sourceRef;`
- `BuildComponentRef` is already exported from `package:build_engine/build_engine.dart`, which both files already import.

- [ ] **Step 1: Write the failing test**

```dart
// test/plugins/combat/combat_action_source_ref_test.dart
import 'package:build_engine/build_engine.dart';
import 'package:build_engine/combat_plugin.dart';
import 'package:build_engine/src/plugins/build_interpretation/self_effect_action.dart';
import 'package:test/test.dart';

const _ref = BuildComponentRef(
  referenceType: 'technique',
  contentId: 'basic_punch',
  instanceEntityId: EntityId(42),
);

void main() {
  test('CombatAction.sourceRef defaults to null', () {
    const action = SelfEffectAction(actor: EntityId(1));
    expect(action.sourceRef, isNull);
  });

  test('AttackAction carries a sourceRef when given one', () {
    const action = AttackAction(
      actor: EntityId(1),
      targets: [EntityId(2)],
      baseDamage: 5,
      damageStat: 'fist',
      sourceRef: _ref,
    );
    expect(action.sourceRef, same(_ref));
  });

  test('SelfEffectAction carries a sourceRef when given one', () {
    const action = SelfEffectAction(actor: EntityId(1), sourceRef: _ref);
    expect(action.sourceRef, same(_ref));
  });

  test('sourceRef does not change effectsFor output (behaviour-neutral)', () {
    final ctx = _newCombatContext();
    const withRef = AttackAction(
      actor: EntityId(1), targets: [EntityId(2)],
      baseDamage: 7, damageStat: 'fist', sourceRef: _ref,
    );
    const withoutRef = AttackAction(
      actor: EntityId(1), targets: [EntityId(2)],
      baseDamage: 7, damageStat: 'fist',
    );
    final a = withRef.effectsFor(const EntityId(2), ctx);
    final b = withoutRef.effectsFor(const EntityId(2), ctx);
    expect(a.map((e) => e.toString()), b.map((e) => e.toString()));
  });
}

PluginContext _newCombatContext() {
  final events = EventBus();
  final entities = EntityRegistry(events);
  final components = ComponentStore();
  final rng = RngService(1);
  final shared = CoreServices(components: components, events: events);
  return PluginContext(
    entities: entities, components: components, events: events, rng: rng,
    rules: RuleEngine(
      entities: entities, components: components, events: events,
      rng: rng, shared: shared),
    queries: QueryEngine(QueryScope(components: components)),
    modifiers: ModifierCollection(),
    content: ContentRegistry(),
    shared: shared,
  );
}
```

- [ ] **Step 2: Run it, verify it fails**

Run: `dart test test/plugins/combat/combat_action_source_ref_test.dart`
Expected: compile failure — `No named parameter with the name 'sourceRef'` / `The getter 'sourceRef' isn't defined`.

- [ ] **Step 3: Add the getter to `CombatAction`**

In `lib/src/plugins/combat/combat_action.dart`, inside `abstract class CombatAction`, after the `priority` getter:

```dart
  /// The build component this action was interpreted from, if any — set
  /// by the build-interpretation layer (`TechniqueActionInterpreter`).
  /// Carries `referenceType` + `contentId` + `instanceEntityId`. `null`
  /// for an action with no build origin (a bare-handed fallback strike, a
  /// rule-spawned action). Consumers: SP0b per-variant usage, SP1 active
  /// tier. Never read by `CombatSystem` — behaviour-neutral, exactly like
  /// [priority]. Defaults to `null` so no existing `CombatAction`
  /// implementation needs to change.
  BuildComponentRef? get sourceRef => null;
```

- [ ] **Step 4: Add the field to `AttackAction`**

Still in `combat_action.dart`, in `class AttackAction`:

```dart
  const AttackAction({
    required this.actor,
    required this.targets,
    required this.baseDamage,
    required this.damageStat,
    this.conditions = const [],
    this.costEffects = const [],
    this.sourceRef,
  });
```

and with the other fields:

```dart
  @override
  final BuildComponentRef? sourceRef;
```

- [ ] **Step 5: Add the field to `SelfEffectAction`**

In `lib/src/plugins/build_interpretation/self_effect_action.dart`, in `class SelfEffectAction`:

```dart
  const SelfEffectAction({
    required this.actor,
    this.conditions = const [],
    this.costEffects = const [],
    this.selfEffects = const [],
    this.sourceRef,
  });
```

and:

```dart
  @override
  final BuildComponentRef? sourceRef;
```

- [ ] **Step 6: Run the test + neighbours**

Run: `dart test test/plugins/combat/ test/plugins/build_interpretation/`
Expected: PASS, no analyzer warnings.

- [ ] **Step 7: Run the combat regression guard**

Run: `dart test test/plugins/combat/combat_system_test.dart`
Expected: unchanged PASS — nothing in `CombatSystem` reads `sourceRef`.

- [ ] **Step 8: Commit**

```bash
git add lib/src/plugins/combat/combat_action.dart \
        lib/src/plugins/build_interpretation/self_effect_action.dart \
        test/plugins/combat/combat_action_source_ref_test.dart
git commit -m "feat(combat): add behaviour-neutral CombatAction.sourceRef seam"
```

---

### Task 2: `TechniqueActionInterpreter` sets `sourceRef`

**Files:**
- Modify: `lib/src/plugins/build_interpretation/technique_action_interpreter.dart`
- Test: `test/plugins/build_interpretation/technique_action_interpreter_source_ref_test.dart`

**Interfaces:**
- Consumes: `AttackAction.sourceRef` / `SelfEffectAction.sourceRef` (Task 1).
- Produces: every `CombatAction` `TechniqueActionInterpreter.interpret` returns has `sourceRef` equal to the `BuildComponentRef` it was interpreted from.

- [ ] **Step 1: Write the failing test**

```dart
// test/plugins/build_interpretation/technique_action_interpreter_source_ref_test.dart
import 'package:build_engine/build_engine.dart';
import 'package:build_engine/combat_plugin.dart';
import 'package:build_engine/src/plugins/build_interpretation/self_effect_action.dart';
import 'package:build_engine/src/plugins/build_interpretation/technique_action_interpreter.dart';
import 'package:build_engine/technique_plugin.dart';
import 'package:test/test.dart';

PluginContext _ctx() {
  final events = EventBus();
  final entities = EntityRegistry(events);
  final components = ComponentStore();
  final rng = RngService(1);
  final shared = CoreServices(components: components, events: events);
  final c = PluginContext(
    entities: entities, components: components, events: events, rng: rng,
    rules: RuleEngine(
      entities: entities, components: components, events: events,
      rng: rng, shared: shared),
    queries: QueryEngine(QueryScope(components: components)),
    modifiers: ModifierCollection(),
    content: ContentRegistry(),
    shared: shared,
  );
  c.content.loadAll(techniqueContentDefinitions);
  return c;
}

void main() {
  test('an attack action carries the sourceRef of its technique component', () {
    final ctx = _ctx();
    const actor = EntityId(1);
    const enemy = EntityId(2);
    const ref = BuildComponentRef(
      referenceType: techniqueReferenceType,
      contentId: TechniqueIds.basicPunch,
      instanceEntityId: EntityId(99),
    );
    final build = ActiveBuild([ref]);

    final actions = const TechniqueActionInterpreter().interpret(
      build: build, actor: actor, targets: [enemy], context: ctx);

    expect(actions, hasLength(1));
    expect(actions.single, isA<AttackAction>());
    expect(actions.single.sourceRef, same(ref));
  });

  test('a guard action carries the sourceRef of its technique component', () {
    final ctx = _ctx();
    const ref = BuildComponentRef(
      referenceType: techniqueReferenceType,
      contentId: TechniqueIds.basicGuard,
      instanceEntityId: EntityId(7),
    );
    final actions = const TechniqueActionInterpreter().interpret(
      build: ActiveBuild([ref]), actor: const EntityId(1),
      targets: const [EntityId(2)], context: ctx);

    expect(actions.single, isA<SelfEffectAction>());
    expect(actions.single.sourceRef, same(ref));
  });
}
```

> If `ActiveBuild`'s constructor differs, mirror an existing
> `technique_action_interpreter` test's build construction — do not invent
> an API.

- [ ] **Step 2: Run it, verify it fails**

Run: `dart test test/plugins/build_interpretation/technique_action_interpreter_source_ref_test.dart`
Expected: FAIL — `sourceRef` is `null`.

- [ ] **Step 3: Thread `ref` through `_actionFor`**

In `technique_action_interpreter.dart`, change `_actionFor` to take the ref and pass it:

```dart
  CombatAction? _actionFor(
    TechniqueDefinition technique,
    EntityId actor,
    List<EntityId> targets,
    BuildComponentRef ref,
  ) {
    if (technique.tags.contains('guard')) {
      return SelfEffectAction(
        actor: actor,
        selfEffects: [ApplyStatus('status:guard:${technique.id}')],
        sourceRef: ref,
      );
    }
    final damage = technique.properties['damage'];
    if (damage == null || targets.isEmpty) return null;
    return AttackAction(
      actor: actor,
      targets: targets,
      baseDamage: damage,
      damageStat: _damageStatFor(technique),
      sourceRef: ref,
    );
  }
```

and at the call site in `interpret`:

```dart
      final action = _actionFor(technique, actor, targets, ref);
```

- [ ] **Step 4: Run the test + neighbours**

Run: `dart test test/plugins/build_interpretation/`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/src/plugins/build_interpretation/technique_action_interpreter.dart \
        test/plugins/build_interpretation/technique_action_interpreter_source_ref_test.dart
git commit -m "feat(build-interpretation): set sourceRef on interpreted technique actions"
```

---

### Task 3: Tuning constants, family-tag prefix, and public renames

**Files:**
- Modify: `lib/src/plugins/technique/technique_vocabulary.dart`
- Modify: `lib/src/plugins/technique/technique_variant_lifecycle.dart`
- Test: `test/plugins/technique/technique_vocabulary_test.dart` (create if absent) or add to `technique_variant_lifecycle_test.dart`

**Interfaces:**
- Produces:
  - `const kInspirationBaseChance = 0.05;` `const kInspirationConcentrationGain = 0.55;` `const kMinMasteryToInspire = 1;` `const kMinUsageToInspire = 3;` `const kInspirationExcludeRetries = 3;` `const kInspirationStrongMasteryBar = 2;` `const kInspirationStrongWeightBar = 6.0;`
  - `const techniqueFamilyTagPrefix = 'family:';`
  - `TechniqueVariant requireTechniqueVariant(EntityId instanceId, PluginContext context)` (was `_requireVariant`) — still throws `TechniqueVariantNotFoundException`.
  - `String techniqueFamilyOf(String legacyId, PluginContext context)` (was `_familyOf`) — behaviour unchanged.

- [ ] **Step 1: Write the failing test**

```dart
// test/plugins/technique/technique_vocabulary_test.dart
import 'package:build_engine/build_engine.dart';
import 'package:build_engine/src/plugins/technique/technique_content.dart';
import 'package:build_engine/src/plugins/technique/technique_variant.dart';
import 'package:build_engine/src/plugins/technique/technique_variant_lifecycle.dart';
import 'package:build_engine/src/plugins/technique/technique_vocabulary.dart';
import 'package:test/test.dart';

void main() {
  test('inspiration tuning constants have their spec values', () {
    expect(kInspirationBaseChance, 0.05);
    expect(kInspirationConcentrationGain, 0.55);
    expect(kMinMasteryToInspire, 1);
    expect(kMinUsageToInspire, 3);
    expect(kInspirationExcludeRetries, 3);
    expect(kInspirationStrongMasteryBar, 2);
    expect(kInspirationStrongWeightBar, 6.0);
    expect(techniqueFamilyTagPrefix, 'family:');
  });

  test('techniqueFamilyOf maps an evolved id to its base family', () {
    final ctx = _ctx()..content.loadAll(techniqueContentDefinitions);
    expect(techniqueFamilyOf(TechniqueIds.heavyPunch, ctx), TechniqueIds.basicPunch);
    expect(techniqueFamilyOf(TechniqueIds.basicKick, ctx), TechniqueIds.basicKick);
  });

  test('requireTechniqueVariant throws for an unknown instance', () {
    final ctx = _ctx();
    expect(
      () => requireTechniqueVariant(const EntityId(123), ctx),
      throwsA(isA<TechniqueVariantNotFoundException>()),
    );
  });
}

PluginContext _ctx() {
  final events = EventBus();
  final entities = EntityRegistry(events);
  final components = ComponentStore();
  final rng = RngService(1);
  final shared = CoreServices(components: components, events: events);
  return PluginContext(
    entities: entities, components: components, events: events, rng: rng,
    rules: RuleEngine(
      entities: entities, components: components, events: events,
      rng: rng, shared: shared),
    queries: QueryEngine(QueryScope(components: components)),
    modifiers: ModifierCollection(),
    content: ContentRegistry(),
    shared: shared,
  );
}
```

- [ ] **Step 2: Run it, verify it fails**

Run: `dart test test/plugins/technique/technique_vocabulary_test.dart`
Expected: FAIL — undefined names.

- [ ] **Step 3: Add the constants**

Append to `lib/src/plugins/technique/technique_vocabulary.dart`:

```dart
// ── SP0b: technique inspiration / discovery tuning ───────────────────
// Placeholder magnitudes — tuned against `game_run` balance sweeps; each
// is a named constant, never inlined in the resolver.

/// Discovery probability at zero usage concentration.
const kInspirationBaseChance = 0.05;

/// How much a fully concentrated usage pattern (one dominant inspirer)
/// adds to the discovery probability. `p` tops out near `0.60` at `c == 1`.
const kInspirationConcentrationGain = 0.55;

/// An inspirer must be at least this per-instance mastery level.
const kMinMasteryToInspire = 1;

/// ...and must have performed at least this many combat actions this run.
const kMinUsageToInspire = 3;

/// The weighted draw re-rolls past an already-owned descriptor set at
/// most this many times before giving up.
const kInspirationExcludeRetries = 3;

/// Mean eligible-inspirer mastery at or above this makes a multi-source
/// blend "strong" (a candidate for a 3rd descriptor).
const kInspirationStrongMasteryBar = 2;

/// ...and the summed damped inspirer weight must also reach this.
const kInspirationStrongWeightBar = 6.0;

/// Descriptor tag prefix that restricts a descriptor to one base family,
/// e.g. `family:basic_kick`. A descriptor with no such tag is universal.
/// The suffix is the full base id (matches `techniqueFamilyOf`'s return).
const techniqueFamilyTagPrefix = 'family:';
```

- [ ] **Step 4: Rename `_requireVariant` and `_familyOf`**

In `lib/src/plugins/technique/technique_variant_lifecycle.dart`:
- Rename `TechniqueVariant _requireVariant(` → `TechniqueVariant requireTechniqueVariant(` and update its doc comment's first line to name the public function. Update all in-file call sites (`hangTechniqueVariant`, `trainTechniqueVariantMastery`, `techniqueVariantMasteryLevel`, `removeTechniqueVariant`).
- Rename `String _familyOf(` → `String techniqueFamilyOf(` and its call site in `mintVariantForLegacyEvolvedId`. Update the doc comment to note it is public so SP0b's inspiration hook can reuse it.

Both are auto-exported: `lib/technique_plugin.dart` already re-exports the whole file.

- [ ] **Step 5: Run the test + the SP0a suite**

Run: `dart test test/plugins/technique/`
Expected: PASS (the SP0a lifecycle tests still green — visibility-only rename).

- [ ] **Step 6: Commit**

```bash
git add lib/src/plugins/technique/technique_vocabulary.dart \
        lib/src/plugins/technique/technique_variant_lifecycle.dart \
        test/plugins/technique/technique_vocabulary_test.dart
git commit -m "feat(technique): add inspiration tuning constants; promote family/require helpers"
```

---

### Task 4: `TechniqueUsageComponent` + usage reducer/accessor

**Files:**
- Create: `lib/src/plugins/technique/technique_usage.dart`
- Modify: `lib/technique_plugin.dart` (export)
- Modify: `lib/src/plugins/technique/technique_variant_lifecycle.dart` (`removeTechniqueVariant` drops the entry)
- Test: `test/plugins/technique/technique_usage_test.dart`

**Interfaces:**
- Consumes: `requireTechniqueVariant` (Task 3), `TechniqueVariant.owner`.
- Produces:
  - `class TechniqueUsageComponent { const TechniqueUsageComponent(this.byInstance); final Map<EntityId, int> byInstance; }`
  - `void recordTechniqueVariantUsage(EntityId instanceId, PluginContext context)` — `+1` on the owner's component; throws `TechniqueVariantNotFoundException` for an unknown instance.
  - `void forgetTechniqueVariantUsage(EntityId instanceId, PluginContext context)` — rebuild the owner's map without `instanceId`; no-op if absent.
  - `int techniqueVariantUsage(EntityId instanceId, PluginContext context)` — `0` when no component / no entry; throws for an unknown instance.

- [ ] **Step 1: Write the failing test**

```dart
// test/plugins/technique/technique_usage_test.dart
import 'package:build_engine/build_engine.dart';
import 'package:build_engine/src/plugins/technique/technique_content.dart';
import 'package:build_engine/src/plugins/technique/technique_descriptor_content.dart';
import 'package:build_engine/src/plugins/technique/technique_usage.dart';
import 'package:build_engine/src/plugins/technique/technique_variant_lifecycle.dart';
import 'package:test/test.dart';

PluginContext _ctx() {
  final events = EventBus();
  final entities = EntityRegistry(events);
  final components = ComponentStore();
  final rng = RngService(1);
  final shared = CoreServices(components: components, events: events);
  final c = PluginContext(
    entities: entities, components: components, events: events, rng: rng,
    rules: RuleEngine(
      entities: entities, components: components, events: events,
      rng: rng, shared: shared),
    queries: QueryEngine(QueryScope(components: components)),
    modifiers: ModifierCollection(),
    content: ContentRegistry(),
    shared: shared,
  );
  c.content.loadAll(techniqueDescriptorContentDefinitions);
  c.content.loadAll(techniqueContentDefinitions);
  return c;
}

void main() {
  late PluginContext ctx;
  late EntityId owner;
  setUp(() {
    ctx = _ctx();
    owner = ctx.entities.create();
  });

  test('usage starts at zero and increments per recorded action', () {
    final id = mintTechniqueVariant(owner, 'basic_punch', {'bear'}, ctx);
    expect(techniqueVariantUsage(id, ctx), 0);
    recordTechniqueVariantUsage(id, ctx);
    recordTechniqueVariantUsage(id, ctx);
    expect(techniqueVariantUsage(id, ctx), 2);
  });

  test('two instances are tracked independently', () {
    final a = mintTechniqueVariant(owner, 'basic_punch', {'bear'}, ctx);
    final b = mintTechniqueVariant(owner, 'basic_kick', {'swift'}, ctx);
    recordTechniqueVariantUsage(a, ctx);
    expect(techniqueVariantUsage(a, ctx), 1);
    expect(techniqueVariantUsage(b, ctx), 0);
  });

  test('an unknown instance id throws', () {
    expect(() => recordTechniqueVariantUsage(const EntityId(999), ctx),
        throwsA(isA<TechniqueVariantNotFoundException>()));
    expect(() => techniqueVariantUsage(const EntityId(999), ctx),
        throwsA(isA<TechniqueVariantNotFoundException>()));
  });

  test('removeTechniqueVariant drops the usage entry', () {
    final id = mintTechniqueVariant(owner, 'basic_punch', {'bear'}, ctx);
    recordTechniqueVariantUsage(id, ctx);
    removeTechniqueVariant(id, ctx);
    final usage = ctx.components.get<TechniqueUsageComponent>(owner);
    expect(usage == null || !usage.byInstance.containsKey(id), isTrue);
  });

  test('forgetTechniqueVariantUsage on an absent instance is a no-op', () {
    final id = mintTechniqueVariant(owner, 'basic_punch', {'bear'}, ctx);
    forgetTechniqueVariantUsage(id, ctx); // never recorded
    expect(techniqueVariantUsage(id, ctx), 0);
  });
}
```

- [ ] **Step 2: Run it, verify it fails**

Run: `dart test test/plugins/technique/technique_usage_test.dart`
Expected: FAIL — `technique_usage.dart` does not exist.

- [ ] **Step 3: Create `technique_usage.dart`**

```dart
// lib/src/plugins/technique/technique_usage.dart
import 'package:build_engine/build_engine.dart';

import 'technique_variant_lifecycle.dart' show requireTechniqueVariant;

/// Per-run tally of how many combat actions each of an owner's technique
/// variant instances has performed. Pure ECS state on the fighter entity.
/// Not persisted — a run's fresh `PluginContext` starts it empty, the
/// same lifetime bound SP0a's per-instance `MasteryDefinition`s have.
///
/// This file imports Core only. The `ActionCompleted` → usage bridge that
/// *feeds* it lives in the composition layer (it needs Combat's event
/// vocabulary, which `lib/src/plugins/technique/` may not name); it calls
/// [recordTechniqueVariantUsage].
class TechniqueUsageComponent {
  const TechniqueUsageComponent(this.byInstance);
  final Map<EntityId, int> byInstance;
}

/// `+1` to variant [instanceId]'s performed-action count on its owner's
/// [TechniqueUsageComponent] (created if absent). Owner is read from
/// `TechniqueVariant.owner` (rule 5). Throws
/// `TechniqueVariantNotFoundException` for an unknown instance id.
void recordTechniqueVariantUsage(EntityId instanceId, PluginContext context) {
  final owner = requireTechniqueVariant(instanceId, context).owner;
  final existing = context.components.get<TechniqueUsageComponent>(owner);
  final next = <EntityId, int>{...?existing?.byInstance};
  next[instanceId] = (next[instanceId] ?? 0) + 1;
  context.components.add<TechniqueUsageComponent>(
      owner, TechniqueUsageComponent(next));
}

/// Rebuilds the owner's [TechniqueUsageComponent] without [instanceId] —
/// the same rebuild pattern `removeTechniqueVariant` uses for
/// `MasteryComponent`. No-op if there is no component or no entry.
void forgetTechniqueVariantUsage(EntityId instanceId, PluginContext context) {
  final owner = requireTechniqueVariant(instanceId, context).owner;
  final existing = context.components.get<TechniqueUsageComponent>(owner);
  if (existing == null || !existing.byInstance.containsKey(instanceId)) return;
  final trimmed = Map<EntityId, int>.of(existing.byInstance)..remove(instanceId);
  context.components.add<TechniqueUsageComponent>(
      owner, TechniqueUsageComponent(trimmed));
}

/// Variant [instanceId]'s performed-action count this run — `0` if never
/// recorded. Owner read from `TechniqueVariant.owner`. Throws
/// `TechniqueVariantNotFoundException` for an unknown instance id.
int techniqueVariantUsage(EntityId instanceId, PluginContext context) {
  final owner = requireTechniqueVariant(instanceId, context).owner;
  final usage = context.components.get<TechniqueUsageComponent>(owner);
  return usage?.byInstance[instanceId] ?? 0;
}
```

- [ ] **Step 4: Wire `removeTechniqueVariant`**

In `technique_variant_lifecycle.dart`, add the import:

```dart
import 'technique_usage.dart' show forgetTechniqueVariantUsage;
```

In `removeTechniqueVariant`, immediately after the `MasteryComponent` trim block and before `context.components.remove<TechniqueVariant>(instanceId);`:

```dart
  forgetTechniqueVariantUsage(instanceId, context);
```

Update `removeTechniqueVariant`'s doc-comment step list: insert "2b. drop any per-instance combat-usage tally" alongside the mastery-progress step.

- [ ] **Step 5: Export from the barrel**

In `lib/technique_plugin.dart`, add (keep the list alphabetical-ish, matching the existing order):

```dart
export 'src/plugins/technique/technique_usage.dart';
```

- [ ] **Step 6: Run the test + the SP0a suite**

Run: `dart test test/plugins/technique/`
Expected: PASS. `dart analyze` clean (watch for an import cycle warning — `technique_usage.dart` ↔ `technique_variant_lifecycle.dart` is a legal mutual import in Dart; if the analyzer complains, it is a real error, stop and reconsider).

- [ ] **Step 7: Commit**

```bash
git add lib/src/plugins/technique/technique_usage.dart \
        lib/src/plugins/technique/technique_variant_lifecycle.dart \
        lib/technique_plugin.dart \
        test/plugins/technique/technique_usage_test.dart
git commit -m "feat(technique): per-variant combat usage tracking"
```

---

### Task 5: Inspiration value types + `TechniqueVariantInspired` event

**Files:**
- Create: `lib/src/plugins/technique/technique_inspiration.dart` (types only, this task)
- Modify: `lib/src/plugins/technique/technique_events.dart`
- Modify: `lib/technique_plugin.dart` (export `technique_inspiration.dart`)
- Test: `test/plugins/technique/technique_inspiration_resolver_test.dart` (types portion)

**Interfaces:**
- Produces:
  - `class Inspirer { const Inspirer({required this.instanceId, required this.axisProfile, required this.masteryLevel, required this.usage}); final EntityId instanceId; final Map<String, num> axisProfile; final int masteryLevel; final int usage; }`
  - `class InspirationResult { const InspirationResult({required this.discovered, required this.familyId, required this.descriptorIds, required this.inspirerInstanceIds}); final bool discovered; final String familyId; final Set<String> descriptorIds; final List<EntityId> inspirerInstanceIds; static const none = InspirationResult(discovered: false, familyId: '', descriptorIds: {}, inspirerInstanceIds: []); }`
  - `class TechniqueVariantInspired { const TechniqueVariantInspired({required this.owner, required this.instanceId, required this.familyId, required this.descriptorIds, required this.inspirerInstanceIds}); final EntityId owner; final EntityId instanceId; final String familyId; final Set<String> descriptorIds; final List<EntityId> inspirerInstanceIds; }`

- [ ] **Step 1: Write the failing test**

```dart
// test/plugins/technique/technique_inspiration_resolver_test.dart
import 'package:build_engine/build_engine.dart';
import 'package:build_engine/src/plugins/technique/technique_events.dart';
import 'package:build_engine/src/plugins/technique/technique_inspiration.dart';
import 'package:test/test.dart';

void main() {
  test('InspirationResult.none is an empty, not-discovered result', () {
    expect(InspirationResult.none.discovered, isFalse);
    expect(InspirationResult.none.familyId, '');
    expect(InspirationResult.none.descriptorIds, isEmpty);
    expect(InspirationResult.none.inspirerInstanceIds, isEmpty);
  });

  test('Inspirer holds its instance, profile, mastery and usage', () {
    const i = Inspirer(
      instanceId: EntityId(3),
      axisProfile: {'power': 6, 'speed': -1},
      masteryLevel: 2,
      usage: 9,
    );
    expect(i.instanceId, const EntityId(3));
    expect(i.axisProfile['power'], 6);
    expect(i.masteryLevel, 2);
    expect(i.usage, 9);
  });

  test('TechniqueVariantInspired carries descriptors and inspirer ids', () {
    const e = TechniqueVariantInspired(
      owner: EntityId(1),
      instanceId: EntityId(2),
      familyId: 'basic_kick',
      descriptorIds: {'strong', 'swift'},
      inspirerInstanceIds: [EntityId(3), EntityId(4)],
    );
    expect(e.familyId, 'basic_kick');
    expect(e.descriptorIds, {'strong', 'swift'});
    expect(e.inspirerInstanceIds, [const EntityId(3), const EntityId(4)]);
  });
}
```

- [ ] **Step 2: Run it, verify it fails**

Run: `dart test test/plugins/technique/technique_inspiration_resolver_test.dart`
Expected: FAIL — files/types missing.

- [ ] **Step 3: Create `technique_inspiration.dart` with the types**

```dart
// lib/src/plugins/technique/technique_inspiration.dart
import 'package:build_engine/build_engine.dart';

/// One of an owner's technique-variant instances, offered to
/// [TechniqueInspirationResolver] as raw material. The caller does **not**
/// pre-filter — the resolver applies the eligibility test itself.
class Inspirer {
  const Inspirer({
    required this.instanceId,
    required this.axisProfile,
    required this.masteryLevel,
    required this.usage,
  });

  /// The variant entity — reported back in [InspirationResult] and the
  /// event, never used in the resolver's arithmetic.
  final EntityId instanceId;

  /// The variant's stored `TechniqueVariant.axisProfile` (signed).
  final Map<String, num> axisProfile;

  /// Per-instance mastery level, `0..3`.
  final int masteryLevel;

  /// Combat actions performed this run, `>= 0`.
  final int usage;
}

/// The outcome of one discovery roll. `discovered == false` ⇒ every other
/// field is empty ([none]).
class InspirationResult {
  const InspirationResult({
    required this.discovered,
    required this.familyId,
    required this.descriptorIds,
    required this.inspirerInstanceIds,
  });

  final bool discovered;

  /// `== trainedFamilyId` on a hit; `''` otherwise.
  final String familyId;

  /// `1..3` descriptor ids on a hit; empty otherwise.
  final Set<String> descriptorIds;

  /// The eligible inspirers the resolver actually used; `[]` on a miss.
  final List<EntityId> inspirerInstanceIds;

  static const none = InspirationResult(
    discovered: false,
    familyId: '',
    descriptorIds: {},
    inspirerInstanceIds: [],
  );
}
```

- [ ] **Step 4: Add the event**

Append to `lib/src/plugins/technique/technique_events.dart`:

```dart
/// One training session inspired a new derived variant. Published exactly
/// once per discovery, from exactly one place —
/// `resolveTechniqueInspirationAfterTraining` — mirroring
/// `TechniqueEvolved`'s single-publisher discipline. Lineage / telemetry
/// / UI consumers subscribe from
/// `package:build_engine/technique_plugin.dart`. RNG internals and
/// intermediate scores are deliberately not exposed.
class TechniqueVariantInspired {
  const TechniqueVariantInspired({
    required this.owner,
    required this.instanceId,
    required this.familyId,
    required this.descriptorIds,
    required this.inspirerInstanceIds,
  });

  final EntityId owner;

  /// The freshly minted variant.
  final EntityId instanceId;

  /// Its base family (`== the trained family`).
  final String familyId;

  /// The drawn descriptors — lets a client name the result.
  final Set<String> descriptorIds;

  /// The eligible variants that influenced it.
  final List<EntityId> inspirerInstanceIds;
}
```

- [ ] **Step 5: Export from the barrel**

In `lib/technique_plugin.dart`:

```dart
export 'src/plugins/technique/technique_inspiration.dart';
```

- [ ] **Step 6: Run the test**

Run: `dart test test/plugins/technique/technique_inspiration_resolver_test.dart test/plugins/technique/technique_events_test.dart`
Expected: PASS (existing `technique_events_test.dart`, if present, still green).

- [ ] **Step 7: Commit**

```bash
git add lib/src/plugins/technique/technique_inspiration.dart \
        lib/src/plugins/technique/technique_events.dart \
        lib/technique_plugin.dart \
        test/plugins/technique/technique_inspiration_resolver_test.dart
git commit -m "feat(technique): inspiration value types and TechniqueVariantInspired event"
```

---

### Task 6: `TechniqueInspirationResolver` — eligibility, weighting, emphasis, concentration, roll

**Files:**
- Modify: `lib/src/plugins/technique/technique_inspiration.dart` (add the resolver + `descriptorCompatibleWithFamily`)
- Test: `test/plugins/technique/technique_inspiration_resolver_test.dart`

**Interfaces:**
- Consumes: `Inspirer`, `InspirationResult` (Task 5); `TechniqueDescriptor` / `TechniqueDescriptor.axes` / `.tags`; `techniqueFamilyTagPrefix`, all `kInspiration*` / `kMin*` constants (Task 3); `RngService`, `weightedPick` (Core barrel).
- Produces:
  - `class TechniqueInspirationResolver { const TechniqueInspirationResolver(); InspirationResult resolve({required String trainedFamilyId, required Iterable<Inspirer> inspirers, required Iterable<TechniqueDescriptor> descriptorPool, required RngService rng, Set<Set<String>> exclude = const {}}); }`
  - `bool descriptorCompatibleWithFamily(TechniqueDescriptor d, String familyId)`

- [ ] **Step 1: Write the failing tests**

Add to `test/plugins/technique/technique_inspiration_resolver_test.dart`:

```dart
import 'dart:math' as math;
import 'package:build_engine/src/plugins/technique/technique_descriptor.dart';
import 'package:build_engine/src/plugins/technique/technique_vocabulary.dart';

TechniqueDescriptor _d(String id, Map<String, num> axes, {Set<String> tags = const {}}) =>
    TechniqueDescriptor(id: id, axes: axes, tags: tags);

Inspirer _insp(int id, Map<String, num> axes, {int mastery = 2, int usage = 9}) =>
    Inspirer(instanceId: EntityId(id), axisProfile: axes, masteryLevel: mastery, usage: usage);

const _resolver = TechniqueInspirationResolver();

void _resolverTests() {
  group('eligibility', () {
    test('zero inspirers → none, and the rng is not drawn', () {
      final rng = RngService(7);
      final res = _resolver.resolve(
        trainedFamilyId: 'basic_punch',
        inspirers: const [],
        descriptorPool: [_d('strong', {'power': 4})],
        rng: rng,
      );
      expect(res.discovered, isFalse);
      // no draw happened: first value matches a fresh generator
      expect(rng.nextDouble(), RngService(7).nextDouble());
    });

    test('an inspirer below the mastery OR usage bar is filtered out', () {
      final res = _resolver.resolve(
        trainedFamilyId: 'basic_punch',
        inspirers: [
          _insp(1, {'power': 6}, mastery: 0, usage: 30), // mastery too low
          _insp(2, {'speed': 5}, mastery: 3, usage: 1),  // usage too low
        ],
        descriptorPool: [_d('strong', {'power': 4})],
        rng: RngService(1),
      );
      expect(res.discovered, isFalse); // nothing eligible
    });

    test('exactly one eligible inspirer can still discover; concentration is 1', () {
      // base 0.05 + gain 0.55 * 1.0 = 0.60 → a seed whose first draw < 0.60 hits
      final res = _resolver.resolve(
        trainedFamilyId: 'basic_punch',
        inspirers: [_insp(1, {'power': 8}, mastery: 3, usage: 30)],
        descriptorPool: [_d('strong', {'power': 4})],
        rng: _seedWithFirstDrawBelow(0.60),
      );
      expect(res.discovered, isTrue);
      expect(res.inspirerInstanceIds, [const EntityId(1)]);
    });
  });

  group('damped weighting', () {
    test('weight grows with mastery at equal usage', () {
      // Verified indirectly: with two equal-usage inspirers on different
      // axes, the higher-mastery one dominates emphasis → its axis is the
      // one drawn under a fixed seed.
      final res = _resolver.resolve(
        trainedFamilyId: 'basic_punch',
        inspirers: [
          _insp(1, {'power': 5}, mastery: 3, usage: 9),
          _insp(2, {'speed': 5}, mastery: 1, usage: 9),
        ],
        descriptorPool: [_d('strong', {'power': 4}), _d('swift', {'speed': 5})],
        rng: _seedThatDiscoversAndDraws(),
      );
      expect(res.descriptorIds.contains('strong'), isTrue);
    });

    test('usage contributes with diminishing returns (√usage)', () {
      // w(usage=4)/w(usage=1) == 2, not 4 — assert via concentration.
      // inspirer A: mastery 1, usage 4 → w = 1*2 = 2
      // inspirer B: mastery 1, usage 1 → w = 1*1 = 1
      // concentration = 2 / 3 ≈ 0.6667 → p = 0.05 + 0.55*0.6667 ≈ 0.4167
      final hit = _resolver.resolve(
        trainedFamilyId: 'basic_punch',
        inspirers: [
          _insp(1, {'power': 5}, mastery: 1, usage: 4),
          _insp(2, {'power': 5}, mastery: 1, usage: 1),
        ],
        descriptorPool: [_d('strong', {'power': 4})],
        rng: _seedWithFirstDrawBelow(0.41),
      );
      final miss = _resolver.resolve(
        trainedFamilyId: 'basic_punch',
        inspirers: [
          _insp(1, {'power': 5}, mastery: 1, usage: 4),
          _insp(2, {'power': 5}, mastery: 1, usage: 1),
        ],
        descriptorPool: [_d('strong', {'power': 4})],
        rng: _seedWithFirstDrawAtLeast(0.42),
      );
      expect(hit.discovered, isTrue);
      expect(miss.discovered, isFalse); // p ≈ 0.4167, so a 0.42 draw misses
    });

    test('usage == 0 contributes nothing; all-zero-usage eligible → none', () {
      final res = _resolver.resolve(
        trainedFamilyId: 'basic_punch',
        inspirers: [_insp(1, {'power': 5}, mastery: 3, usage: 0)],
        descriptorPool: [_d('strong', {'power': 4})],
        rng: RngService(1),
      );
      // usage 0 fails kMinUsageToInspire (3) anyway → none
      expect(res.discovered, isFalse);
    });
  });

  group('emphasis uses positive axes only', () {
    test("a bear-like inspirer's negative speed never suppresses a speed draw", () {
      // Single eligible inspirer {power: 6, speed: -1}. Emphasis = {power: 1.0}
      // (speed dropped, not -x). With only a speed descriptor available and
      // no positive overlap, the draw finds nothing → none (not a
      // "negative pushed it away" artefact — verified by the pool-swap below).
      final noOverlap = _resolver.resolve(
        trainedFamilyId: 'basic_punch',
        inspirers: [_insp(1, {'power': 6, 'speed': -1}, mastery: 3, usage: 30)],
        descriptorPool: [_d('swift', {'speed': 5})],
        rng: _seedWithFirstDrawBelow(0.60),
      );
      expect(noOverlap.discovered, isFalse); // rolled a hit, but 0 positive-overlap candidates

      final withOverlap = _resolver.resolve(
        trainedFamilyId: 'basic_punch',
        inspirers: [_insp(1, {'power': 6, 'speed': -1}, mastery: 3, usage: 30)],
        descriptorPool: [_d('strong', {'power': 4})],
        rng: _seedWithFirstDrawBelow(0.60),
      );
      expect(withOverlap.descriptorIds, {'strong'});
    });
  });

  group('concentration & roll bounds', () {
    test('p stays in [0,1] and is monotonic in concentration', () {
      // even 3-way spread → c ≈ 0.333 → p ≈ 0.233; one dominant → c ≈ 1 → p ≈ 0.6
      final spread = _resolver.resolve(
        trainedFamilyId: 'basic_punch',
        inspirers: [
          _insp(1, {'power': 5}, mastery: 2, usage: 9),
          _insp(2, {'power': 5}, mastery: 2, usage: 9),
          _insp(3, {'power': 5}, mastery: 2, usage: 9),
        ],
        descriptorPool: [_d('strong', {'power': 4})],
        rng: _seedWithFirstDrawBelow(0.24),
      );
      expect(spread.discovered, isTrue);
      final spreadMiss = _resolver.resolve(
        trainedFamilyId: 'basic_punch',
        inspirers: [
          _insp(1, {'power': 5}, mastery: 2, usage: 9),
          _insp(2, {'power': 5}, mastery: 2, usage: 9),
          _insp(3, {'power': 5}, mastery: 2, usage: 9),
        ],
        descriptorPool: [_d('strong', {'power': 4})],
        rng: _seedWithFirstDrawAtLeast(0.24),
      );
      expect(spreadMiss.discovered, isFalse);
    });
  });

  group('determinism', () {
    test('identical inputs + RngService(seed) → identical result twice', () {
      InspirationResult run() => _resolver.resolve(
            trainedFamilyId: 'basic_punch',
            inspirers: [
              _insp(1, {'power': 6}, mastery: 3, usage: 16),
              _insp(2, {'speed': 5}, mastery: 2, usage: 9),
            ],
            descriptorPool: [
              _d('strong', {'power': 4}),
              _d('swift', {'speed': 5}),
              _d('iron', {'power': 5, 'endurance': 2}),
            ],
            rng: RngService(20260903),
          );
      final a = run();
      final b = run();
      expect(a.discovered, b.discovered);
      expect(a.descriptorIds, b.descriptorIds);
      expect(a.inspirerInstanceIds, b.inspirerInstanceIds);
    });
  });
}

// --- seed helpers: RngService is a deterministic LCG-ish stream; scan
// seeds until the first nextDouble() lands where the test needs it. Keep
// the scan bounded and assert it found one.
RngService _seedWithFirstDrawBelow(double bound) => _scanSeed((v) => v < bound);
RngService _seedWithFirstDrawAtLeast(double bound) => _scanSeed((v) => v >= bound);
RngService _seedThatDiscoversAndDraws() => _seedWithFirstDrawBelow(0.60);

RngService _scanSeed(bool Function(double first) ok) {
  for (var s = 1; s < 5000; s++) {
    if (ok(RngService(s).nextDouble())) return RngService(s);
  }
  fail('no seed found for the required first draw');
}
```

And register it: in `main()` add `_resolverTests();` plus, near the compatibility work in the next task, `_compatibilityTests();`.

> The seed-scan helpers keep these tests robust to `RngService`'s exact
> algorithm. If the resolver draws the discovery roll first (it must —
> see Step 3), `_seedWithFirstDrawBelow` reliably forces a hit/miss.

- [ ] **Step 2: Run, verify failure**

Run: `dart test test/plugins/technique/technique_inspiration_resolver_test.dart`
Expected: FAIL — `TechniqueInspirationResolver` undefined.

- [ ] **Step 3: Implement the resolver (steps 0–4 + the draw skeleton)**

Add to `lib/src/plugins/technique/technique_inspiration.dart`:

```dart
import 'dart:math' show sqrt;

import 'technique_descriptor.dart';
import 'technique_vocabulary.dart';
```

```dart
/// Whether descriptor [d] may be drawn for a variant of base family
/// [familyId]. A descriptor with no `family:` tag is universal; one with
/// any `family:` tag is compatible only if one of them names [familyId].
bool descriptorCompatibleWithFamily(TechniqueDescriptor d, String familyId) {
  final familyTags =
      d.tags.where((t) => t.startsWith(techniqueFamilyTagPrefix)).toList();
  if (familyTags.isEmpty) return true;
  return familyTags.contains('$techniqueFamilyTagPrefix$familyId');
}

/// Pure blend of an owner's high-mastery, heavily-used technique variants
/// into a descriptor set for a new variant on the trained family. A
/// `const` class with one method, drawing randomness only from the
/// injected [RngService] — mirrors `EvolutionResolver` / `RewardResolver`.
class TechniqueInspirationResolver {
  const TechniqueInspirationResolver();

  InspirationResult resolve({
    required String trainedFamilyId,
    required Iterable<Inspirer> inspirers,
    required Iterable<TechniqueDescriptor> descriptorPool,
    required RngService rng,
    Set<Set<String>> exclude = const {},
  }) {
    // Step 0 — eligibility (return before touching rng).
    final eligible = [
      for (final i in inspirers)
        if (i.masteryLevel >= kMinMasteryToInspire &&
            i.usage >= kMinUsageToInspire)
          i,
    ];
    if (eligible.isEmpty) return InspirationResult.none;

    // Step 1 — damped inspirer weights: w = mastery * sqrt(usage).
    final weights = [
      for (final i in eligible) i.masteryLevel * sqrt(i.usage),
    ];
    final totalWeight = weights.fold<double>(0, (s, w) => s + w);
    if (totalWeight <= 0) return InspirationResult.none;

    // Step 2 — emphasis E from positive axis contributions only.
    final emphasis = <String, double>{};
    for (var n = 0; n < eligible.length; n++) {
      final w = weights[n];
      eligible[n].axisProfile.forEach((axis, mag) {
        if (mag > 0) emphasis[axis] = (emphasis[axis] ?? 0) + w * mag;
      });
    }
    final emphasisTotal = emphasis.values.fold<double>(0, (s, v) => s + v);
    if (emphasisTotal <= 0) return InspirationResult.none;
    emphasis.updateAll((_, v) => v / emphasisTotal);

    // Step 3 — concentration c = max weight / total weight.
    final maxWeight = weights.reduce((a, b) => a > b ? a : b);
    final concentration = maxWeight / totalWeight;

    // Step 4 — the single discovery roll (the one-per-training guarantee).
    final p = (kInspirationBaseChance +
            kInspirationConcentrationGain * concentration)
        .clamp(0.0, 1.0);
    if (rng.nextDouble() >= p) return InspirationResult.none;

    // Steps 5–8 — compatible pool, k, weighted draw, exclusion retry.
    return _draw(
      trainedFamilyId: trainedFamilyId,
      eligible: eligible,
      weights: weights,
      totalWeight: totalWeight,
      emphasis: emphasis,
      descriptorPool: descriptorPool,
      rng: rng,
      exclude: exclude,
    );
  }

  InspirationResult _draw({
    required String trainedFamilyId,
    required List<Inspirer> eligible,
    required List<double> weights,
    required double totalWeight,
    required Map<String, double> emphasis,
    required Iterable<TechniqueDescriptor> descriptorPool,
    required RngService rng,
    required Set<Set<String>> exclude,
  }) {
    // Step 5 — compatible descriptor pool.
    final compatible = [
      for (final d in descriptorPool)
        if (descriptorCompatibleWithFamily(d, trainedFamilyId)) d,
    ];
    if (compatible.isEmpty) return InspirationResult.none;

    // Step 6 — descriptor count k.
    final meanMastery =
        eligible.map((i) => i.masteryLevel).reduce((a, b) => a + b) /
            eligible.length;
    final strong = meanMastery >= kInspirationStrongMasteryBar &&
        totalWeight >= kInspirationStrongWeightBar;
    var k = eligible.length >= 2 ? 2 : 1;
    if (eligible.length >= 2 && strong) k = 3;
    k = k.clamp(1, 3);
    if (k > compatible.length) k = compatible.length;

    final inspirerIds = [for (final i in eligible) i.instanceId];

    // Steps 7–8 — weighted draw without replacement, exclusion retry.
    for (var attempt = 0; attempt <= kInspirationExcludeRetries; attempt++) {
      final remaining = [...compatible];
      final picked = <String>{};
      for (var d = 0; d < k; d++) {
        final chosen = weightedPick(
          remaining,
          (cand) => _overlap(emphasis, cand),
          rng,
        );
        if (chosen == null) break; // no positive-overlap candidate left
        picked.add(chosen.id);
        remaining.remove(chosen);
      }
      if (picked.isEmpty) return InspirationResult.none;
      final isExcluded = exclude.any((s) => _setEquals(s, picked));
      if (!isExcluded) {
        return InspirationResult(
          discovered: true,
          familyId: trainedFamilyId,
          descriptorIds: picked,
          inspirerInstanceIds: inspirerIds,
        );
      }
      // excluded → loop, redrawing with the already-advanced rng.
    }
    return InspirationResult.none;
  }
}

double _overlap(Map<String, double> emphasis, TechniqueDescriptor d) {
  var sum = 0.0;
  d.axes.forEach((axis, mag) {
    if (mag > 0) sum += (emphasis[axis] ?? 0) * mag;
  });
  return sum;
}

bool _setEquals(Set<String> a, Set<String> b) =>
    a.length == b.length && a.every(b.contains);
```

- [ ] **Step 4: Run the tests**

Run: `dart test test/plugins/technique/technique_inspiration_resolver_test.dart`
Expected: PASS. `dart analyze` clean.

- [ ] **Step 5: Commit**

```bash
git add lib/src/plugins/technique/technique_inspiration.dart \
        test/plugins/technique/technique_inspiration_resolver_test.dart
git commit -m "feat(technique): implement inspiration weighting and eligibility"
```

---

### Task 7: Resolver — descriptor compatibility, count, weighted draw, exclusion

**Files:**
- Modify: `test/plugins/technique/technique_inspiration_resolver_test.dart` (compatibility / count / draw / exclusion cases)
- Modify: `lib/src/plugins/technique/technique_inspiration.dart` only if a case exposes a defect

**Interfaces:**
- Consumes/Produces: unchanged from Task 6 — this task is the behavioural lock for steps 5–8 that Task 6 implemented.

- [ ] **Step 1: Write the failing/característica tests**

Add a `_compatibilityTests()` group to the resolver test file and call it from `main()`:

```dart
void _compatibilityTests() {
  group('descriptorCompatibleWithFamily', () {
    test('no family tag → universal', () {
      expect(descriptorCompatibleWithFamily(_d('strong', {'power': 4}), 'basic_kick'), isTrue);
    });
    test('matching family tag → compatible', () {
      expect(
        descriptorCompatibleWithFamily(
          _d('kicker', {'power': 4}, tags: {'family:basic_kick'}), 'basic_kick'),
        isTrue);
    });
    test('non-matching family tag → incompatible', () {
      expect(
        descriptorCompatibleWithFamily(
          _d('puncher', {'power': 4}, tags: {'family:basic_punch'}), 'basic_kick'),
        isFalse);
    });
  });

  group('draw respects compatibility', () {
    test('a family:basic_kick descriptor is never drawn for basic_punch training', () {
      final res = _resolver.resolve(
        trainedFamilyId: 'basic_punch',
        inspirers: [_insp(1, {'power': 8}, mastery: 3, usage: 30)],
        descriptorPool: [
          _d('kickonly', {'power': 9}, tags: {'family:basic_kick'}),
          _d('strong', {'power': 4}),
        ],
        rng: _seedWithFirstDrawBelow(0.60),
      );
      expect(res.descriptorIds, {'strong'});
    });

    test('all pooled descriptors restricted away → none', () {
      final res = _resolver.resolve(
        trainedFamilyId: 'basic_punch',
        inspirers: [_insp(1, {'power': 8}, mastery: 3, usage: 30)],
        descriptorPool: [_d('kickonly', {'power': 9}, tags: {'family:basic_kick'})],
        rng: _seedWithFirstDrawBelow(0.60),
      );
      expect(res.discovered, isFalse);
    });
  });

  group('descriptor count k', () {
    List<TechniqueDescriptor> pool() => [
          _d('strong', {'power': 4}),
          _d('swift', {'speed': 5}),
          _d('iron', {'power': 5, 'endurance': 2}),
          _d('bull', {'power': 6}),
        ];

    test('single ordinary source → 1', () {
      final res = _resolver.resolve(
        trainedFamilyId: 'basic_punch',
        inspirers: [_insp(1, {'power': 5}, mastery: 1, usage: 9)],
        descriptorPool: pool(),
        rng: _seedWithFirstDrawBelow(0.60),
      );
      expect(res.descriptorIds, hasLength(1));
    });

    test('two ordinary sources → 2', () {
      final res = _resolver.resolve(
        trainedFamilyId: 'basic_punch',
        inspirers: [
          _insp(1, {'power': 5}, mastery: 1, usage: 9),
          _insp(2, {'speed': 5}, mastery: 1, usage: 9),
        ],
        descriptorPool: pool(),
        rng: _seedWithFirstDrawBelow(0.30),
      );
      expect(res.descriptorIds, hasLength(2));
    });

    test('two strong sources → 3 (mean mastery ≥ 2 and Σw ≥ 6.0)', () {
      // each: mastery 3, usage 9 → w = 3*3 = 9; Σw = 18; mean mastery 3
      final res = _resolver.resolve(
        trainedFamilyId: 'basic_punch',
        inspirers: [
          _insp(1, {'power': 6}, mastery: 3, usage: 9),
          _insp(2, {'speed': 6}, mastery: 3, usage: 9),
        ],
        descriptorPool: pool(),
        rng: _seedWithFirstDrawBelow(0.30),
      );
      expect(res.descriptorIds, hasLength(3));
    });

    test('k never exceeds the compatible pool size', () {
      final res = _resolver.resolve(
        trainedFamilyId: 'basic_punch',
        inspirers: [
          _insp(1, {'power': 6}, mastery: 3, usage: 9),
          _insp(2, {'speed': 6}, mastery: 3, usage: 9),
        ],
        descriptorPool: [_d('strong', {'power': 4})], // only 1 compatible
        rng: _seedWithFirstDrawBelow(0.30),
      );
      expect(res.descriptorIds, hasLength(1));
      expect(res.discovered, isTrue);
    });
  });

  group('exclusion retry', () {
    test('the only reachable blend is excluded → none after the retries', () {
      final res = _resolver.resolve(
        trainedFamilyId: 'basic_punch',
        inspirers: [_insp(1, {'power': 8}, mastery: 3, usage: 30)],
        descriptorPool: [_d('strong', {'power': 4})],
        rng: _seedWithFirstDrawBelow(0.60),
        exclude: {
          {'strong'}
        },
      );
      expect(res.discovered, isFalse);
    });

    test('a non-matching exclude set does not block the draw', () {
      final res = _resolver.resolve(
        trainedFamilyId: 'basic_punch',
        inspirers: [_insp(1, {'power': 8}, mastery: 3, usage: 30)],
        descriptorPool: [_d('strong', {'power': 4})],
        rng: _seedWithFirstDrawBelow(0.60),
        exclude: {
          {'swift'}
        },
      );
      expect(res.descriptorIds, {'strong'});
    });

    test('a near-duplicate ({strong,fast} vs owned {strong,swift}) is allowed', () {
      final res = _resolver.resolve(
        trainedFamilyId: 'basic_punch',
        inspirers: [
          _insp(1, {'power': 6}, mastery: 2, usage: 9),
          _insp(2, {'speed': 6}, mastery: 2, usage: 9),
        ],
        descriptorPool: [_d('strong', {'power': 4}), _d('fast', {'speed': 4})],
        rng: _seedWithFirstDrawBelow(0.30),
        exclude: {
          {'strong', 'swift'}
        },
      );
      expect(res.discovered, isTrue);
      expect(res.descriptorIds, {'strong', 'fast'});
    });
  });
}
```

- [ ] **Step 2: Run the tests**

Run: `dart test test/plugins/technique/technique_inspiration_resolver_test.dart`
Expected: mostly PASS from Task 6's implementation. If a `k`/draw/exclusion case fails, fix `_draw` minimally and re-run. Do not touch steps 0–4.

- [ ] **Step 3: If any seed helper cannot force the required probability** (e.g. `k == 2` needs `p` computed from a 2-inspirer concentration), adjust that test's `_seedWithFirstDrawBelow` bound to the actual `p` for its inspirer set (`p = 0.05 + 0.55 * maxW/ΣW`), computed by hand in a comment. Never weaken an assertion.

- [ ] **Step 4: Commit**

```bash
git add test/plugins/technique/technique_inspiration_resolver_test.dart \
        lib/src/plugins/technique/technique_inspiration.dart
git commit -m "feat(technique): add descriptor compatibility to inspiration"
```

---

### Task 8: `resolveTechniqueInspirationAfterTraining` hook

**Files:**
- Modify: `lib/src/plugins/technique/technique_inspiration.dart`
- Test: `test/plugins/technique/technique_inspiration_flow_test.dart`

**Interfaces:**
- Consumes: `TechniqueInspirationResolver` (Task 6/7); `ownedTechniqueVariants`, `mintTechniqueVariant`, `requireTechniqueVariant`, `techniqueFamilyOf` (Tasks 3–4); `techniqueVariantMasteryLevel`, `trainTechniqueVariantMastery` (SP0a); `techniqueVariantUsage`, `recordTechniqueVariantUsage` (Task 4); `techniqueDescriptorFromContent` + `ContentRegistry.allOfType('technique_descriptor')`; `TechniqueDefinition`; `TechniqueVariantInspired` (Task 5).
- Produces:
  - `InspirationResult resolveTechniqueInspirationAfterTraining(EntityId owner, TechniqueDefinition trainedTechnique, Map<String, num> styleCentre, PluginContext context, {String? styleId})` — one resolver roll; on a hit, `mintTechniqueVariant(owner, familyId, result.descriptorIds, context, styleId: styleId, styleCentre: styleCentre)` then publishes `TechniqueVariantInspired` exactly once; returns the `InspirationResult`.

- [ ] **Step 1: Write the failing test**

```dart
// test/plugins/technique/technique_inspiration_flow_test.dart
import 'package:build_engine/build_engine.dart';
import 'package:build_engine/src/plugins/technique/technique_content.dart';
import 'package:build_engine/src/plugins/technique/technique_descriptor_content.dart';
import 'package:build_engine/src/plugins/technique/technique_events.dart';
import 'package:build_engine/src/plugins/technique/technique_inspiration.dart';
import 'package:build_engine/src/plugins/technique/technique_usage.dart';
import 'package:build_engine/src/plugins/technique/technique_variant.dart';
import 'package:build_engine/src/plugins/technique/technique_variant_lifecycle.dart';
import 'package:build_engine/src/plugins/technique/technique_vocabulary.dart';
import 'package:test/test.dart';

PluginContext _ctx(int seed) {
  final events = EventBus();
  final entities = EntityRegistry(events);
  final components = ComponentStore();
  final rng = RngService(seed);
  final shared = CoreServices(components: components, events: events);
  final c = PluginContext(
    entities: entities, components: components, events: events, rng: rng,
    rules: RuleEngine(
      entities: entities, components: components, events: events,
      rng: rng, shared: shared),
    queries: QueryEngine(QueryScope(components: components)),
    modifiers: ModifierCollection(),
    content: ContentRegistry(),
    shared: shared,
  );
  c.content.loadAll(techniqueDescriptorContentDefinitions);
  c.content.loadAll(techniqueContentDefinitions);
  return c;
}

/// Mint an eligible inspirer: high mastery, plenty of recorded usage.
EntityId _eligibleInspirer(
    PluginContext ctx, EntityId owner, String family, Set<String> descriptors) {
  final id = mintTechniqueVariant(owner, family, descriptors, ctx);
  trainTechniqueVariantMastery(id, 999, ctx); // level 3
  for (var i = 0; i < 20; i++) {
    recordTechniqueVariantUsage(id, ctx);
  }
  return id;
}

/// Scan seeds for one whose run produces a discovery for [body].
int _seedThatDiscovers(bool Function(int seed) body) {
  for (var s = 1; s < 3000; s++) {
    if (body(s)) return s;
  }
  fail('no seed produced a discovery');
}

void main() {
  test('cross-pollination: high-mastery Punch usage inspires a Kick variant', () {
    late TechniqueVariantInspired event;
    var eventCount = 0;

    final seed = _seedThatDiscovers((s) {
      final ctx = _ctx(s);
      final owner = ctx.entities.create();
      _eligibleInspirer(ctx, owner, 'basic_punch', {'bear'});   // power
      _eligibleInspirer(ctx, owner, 'basic_punch', {'swift'});  // speed
      final res = resolveTechniqueInspirationAfterTraining(
        owner, techniqueDefinition('basic_kick', ctx), const {}, ctx);
      return res.discovered;
    });

    final ctx = _ctx(seed);
    final owner = ctx.entities.create();
    final punchA = _eligibleInspirer(ctx, owner, 'basic_punch', {'bear'});
    final punchB = _eligibleInspirer(ctx, owner, 'basic_punch', {'swift'});
    ctx.events.subscribe<TechniqueVariantInspired>((e) {
      event = e;
      eventCount++;
    });

    final res = resolveTechniqueInspirationAfterTraining(
      owner, techniqueDefinition('basic_kick', ctx), const {}, ctx,
      styleId: 'shaolin');

    expect(res.discovered, isTrue);
    expect(eventCount, 1);
    expect(event.familyId, 'basic_kick');
    final minted = ctx.components.get<TechniqueVariant>(event.instanceId)!;
    expect(minted.baseFamilyId, 'basic_kick');
    expect(minted.owner, owner);
    expect(minted.styleId, 'shaolin');
    expect(event.inspirerInstanceIds.toSet(), {punchA, punchB});
    // seeded by power/speed descriptors → at least one axis is power or speed
    expect(
      minted.axisProfile.keys.any((k) => k == 'power' || k == 'speed'),
      isTrue);
  });

  test('a newborn inspired variant cannot chain a second discovery', () {
    final seed = _seedThatDiscovers((s) {
      final ctx = _ctx(s);
      final owner = ctx.entities.create();
      _eligibleInspirer(ctx, owner, 'basic_punch', {'bear'});
      _eligibleInspirer(ctx, owner, 'basic_punch', {'swift'});
      return resolveTechniqueInspirationAfterTraining(
              owner, techniqueDefinition('basic_kick', ctx), const {}, ctx)
          .discovered;
    });
    final ctx = _ctx(seed);
    final owner = ctx.entities.create();
    _eligibleInspirer(ctx, owner, 'basic_punch', {'bear'});
    _eligibleInspirer(ctx, owner, 'basic_punch', {'swift'});
    final first = resolveTechniqueInspirationAfterTraining(
      owner, techniqueDefinition('basic_kick', ctx), const {}, ctx);
    expect(first.discovered, isTrue);

    // The freshly minted variant has mastery 0 / usage 0 → not eligible.
    var events = 0;
    ctx.events.subscribe<TechniqueVariantInspired>((_) => events++);
    // Re-run against the SAME still-eligible punches — still ≤ 1 discovery
    // per call, and the newborn contributes nothing.
    final second = resolveTechniqueInspirationAfterTraining(
      owner, techniqueDefinition('basic_kick', ctx), const {}, ctx);
    expect(second.inspirerInstanceIds, isNot(contains(first.instanceId)));
    expect(events, lessThanOrEqualTo(1));
  });

  test('below-threshold inspirers → no event, no mint', () {
    final ctx = _ctx(1);
    final owner = ctx.entities.create();
    final weak = mintTechniqueVariant(owner, 'basic_punch', {'bear'}, ctx);
    trainTechniqueVariantMastery(weak, 999, ctx);
    recordTechniqueVariantUsage(weak, ctx); // usage 1 < kMinUsageToInspire
    final before = ctx.components.entitiesWith<TechniqueVariant>().length;
    var events = 0;
    ctx.events.subscribe<TechniqueVariantInspired>((_) => events++);

    final res = resolveTechniqueInspirationAfterTraining(
      owner, techniqueDefinition('basic_kick', ctx), const {}, ctx);

    expect(res.discovered, isFalse);
    expect(events, 0);
    expect(ctx.components.entitiesWith<TechniqueVariant>().length, before);
  });

  test('inspirers are never mutated by a discovery', () {
    final seed = _seedThatDiscovers((s) {
      final ctx = _ctx(s);
      final owner = ctx.entities.create();
      _eligibleInspirer(ctx, owner, 'basic_punch', {'bear'});
      _eligibleInspirer(ctx, owner, 'basic_punch', {'swift'});
      return resolveTechniqueInspirationAfterTraining(
              owner, techniqueDefinition('basic_kick', ctx), const {}, ctx)
          .discovered;
    });
    final ctx = _ctx(seed);
    final owner = ctx.entities.create();
    final a = _eligibleInspirer(ctx, owner, 'basic_punch', {'bear'});
    final aBefore = ctx.components.get<TechniqueVariant>(a)!;
    final aProfileBefore = Map<String, num>.of(aBefore.axisProfile);
    final aMasteryBefore = techniqueVariantMasteryLevel(a, ctx);
    _eligibleInspirer(ctx, owner, 'basic_punch', {'swift'});

    resolveTechniqueInspirationAfterTraining(
      owner, techniqueDefinition('basic_kick', ctx), const {}, ctx);

    final aAfter = ctx.components.get<TechniqueVariant>(a)!;
    expect(aAfter.descriptorIds, aBefore.descriptorIds);
    expect(aAfter.axisProfile, aProfileBefore);
    expect(techniqueVariantMasteryLevel(a, ctx), aMasteryBefore);
  });
}
```

- [ ] **Step 2: Run it, verify it fails**

Run: `dart test test/plugins/technique/technique_inspiration_flow_test.dart`
Expected: FAIL — `resolveTechniqueInspirationAfterTraining` undefined.

- [ ] **Step 3: Implement the hook**

Add to `lib/src/plugins/technique/technique_inspiration.dart`:

```dart
import 'technique_content.dart' show techniqueDefinition;
import 'technique_events.dart';
import 'technique_usage.dart' show techniqueVariantUsage;
import 'technique_variant_lifecycle.dart'
    show
        mintTechniqueVariant,
        ownedTechniqueVariants,
        requireTechniqueVariant,
        techniqueFamilyOf,
        techniqueVariantMasteryLevel;
```

> `import` of `technique_descriptor.dart` for `techniqueDescriptorFromContent`
> is already present from Task 6.

```dart
/// The one authoritative "did this training session inspire a new
/// variant?" step — call once after a training session, parallel to
/// `resolveTechniqueEvolutionAfterTraining`. [styleCentre] is the trained
/// family's axis nudge for the character's style; the caller supplies it
/// (the technique plugin never imports `martial_arts`).
///
/// Gathers [owner]'s variant instances as [Inspirer]s (mastery + usage
/// from this plugin's own trackers — a newly minted variant has
/// `masteryLevel 0` / `usage 0` and so cannot inspire), runs
/// [TechniqueInspirationResolver] exactly once, and on a hit:
///   * `mintTechniqueVariant(owner, familyId, descriptorIds, context,
///      styleId: styleId, styleCentre: styleCentre)` — owned but loose,
///   * publishes [TechniqueVariantInspired] exactly once.
/// One call → one roll → at most one mint and one event. No cooldown, no
/// mutable state. Returns the [InspirationResult]; the caller owns
/// telemetry / UI. The inspirers are never touched.
InspirationResult resolveTechniqueInspirationAfterTraining(
  EntityId owner,
  TechniqueDefinition trainedTechnique,
  Map<String, num> styleCentre,
  PluginContext context, {
  String? styleId,
}) {
  final familyId = techniqueFamilyOf(trainedTechnique.id, context);

  final inspirers = <Inspirer>[];
  final exclude = <Set<String>>{};
  for (final e in ownedTechniqueVariants(owner, context)) {
    final v = requireTechniqueVariant(e, context);
    inspirers.add(Inspirer(
      instanceId: e,
      axisProfile: v.axisProfile,
      masteryLevel: techniqueVariantMasteryLevel(e, context),
      usage: techniqueVariantUsage(e, context),
    ));
    if (v.baseFamilyId == familyId) exclude.add(v.descriptorIds);
  }

  final pool = [
    for (final def in context.content.allOfType('technique_descriptor'))
      techniqueDescriptorFromContent(def),
  ];

  final result = const TechniqueInspirationResolver().resolve(
    trainedFamilyId: familyId,
    inspirers: inspirers,
    descriptorPool: pool,
    rng: context.rng,
    exclude: exclude,
  );
  if (!result.discovered) return result;

  final instance = mintTechniqueVariant(
    owner,
    familyId,
    result.descriptorIds,
    context,
    styleId: styleId,
    styleCentre: styleCentre,
  );
  context.events.publish(TechniqueVariantInspired(
    owner: owner,
    instanceId: instance,
    familyId: familyId,
    descriptorIds: result.descriptorIds,
    inspirerInstanceIds: result.inspirerInstanceIds,
  ));
  return result;
}
```

- [ ] **Step 4: Run the flow test + the whole technique suite**

Run: `dart test test/plugins/technique/`
Expected: PASS. `dart analyze` clean.

- [ ] **Step 5: Commit**

```bash
git add lib/src/plugins/technique/technique_inspiration.dart \
        test/plugins/technique/technique_inspiration_flow_test.dart
git commit -m "feat(technique): post-training inspiration hook and one-per-session publish"
```

---

### Task 9: `martial_arts` style-centre table

**Files:**
- Create: `lib/src/plugins/martial_arts/style_centre.dart`
- Modify: `lib/martial_arts_plugin.dart` (export)
- Test: `test/plugins/martial_arts/style_centre_test.dart`

**Interfaces:**
- Produces: `Map<String, num> styleCentre(String styleId, String familyId)` — a per-style, per-base-family axis nudge; `const {}` for any unlisted pair.

- [ ] **Step 1: Write the failing test**

```dart
// test/plugins/martial_arts/style_centre_test.dart
import 'package:build_engine/src/plugins/martial_arts/martial_styles.dart';
import 'package:build_engine/src/plugins/martial_arts/style_centre.dart';
import 'package:test/test.dart';

const _families = [
  'basic_punch', 'basic_slash', 'basic_guard',
  'basic_palm', 'basic_finger', 'basic_kick',
];
const _styles = [
  MartialStyles.polearming, MartialStyles.wrestling, MartialStyles.fencing,
  MartialStyles.shaolin, MartialStyles.taiChi, MartialStyles.kunlun,
];

void main() {
  test('a known style/family pair returns its nudge', () {
    expect(styleCentre(MartialStyles.wrestling, 'basic_punch'), {'power': 3});
    expect(styleCentre(MartialStyles.taiChi, 'basic_guard'), {'endurance': 3});
  });

  test('an unknown style or family returns an empty map', () {
    expect(styleCentre('made_up_style', 'basic_punch'), isEmpty);
    expect(styleCentre(MartialStyles.shaolin, 'made_up_family'), isEmpty);
  });

  test('every shipped style × base family resolves without throwing', () {
    for (final s in _styles) {
      for (final f in _families) {
        final centre = styleCentre(s, f);
        expect(centre, isA<Map<String, num>>());
        for (final v in centre.values) {
          expect(v, isA<num>());
        }
      }
    }
  });
}
```

- [ ] **Step 2: Run it, verify it fails**

Run: `dart test test/plugins/martial_arts/style_centre_test.dart`
Expected: FAIL — file missing.

- [ ] **Step 3: Create `style_centre.dart`**

```dart
// lib/src/plugins/martial_arts/style_centre.dart

/// The per-style, per-base-family axis nudge applied to a technique
/// variant minted while practising that style — passed by a composition
/// layer into `resolveTechniqueInspirationAfterTraining` /
/// `mintTechniqueVariant`'s `styleCentre` parameter. Content-shaped: a
/// `const` table today, a `ContentRegistry` batch later if it grows.
///
/// The family keys are the six Technique-plugin base ids
/// (`basic_punch` … `basic_kick`) as bare strings — MartialArts does not
/// import the Technique plugin. An unlisted style or family pair yields
/// `const {}` (a legitimate "no nudge").
Map<String, num> styleCentre(String styleId, String familyId) =>
    _styleCentres[styleId]?[familyId] ?? const {};

/// Axis keys mirror `TechniqueAxes` (`power` / `speed` / `endurance` /
/// `precision`). Magnitudes are deliberately small (1–3): a starting
/// bias, not a defining trait. Roughly follows each style's
/// `styleAlignedFamilies` lane.
const _styleCentres = <String, Map<String, Map<String, num>>>{
  // ── western ───────────────────────────────────────────────────────
  'polearming': {
    'basic_punch': {'precision': 1},
    'basic_slash': {},
    'basic_guard': {'endurance': 1},
    'basic_palm': {},
    'basic_finger': {'precision': 2},
    'basic_kick': {'power': 2},
  },
  'wrestling': {
    'basic_punch': {'power': 3},
    'basic_slash': {},
    'basic_guard': {'endurance': 3},
    'basic_palm': {'power': 1},
    'basic_finger': {},
    'basic_kick': {'endurance': 1},
  },
  'fencing': {
    'basic_punch': {'speed': 2},
    'basic_slash': {'speed': 2, 'precision': 1},
    'basic_guard': {'speed': 1},
    'basic_palm': {},
    'basic_finger': {'precision': 3},
    'basic_kick': {},
  },
  // ── eastern ───────────────────────────────────────────────────────
  'shaolin': {
    'basic_punch': {'power': 2, 'endurance': 1},
    'basic_slash': {},
    'basic_guard': {'endurance': 2},
    'basic_palm': {'power': 3},
    'basic_finger': {'precision': 1},
    'basic_kick': {'power': 2},
  },
  'taiChi': {
    'basic_punch': {},
    'basic_slash': {},
    'basic_guard': {'endurance': 3},
    'basic_palm': {'endurance': 2, 'precision': 1},
    'basic_finger': {'precision': 2},
    'basic_kick': {},
  },
  'kunlun': {
    'basic_punch': {'speed': 2},
    'basic_slash': {'speed': 3},
    'basic_guard': {},
    'basic_palm': {},
    'basic_finger': {'speed': 2, 'precision': 2},
    'basic_kick': {'speed': 1},
  },
};
```

- [ ] **Step 4: Export from the barrel**

In `lib/martial_arts_plugin.dart`, add (keep with the other `martial_arts/` exports):

```dart
export 'src/plugins/martial_arts/style_centre.dart';
```

- [ ] **Step 5: Run the test + the martial_arts suite + the architecture guard**

Run: `dart test test/plugins/martial_arts/ test/integration/architecture_dependency_test.dart`
Expected: PASS — `style_centre.dart` names no Technique symbol, so nothing new is coupled.

- [ ] **Step 6: Commit**

```bash
git add lib/src/plugins/martial_arts/style_centre.dart \
        lib/martial_arts_plugin.dart \
        test/plugins/martial_arts/style_centre_test.dart
git commit -m "feat(martial-arts): style-centre axis-nudge table"
```

---

### Task 10: Harness wiring + docs

**Files:**
- Modify: `lib/src/plugins/game/combat_stage.dart`
- Modify: `lib/src/plugins/game/training_stage.dart`
- Modify: `lib/src/plugins/game/game_run.dart`
- Modify: `CHANGELOG.md`, `ARCHITECTURE.md`
- Test: `test/plugins/game/combat_stage_usage_test.dart`

**Interfaces:**
- Consumes: `techniqueReferenceType`, `recordTechniqueVariantUsage` (Task 4); `resolveTechniqueInspirationAfterTraining` (Task 8); `styleCentre` (Task 9); `techniqueFamilyOf` (Task 3).
- Produces: `TrainingStage({..., required String styleId})`; usage recorded during harness fights; one inspiration hook call after the harness evolution block.

- [ ] **Step 1: Write the failing test**

```dart
// test/plugins/game/combat_stage_usage_test.dart
//
// The harness ActionCompleted subscription attributes a performed action
// to its technique-variant instance.
import 'package:build_engine/build_engine.dart';
import 'package:build_engine/combat_plugin.dart';
import 'package:build_engine/src/plugins/technique/technique_usage.dart';
import 'package:build_engine/technique_plugin.dart';
import 'package:test/test.dart';

void main() {
  test('an ActionCompleted for a technique-instance action bumps its usage', () {
    // This mirrors the three lines CombatStage.runFight adds to its
    // existing events.subscribe<ActionCompleted> handler.
    final events = EventBus();
    final entities = EntityRegistry(events);
    final components = ComponentStore();
    final rng = RngService(1);
    final shared = CoreServices(components: components, events: events);
    final ctx = PluginContext(
      entities: entities, components: components, events: events, rng: rng,
      rules: RuleEngine(
        entities: entities, components: components, events: events,
        rng: rng, shared: shared),
      queries: QueryEngine(QueryScope(components: components)),
      modifiers: ModifierCollection(),
      content: ContentRegistry(),
      shared: shared,
    );
    ctx.content.loadAll(techniqueContentDefinitions);
    final owner = ctx.entities.create();
    final instance = mintTechniqueVariant(owner, 'basic_punch', const {}, ctx);

    final sub = events.subscribe<ActionCompleted>((e) {
      final ref = e.action.sourceRef;
      if (ref != null &&
          ref.referenceType == techniqueReferenceType &&
          ref.instanceEntityId != null) {
        recordTechniqueVariantUsage(ref.instanceEntityId!, ctx);
      }
    });

    final action = AttackAction(
      actor: owner, targets: [const EntityId(999)],
      baseDamage: 1, damageStat: 'fist',
      sourceRef: BuildComponentRef(
        referenceType: techniqueReferenceType,
        contentId: 'basic_punch',
        instanceEntityId: instance,
      ),
    );
    events.publish(ActionCompleted(const EntityId(1), owner, const [EntityId(999)], action));
    events.publish(ActionCompleted(const EntityId(1), owner, const [EntityId(999)], action));
    sub.cancel();

    expect(techniqueVariantUsage(instance, ctx), 2);
  });

  test('a null / non-technique / instance-less sourceRef records nothing', () {
    // Same handler, actions that must be ignored: assert no throw and no
    // TechniqueUsageComponent appears.
    // (Full body mirrors the test above with sourceRef: null and with a
    //  ref whose instanceEntityId is null.)
  }, skip: 'fill in mirroring the first test');
}
```

> Flesh out the second case the same way; it exists to lock the guard
> conditions. Keep it un-skipped in the final commit.

- [ ] **Step 2: Run it, verify it fails** (the first test fails only if the wiring symbols are wrong; it should pass once Tasks 4/2/1 are in — its real purpose is documenting the handler. If it already passes, that is fine; proceed.)

Run: `dart test test/plugins/game/combat_stage_usage_test.dart`

- [ ] **Step 3: Extend `CombatStage.runFight`'s subscription**

In `lib/src/plugins/game/combat_stage.dart`, add the import:

```dart
import 'package:build_engine/technique_plugin.dart';
```

Change the existing subscription block:

```dart
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
```

(Preserve the original `if (e.battle == battle) turnsUsed++;` semantics — the early `return` is the equivalent.)

- [ ] **Step 4: Add the inspiration call to `TrainingStage`**

In `lib/src/plugins/game/training_stage.dart`:
- add `import 'package:build_engine/martial_arts_plugin.dart';`
- add a constructor field:

```dart
  TrainingStage({
    required this.character,
    required this.context,
    required this.recordingPolicy,
    required this.rng,
    required this.events,
    required this.tomeManager,
    required this.styleId,
  });
  ...
  final String styleId;
```

- inside `runTraining`, in the `else` (technique) branch, immediately after the `if (evolution.evolved) { ... }` block but still inside `if (learning.learned) {`:

```dart
        // SP0b: a training session may also *inspire* a brand-new loose
        // variant, seeded by the player's high-mastery / high-usage
        // variants. Parallel to evolution, never a replacement. In this
        // harness the player holds no TechniqueVariant instances yet
        // (the legacy learn/evolve path is still used), so this is inert
        // until a later pass migrates the harness — the call is here to
        // keep the one-authoritative-post-training-step shape visible and
        // compiled.
        final family = techniqueFamilyOf(technique.id, context);
        resolveTechniqueInspirationAfterTraining(
          character,
          technique,
          styleCentre(styleId, family),
          context,
          styleId: styleId,
        );
```

- [ ] **Step 5: Pass `styleId` from `game_run.dart`**

In `lib/src/plugins/game/game_run.dart`, in the `TrainingStage(` construction, add:

```dart
    styleId: styleId,
```

(`styleId` is already in scope — it is chosen a few lines above via `recordingPolicy.chooseStartingStyle`.)

- [ ] **Step 6: Run the game suite + full suite**

Run: `dart test test/plugins/game/ && dart test`
Expected: PASS. In particular the `game_run` seed-reproducibility / golden tests stay green — the inspiration hook makes **no** `context.rng` draw when there are zero eligible inspirers (it returns before Step 1), which is always the case in the current harness, so the RNG stream is unchanged.

- [ ] **Step 7: Update `CHANGELOG.md`**

Under `## Unreleased`, add a new `### Added — Technique inspiration / discovery (SP0b)` section:

```markdown
### Added — Technique inspiration / discovery (SP0b)

- `CombatAction.sourceRef: BuildComponentRef?` — optional, default `null`,
  behaviour-neutral. Set by `TechniqueActionInterpreter` on every action
  it builds so a performed action can be attributed to a technique-variant
  instance. `AttackAction` / `SelfEffectAction` gain the matching
  constructor parameter. Also the SP1 active-tier seam.
- `TechniqueUsageComponent` + `recordTechniqueVariantUsage` /
  `techniqueVariantUsage` on
  `package:build_engine/technique_plugin.dart` — per-run, per-variant
  count of performed combat actions. Fed by the composition layer's
  `ActionCompleted` subscription (the Technique plugin itself stays
  Combat-free). Dropped by `removeTechniqueVariant`.
- `TechniqueInspirationResolver.resolve({trainedFamilyId, inspirers,
  descriptorPool, rng, exclude})` — pure: eligibility filter
  (`masteryLevel >= 1 && usage >= 3`), damped weights
  (`mastery * sqrt(usage)`), positive-axis emphasis, usage concentration
  → discovery probability, family-compatibility filter, behaviour-driven
  descriptor count (1–3), weighted draw without replacement, bounded
  exact-duplicate exclusion retry. `Inspirer` / `InspirationResult`
  (`InspirationResult.none`) value types.
- `resolveTechniqueInspirationAfterTraining(owner, trainedTechnique,
  styleCentre, context, {styleId})` — the one authoritative post-training
  discovery step, parallel to `resolveTechniqueEvolutionAfterTraining`.
  One roll → at most one minted (owned, loose) variant on the **trained**
  family (cross-pollination preserved) → publishes `TechniqueVariantInspired`
  exactly once. Inspirers are never mutated.
- `TechniqueVariantInspired {owner, instanceId, familyId, descriptorIds,
  inspirerInstanceIds}` event.
- Tuning constants in `technique_vocabulary.dart` (`kInspirationBaseChance`
  … `kInspirationStrongWeightBar`) + `techniqueFamilyTagPrefix`.
- `styleCentre(styleId, familyId)` on
  `package:build_engine/martial_arts_plugin.dart` — per-style, per-base-family
  axis nudge for a minted variant.
- SP0a's `_familyOf` / `_requireVariant` promoted to public
  `techniqueFamilyOf` / `requireTechniqueVariant` (visibility only).
```

- [ ] **Step 8: Update `ARCHITECTURE.md`**

Immediately after the `## Technique instancing (SP0a)` section (ends near line 488), insert a new section:

```markdown
## Technique inspiration / discovery (SP0b) (`lib/src/plugins/technique/`)

New variants come from how the player fights. `CombatAction.sourceRef`
(optional `BuildComponentRef`, default `null`, never read by
`CombatSystem`) lets a performed action be attributed to a variant
instance; the composition layer's existing `ActionCompleted` subscription
calls the Core-only `recordTechniqueVariantUsage`, accumulating a
per-run `TechniqueUsageComponent` on the fighter. `lib/src/plugins/technique/`
still names neither `combat` nor `martial_arts` — the bridge lives in the
harness, the same split `TechniqueActionInterpreter` already uses.

`TechniqueInspirationResolver` is pure (randomness only from an injected
`RngService`): it filters inspirers by `masteryLevel >= 1 && usage >= 3`,
weights them `mastery * sqrt(usage)` (usage has diminishing returns so a
long-lived variant cannot monopolise discoveries), builds a
positive-axis-only emphasis profile, converts usage concentration
(`maxWeight / totalWeight`) into a discovery probability, filters the
descriptor pool by a `family:<base>` compatibility tag, picks a
behaviour-driven count (1 for one source, 2 for several, 3 for a strong
blend, hard cap 3), and draws without replacement with a bounded
exact-duplicate exclusion retry. One roll per call.

`resolveTechniqueInspirationAfterTraining` is the sole caller and the
sole publisher of `TechniqueVariantInspired` — parallel to
`resolveTechniqueEvolutionAfterTraining`. On a hit it mints one **owned
but loose** variant on the **trained** family (inspirers may be any
family — cross-pollination), seeded by the drawn descriptors plus the
style centre the caller passes in (`martial_arts`'s `styleCentre`; the
technique plugin never looks it up). Inspirers are never mutated; a
freshly minted variant starts `masteryLevel 0` / `usage 0` and so cannot
chain a second discovery. Usage is per-run, like SP0a's per-instance
mastery. The evolution path is untouched and still runs alongside.
```

- [ ] **Step 9: Full verification**

Run: `dart test && dart analyze && dart test test/integration/architecture_dependency_test.dart`
Expected: all green; test count = prior baseline + the SP0b tests; zero analyzer issues.

- [ ] **Step 10: Commit**

```bash
git add lib/src/plugins/game/combat_stage.dart \
        lib/src/plugins/game/training_stage.dart \
        lib/src/plugins/game/game_run.dart \
        CHANGELOG.md ARCHITECTURE.md \
        test/plugins/game/combat_stage_usage_test.dart
git commit -m "test(technique): lock SP0b discovery invariants; wire harness usage + inspiration"
```

---

## Self-Review

**1. Spec coverage**

| Spec section | Task |
|---|---|
| §4.1 `CombatAction.sourceRef` + `AttackAction`/`SelfEffectAction` | Task 1 |
| §4.2 `TechniqueActionInterpreter` sets `sourceRef` | Task 2 |
| §4.3 behaviour-neutrality | Task 1 step 3/7, Task 10 step 6 |
| §5.1 `TechniqueUsageComponent` | Task 4 |
| §5.2 `ActionCompleted` → usage bridge (composition layer) | Task 4 (reducer) + Task 10 (bridge) |
| §5.3 `techniqueVariantUsage` + `removeTechniqueVariant` cleanup | Task 4 |
| §6.1 `Inspirer` / `InspirationResult` / resolver signature | Task 5 + Task 6 |
| §6.2 steps 0–4 (eligibility, weights, emphasis, concentration, roll) | Task 6 |
| §6.2 steps 5–8 (compatibility, count, draw, exclusion) | Task 6 impl + Task 7 lock |
| §6.3 tuning constants | Task 3 |
| §7 `resolveTechniqueInspirationAfterTraining` + `techniqueFamilyOf` promotion | Task 3 + Task 8 |
| §7 caller wiring (`training_stage` / `game_run`) | Task 10 |
| §8 `TechniqueVariantInspired` | Task 5 |
| §9 `styleCentre` table | Task 9 |
| §10 coexistence with evolution | Task 10 (call placement) + Task 8 flow test |
| §12 edge cases | Task 6/7/8 test lists |
| §13 files | File Structure section |
| §14 testing | Tasks 1,2,4,6,7,8,9,10 test steps |
| §15 open questions #2 (`family:<base>` = full base id), #4 (`techniqueFamilyOf` visibility) | resolved in Task 3 |

**2. Placeholder scan** — the second case in Task 10 step 1 is marked `skip` with an explicit instruction to fill it in mirroring the first before the final commit; every other code block is complete. No "TBD"/"add error handling"/"similar to Task N".

**3. Type consistency** — `sourceRef` (`BuildComponentRef?`), `TechniqueUsageComponent.byInstance` (`Map<EntityId,int>`), `recordTechniqueVariantUsage(EntityId, PluginContext)`, `techniqueVariantUsage(EntityId, PluginContext) -> int`, `Inspirer{instanceId,axisProfile,masteryLevel,usage}`, `InspirationResult{discovered,familyId,descriptorIds:Set<String>,inspirerInstanceIds:List<EntityId>}`, `TechniqueInspirationResolver.resolve({trainedFamilyId,inspirers,descriptorPool,rng,exclude})`, `descriptorCompatibleWithFamily(TechniqueDescriptor,String)->bool`, `resolveTechniqueInspirationAfterTraining(EntityId,TechniqueDefinition,Map<String,num>,PluginContext,{String? styleId})`, `styleCentre(String,String)->Map<String,num>`, `requireTechniqueVariant`/`techniqueFamilyOf` (public renames) — all consistent across tasks.

**4. Risk notes for the executor**
- `ActiveBuild` constructor shape in Task 2's test — mirror an existing interpreter test rather than assume `ActiveBuild([ref])`.
- `RngService` seed-scan helpers assume the discovery roll is `rng`'s **first** draw in `resolve` — Task 6 step 3 puts it there (Step 4, before `_draw`). Keep that ordering.
- Task 10: confirm no `game_run` golden test pins an exact RNG-derived sequence that a *future* variant-holding harness would shift; today it does not shift because the hook returns before any draw with zero eligible inspirers.
