# Technique Instancing (SP0a) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give each technique a player holds its own instance entity carrying descriptor-driven axis attributes and per-instance mastery, so a martial build can be personal.

**Architecture:** A Technique-plugin-only feature built on primitives already shipped. A minted `EntityId` per variant carries a `TechniqueVariant` component (`baseFamilyId`, `descriptorIds`, resolved `axisProfile`, `styleId`). Descriptors are content (`{id, axis, magnitude}`); a pure `TechniqueVariantResolver` sums them (plus a style centre) into the axis profile. Per-instance mastery uses the existing `MasteryTracker` keyed by an instance-scoped subject string. The Tome carries the instance via the already-optional `BuildComponentRef.instanceEntityId`. Nothing turns the axis profile into combat numbers yet — that is SP1.

**Tech Stack:** Dart, `package:build_engine` (this repo), `package:test`. No new dependencies.

**Spec:** `docs/superpowers/specs/2026-09-02-technique-instancing-design.md`

## Global Constraints

- **Zero core change.** Every new/changed file is under `lib/src/plugins/technique/` (plus `CHANGELOG.md`, `ARCHITECTURE.md`, and the `lib/technique_plugin.dart` barrel). Do not touch `lib/src/` outside `plugins/technique/`, and do not touch any other plugin. If a task seems to need a core change, stop and flag it.
- **No `MasteryTracker` change.** It has no `undefine`; per-instance `MasteryDefinition`s stay registered for the life of the `PluginContext`. Removal clears only the `MasteryComponent` progress entry.
- **`EntityRegistry.destroy` does not cascade component cleanup** — remove the `TechniqueVariant` component explicitly before destroying an instance.
- **Additive only.** `EvolutionResolver`, `TechniqueDefinition.evolutionCandidates`, and the hand-authored evolved ids (`heavy_punch`, `lightning_jab`, …) keep working unchanged. All existing tests must stay green.
- **Content type string:** technique descriptors use `'type': 'technique_descriptor'`. Axes are the open string set `power` / `speed` / `endurance` / `precision` (launch content).
- **Determinism:** no `RngService` anywhere in SP0a. All resolution is additive arithmetic.
- **Test harness:** build a `PluginContext` with the `_newContext()` helper pattern from `test/plugins/technique/technique_lifecycle_test.dart` (copy it into each new test file). Tests may import `package:build_engine/src/plugins/technique/...` directly, as the existing technique tests do.
- **Commits:** follow the repo convention — `feat(technique): …` / `test(technique): …` / `docs: …`, and append the trailers this repo already uses:
  ```
  Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
  Claude-Session: https://claude.ai/code/session_01SQVSoEaNrnjQvQkaBBn1Z7
  ```
- **After every task:** run the full technique suite — `dart test test/plugins/technique/` — and `dart analyze`; both must be clean before the commit step.

---

## File Structure

**New — `lib/src/plugins/technique/`**

| File | Responsibility |
|------|----------------|
| `technique_descriptor.dart` | `TechniqueDescriptor` value type; `techniqueDescriptorFromContent`; `techniqueDescriptor(id, context)` accessor; `UnknownTechniqueDescriptorException`. |
| `technique_descriptor_content.dart` | `techniqueDescriptorContentDefinitions` (launch data); `TechniqueAxes` constants. |
| `technique_variant.dart` | `TechniqueVariant` component (pure data). |
| `technique_variant_resolver.dart` | `TechniqueVariantResolver` — pure descriptors (+ styleCentre) → axisProfile. |
| `technique_variant_lifecycle.dart` | `mintTechniqueVariant`, `hangTechniqueVariant`, `removeTechniqueVariant`, `trainTechniqueVariantMastery`, `techniqueVariantMasteryLevel`, `mintVariantForLegacyEvolvedId`; `TechniqueVariantNotFoundException`. |

**Modified**

| File | Change |
|------|--------|
| `lib/src/plugins/technique/technique_vocabulary.dart` | add `techniqueInstanceSubject(EntityId)`. |
| `lib/src/plugins/technique/technique_events.dart` | add `TechniqueVariantMinted`, `TechniqueVariantRemoved`; add optional `instanceId` to `TechniqueAddedToTome`. |
| `lib/src/plugins/technique/technique_plugin.dart` | register `techniqueDescriptorContentDefinitions` in `initialize` (guarded). |
| `lib/technique_plugin.dart` | export the 4 new public files. |
| `CHANGELOG.md` | public-surface additions. |
| `ARCHITECTURE.md` | Technique section: instances + descriptor/axis model. |

**New tests — `test/plugins/technique/`**

`technique_descriptor_test.dart`, `technique_variant_test.dart`, `technique_variant_resolver_test.dart`, `technique_variant_lifecycle_test.dart`, `technique_variant_plugin_test.dart`.

---

## Task 1: `TechniqueDescriptor` type + content accessor

**Files:**
- Create: `lib/src/plugins/technique/technique_descriptor.dart`
- Test: `test/plugins/technique/technique_descriptor_test.dart`

**Interfaces:**
- Consumes: `ContentDefinition` (`.id`, `.tags`, `.extra`) and `PluginContext` (`.content.find`) from `package:build_engine/build_engine.dart`.
- Produces:
  - `class TechniqueDescriptor { const TechniqueDescriptor({required String id, required String axis, required num magnitude, Set<String> tags}); final String id; final String axis; final num magnitude; final Set<String> tags; }`
  - `TechniqueDescriptor techniqueDescriptorFromContent(ContentDefinition definition)`
  - `TechniqueDescriptor techniqueDescriptor(String id, PluginContext context)` — throws `UnknownTechniqueDescriptorException` if no content with that id has an `axis` field.
  - `class UnknownTechniqueDescriptorException implements Exception { const UnknownTechniqueDescriptorException(String id); final String id; }`

- [ ] **Step 1: Write the failing test**

```dart
// test/plugins/technique/technique_descriptor_test.dart
import 'package:build_engine/build_engine.dart';
import 'package:build_engine/src/plugins/technique/technique_descriptor.dart';
import 'package:test/test.dart';

void main() {
  test('parses a descriptor from content', () {
    final registry = ContentRegistry();
    registry.loadAll(const [
      {
        'id': 'bear',
        'type': 'technique_descriptor',
        'tags': ['technique_descriptor', 'beast'],
        'axis': 'power',
        'magnitude': 6,
      },
    ]);
    final d = techniqueDescriptorFromContent(registry.get('bear'));
    expect(d.id, 'bear');
    expect(d.axis, 'power');
    expect(d.magnitude, 6);
    expect(d.tags, contains('beast'));
  });

  test('accessor throws for an unknown descriptor id', () {
    final registry = ContentRegistry();
    expect(
      () => _lookup(registry, 'no_such'),
      throwsA(isA<UnknownTechniqueDescriptorException>()),
    );
  });
}

TechniqueDescriptor _lookup(ContentRegistry registry, String id) {
  // techniqueDescriptor takes a PluginContext; exercise the same logic via a
  // tiny shim so this test needs no full context.
  final def = registry.find(id);
  if (def == null || def.extra['axis'] == null) {
    throw UnknownTechniqueDescriptorException(id);
  }
  return techniqueDescriptorFromContent(def);
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `dart test test/plugins/technique/technique_descriptor_test.dart`
Expected: FAIL — `technique_descriptor.dart` does not exist / `TechniqueDescriptor` undefined.

- [ ] **Step 3: Write minimal implementation**

```dart
// lib/src/plugins/technique/technique_descriptor.dart
import 'package:build_engine/build_engine.dart';

/// A thematic modifier a technique variant can carry. Content data,
/// loaded via `ContentRegistry` like `TechniqueDefinition` already is.
/// `axis` is one of the open string set in `technique_descriptor_content.dart`
/// (`power` / `speed` / `endurance` / `precision` at launch); `magnitude`
/// is signed. `tags` are free thematic tags for SP0b matching.
class TechniqueDescriptor {
  const TechniqueDescriptor({
    required this.id,
    required this.axis,
    required this.magnitude,
    this.tags = const {},
  });

  final String id;
  final String axis;
  final num magnitude;
  final Set<String> tags;
}

/// Thrown by [techniqueDescriptor] when no loaded content with [id] is a
/// descriptor (no `axis` field).
class UnknownTechniqueDescriptorException implements Exception {
  const UnknownTechniqueDescriptorException(this.id);
  final String id;
  @override
  String toString() => 'Unknown technique descriptor: $id';
}

/// Builds a [TechniqueDescriptor] from an already-parsed [ContentDefinition]
/// — mirrors `techniqueDefinitionFromContent`.
TechniqueDescriptor techniqueDescriptorFromContent(ContentDefinition definition) =>
    TechniqueDescriptor(
      id: definition.id,
      axis: definition.extra['axis'] as String,
      magnitude: definition.extra['magnitude'] as num,
      tags: definition.tags,
    );

/// Resolves descriptor [id] from [context]'s loaded content — the same
/// convenience `techniqueDefinition` provides. Throws
/// [UnknownTechniqueDescriptorException] if [id] is absent or not a
/// descriptor.
TechniqueDescriptor techniqueDescriptor(String id, PluginContext context) {
  final definition = context.content.find(id);
  if (definition == null || definition.extra['axis'] == null) {
    throw UnknownTechniqueDescriptorException(id);
  }
  return techniqueDescriptorFromContent(definition);
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `dart test test/plugins/technique/technique_descriptor_test.dart`
Expected: PASS (both tests).

- [ ] **Step 5: Run the full technique suite + analyze**

Run: `dart test test/plugins/technique/ && dart analyze`
Expected: all green, no analyzer issues.

- [ ] **Step 6: Commit**

```bash
git add lib/src/plugins/technique/technique_descriptor.dart test/plugins/technique/technique_descriptor_test.dart
git commit -m "feat(technique): TechniqueDescriptor content type + accessor"
```

---

## Task 2: Descriptor launch content + axis constants

**Files:**
- Create: `lib/src/plugins/technique/technique_descriptor_content.dart`
- Test: append to `test/plugins/technique/technique_descriptor_test.dart`

**Interfaces:**
- Consumes: nothing (pure data + `ContentRegistry.loadAll` in the test).
- Produces:
  - `abstract final class TechniqueAxes { static const power = 'power'; static const speed = 'speed'; static const endurance = 'endurance'; static const precision = 'precision'; static const all = [power, speed, endurance, precision]; }`
  - `const List<Map<String, dynamic>> techniqueDescriptorContentDefinitions` — every entry has `id`, `'type': 'technique_descriptor'`, `tags` (including `'technique_descriptor'`), `axis`, `magnitude`.

- [ ] **Step 1: Write the failing test**

```dart
// add to test/plugins/technique/technique_descriptor_test.dart
import 'package:build_engine/src/plugins/technique/technique_descriptor_content.dart';

// ...inside main():
  test('launch descriptor content loads and every entry is a valid descriptor', () {
    final registry = ContentRegistry();
    registry.loadAll(techniqueDescriptorContentDefinitions);
    for (final raw in techniqueDescriptorContentDefinitions) {
      final id = raw['id'] as String;
      final d = techniqueDescriptorFromContent(registry.get(id));
      expect(TechniqueAxes.all, contains(d.axis),
          reason: '$id has an unknown axis ${d.axis}');
      expect(d.magnitude, isA<num>());
    }
    // at least one descriptor per launch axis
    for (final axis in TechniqueAxes.all) {
      expect(
        techniqueDescriptorContentDefinitions.any((r) => r['axis'] == axis),
        isTrue,
        reason: 'no descriptor for axis $axis',
      );
    }
  });
```

- [ ] **Step 2: Run test to verify it fails**

Run: `dart test test/plugins/technique/technique_descriptor_test.dart`
Expected: FAIL — `technique_descriptor_content.dart` missing.

- [ ] **Step 3: Write minimal implementation**

```dart
// lib/src/plugins/technique/technique_descriptor_content.dart

/// The abstract attribute axes a technique variant's descriptors sum
/// onto. Open set — a plugin adds one by authoring descriptors for it,
/// no code change. These four ship at launch.
abstract final class TechniqueAxes {
  static const power = 'power';
  static const speed = 'speed';
  static const endurance = 'endurance';
  static const precision = 'precision';

  static const all = [power, speed, endurance, precision];
}

/// Launch descriptor set. Each maps a thematic id to one axis with a
/// signed magnitude; a descriptor may also nudge a second axis (authored
/// as a separate entry sharing the id prefix is avoided — keep one axis
/// per descriptor for SP0a; multi-axis descriptors are an SP0b concern).
const techniqueDescriptorContentDefinitions = <Map<String, dynamic>>[
  // ── power ────────────────────────────────────────────────────────
  {'id': 'bear', 'type': 'technique_descriptor', 'tags': ['technique_descriptor', 'beast'], 'axis': 'power', 'magnitude': 6},
  {'id': 'elephant', 'type': 'technique_descriptor', 'tags': ['technique_descriptor', 'beast'], 'axis': 'power', 'magnitude': 8},
  {'id': 'strong', 'type': 'technique_descriptor', 'tags': ['technique_descriptor'], 'axis': 'power', 'magnitude': 4},
  {'id': 'destruction', 'type': 'technique_descriptor', 'tags': ['technique_descriptor'], 'axis': 'power', 'magnitude': 9},
  {'id': 'thunder', 'type': 'technique_descriptor', 'tags': ['technique_descriptor', 'weather'], 'axis': 'power', 'magnitude': 7},
  {'id': 'iron', 'type': 'technique_descriptor', 'tags': ['technique_descriptor', 'material'], 'axis': 'power', 'magnitude': 5},

  // ── speed ────────────────────────────────────────────────────────
  {'id': 'swift', 'type': 'technique_descriptor', 'tags': ['technique_descriptor'], 'axis': 'speed', 'magnitude': 5},
  {'id': 'fast', 'type': 'technique_descriptor', 'tags': ['technique_descriptor'], 'axis': 'speed', 'magnitude': 4},
  {'id': 'lightning', 'type': 'technique_descriptor', 'tags': ['technique_descriptor', 'weather'], 'axis': 'speed', 'magnitude': 8},
  {'id': 'light', 'type': 'technique_descriptor', 'tags': ['technique_descriptor'], 'axis': 'speed', 'magnitude': 6},
  {'id': 'flash', 'type': 'technique_descriptor', 'tags': ['technique_descriptor'], 'axis': 'speed', 'magnitude': 7},

  // ── endurance ────────────────────────────────────────────────────
  {'id': 'immortal', 'type': 'technique_descriptor', 'tags': ['technique_descriptor'], 'axis': 'endurance', 'magnitude': 9},
  {'id': 'wall', 'type': 'technique_descriptor', 'tags': ['technique_descriptor'], 'axis': 'endurance', 'magnitude': 5},
  {'id': 'mountain', 'type': 'technique_descriptor', 'tags': ['technique_descriptor'], 'axis': 'endurance', 'magnitude': 7},
  {'id': 'undead', 'type': 'technique_descriptor', 'tags': ['technique_descriptor'], 'axis': 'endurance', 'magnitude': 6},
  {'id': 'rooted', 'type': 'technique_descriptor', 'tags': ['technique_descriptor'], 'axis': 'endurance', 'magnitude': 4},

  // ── precision ────────────────────────────────────────────────────
  {'id': 'bullseye', 'type': 'technique_descriptor', 'tags': ['technique_descriptor'], 'axis': 'precision', 'magnitude': 6},
  {'id': 'hawkseye', 'type': 'technique_descriptor', 'tags': ['technique_descriptor', 'beast'], 'axis': 'precision', 'magnitude': 7},
  {'id': 'one_hit', 'type': 'technique_descriptor', 'tags': ['technique_descriptor'], 'axis': 'precision', 'magnitude': 9},
  {'id': 'needle', 'type': 'technique_descriptor', 'tags': ['technique_descriptor'], 'axis': 'precision', 'magnitude': 5},
  {'id': 'focused', 'type': 'technique_descriptor', 'tags': ['technique_descriptor'], 'axis': 'precision', 'magnitude': 4},
];
```

- [ ] **Step 4: Run test to verify it passes**

Run: `dart test test/plugins/technique/technique_descriptor_test.dart`
Expected: PASS.

- [ ] **Step 5: Run the full technique suite + analyze**

Run: `dart test test/plugins/technique/ && dart analyze`
Expected: green.

- [ ] **Step 6: Commit**

```bash
git add lib/src/plugins/technique/technique_descriptor_content.dart test/plugins/technique/technique_descriptor_test.dart
git commit -m "feat(technique): launch descriptor content + TechniqueAxes"
```

---

## Task 3: `TechniqueVariant` component

**Files:**
- Create: `lib/src/plugins/technique/technique_variant.dart`
- Test: `test/plugins/technique/technique_variant_test.dart`

**Interfaces:**
- Consumes: nothing.
- Produces:
  - `class TechniqueVariant { const TechniqueVariant({required String baseFamilyId, required Set<String> descriptorIds, required Map<String, num> axisProfile, String? styleId}); final String baseFamilyId; final Set<String> descriptorIds; final Map<String, num> axisProfile; final String? styleId; }`

- [ ] **Step 1: Write the failing test**

```dart
// test/plugins/technique/technique_variant_test.dart
import 'package:build_engine/src/plugins/technique/technique_variant.dart';
import 'package:test/test.dart';

void main() {
  test('holds its family, descriptors, resolved profile and style', () {
    const v = TechniqueVariant(
      baseFamilyId: 'basic_punch',
      descriptorIds: {'bear', 'thunder'},
      axisProfile: {'power': 13},
      styleId: 'wing_chun',
    );
    expect(v.baseFamilyId, 'basic_punch');
    expect(v.descriptorIds, {'bear', 'thunder'});
    expect(v.axisProfile['power'], 13);
    expect(v.styleId, 'wing_chun');
  });

  test('a basic variant has an empty descriptor set and null style', () {
    const v = TechniqueVariant(
      baseFamilyId: 'basic_kick',
      descriptorIds: {},
      axisProfile: {},
    );
    expect(v.descriptorIds, isEmpty);
    expect(v.axisProfile, isEmpty);
    expect(v.styleId, isNull);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `dart test test/plugins/technique/technique_variant_test.dart`
Expected: FAIL — `TechniqueVariant` undefined.

- [ ] **Step 3: Write minimal implementation**

```dart
// lib/src/plugins/technique/technique_variant.dart

/// Per-instance variant state for one technique the owner holds. Pure
/// data, no behaviour — the `ComponentStore` component attached to a
/// technique instance entity.
///
/// [axisProfile] is the **stored** result of resolving [descriptorIds]
/// (plus a style centre) at mint time — see `TechniqueVariantResolver`.
/// It is not recomputed on read, so a later content change to a
/// descriptor's magnitude does not silently restat existing instances.
class TechniqueVariant {
  const TechniqueVariant({
    required this.baseFamilyId,
    required this.descriptorIds,
    required this.axisProfile,
    this.styleId,
  });

  /// The base family this is a variant of, e.g. `'basic_punch'`.
  final String baseFamilyId;

  /// Thematic descriptor ids carried by this instance.
  final Set<String> descriptorIds;

  /// Resolved axis contributions, e.g. `{'power': 13, 'speed': -1}`.
  final Map<String, num> axisProfile;

  /// The style this variant is tied to; `null` for a basic technique.
  final String? styleId;
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `dart test test/plugins/technique/technique_variant_test.dart`
Expected: PASS.

- [ ] **Step 5: Run the full technique suite + analyze**

Run: `dart test test/plugins/technique/ && dart analyze`
Expected: green.

- [ ] **Step 6: Commit**

```bash
git add lib/src/plugins/technique/technique_variant.dart test/plugins/technique/technique_variant_test.dart
git commit -m "feat(technique): TechniqueVariant component"
```

---

## Task 4: `TechniqueVariantResolver`

**Files:**
- Create: `lib/src/plugins/technique/technique_variant_resolver.dart`
- Test: `test/plugins/technique/technique_variant_resolver_test.dart`

**Interfaces:**
- Consumes: `TechniqueDescriptor` (Task 1).
- Produces:
  - `class TechniqueVariantResolver { const TechniqueVariantResolver(); Map<String, num> resolve({required Iterable<TechniqueDescriptor> descriptors, Map<String, num> styleCentre = const {}}); }`

- [ ] **Step 1: Write the failing test**

```dart
// test/plugins/technique/technique_variant_resolver_test.dart
import 'package:build_engine/src/plugins/technique/technique_descriptor.dart';
import 'package:build_engine/src/plugins/technique/technique_variant_resolver.dart';
import 'package:test/test.dart';

const _bear = TechniqueDescriptor(id: 'bear', axis: 'power', magnitude: 6);
const _thunder = TechniqueDescriptor(id: 'thunder', axis: 'power', magnitude: 7);
const _swift = TechniqueDescriptor(id: 'swift', axis: 'speed', magnitude: 5);
const _drag = TechniqueDescriptor(id: 'drag', axis: 'speed', magnitude: -2);

void main() {
  const resolver = TechniqueVariantResolver();

  test('empty descriptors and empty centre yields empty profile', () {
    expect(resolver.resolve(descriptors: const []), isEmpty);
  });

  test('one descriptor yields its axis and magnitude', () {
    expect(resolver.resolve(descriptors: const [_bear]), {'power': 6});
  });

  test('descriptors on the same axis sum', () {
    expect(resolver.resolve(descriptors: const [_bear, _thunder]), {'power': 13});
  });

  test('descriptors on different axes are separate keys', () {
    expect(
      resolver.resolve(descriptors: const [_bear, _swift]),
      {'power': 6, 'speed': 5},
    );
  });

  test('negative magnitude subtracts', () {
    expect(
      resolver.resolve(descriptors: const [_swift, _drag]),
      {'speed': 3},
    );
  });

  test('style centre is the additive base', () {
    expect(
      resolver.resolve(
        descriptors: const [_bear],
        styleCentre: const {'power': 2, 'endurance': 1},
      ),
      {'power': 8, 'endurance': 1},
    );
  });

  test('deterministic — identical inputs, identical output', () {
    final a = resolver.resolve(descriptors: const [_bear, _swift, _thunder]);
    final b = resolver.resolve(descriptors: const [_bear, _swift, _thunder]);
    expect(a, b);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `dart test test/plugins/technique/technique_variant_resolver_test.dart`
Expected: FAIL — `TechniqueVariantResolver` undefined.

- [ ] **Step 3: Write minimal implementation**

```dart
// lib/src/plugins/technique/technique_variant_resolver.dart
import 'technique_descriptor.dart';

/// Pure. A descriptor set (plus an optional style centre) → an axis
/// profile. Mirrors `BuildResolver` / `ModifierResolver`'s "function, no
/// storage" shape.
class TechniqueVariantResolver {
  const TechniqueVariantResolver();

  /// Sums each descriptor's `(axis, magnitude)` onto a copy of
  /// [styleCentre]. Additive and commutative, so the result is
  /// deterministic regardless of iteration order.
  Map<String, num> resolve({
    required Iterable<TechniqueDescriptor> descriptors,
    Map<String, num> styleCentre = const {},
  }) {
    final profile = <String, num>{...styleCentre};
    for (final d in descriptors) {
      profile[d.axis] = (profile[d.axis] ?? 0) + d.magnitude;
    }
    return profile;
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `dart test test/plugins/technique/technique_variant_resolver_test.dart`
Expected: PASS (7 tests).

- [ ] **Step 5: Run the full technique suite + analyze**

Run: `dart test test/plugins/technique/ && dart analyze`
Expected: green.

- [ ] **Step 6: Commit**

```bash
git add lib/src/plugins/technique/technique_variant_resolver.dart test/plugins/technique/technique_variant_resolver_test.dart
git commit -m "feat(technique): TechniqueVariantResolver (pure descriptors -> axis profile)"
```

---

## Task 5: Instance mastery subject + variant events

**Files:**
- Modify: `lib/src/plugins/technique/technique_vocabulary.dart` (add one function near `techniqueSubject`)
- Modify: `lib/src/plugins/technique/technique_events.dart` (add two classes; one field on `TechniqueAddedToTome`)
- Test: `test/plugins/technique/technique_events_test.dart` (append)

**Interfaces:**
- Consumes: `EntityId`, `SlotId` from `package:build_engine/build_engine.dart`.
- Produces:
  - `String techniqueInstanceSubject(EntityId instance)` → `'technique:instance:<value>'`
  - `class TechniqueVariantMinted { const TechniqueVariantMinted(EntityId owner, EntityId instanceId, String baseFamilyId); final EntityId owner; final EntityId instanceId; final String baseFamilyId; }`
  - `class TechniqueVariantRemoved { const TechniqueVariantRemoved(EntityId owner, EntityId instanceId); final EntityId owner; final EntityId instanceId; }`
  - `TechniqueAddedToTome` gains `final EntityId? instanceId;` and its constructor becomes `const TechniqueAddedToTome(this.owner, this.definitionId, this.slot, {this.instanceId});`

- [ ] **Step 1: Write the failing test**

```dart
// append to test/plugins/technique/technique_events_test.dart
import 'package:build_engine/build_engine.dart';
import 'package:build_engine/src/plugins/technique/technique_vocabulary.dart';

// ...inside main():
  test('techniqueInstanceSubject is instance-scoped and stable', () {
    const a = EntityId(7);
    const b = EntityId(8);
    expect(techniqueInstanceSubject(a), 'technique:instance:7');
    expect(techniqueInstanceSubject(a), techniqueInstanceSubject(a));
    expect(techniqueInstanceSubject(a) == techniqueInstanceSubject(b), isFalse);
  });

  test('TechniqueAddedToTome can carry an instance id', () {
    const e = TechniqueAddedToTome(EntityId(1), 'basic_punch', SlotId('r0c0'),
        instanceId: EntityId(42));
    expect(e.instanceId, const EntityId(42));
  });

  test('variant mint / remove events carry owner + instance', () {
    const minted = TechniqueVariantMinted(EntityId(1), EntityId(42), 'basic_punch');
    const removed = TechniqueVariantRemoved(EntityId(1), EntityId(42));
    expect(minted.instanceId, const EntityId(42));
    expect(minted.baseFamilyId, 'basic_punch');
    expect(removed.instanceId, const EntityId(42));
  });
```

(If `technique_events_test.dart` has no `main()` yet, create it with the standard `import 'package:test/test.dart'; void main() { ... }` wrapper and the imports above.)

- [ ] **Step 2: Run test to verify it fails**

Run: `dart test test/plugins/technique/technique_events_test.dart`
Expected: FAIL — `techniqueInstanceSubject` / `TechniqueVariantMinted` undefined; `instanceId` named param unknown.

- [ ] **Step 3: Write minimal implementation**

In `technique_vocabulary.dart`, directly after `techniqueSubject`:

```dart
/// The per-instance Mastery subject for a technique variant entity —
/// `'technique:instance:<entityValue>'`. Distinct from
/// [techniqueSubject] (the base-family subject) so each variant a player
/// holds is drilled independently. `MasteryTracker` treats it like any
/// other subject string; it registers/reads it, never interprets it.
String techniqueInstanceSubject(EntityId instance) =>
    'technique:instance:${instance.value}';
```

In `technique_events.dart`, change `TechniqueAddedToTome`:

```dart
class TechniqueAddedToTome {
  const TechniqueAddedToTome(this.owner, this.definitionId, this.slot,
      {this.instanceId});

  final EntityId owner;
  final String definitionId;
  final SlotId slot;

  /// The technique-variant instance that was hung, if this placement
  /// carries one (SP0a onwards). `null` for a pre-instancing placement.
  final EntityId? instanceId;
}
```

and add:

```dart
/// Published by `mintTechniqueVariant` once a new technique-variant
/// instance entity exists for [owner]. Mirrors `ItemAddedToTome`'s
/// "TomeService has no EventBus of its own" reasoning for living here.
class TechniqueVariantMinted {
  const TechniqueVariantMinted(this.owner, this.instanceId, this.baseFamilyId);
  final EntityId owner;
  final EntityId instanceId;
  final String baseFamilyId;
}

/// Published by `removeTechniqueVariant` once the instance entity and its
/// per-instance state are gone.
class TechniqueVariantRemoved {
  const TechniqueVariantRemoved(this.owner, this.instanceId);
  final EntityId owner;
  final EntityId instanceId;
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `dart test test/plugins/technique/technique_events_test.dart`
Expected: PASS.

- [ ] **Step 5: Run the full technique suite + analyze**

Run: `dart test test/plugins/technique/ && dart analyze`
Expected: green (the `instanceId` param is optional, so existing `TechniqueAddedToTome(...)` call sites are unaffected).

- [ ] **Step 6: Commit**

```bash
git add lib/src/plugins/technique/technique_vocabulary.dart lib/src/plugins/technique/technique_events.dart test/plugins/technique/technique_events_test.dart
git commit -m "feat(technique): instance mastery subject + variant mint/remove events"
```

---

## Task 6: `mintTechniqueVariant`

**Files:**
- Create: `lib/src/plugins/technique/technique_variant_lifecycle.dart`
- Test: `test/plugins/technique/technique_variant_lifecycle_test.dart`

**Interfaces:**
- Consumes: `techniqueDescriptor` (T1), `TechniqueVariantResolver` (T4), `TechniqueVariant` (T3), `techniqueInstanceSubject` (T5), `TechniqueVariantMinted` (T5), `techniqueMasteryThresholds` (existing, `technique_vocabulary.dart`), `PluginContext` (`.entities.create`, `.components.add`, `.mastery.define`, `.events.publish`).
- Produces:
  - `EntityId mintTechniqueVariant(EntityId owner, String baseFamilyId, Set<String> descriptorIds, PluginContext context, {String? styleId, Map<String, num> styleCentre = const {}})`

- [ ] **Step 1: Write the failing test**

```dart
// test/plugins/technique/technique_variant_lifecycle_test.dart
import 'package:build_engine/build_engine.dart';
import 'package:build_engine/src/plugins/technique/technique_descriptor_content.dart';
import 'package:build_engine/src/plugins/technique/technique_variant.dart';
import 'package:build_engine/src/plugins/technique/technique_variant_lifecycle.dart';
import 'package:build_engine/src/plugins/technique/technique_vocabulary.dart';
import 'package:test/test.dart';

PluginContext _newContext() {
  final events = EventBus();
  final entities = EntityRegistry(events);
  final components = ComponentStore();
  final rng = RngService(1);
  final shared = CoreServices(components: components, events: events);
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
      shared: shared,
    ),
    queries: QueryEngine(QueryScope(components: components)),
    modifiers: ModifierCollection(),
    content: ContentRegistry(),
    shared: shared,
  );
}

void main() {
  late PluginContext context;
  late EntityId owner;

  setUp(() {
    context = _newContext();
    context.content.loadAll(techniqueDescriptorContentDefinitions);
    owner = context.entities.create();
  });

  test('mint creates a live instance with a resolved axis profile', () {
    final id = mintTechniqueVariant(
      owner, 'basic_punch', {'bear', 'thunder'}, context,
      styleId: 'wing_chun',
    );
    expect(context.entities.isAlive(id), isTrue);
    final v = context.components.get<TechniqueVariant>(id)!;
    expect(v.baseFamilyId, 'basic_punch');
    expect(v.descriptorIds, {'bear', 'thunder'});
    expect(v.axisProfile['power'], 13); // bear 6 + thunder 7
    expect(v.styleId, 'wing_chun');
  });

  test('mint applies the style centre additively', () {
    final id = mintTechniqueVariant(
      owner, 'basic_kick', {'swift'}, context,
      styleCentre: const {'speed': 3},
    );
    expect(context.components.get<TechniqueVariant>(id)!.axisProfile['speed'], 8);
  });

  test('mint registers a per-instance mastery definition', () {
    final id = mintTechniqueVariant(owner, 'basic_punch', const {}, context);
    expect(
      context.mastery.definitionOf(techniqueInstanceSubject(id)),
      isNotNull,
    );
  });

  test('mint publishes TechniqueVariantMinted', () {
    TechniqueVariantMinted? seen;
    context.events.subscribe<TechniqueVariantMinted>((e) => seen = e);
    final id = mintTechniqueVariant(owner, 'basic_slash', {'iron'}, context);
    expect(seen, isNotNull);
    expect(seen!.instanceId, id);
    expect(seen!.baseFamilyId, 'basic_slash');
  });

  test('mint with an unknown descriptor throws', () {
    expect(
      () => mintTechniqueVariant(owner, 'basic_punch', {'nonsense'}, context),
      throwsA(isA<UnknownTechniqueDescriptorException>()),
    );
  });

  test('a basic variant mints with an empty profile', () {
    final id = mintTechniqueVariant(owner, 'basic_guard', const {}, context);
    expect(context.components.get<TechniqueVariant>(id)!.axisProfile, isEmpty);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `dart test test/plugins/technique/technique_variant_lifecycle_test.dart`
Expected: FAIL — `mintTechniqueVariant` undefined.

- [ ] **Step 3: Write minimal implementation**

```dart
// lib/src/plugins/technique/technique_variant_lifecycle.dart
import 'package:build_engine/build_engine.dart';

import 'technique_descriptor.dart';
import 'technique_events.dart';
import 'technique_variant.dart';
import 'technique_variant_resolver.dart';
import 'technique_vocabulary.dart';

export 'technique_descriptor.dart' show UnknownTechniqueDescriptorException;

/// Mints one technique-variant instance for [owner]: a fresh entity
/// carrying a [TechniqueVariant] whose [TechniqueVariant.axisProfile] is
/// [descriptorIds] (+ [styleCentre]) resolved once, now. Registers a
/// per-instance `MasteryDefinition` on the shared
/// [techniqueMasteryThresholds] curve and publishes
/// [TechniqueVariantMinted].
///
/// SP0a does not decide *which* descriptors or *what* style centre —
/// callers (style seeding, SP0b's inspiration path, tests) pass them.
/// Throws [UnknownTechniqueDescriptorException] if any id in
/// [descriptorIds] is not loaded descriptor content.
EntityId mintTechniqueVariant(
  EntityId owner,
  String baseFamilyId,
  Set<String> descriptorIds,
  PluginContext context, {
  String? styleId,
  Map<String, num> styleCentre = const {},
}) {
  final descriptors = [
    for (final id in descriptorIds) techniqueDescriptor(id, context),
  ];
  final axisProfile = const TechniqueVariantResolver()
      .resolve(descriptors: descriptors, styleCentre: styleCentre);

  final instance = context.entities.create();
  context.components.add<TechniqueVariant>(
    instance,
    TechniqueVariant(
      baseFamilyId: baseFamilyId,
      descriptorIds: descriptorIds,
      axisProfile: axisProfile,
      styleId: styleId,
    ),
  );
  context.mastery.define(
    MasteryDefinition(
      subject: techniqueInstanceSubject(instance),
      thresholds: techniqueMasteryThresholds,
    ),
  );
  context.events.publish(
    TechniqueVariantMinted(owner, instance, baseFamilyId),
  );
  return instance;
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `dart test test/plugins/technique/technique_variant_lifecycle_test.dart`
Expected: PASS (6 tests).

- [ ] **Step 5: Run the full technique suite + analyze**

Run: `dart test test/plugins/technique/ && dart analyze`
Expected: green.

- [ ] **Step 6: Commit**

```bash
git add lib/src/plugins/technique/technique_variant_lifecycle.dart test/plugins/technique/technique_variant_lifecycle_test.dart
git commit -m "feat(technique): mintTechniqueVariant"
```

---

## Task 7: `hangTechniqueVariant`

**Files:**
- Modify: `lib/src/plugins/technique/technique_variant_lifecycle.dart` (add function + exception)
- Test: append to `test/plugins/technique/technique_variant_lifecycle_test.dart`

**Interfaces:**
- Consumes: `mintTechniqueVariant` (T6); `techniqueDefinition` + `isTechniqueLearned` + `TechniqueNotLearnedException` + `techniqueReferenceType` (existing, `technique_content.dart` / `technique_lifecycle.dart` / `technique_vocabulary.dart`); `context.tome.insert`; `context.components.get<TechniqueVariant>`.
- Produces:
  - `void hangTechniqueVariant(EntityId owner, SlotId slot, EntityId instanceId, PluginContext context)`
  - `class TechniqueVariantNotFoundException implements Exception { const TechniqueVariantNotFoundException(EntityId instanceId); final EntityId instanceId; }`

- [ ] **Step 1: Write the failing test**

```dart
// append to test/plugins/technique/technique_variant_lifecycle_test.dart
import 'package:build_engine/src/plugins/technique/technique_content.dart';
import 'package:build_engine/src/plugins/technique/technique_lifecycle.dart';

// ...inside main(): add a nested group so the extra content load is scoped
  group('hangTechniqueVariant', () {
    setUp(() {
      context.content.loadAll(techniqueContentDefinitions);
      context.progression.define(const ProgressionDefinition(
          subject: 'technique:basic_punch:knowledge', thresholds: [10]));
      for (final def in techniqueContentDefinitions) {
        context.mastery.define(MasteryDefinition(
            subject: 'technique:${def['id']}', thresholds: const [5, 15, 30]));
      }
    });

    test('a derived variant hangs without a learning gate, ref carries the instance', () {
      final id = mintTechniqueVariant(
          owner, 'basic_punch', {'bear'}, context, styleId: 'wing_chun');

      hangTechniqueVariant(owner, const SlotId('r0c0'), id, context);

      final placements = context.tome.inspect(owner);
      expect(placements, hasLength(1));
      expect(placements.single.buildComponentRef.contentId, 'basic_punch');
      expect(placements.single.buildComponentRef.instanceEntityId, id);
    });

    test('a basic variant is gated on the family being learned', () {
      final id = mintTechniqueVariant(owner, 'basic_punch', const {}, context);
      expect(
        () => hangTechniqueVariant(owner, const SlotId('r0c0'), id, context),
        throwsA(isA<TechniqueNotLearnedException>()),
      );

      final family = techniqueDefinition('basic_punch', context);
      discoverTechnique(owner, family, context);
      attemptToLearnTechnique(owner, family, 10, context);

      hangTechniqueVariant(owner, const SlotId('r0c0'), id, context);
      expect(context.tome.inspect(owner), hasLength(1));
    });

    test('hanging an unknown instance id throws', () {
      expect(
        () => hangTechniqueVariant(
            owner, const SlotId('r0c0'), const EntityId(999), context),
        throwsA(isA<TechniqueVariantNotFoundException>()),
      );
    });

    test('hang publishes TechniqueAddedToTome with the instance id', () {
      TechniqueAddedToTome? seen;
      context.events.subscribe<TechniqueAddedToTome>((e) => seen = e);
      final id = mintTechniqueVariant(owner, 'basic_slash', {'iron'}, context,
          styleId: 'boxing');
      hangTechniqueVariant(owner, const SlotId('r0c0'), id, context);
      expect(seen?.instanceId, id);
    });
  });
```

**Note:** the Tome must have a definition + instance for `owner` before `insert`. If `context.tome.insert` throws `StateError` ("owner has no Tome"), add to this group's `setUp`:
```dart
context.tome.defineTome(TomeDefinition(id: 'test_tome', container: () => Container.grid(rows: 3, cols: 3)));
context.tome.createTome(owner, 'test_tome');
```
Check `TomeService`/`TomeDefinition` signatures in `lib/src/tome/` and match them exactly (the grid factory arg names may be `width`/`height` or `rows`/`cols`).

- [ ] **Step 2: Run test to verify it fails**

Run: `dart test test/plugins/technique/technique_variant_lifecycle_test.dart -N hangTechniqueVariant`
Expected: FAIL — `hangTechniqueVariant` undefined.

- [ ] **Step 3: Write minimal implementation** (add to `technique_variant_lifecycle.dart`)

```dart
/// Thrown by [hangTechniqueVariant] / [removeTechniqueVariant] when
/// [instanceId] has no [TechniqueVariant] component.
class TechniqueVariantNotFoundException implements Exception {
  const TechniqueVariantNotFoundException(this.instanceId);
  final EntityId instanceId;
  @override
  String toString() => 'No technique variant for instance $instanceId';
}

/// Hangs the variant instance [instanceId] in [owner]'s Tome [slot].
///
/// A **basic** variant (no descriptors, no style) is gated on the base
/// family being `isTechniqueLearned` — the same rule `addTechniqueToTome`
/// enforces. A **derived** variant has no learning gate (mirrors "evolved
/// branches are never learned separately"). The written `BuildComponentRef`
/// carries `instanceEntityId: instanceId`, and [TechniqueAddedToTome] is
/// published with that instance.
void hangTechniqueVariant(
  EntityId owner,
  SlotId slot,
  EntityId instanceId,
  PluginContext context,
) {
  final variant = context.components.get<TechniqueVariant>(instanceId);
  if (variant == null) {
    throw TechniqueVariantNotFoundException(instanceId);
  }
  final isBasic = variant.styleId == null && variant.descriptorIds.isEmpty;
  if (isBasic) {
    final family = techniqueDefinition(variant.baseFamilyId, context);
    if (!isTechniqueLearned(owner, family, context)) {
      throw TechniqueNotLearnedException(variant.baseFamilyId);
    }
  }
  context.tome.insert(
    owner,
    slot,
    BuildComponentRef(
      referenceType: techniqueReferenceType,
      contentId: variant.baseFamilyId,
      instanceEntityId: instanceId,
    ),
  );
  context.events.publish(
    TechniqueAddedToTome(owner, variant.baseFamilyId, slot,
        instanceId: instanceId),
  );
}
```

Add the needed imports to the file:
```dart
import 'technique_content.dart' show techniqueDefinition;
import 'technique_lifecycle.dart' show isTechniqueLearned, TechniqueNotLearnedException;
```

- [ ] **Step 4: Run test to verify it passes**

Run: `dart test test/plugins/technique/technique_variant_lifecycle_test.dart`
Expected: PASS (all groups).

- [ ] **Step 5: Run the full technique suite + analyze**

Run: `dart test test/plugins/technique/ && dart analyze`
Expected: green.

- [ ] **Step 6: Commit**

```bash
git add lib/src/plugins/technique/technique_variant_lifecycle.dart test/plugins/technique/technique_variant_lifecycle_test.dart
git commit -m "feat(technique): hangTechniqueVariant (instance-carrying Tome ref)"
```

---

## Task 8: Per-instance mastery helpers

**Files:**
- Modify: `lib/src/plugins/technique/technique_variant_lifecycle.dart`
- Test: append to `test/plugins/technique/technique_variant_lifecycle_test.dart`

**Interfaces:**
- Consumes: `techniqueInstanceSubject` (T5); `context.mastery.increase` / `.levelOf`.
- Produces:
  - `void trainTechniqueVariantMastery(EntityId owner, EntityId instanceId, num amount, PluginContext context)`
  - `int techniqueVariantMasteryLevel(EntityId owner, EntityId instanceId, PluginContext context)`

- [ ] **Step 1: Write the failing test**

```dart
// append to test/plugins/technique/technique_variant_lifecycle_test.dart
  group('per-instance mastery', () {
    test('two instances of the same base master independently', () {
      final a = mintTechniqueVariant(owner, 'basic_punch', {'bear'}, context,
          styleId: 's');
      final b = mintTechniqueVariant(owner, 'basic_punch', {'swift'}, context,
          styleId: 's');

      trainTechniqueVariantMastery(owner, a, 20, context);

      expect(techniqueVariantMasteryLevel(owner, a, context), greaterThan(0));
      expect(techniqueVariantMasteryLevel(owner, b, context), 0);
    });
  });
```

- [ ] **Step 2: Run test to verify it fails**

Run: `dart test test/plugins/technique/technique_variant_lifecycle_test.dart -N "per-instance mastery"`
Expected: FAIL — helpers undefined.

- [ ] **Step 3: Write minimal implementation** (add to `technique_variant_lifecycle.dart`)

```dart
/// Adds [amount] proficiency to the per-instance MASTERY of variant
/// [instanceId]. Keyed by [techniqueInstanceSubject], so it never moves
/// the base family's own mastery.
void trainTechniqueVariantMastery(
  EntityId owner,
  EntityId instanceId,
  num amount,
  PluginContext context,
) =>
    context.mastery.increase(owner, techniqueInstanceSubject(instanceId), amount);

/// Variant [instanceId]'s current MASTERY level — `0` if never trained.
int techniqueVariantMasteryLevel(
  EntityId owner,
  EntityId instanceId,
  PluginContext context,
) =>
    context.mastery.levelOf(owner, techniqueInstanceSubject(instanceId));
```

- [ ] **Step 4: Run test to verify it passes**

Run: `dart test test/plugins/technique/technique_variant_lifecycle_test.dart`
Expected: PASS.

- [ ] **Step 5: Run the full technique suite + analyze**

Run: `dart test test/plugins/technique/ && dart analyze`
Expected: green.

- [ ] **Step 6: Commit**

```bash
git add lib/src/plugins/technique/technique_variant_lifecycle.dart test/plugins/technique/technique_variant_lifecycle_test.dart
git commit -m "feat(technique): per-instance variant mastery helpers"
```

---

## Task 9: `removeTechniqueVariant`

**Files:**
- Modify: `lib/src/plugins/technique/technique_variant_lifecycle.dart`
- Test: append to `test/plugins/technique/technique_variant_lifecycle_test.dart`

**Interfaces:**
- Consumes: `context.tome.inspect` / `.remove`; `context.components.get<MasteryComponent>` / `.remove<TechniqueVariant>`; `context.entities.destroy`; `TechniqueVariantRemoved` (T5); `techniqueInstanceSubject` (T5).
- Produces:
  - `void removeTechniqueVariant(EntityId owner, EntityId instanceId, PluginContext context)`

- [ ] **Step 1: Write the failing test**

```dart
// append to test/plugins/technique/technique_variant_lifecycle_test.dart
  group('removeTechniqueVariant', () {
    setUp(() {
      context.content.loadAll(techniqueContentDefinitions);
      for (final def in techniqueContentDefinitions) {
        context.mastery.define(MasteryDefinition(
            subject: 'technique:${def['id']}', thresholds: const [5, 15, 30]));
      }
      // Tome for the owner — match your TomeService/TomeDefinition API.
      context.tome.defineTome(TomeDefinition(
          id: 'test_tome', container: () => Container.grid(rows: 3, cols: 3)));
      context.tome.createTome(owner, 'test_tome');
    });

    test('removes the placement, the progress, the component, and the entity', () {
      final id = mintTechniqueVariant(owner, 'basic_punch', {'bear'}, context,
          styleId: 'wing_chun');
      hangTechniqueVariant(owner, const SlotId('r0c0'), id, context);
      trainTechniqueVariantMastery(owner, id, 10, context);

      removeTechniqueVariant(owner, id, context);

      expect(context.tome.inspect(owner), isEmpty);
      expect(context.components.get<TechniqueVariant>(id), isNull);
      expect(context.entities.isAlive(id), isFalse);
      expect(
        context.mastery.progressOf(owner, techniqueInstanceSubject(id)),
        0,
      );
    });

    test('publishes TechniqueVariantRemoved', () {
      TechniqueVariantRemoved? seen;
      context.events.subscribe<TechniqueVariantRemoved>((e) => seen = e);
      final id = mintTechniqueVariant(owner, 'basic_kick', const {}, context);
      removeTechniqueVariant(owner, id, context);
      expect(seen?.instanceId, id);
    });

    test('removing an unknown instance throws', () {
      expect(
        () => removeTechniqueVariant(owner, const EntityId(999), context),
        throwsA(isA<TechniqueVariantNotFoundException>()),
      );
    });
  });
```

- [ ] **Step 2: Run test to verify it fails**

Run: `dart test test/plugins/technique/technique_variant_lifecycle_test.dart -N removeTechniqueVariant`
Expected: FAIL — `removeTechniqueVariant` undefined.

- [ ] **Step 3: Write minimal implementation** (add to `technique_variant_lifecycle.dart`)

```dart
/// Fully removes variant instance [instanceId] for [owner]:
///   1. drop any Tome placement holding it,
///   2. clear its per-instance mastery progress (the `MasteryDefinition`
///      stays — `MasteryTracker` has no undefine; a definition with no
///      progress reads level 0 and is inert),
///   3. remove the `TechniqueVariant` component (entity destroy does not
///      cascade — documented),
///   4. destroy the entity,
///   5. publish [TechniqueVariantRemoved].
///
/// Throws [TechniqueVariantNotFoundException] if [instanceId] has no
/// variant component.
void removeTechniqueVariant(
  EntityId owner,
  EntityId instanceId,
  PluginContext context,
) {
  if (context.components.get<TechniqueVariant>(instanceId) == null) {
    throw TechniqueVariantNotFoundException(instanceId);
  }

  for (final placement in context.tome.inspect(owner)) {
    if (placement.buildComponentRef.instanceEntityId == instanceId) {
      context.tome.remove(owner, placement.slot);
    }
  }

  final subject = techniqueInstanceSubject(instanceId);
  final mastery = context.components.get<MasteryComponent>(owner);
  if (mastery != null && mastery.progress.containsKey(subject)) {
    final trimmed = Map<String, num>.of(mastery.progress)..remove(subject);
    context.components.add<MasteryComponent>(owner, MasteryComponent(trimmed));
  }

  context.components.remove<TechniqueVariant>(instanceId);
  context.entities.destroy(instanceId);
  context.events.publish(TechniqueVariantRemoved(owner, instanceId));
}
```

If `MasteryComponent` is not exported from `package:build_engine/build_engine.dart`, add:
```dart
import 'package:build_engine/src/components/mastery_component.dart';
```

- [ ] **Step 4: Run test to verify it passes**

Run: `dart test test/plugins/technique/technique_variant_lifecycle_test.dart`
Expected: PASS.

- [ ] **Step 5: Run the full technique suite + analyze**

Run: `dart test test/plugins/technique/ && dart analyze`
Expected: green.

- [ ] **Step 6: Commit**

```bash
git add lib/src/plugins/technique/technique_variant_lifecycle.dart test/plugins/technique/technique_variant_lifecycle_test.dart
git commit -m "feat(technique): removeTechniqueVariant (symmetric cleanup)"
```

---

## Task 10: Plugin registration + barrel exports

**Files:**
- Modify: `lib/src/plugins/technique/technique_plugin.dart`
- Modify: `lib/technique_plugin.dart` (barrel)
- Test: `test/plugins/technique/technique_variant_plugin_test.dart`

**Interfaces:**
- Consumes: `techniqueDescriptorContentDefinitions` (T2); the existing `TechniquePlugin` / `PluginSdk.registerContentBatch`.
- Produces: after `TechniquePlugin().initialize(context)`, `techniqueDescriptor('bear', context)` succeeds; `TechniqueDescriptor`, `TechniqueVariant`, `TechniqueVariantResolver`, `mintTechniqueVariant`, etc. are importable from `package:build_engine/technique_plugin.dart`.

- [ ] **Step 1: Write the failing test**

```dart
// test/plugins/technique/technique_variant_plugin_test.dart
import 'package:build_engine/build_engine.dart';
import 'package:build_engine/technique_plugin.dart';
import 'package:test/test.dart';

PluginContext _newContext() {
  final events = EventBus();
  final entities = EntityRegistry(events);
  final components = ComponentStore();
  final rng = RngService(1);
  final shared = CoreServices(components: components, events: events);
  return PluginContext(
    entities: entities,
    components: components,
    events: events,
    rng: rng,
    rules: RuleEngine(
      entities: entities, components: components, events: events, rng: rng,
      shared: shared),
    queries: QueryEngine(QueryScope(components: components)),
    modifiers: ModifierCollection(),
    content: ContentRegistry(),
    shared: shared,
  );
}

void main() {
  test('initialize loads descriptor content', () {
    final context = _newContext();
    TechniquePlugin().initialize(context);
    final d = techniqueDescriptor('bear', context);
    expect(d.axis, 'power');
  });

  test('initialize twice on one context does not double-load', () {
    final context = _newContext();
    final plugin = TechniquePlugin()..initialize(context);
    plugin.initialize(context); // must not throw ContentDuplicateIdException
    expect(techniqueDescriptor('swift', context).axis, 'speed');
  });

  test('variant API is exported from the plugin barrel', () {
    final context = _newContext();
    TechniquePlugin().initialize(context);
    final owner = context.entities.create();
    final id = mintTechniqueVariant(owner, 'basic_punch', {'bear'}, context,
        styleId: 'x');
    expect(context.components.get<TechniqueVariant>(id)!.axisProfile['power'], 6);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `dart test test/plugins/technique/technique_variant_plugin_test.dart`
Expected: FAIL — `techniqueDescriptor` / `mintTechniqueVariant` / `TechniqueVariant` not exported from `package:build_engine/technique_plugin.dart`; descriptor content not loaded.

- [ ] **Step 3: Write minimal implementation**

In `lib/src/plugins/technique/technique_plugin.dart` `initialize`, after the existing `techniqueContentDefinitions` guard block, add:

```dart
    import '../technique/technique_descriptor_content.dart'; // top of file, with the others

    // (inside initialize, after the technique batch guard)
    final firstDescriptorId =
        techniqueDescriptorContentDefinitions.first['id'] as String;
    if (context.content.find(firstDescriptorId) == null) {
      sdk.registerContentBatch(techniqueDescriptorContentDefinitions);
    }
```

(Place the `import` with the file's other imports, not inline.)

In `lib/technique_plugin.dart`, add exports next to the existing `export 'src/plugins/technique/...';` lines:

```dart
export 'src/plugins/technique/technique_descriptor.dart';
export 'src/plugins/technique/technique_descriptor_content.dart';
export 'src/plugins/technique/technique_variant.dart';
export 'src/plugins/technique/technique_variant_resolver.dart';
export 'src/plugins/technique/technique_variant_lifecycle.dart';
```

- [ ] **Step 4: Run test to verify it passes**

Run: `dart test test/plugins/technique/technique_variant_plugin_test.dart`
Expected: PASS.

- [ ] **Step 5: Run the full suite + analyze**

Run: `dart test test/plugins/technique/ && dart analyze`
Expected: green. Also run `dart test test/` once here to confirm no cross-plugin regression from the new exports.

- [ ] **Step 6: Commit**

```bash
git add lib/src/plugins/technique/technique_plugin.dart lib/technique_plugin.dart test/plugins/technique/technique_variant_plugin_test.dart
git commit -m "feat(technique): register descriptor content + export variant API"
```

---

## Task 11: Legacy evolved-id coexistence shim

**Files:**
- Modify: `lib/src/plugins/technique/technique_variant_lifecycle.dart`
- Test: append to `test/plugins/technique/technique_variant_lifecycle_test.dart`

**Interfaces:**
- Consumes: `mintTechniqueVariant` (T6); `techniqueDefinition` + `TechniqueIds` (existing).
- Produces:
  - `EntityId mintVariantForLegacyEvolvedId(EntityId owner, String legacyId, PluginContext context, {String? styleId})` — maps a hand-authored evolved id (`lightning_jab`, …) to `mintTechniqueVariant(owner, <its base family>, <mapped descriptors>, …)`.

- [ ] **Step 1: Write the failing test**

```dart
// append to test/plugins/technique/technique_variant_lifecycle_test.dart
  group('legacy coexistence', () {
    setUp(() => context.content.loadAll(techniqueContentDefinitions));

    test('mints a variant for a legacy evolved id with mapped descriptors', () {
      final id = mintVariantForLegacyEvolvedId(
          owner, TechniqueIds.heavyPunch, context, styleId: 'boxing');
      final v = context.components.get<TechniqueVariant>(id)!;
      expect(v.baseFamilyId, TechniqueIds.basicPunch);
      expect(v.descriptorIds, contains('strong'));
      // profile matches the resolver over the mapped descriptors
      final expected = const TechniqueVariantResolver().resolve(descriptors: [
        for (final d in v.descriptorIds) techniqueDescriptor(d, context),
      ]);
      expect(v.axisProfile, expected);
    });

    test('legacy ids still resolve as plain definitions (nothing broke)', () {
      expect(
        techniqueDefinition(TechniqueIds.lightningJab, context).id,
        TechniqueIds.lightningJab,
      );
    });

    test('an unmapped legacy id mints a plain (descriptor-less) variant', () {
      final id = mintVariantForLegacyEvolvedId(
          owner, TechniqueIds.basicSlash, context);
      expect(context.components.get<TechniqueVariant>(id)!.descriptorIds, isEmpty);
    });
  });
```

- [ ] **Step 2: Run test to verify it fails**

Run: `dart test test/plugins/technique/technique_variant_lifecycle_test.dart -N "legacy coexistence"`
Expected: FAIL — `mintVariantForLegacyEvolvedId` undefined.

- [ ] **Step 3: Write minimal implementation** (add to `technique_variant_lifecycle.dart`)

```dart
import 'technique_vocabulary.dart' show TechniqueIds; // extend the existing import

/// Descriptor sets for the hand-authored evolved ids, so save data / SP4
/// / SP0b can turn a legacy id into an instanced variant. Only the ids
/// with an obvious thematic reading are mapped; anything absent mints a
/// plain (descriptor-less) variant of its base family.
const _legacyEvolvedDescriptors = <String, Set<String>>{
  TechniqueIds.heavyPunch: {'strong'},
  TechniqueIds.fastPunch: {'fast'},
  TechniqueIds.lightPunch: {'focused'},
  TechniqueIds.hammerBlow: {'strong', 'iron'},
  TechniqueIds.mountainBreaker: {'mountain', 'strong'},
  TechniqueIds.lightningJab: {'lightning'},
  TechniqueIds.flashStrike: {'flash'},
  TechniqueIds.thunderFlash: {'thunder', 'flash'},
  TechniqueIds.heavySlash: {'strong'},
  TechniqueIds.quickSlash: {'swift'},
  TechniqueIds.lightningSlash: {'lightning'},
  TechniqueIds.mountainCleave: {'mountain', 'strong'},
  TechniqueIds.ironPalm: {'iron'},
  TechniqueIds.thunderPalm: {'thunder'},
  TechniqueIds.lightningFinger: {'lightning'},
  TechniqueIds.needleFinger: {'needle'},
  TechniqueIds.piercingFinger: {'needle', 'one_hit'},
  TechniqueIds.thrustKick: {'strong'},
  TechniqueIds.spinningKick: {'strong'},
  TechniqueIds.whirlwindKick: {'swift', 'strong'},
};

/// The base family for [legacyId], read from its content's family tag.
String _familyOf(String legacyId, PluginContext context) {
  final tags = techniqueDefinition(legacyId, context).tags;
  const familyTagToBase = {
    'fist': TechniqueIds.basicPunch,
    'blade': TechniqueIds.basicSlash,
    'guard': TechniqueIds.basicGuard,
    'palm': TechniqueIds.basicPalm,
    'finger': TechniqueIds.basicFinger,
    'kick': TechniqueIds.basicKick,
  };
  for (final entry in familyTagToBase.entries) {
    if (tags.contains(entry.key)) return entry.value;
  }
  return legacyId; // already a base, or unknown — mint against itself
}

/// Mints an instanced variant equivalent to a hand-authored evolved id.
/// Additive: the legacy definition still resolves via `techniqueDefinition`
/// and nothing calls this unless a caller opts in.
EntityId mintVariantForLegacyEvolvedId(
  EntityId owner,
  String legacyId,
  PluginContext context, {
  String? styleId,
}) =>
    mintTechniqueVariant(
      owner,
      _familyOf(legacyId, context),
      _legacyEvolvedDescriptors[legacyId] ?? const {},
      context,
      styleId: styleId,
    );
```

- [ ] **Step 4: Run test to verify it passes**

Run: `dart test test/plugins/technique/technique_variant_lifecycle_test.dart`
Expected: PASS.

- [ ] **Step 5: Run the full suite + analyze**

Run: `dart test test/ && dart analyze`
Expected: green — every existing test still passes (coexistence proven).

- [ ] **Step 6: Commit**

```bash
git add lib/src/plugins/technique/technique_variant_lifecycle.dart test/plugins/technique/technique_variant_lifecycle_test.dart
git commit -m "feat(technique): legacy evolved-id -> variant coexistence shim"
```

---

## Task 12: Documentation

**Files:**
- Modify: `CHANGELOG.md`
- Modify: `ARCHITECTURE.md`

**Interfaces:** none (docs only).

- [ ] **Step 1: Update `CHANGELOG.md`**

Add an entry under the current unreleased/next section, matching the file's existing format:

```markdown
### Added — Technique instancing (SP0a)
- `TechniqueDescriptor` content type (`type: 'technique_descriptor'`), launch
  descriptor set, and `TechniqueAxes` (`power`/`speed`/`endurance`/`precision`).
- `TechniqueVariant` component: `baseFamilyId`, `descriptorIds`, resolved
  `axisProfile`, `styleId`.
- `TechniqueVariantResolver` — pure descriptors (+ style centre) → axis profile.
- `mintTechniqueVariant` / `hangTechniqueVariant` / `removeTechniqueVariant`;
  `trainTechniqueVariantMastery` / `techniqueVariantMasteryLevel`;
  `mintVariantForLegacyEvolvedId`.
- `techniqueInstanceSubject(EntityId)` — per-instance Mastery subject.
- Events: `TechniqueVariantMinted`, `TechniqueVariantRemoved`; optional
  `instanceId` on `TechniqueAddedToTome`.

### Notes
- Additive: `EvolutionResolver` and the hand-authored evolved ids are
  unchanged; per-instance `MasteryDefinition`s are not unregistered on removal
  (no `MasteryTracker.undefine`) — a run's fresh `PluginContext` resets them.
```

- [ ] **Step 2: Update `ARCHITECTURE.md`**

In the Technique plugin section, add a subsection after the existing description:

```markdown
### Technique instancing (SP0a)

A technique the player holds is a **variant instance** — a minted `EntityId`
carrying a `TechniqueVariant` component (`baseFamilyId`, `descriptorIds`,
resolved `axisProfile`, `styleId`), referenced from the Tome via the
already-optional `BuildComponentRef.instanceEntityId`. Multiple variants of one
base family coexist; a **basic** technique is a variant with an empty descriptor
set.

Variety is data: a `TechniqueDescriptor` (`{id, axis, magnitude}`, content type
`technique_descriptor`) names a thematic modifier — `bear → power`, `hawkseye →
precision`. `TechniqueVariantResolver` (pure, additive) sums a descriptor set
plus a per-family style centre into the stored `axisProfile`. Axes are an open
string set; `power`/`speed`/`endurance`/`precision` ship at launch. Nothing
reads `axisProfile` into a calculation yet — SP1 maps it to an `EffectProfile`.

Mastery is **per instance**: `techniqueInstanceSubject(EntityId)` keys the
existing `MasteryTracker` on the shared `techniqueMasteryThresholds` curve.
`MasteryTracker` has no `undefine`, so `removeTechniqueVariant` clears only the
progress entry; a run's fresh `PluginContext` discards the registry.

Zero core change: instances use `EntityRegistry`/`ComponentStore`, mastery uses
`MasteryTracker`, the Tome ref field already existed. The hand-authored
evolution path (`EvolutionResolver`, evolved ids) is untouched;
`mintVariantForLegacyEvolvedId` bridges an old id to a variant on demand.
```

- [ ] **Step 3: Verify docs build / no broken references**

Run: `dart analyze` (docs don't compile, but confirm nothing else regressed) and re-read both edits for accuracy against the shipped code.

- [ ] **Step 4: Commit**

```bash
git add CHANGELOG.md ARCHITECTURE.md
git commit -m "docs: technique instancing (SP0a) — CHANGELOG + ARCHITECTURE"
```

---

## Final verification

- [ ] Run the entire suite: `dart test test/` — all green, including the pre-existing technique/evolution/integration tests and the architecture-dependency test (`test/integration/architecture_dependency_test.dart`).
- [ ] `dart analyze` — zero issues.
- [ ] Confirm `git log --oneline` shows one commit per task, all on branch `sp0a-technique-instancing`.
- [ ] Grep check — no file outside `lib/src/plugins/technique/`, `lib/technique_plugin.dart`, `CHANGELOG.md`, `ARCHITECTURE.md`, `test/plugins/technique/` was modified:
  `git diff --stat 314f75a..HEAD` (or the branch's merge-base) should list only those paths plus the two spec/plan docs.

---

## Self-Review (completed by plan author)

**1. Spec coverage.** Spec §4.1 base/instance split → T3, T6. §4.2 `TechniqueVariant` → T3. §4.3 descriptors → T1, T2. §4.4 axes → T2. §4.5 resolver → T4. §5 per-instance mastery → T5, T8; cleanup deviation (no `undefine`) captured in Global Constraints + T9. §6 lifecycle (mint/hang/remove) → T6, T7, T9; `TechniqueAddedToTome.instanceId` + new events → T5. §7 coexistence → T11. §11 files → all tasks; barrel + docs → T10, T12. §12 open questions Q2/Q3/Q4/Q5 are design-time decisions, not build items — Q3 (angle/rhythm as descriptors) is realized by T2's one-axis-per-descriptor rule; Q4 (style centre in `martial_arts`) is out of SP0a (mint takes `styleCentre` as a param, caller supplies it). No spec section is unimplemented.

**2. Placeholder scan.** No "TBD"/"handle errors"/"similar to". Every code step has full source. Two flagged verification points (does `_parse` accept an unknown `type`; exact `TomeDefinition`/`Container.grid` arg names) are written as "match the API in `lib/src/...`" with the file named — these are lookups the executor does, not gaps in intent.

**3. Type consistency.** `mintTechniqueVariant(owner, baseFamilyId, descriptorIds, context, {styleId, styleCentre})` — same arg order in T6, T7, T8, T9, T11 tests. `techniqueInstanceSubject(EntityId)` — T5 def, used T6/T8/T9. `TechniqueVariant` field names (`baseFamilyId`/`descriptorIds`/`axisProfile`/`styleId`) — consistent T3 → T6/T7/T9/T11. `techniqueDescriptor(id, context)` throws `UnknownTechniqueDescriptorException` — T1 def, asserted T6. `removeTechniqueVariant` / `hangTechniqueVariant` throw `TechniqueVariantNotFoundException` — T7 def, reused T9.
