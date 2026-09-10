# Engine-Owned Affix API (`AffixPlugin`) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give `build_engine` a dedicated `AffixPlugin` that owns canonical affix identity, mechanics (stat + non-stat), deterministic reward-slot selection, and engine-minted acquisition-event identity — enumerable from content, driven by the one `RngService`, wired end-to-end through the headless `runGame` harness and recorded through the existing Almanac.

**Architecture:** A new content plugin at `lib/src/plugins/affix/` (barrel `package:build_engine/affix_plugin.dart`) modelled on `ConsumablePlugin`. Content type `'affix'`; pools selected by `affix_pool:*` tags; a small engine resolver applies physique-tradition affinity weighting + a per-slot no-affix chance; each affix carries one closed `AffixMechanic` (`WeaponStatBonus` / `ImmediateHeal` / `BankProgression`). `acquireAffixes(...)` applies mechanics, mints one `affixEventId` per acquired affix via an engine-owned per-run `AffixAcquisitionIdSource`, and returns a plain `AffixAcquisition` record (no `almanac.dart` type). The headless harness resolves + acquires in `RewardStage`, publishes an `AffixAcquired` event, and `HeadlessGameAlmanacBridge` records it.

**Tech Stack:** Dart `^3.7.0` (pure package, no Flutter), `package:test ^1.25.0`. Run tests with `dart test <path> -r compact`; lint with `dart analyze`.

**Spec:** `docs/superpowers/specs/2026-09-10-engine-affix-plugin-design.md`

## Global Constraints

Every task's requirements implicitly include this section. Values are copied verbatim from the spec.

- **CORE PROVIDES VERBS, PLUGINS PROVIDE NOUNS.** All affix code lives under `lib/src/plugins/affix/`. No affix vocabulary enters `lib/src/` core.
- **Content type is `'affix'`.** Pools are enumerated with `registry.withTag('affix_pool:item_prefix' | 'affix_pool:item_suffix' | 'affix_pool:technique_prefix' | 'affix_pool:technique_suffix')`. No second engine roster; no client roster.
- **One `AffixMechanic` per affix** — closed union `WeaponStatBonus(num amount)` / `ImmediateHeal(num amount)` / `BankProgression(num amount)`. Not an `Effect` list.
- **`AffixResolution` is immutable, ordered, exactly 2 slots** — `List<AffixResolvedSlot>` of length 2, positions `0` (`slotKind: 'prefix'`) and `1` (`slotKind: 'suffix'`), each `affix` independently nullable (`null` == no affix). The four states `none` / `prefix only` / `suffix only` / `prefix + suffix` must all stay reachable; none collapses.
- **`kNoAffixChance = 0.34`** — a `const` in `affix_resolver.dart`, per slot.
- **Affinity weighting:** favoured `lean` weight `3`, opposite `1`, `neutral` always `2`; unknown / null tradition → every lean weight `2`. `western → force` favoured, `eastern → flow` favoured.
- **Exactly one RNG.** Slot resolution draws only from the injected `RngService` via the shared `weightedPick` helper. `acquireAffixes` and `AffixAcquisitionIdSource` consume no RNG. No UUID, timestamp, or second randomness source.
- **RNG draw order (normative):** for each slot in position order (prefix, then suffix) — one `rng.nextDouble()` for the no-affix check, then, if kept, `weightedPick`'s single `rng.nextDouble()`.
- **`affixEventId` has one owner: `AffixAcquisitionIdSource`** — a `build_engine` type, one instance per logical run, deterministic monotonic counter. `acquireAffixes` is its only caller. Ids are unique **within one logical run** (identified by its `runId`); distinct logical runs must supply distinct `runId`s — no global-uniqueness guarantee, no allocator anywhere else.
- **`AffixAcquisition` is a plain engine record** — `affixId`, `affixEventId`, `runId`, `runNumber`, `stat` (non-null `String`), `value` (`num`), `category` (`String`). `affix_acquisition.dart` does not import `almanac.dart`; no affix-plugin file has any path to `src/plugins/almanac/`.
- **`stat` mapping:** `WeaponStatBonus` → the `WeaponStatTags.matchOrFallback` result; `ImmediateHeal` → `'heal'`; `BankProgression` → `'bank_progression'`. (`AffixSnapshot.stat` is a frozen non-nullable `String`.)
- **`recordAffixUsed` stays unused** — discovery only.
- **No Almanac schema change.** `AffixSnapshot` / `AffixObservation` / `AlmanacAffixRecord` / `recordAffixDiscovered` used as-is. Idempotency key stays `(affixId, affixEventId)`.
- **Content port is verbatim** — 33 entries from `Tome_client/lib/core/engine/reward_affix.dart` (11 item prefixes, 9 item suffixes, 7 technique prefixes, 6 technique suffixes), preserving label, magnitude, lean. Ids are minted `af_*` tokens, never derived from the label; the two cross-pool labels (`Flowing`, `of Still Water`) get distinct ids.
- **Do not modify** the Almanac module, `RewardDefinition` / `RewardCandidate` / `RewardResolver`, combat, training, or unrelated content.
- **`dart analyze` clean and `dart test` green at every task boundary.** Do not weaken, skip, or rebaseline unrelated tests.
- **Commit trailer** (every commit):
  ```
  Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
  Claude-Session: https://claude.ai/code/session_017TxrxRpbJZ8Bk56CVW5xA2
  ```

---

## File Structure

**Create — plugin (`lib/src/plugins/affix/`):**

| File | Responsibility |
|---|---|
| `affix_types.dart` | `enum AffixLean { neutral, force, flow }`, `enum AffixDomain { item, technique }`, `abstract final class AffixCategories`, `abstract final class AffixPoolTags` |
| `affix_mechanic.dart` | `sealed class AffixMechanic` (`num get amount`) + `WeaponStatBonus` / `ImmediateHeal` / `BankProgression` + `AffixMechanic.fromJson` |
| `affix_definition.dart` | `class AffixDefinition`, `affixDefinitionFromContent(ContentDefinition)`, `affixDefinition(String, PluginContext)` |
| `affix_content.dart` | `final affixContentDefinitions` — the 33 ported entries + small private builders |
| `affix_plugin.dart` | `class AffixPlugin extends GamePlugin` — tag + content registration, load-once guard, content-parse validation |
| `affix_resolver.dart` | `class AffixRewardContext`, `class AffixResolvedSlot`, `class AffixResolution`, `const kNoAffixChance`, `resolveRewardAffixes(...)` |
| `affix_application.dart` | `sealed class AffixApplicationTarget` + `ItemInstanceTarget` / `CharacterTarget`, `applyAffixMechanic(...)` |
| `affix_acquisition.dart` | `class RunRef`, `class AffixAcquisitionIdSource`, `class AffixAcquisition`, `acquireAffixes(...)` |

**Create — barrel:** `lib/affix_plugin.dart`

**Create — tests (`test/plugins/affix/`):** `affix_mechanic_test.dart`, `affix_definition_test.dart`, `affix_content_test.dart`, `affix_plugin_test.dart`, `affix_resolver_test.dart`, `affix_application_test.dart`, `affix_acquisition_test.dart`, `affix_barrel_test.dart`. **Create — `test/plugins/game/affix_reward_wiring_test.dart`**, **`test/integration/affix_end_to_end_test.dart`**.

**Modify — headless harness (`lib/src/plugins/game/`):**

| File | Change |
|---|---|
| `run_events.dart` | add `class AffixAcquired { final AffixAcquisition acquisition; final String rewardBaseId; }` + events-table doc row |
| `reward_stage.dart` | new ctor fields `physiqueTradition` / `runId` / `runNumber` / `affixIdSource`; in `resolveReward`'s `itemOrTechnique` branch resolve + acquire + publish; append acquired affix ids to the return string |
| `game_run.dart` | `AffixPlugin().initialize(context)` after `ConsumablePlugin`; build one `AffixAcquisitionIdSource`; pass it + tradition + run id/number into `RewardStage` |
| `almanac_bridge.dart` | subscribe `AffixAcquired`; build `AffixObservation` / `AffixSnapshot` from `e.acquisition` and call `recordAffixDiscovered`; accumulate `AffixSnapshot`s and feed `_buildSnapshot`'s `affixes` / `affixCategories` (replacing the `const []` stubs) |

`run_content.dart` needs no code change.

---

## Shared test helper

Several affix tests build a bare `PluginContext`. Copy this helper into each test file that needs it (it mirrors `test/plugins/consumable/consumable_plugin_test.dart`):

```dart
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
```

---

## Task 1: `AffixMechanic` union + `fromJson`

**Files:**
- Create: `lib/src/plugins/affix/affix_mechanic.dart`
- Test: `test/plugins/affix/affix_mechanic_test.dart`

**Interfaces:**
- Consumes: `ContentFieldException` (from `package:build_engine/build_engine.dart`).
- Produces: `sealed class AffixMechanic { const AffixMechanic(); num get amount; factory AffixMechanic.fromJson(Map<String, dynamic> json); }`; `class WeaponStatBonus extends AffixMechanic { const WeaponStatBonus(this.amount); @override final num amount; }`; `class ImmediateHeal extends AffixMechanic { const ImmediateHeal(this.amount); @override final num amount; }`; `class BankProgression extends AffixMechanic { const BankProgression(this.amount); @override final num amount; }`. JSON kinds: `'weapon_stat_bonus'` → `WeaponStatBonus`, `'heal'` → `ImmediateHeal`, `'bank_progression'` → `BankProgression`.

- [ ] **Step 1: Write the failing test**

```dart
// test/plugins/affix/affix_mechanic_test.dart
import 'package:build_engine/affix_plugin.dart';
import 'package:build_engine/build_engine.dart' show ContentFieldException;
import 'package:test/test.dart';

void main() {
  test('fromJson dispatches on kind and reads amount', () {
    expect(AffixMechanic.fromJson({'kind': 'weapon_stat_bonus', 'amount': 3}),
        isA<WeaponStatBonus>().having((m) => m.amount, 'amount', 3));
    expect(AffixMechanic.fromJson({'kind': 'heal', 'amount': 12}),
        isA<ImmediateHeal>().having((m) => m.amount, 'amount', 12));
    expect(AffixMechanic.fromJson({'kind': 'bank_progression', 'amount': 2}),
        isA<BankProgression>().having((m) => m.amount, 'amount', 2));
  });

  test('unknown kind throws ContentFieldException on mechanic.kind', () {
    expect(() => AffixMechanic.fromJson({'kind': 'teleport', 'amount': 1}),
        throwsA(isA<ContentFieldException>().having((e) => e.path, 'path', 'mechanic.kind')));
  });

  test('missing / non-num amount throws ContentFieldException on mechanic.amount', () {
    expect(() => AffixMechanic.fromJson({'kind': 'heal'}),
        throwsA(isA<ContentFieldException>().having((e) => e.path, 'path', 'mechanic.amount')));
    expect(() => AffixMechanic.fromJson({'kind': 'heal', 'amount': 'lots'}),
        throwsA(isA<ContentFieldException>().having((e) => e.path, 'path', 'mechanic.amount')));
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `dart test test/plugins/affix/affix_mechanic_test.dart -r compact`
Expected: FAIL — `package:build_engine/affix_plugin.dart` does not exist / `AffixMechanic` undefined.

- [ ] **Step 3: Create the barrel stub so imports resolve**

```dart
// lib/affix_plugin.dart
/// The Affix plugin's public surface — import this, never
/// `package:build_engine/src/plugins/affix/...` directly.
library;

export 'src/plugins/affix/affix_mechanic.dart';
```

- [ ] **Step 4: Write the implementation**

```dart
// lib/src/plugins/affix/affix_mechanic.dart
import 'package:build_engine/build_engine.dart' show ContentFieldException;

/// The single mechanical effect an affix carries. Closed union: exactly
/// three variants in v1. `amount` is the canonical magnitude the engine
/// owns; nothing infers it from a label.
sealed class AffixMechanic {
  const AffixMechanic();

  num get amount;

  /// Parses a `{"kind": ..., "amount": ...}` object. Throws
  /// [ContentFieldException] (path `mechanic.kind` / `mechanic.amount`)
  /// on an unknown kind or a missing / non-numeric amount — the same
  /// exception `ContentRegistry` wraps as `ContentValidationException`.
  factory AffixMechanic.fromJson(Map<String, dynamic> json) {
    final amount = json['amount'];
    if (amount is! num) {
      throw ContentFieldException('mechanic.amount', 'required num field missing or not a number');
    }
    switch (json['kind']) {
      case 'weapon_stat_bonus':
        return WeaponStatBonus(amount);
      case 'heal':
        return ImmediateHeal(amount);
      case 'bank_progression':
        return BankProgression(amount);
      default:
        throw ContentFieldException('mechanic.kind', 'unknown affix mechanic kind: ${json['kind']}');
    }
  }
}

/// A flat bonus to an item copy's resolved weapon stat (bound via
/// `addItemStatBonuses`). Item-domain affixes only.
class WeaponStatBonus extends AffixMechanic {
  const WeaponStatBonus(this.amount);
  @override
  final num amount;
}

/// Restore `amount` vitality immediately. Technique-domain affixes only.
class ImmediateHeal extends AffixMechanic {
  const ImmediateHeal(this.amount);
  @override
  final num amount;
}

/// Bank `amount` extra upgrade points. Technique-domain affixes only.
class BankProgression extends AffixMechanic {
  const BankProgression(this.amount);
  @override
  final num amount;
}
```

- [ ] **Step 5: Run test to verify it passes**

Run: `dart test test/plugins/affix/affix_mechanic_test.dart -r compact`
Expected: PASS (3 tests).

- [ ] **Step 6: Commit**

```bash
git add lib/affix_plugin.dart lib/src/plugins/affix/affix_mechanic.dart test/plugins/affix/affix_mechanic_test.dart
git commit -m "feat(affix): AffixMechanic union (weapon_stat_bonus / heal / bank_progression)"
```

---

## Task 2: `AffixLean` / `AffixDomain` / category & pool-tag vocab + `AffixDefinition`

**Files:**
- Create: `lib/src/plugins/affix/affix_types.dart`, `lib/src/plugins/affix/affix_definition.dart`
- Modify: `lib/affix_plugin.dart`
- Test: `test/plugins/affix/affix_definition_test.dart`

**Interfaces:**
- Consumes: `AffixMechanic` (Task 1); `ContentDefinition`, `ContentRegistry`, `PluginContext`, `ContentFieldException` (from `build_engine`).
- Produces:
  - `enum AffixLean { neutral, force, flow }`
  - `enum AffixDomain { item, technique }`
  - `abstract final class AffixCategories { static const itemPrefix = 'item_prefix'; static const itemSuffix = 'item_suffix'; static const techniquePrefix = 'technique_prefix'; static const techniqueSuffix = 'technique_suffix'; static const all = [itemPrefix, itemSuffix, techniquePrefix, techniqueSuffix]; }`
  - `abstract final class AffixPoolTags { static const itemPrefix = 'affix_pool:item_prefix'; static const itemSuffix = 'affix_pool:item_suffix'; static const techniquePrefix = 'affix_pool:technique_prefix'; static const techniqueSuffix = 'affix_pool:technique_suffix'; static String forSlot(AffixDomain domain, String slotKind); }`
  - `class AffixDefinition { const AffixDefinition({required String id, required String label, required String category, required AffixLean lean, required AffixMechanic mechanic}); final String id; final String label; final String category; final AffixLean lean; final AffixMechanic mechanic; }`
  - `AffixDefinition affixDefinitionFromContent(ContentDefinition d)` — reads `d.extra['label']` (non-empty String), `d.extra['category']` (one of `AffixCategories.all`), the single `lean:*` tag in `d.tags`, `d.extra['mechanic']` (Map → `AffixMechanic.fromJson`). Throws `ContentFieldException` on any violation.
  - `AffixDefinition affixDefinition(String id, PluginContext context) => affixDefinitionFromContent(context.content.get(id))`

- [ ] **Step 1: Write the failing test**

```dart
// test/plugins/affix/affix_definition_test.dart
import 'package:build_engine/affix_plugin.dart';
import 'package:build_engine/build_engine.dart';
import 'package:test/test.dart';

ContentDefinition _load(ContentRegistry r, Map<String, dynamic> json) => r.load(json);

Map<String, dynamic> _keen() => {
      'id': 'af_keen',
      'type': 'affix',
      'tags': ['affix', 'affix_pool:item_prefix', 'lean:neutral'],
      'label': 'Keen',
      'category': 'item_prefix',
      'mechanic': {'kind': 'weapon_stat_bonus', 'amount': 3},
    };

void main() {
  test('affixDefinitionFromContent maps every field', () {
    final r = ContentRegistry();
    final def = affixDefinitionFromContent(_load(r, _keen()));
    expect(def.id, 'af_keen');
    expect(def.label, 'Keen');
    expect(def.category, AffixCategories.itemPrefix);
    expect(def.lean, AffixLean.neutral);
    expect(def.mechanic, isA<WeaponStatBonus>().having((m) => m.amount, 'amount', 3));
  });

  test('missing label / bad category / missing lean tag each throw ContentFieldException', () {
    final r = ContentRegistry();
    expect(() => affixDefinitionFromContent(_load(r, {..._keen(), 'id': 'a1'}..remove('label'))),
        throwsA(isA<ContentFieldException>().having((e) => e.path, 'path', 'label')));
    expect(() => affixDefinitionFromContent(_load(r, {..._keen(), 'id': 'a2', 'category': 'nope'})),
        throwsA(isA<ContentFieldException>().having((e) => e.path, 'path', 'category')));
    expect(
        () => affixDefinitionFromContent(
            _load(r, {..._keen(), 'id': 'a3', 'tags': ['affix', 'affix_pool:item_prefix']})),
        throwsA(isA<ContentFieldException>().having((e) => e.path, 'path', 'tags')));
  });

  test('AffixPoolTags.forSlot builds the tag string', () {
    expect(AffixPoolTags.forSlot(AffixDomain.item, 'prefix'), 'affix_pool:item_prefix');
    expect(AffixPoolTags.forSlot(AffixDomain.technique, 'suffix'), 'affix_pool:technique_suffix');
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `dart test test/plugins/affix/affix_definition_test.dart -r compact`
Expected: FAIL — `AffixDefinition` / `AffixCategories` / `affixDefinitionFromContent` undefined.

- [ ] **Step 3: Write `affix_types.dart`** (`AffixCategories.all` is a plain 4-element list — do not add logic to it)

```dart
// lib/src/plugins/affix/affix_types.dart

/// An affix's affinity lean. Maps to physique tradition in the resolver:
/// `western → force` favoured, `eastern → flow` favoured; `neutral` is
/// always mid-weight.
enum AffixLean { neutral, force, flow }

/// Which reward domain an affix slot belongs to.
enum AffixDomain { item, technique }

/// The canonical `category` string stored on every affix definition and
/// carried into the Almanac. Not a tag — display / history data.
abstract final class AffixCategories {
  static const itemPrefix = 'item_prefix';
  static const itemSuffix = 'item_suffix';
  static const techniquePrefix = 'technique_prefix';
  static const techniqueSuffix = 'technique_suffix';
  static const all = [itemPrefix, itemSuffix, techniquePrefix, techniqueSuffix];
}

/// The `affix_pool:*` tags the resolver enumerates. `category` and the
/// pool tag's suffix are deliberately the same four strings.
abstract final class AffixPoolTags {
  static const itemPrefix = 'affix_pool:item_prefix';
  static const itemSuffix = 'affix_pool:item_suffix';
  static const techniquePrefix = 'affix_pool:technique_prefix';
  static const techniqueSuffix = 'affix_pool:technique_suffix';

  static String forSlot(AffixDomain domain, String slotKind) =>
      'affix_pool:${domain == AffixDomain.item ? 'item' : 'technique'}_$slotKind';
}
```

- [ ] **Step 4: Write `affix_definition.dart`**

```dart
// lib/src/plugins/affix/affix_definition.dart
import 'package:build_engine/build_engine.dart';

import 'affix_mechanic.dart';
import 'affix_types.dart';

/// An affix's immutable, content-derived shape. Built from a loaded
/// `ContentDefinition` of `type: 'affix'` via [affixDefinitionFromContent]
/// — never hand-written. `id` is an opaque `af_*` token; `label` is the
/// only display string and is deterministic from the definition.
class AffixDefinition {
  const AffixDefinition({
    required this.id,
    required this.label,
    required this.category,
    required this.lean,
    required this.mechanic,
  });

  final String id;
  final String label;
  final String category;
  final AffixLean lean;
  final AffixMechanic mechanic;
}

AffixLean _leanFromTags(Set<String> tags) {
  for (final tag in tags) {
    if (tag.startsWith('lean:')) {
      return switch (tag.substring(5)) {
        'neutral' => AffixLean.neutral,
        'force' => AffixLean.force,
        'flow' => AffixLean.flow,
        _ => throw ContentFieldException('tags', 'unknown lean tag: $tag'),
      };
    }
  }
  throw ContentFieldException('tags', 'missing a lean:* tag');
}

AffixDefinition affixDefinitionFromContent(ContentDefinition d) {
  final label = d.extra['label'];
  if (label is! String || label.isEmpty) {
    throw ContentFieldException('label', 'required non-empty string field missing');
  }
  final category = d.extra['category'];
  if (category is! String || !AffixCategories.all.contains(category)) {
    throw ContentFieldException('category', 'must be one of ${AffixCategories.all}');
  }
  final mechanicRaw = d.extra['mechanic'];
  if (mechanicRaw is! Map) {
    throw ContentFieldException('mechanic', 'required object field missing');
  }
  final mechanic = AffixMechanic.fromJson(
    mechanicRaw.map((k, v) => MapEntry(k as String, v)),
  );
  return AffixDefinition(
    id: d.id,
    label: label,
    category: category,
    lean: _leanFromTags(d.tags),
    mechanic: mechanic,
  );
}

/// Resolves and parses affix [id] from [context]'s loaded content in one
/// call — mirrors `itemDefinition` / `consumableDefinition`.
AffixDefinition affixDefinition(String id, PluginContext context) =>
    affixDefinitionFromContent(context.content.get(id));
```

- [ ] **Step 5: Extend the barrel**

```dart
// lib/affix_plugin.dart — add these exports
export 'src/plugins/affix/affix_types.dart';
export 'src/plugins/affix/affix_definition.dart'
    show AffixDefinition, affixDefinitionFromContent, affixDefinition;
```

- [ ] **Step 6: Run test to verify it passes**

Run: `dart test test/plugins/affix/affix_definition_test.dart -r compact`
Expected: PASS (3 tests).

- [ ] **Step 7: Commit**

```bash
git add lib/src/plugins/affix/affix_types.dart lib/src/plugins/affix/affix_definition.dart lib/affix_plugin.dart test/plugins/affix/affix_definition_test.dart
git commit -m "feat(affix): AffixDefinition + lean/category/pool-tag vocabulary"
```

---

## Task 3: Ported affix content — the 33 entries

**Files:**
- Create: `lib/src/plugins/affix/affix_content.dart`
- Modify: `lib/affix_plugin.dart`
- Test: `test/plugins/affix/affix_content_test.dart`

**Interfaces:**
- Consumes: nothing at compile time (plain maps); parsed by `affixDefinitionFromContent` (Task 2) in tests.
- Produces: `final List<Map<String, dynamic>> affixContentDefinitions` — 33 entries. Each entry: `{'id': 'af_*', 'type': 'affix', 'tags': ['affix', 'affix_pool:<cat>', 'lean:<lean>'], 'label': <String>, 'category': '<cat>', 'mechanic': {'kind': ..., 'amount': ...}}` where `<cat>` is one of `item_prefix` / `item_suffix` / `technique_prefix` / `technique_suffix`.

- [ ] **Step 1: Write the failing test**

```dart
// test/plugins/affix/affix_content_test.dart
import 'package:build_engine/affix_plugin.dart';
import 'package:build_engine/build_engine.dart';
import 'package:test/test.dart';

void main() {
  test('33 entries: 11 / 9 / 7 / 6 per pool', () {
    int count(String cat) =>
        affixContentDefinitions.where((e) => e['category'] == cat).length;
    expect(affixContentDefinitions, hasLength(33));
    expect(count('item_prefix'), 11);
    expect(count('item_suffix'), 9);
    expect(count('technique_prefix'), 7);
    expect(count('technique_suffix'), 6);
  });

  test('every id is a distinct opaque af_* token, none equal to its label', () {
    final ids = affixContentDefinitions.map((e) => e['id'] as String).toList();
    expect(ids.toSet(), hasLength(33));
    for (final e in affixContentDefinitions) {
      final id = e['id'] as String;
      expect(id, startsWith('af_'));
      expect(id, isNot(equalsIgnoringCase(e['label'] as String)));
    }
  });

  test('every entry parses, and tag pool matches category + mechanic family', () {
    final r = ContentRegistry()..loadAll(affixContentDefinitions);
    for (final raw in affixContentDefinitions) {
      final def = affixDefinitionFromContent(r.get(raw['id'] as String));
      final tags = (raw['tags'] as List).cast<String>();
      expect(tags, contains('affix_pool:${def.category}'));
      final isItem =
          def.category == 'item_prefix' || def.category == 'item_suffix';
      expect(def.mechanic is WeaponStatBonus, isItem,
          reason: '${def.id}: item pools are weapon_stat_bonus, technique pools are heal/bank');
      expect(def.mechanic.amount, greaterThan(0));
    }
  });

  test('cross-pool labels have distinct ids', () {
    Map<String, dynamic> byId(String id) =>
        affixContentDefinitions.firstWhere((e) => e['id'] == id);
    expect(byId('af_flowing')['label'], 'Flowing');
    expect(byId('af_flowing_technique')['label'], 'Flowing');
    expect(byId('af_of_still_water')['label'], 'of Still Water');
    expect(byId('af_of_still_water_technique')['label'], 'of Still Water');
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `dart test test/plugins/affix/affix_content_test.dart -r compact`
Expected: FAIL — `affixContentDefinitions` undefined.

- [ ] **Step 3: Write `affix_content.dart`**

```dart
// lib/src/plugins/affix/affix_content.dart

/// The 33 reward affixes, ported verbatim (label / magnitude / lean)
/// from the client's `lib/core/engine/reward_affix.dart`. Ids are minted
/// `af_*` tokens; the two cross-pool labels (`Flowing`, `of Still
/// Water`) carry distinct ids. Item-pool affixes are all
/// `weapon_stat_bonus`; technique-pool affixes are `heal` or
/// `bank_progression`, per the source entry.
///
/// `final`, not `const` — the builders below keep 33 near-identical
/// entries DRY; `ContentRegistry` only needs `List<Map<String, dynamic>>`.
Map<String, dynamic> _affix(
  String id,
  String label,
  String category,
  String lean,
  Map<String, dynamic> mechanic,
) => {
      'id': id,
      'type': 'affix',
      'tags': ['affix', 'affix_pool:$category', 'lean:$lean'],
      'label': label,
      'category': category,
      'mechanic': mechanic,
    };

Map<String, dynamic> _stat(num a) => {'kind': 'weapon_stat_bonus', 'amount': a};
Map<String, dynamic> _heal(num a) => {'kind': 'heal', 'amount': a};
Map<String, dynamic> _bank(num a) => {'kind': 'bank_progression', 'amount': a};

final List<Map<String, dynamic>> affixContentDefinitions = <Map<String, dynamic>>[
  // ---- item prefixes (11) — weapon_stat_bonus ----
  _affix('af_plain', 'Plain', 'item_prefix', 'neutral', _stat(1)),
  _affix('af_sturdy', 'Sturdy', 'item_prefix', 'neutral', _stat(2)),
  _affix('af_keen', 'Keen', 'item_prefix', 'neutral', _stat(3)),
  _affix('af_tempered', 'Tempered', 'item_prefix', 'neutral', _stat(3)),
  _affix('af_masterwork', 'Masterwork', 'item_prefix', 'neutral', _stat(5)),
  _affix('af_heavy', 'Heavy', 'item_prefix', 'force', _stat(4)),
  _affix('af_brutal', 'Brutal', 'item_prefix', 'force', _stat(5)),
  _affix('af_ember_forged', 'Ember-Forged', 'item_prefix', 'force', _stat(6)),
  _affix('af_swift', 'Swift', 'item_prefix', 'flow', _stat(3)),
  _affix('af_flowing', 'Flowing', 'item_prefix', 'flow', _stat(4)),
  _affix('af_whispering', 'Whispering', 'item_prefix', 'flow', _stat(3)),

  // ---- item suffixes (9) — weapon_stat_bonus ----
  _affix('af_of_the_journeyman', 'of the Journeyman', 'item_suffix', 'neutral', _stat(2)),
  _affix('af_of_the_vanguard', 'of the Vanguard', 'item_suffix', 'neutral', _stat(3)),
  _affix('af_of_the_anvil', 'of the Anvil', 'item_suffix', 'neutral', _stat(4)),
  _affix('af_of_the_ember', 'of the Ember', 'item_suffix', 'force', _stat(4)),
  _affix('af_of_the_bear', 'of the Bear', 'item_suffix', 'force', _stat(5)),
  _affix('af_of_the_avalanche', 'of the Avalanche', 'item_suffix', 'force', _stat(7)),
  _affix('af_of_the_gale', 'of the Gale', 'item_suffix', 'flow', _stat(4)),
  _affix('af_of_still_water', 'of Still Water', 'item_suffix', 'flow', _stat(5)),
  _affix('af_of_the_reed', 'of the Reed', 'item_suffix', 'flow', _stat(3)),

  // ---- technique prefixes (7) — heal / bank_progression ----
  _affix('af_hard_won', 'Hard-Won', 'technique_prefix', 'neutral', _bank(1)),
  _affix('af_clean', 'Clean', 'technique_prefix', 'neutral', _bank(1)),
  _affix('af_drilled', 'Drilled', 'technique_prefix', 'neutral', _bank(2)),
  _affix('af_grounding', 'Grounding', 'technique_prefix', 'force', _heal(12)),
  _affix('af_iron_willed', 'Iron-Willed', 'technique_prefix', 'force', _bank(2)),
  _affix('af_serene', 'Serene', 'technique_prefix', 'flow', _heal(10)),
  _affix('af_flowing_technique', 'Flowing', 'technique_prefix', 'flow', _heal(14)),

  // ---- technique suffixes (6) — heal / bank_progression ----
  _affix('af_of_the_first_form', 'of the First Form', 'technique_suffix', 'neutral', _bank(1)),
  _affix('af_of_seven_stars', 'of Seven Stars', 'technique_suffix', 'neutral', _bank(2)),
  _affix('af_of_the_rising_sun', 'of the Rising Sun', 'technique_suffix', 'force', _heal(14)),
  _affix('af_of_the_iron_ox', 'of the Iron Ox', 'technique_suffix', 'force', _bank(2)),
  _affix('af_of_still_water_technique', 'of Still Water', 'technique_suffix', 'flow', _heal(16)),
  _affix('af_of_the_coiled_spring', 'of the Coiled Spring', 'technique_suffix', 'flow', _bank(2)),
];
```

- [ ] **Step 4: Extend the barrel**

```dart
// lib/affix_plugin.dart — add
export 'src/plugins/affix/affix_content.dart' show affixContentDefinitions;
```

- [ ] **Step 5: Run test to verify it passes**

Run: `dart test test/plugins/affix/affix_content_test.dart -r compact`
Expected: PASS (4 tests).

- [ ] **Step 6: Commit**

```bash
git add lib/src/plugins/affix/affix_content.dart lib/affix_plugin.dart test/plugins/affix/affix_content_test.dart
git commit -m "feat(affix): port the 33 reward affixes into engine content"
```

---

## Task 4: `AffixPlugin` — registration + content-parse validation

**Files:**
- Create: `lib/src/plugins/affix/affix_plugin.dart`
- Modify: `lib/affix_plugin.dart`
- Test: `test/plugins/affix/affix_plugin_test.dart`

**Interfaces:**
- Consumes: `GamePlugin`, `PluginSdk`, `PluginContext`, `ContentFieldException`, `ContentValidationException` (from `build_engine`); `affixContentDefinitions` (Task 3); `affixDefinitionFromContent`, `AffixDefinition`, `AffixCategories` (Task 2); `WeaponStatBonus` (Task 1).
- Produces: `class AffixPlugin extends GamePlugin` with `id == 'affix'`, `version == '0.1.0'`. `initialize`: registers the `affix`, `lean:{neutral,force,flow}`, `affix_pool:{item_prefix,item_suffix,technique_prefix,technique_suffix}` tags; loads `affixContentDefinitions` once (guarded by `context.content.find(<first id>) == null`); then validates every entry through `affixDefinitionFromContent` + a pool ⇔ mechanic-family check, wrapping any `ContentFieldException` as `ContentValidationException`. `unregister`: `sdk.disposeAll()`.

- [ ] **Step 1: Write the failing test**

```dart
// test/plugins/affix/affix_plugin_test.dart
import 'package:build_engine/affix_plugin.dart';
import 'package:build_engine/build_engine.dart';
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
  test('initialize loads content and enumerates by pool tag', () {
    final ctx = _ctx();
    AffixPlugin().initialize(ctx);
    expect(ctx.content.allOfType('affix'), hasLength(33));
    expect(ctx.content.withTag('affix_pool:item_prefix'), hasLength(11));
    expect(ctx.content.withTag('affix_pool:technique_suffix'), hasLength(6));
  });

  test('initialize is idempotent (second call, e.g. after unregister, does not throw)', () {
    final ctx = _ctx();
    AffixPlugin().initialize(ctx);
    expect(() => AffixPlugin()..initialize(ctx)..unregister(ctx), returnsNormally);
  });

  test('runs standalone (no other plugin initialized)', () {
    expect(() => AffixPlugin().initialize(_ctx()), returnsNormally);
  });

  test('a malformed affix entry makes initialize throw ContentValidationException', () {
    final ctx = _ctx();
    // Pre-load a bad entry under a shipped id so the load-once guard skips
    // registerContentBatch and the validation loop hits this map.
    ctx.content.load({
      'id': 'af_keen',
      'type': 'affix',
      'tags': ['affix', 'affix_pool:item_prefix', 'lean:neutral'],
      'label': 'Keen',
      'category': 'item_prefix',
      'mechanic': {'kind': 'heal', 'amount': 3}, // wrong family for an item pool
    });
    expect(() => AffixPlugin().initialize(ctx), throwsA(isA<ContentValidationException>()));
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `dart test test/plugins/affix/affix_plugin_test.dart -r compact`
Expected: FAIL — `AffixPlugin` undefined.

- [ ] **Step 3: Write `affix_plugin.dart`**

```dart
// lib/src/plugins/affix/affix_plugin.dart
import 'package:build_engine/build_engine.dart';

import 'affix_content.dart';
import 'affix_definition.dart';
import 'affix_mechanic.dart';
import 'affix_types.dart';

/// The Affix plugin: canonical reward-affix content (`type: 'affix'`),
/// enumerated by `affix_pool:*` tags. Pure content — no components, no
/// rules, no resources, no plugin-order constraint beyond needing the
/// Item / Technique content domains present when the resolver runs (the
/// harness initializes it after both). Modelled on `ConsumablePlugin`.
class AffixPlugin extends GamePlugin {
  @override
  String get id => 'affix';

  @override
  String get version => '0.1.0';

  late PluginSdk sdk;

  @override
  void initialize(PluginContext context) {
    sdk = PluginSdk(context);
    sdk.registerTag('affix', description: 'A reward affix (prefix / suffix).');
    for (final lean in const ['neutral', 'force', 'flow']) {
      sdk.registerTag('lean:$lean', description: 'Affix affinity lean.');
    }
    for (final cat in AffixCategories.all) {
      sdk.registerTag('affix_pool:$cat', description: 'Affix reward pool: $cat.');
    }

    // ContentRegistry has no unload — guard against loading twice.
    if (context.content.find(affixContentDefinitions.first['id'] as String) == null) {
      sdk.registerContentBatch(affixContentDefinitions);
    }

    // Validate every entry through the production parse path, then check
    // the pool ⇔ mechanic-family correspondence.
    for (final json in affixContentDefinitions) {
      final defId = json['id'] as String;
      try {
        final def = affixDefinitionFromContent(context.content.get(defId));
        final isItemPool = def.category == AffixCategories.itemPrefix ||
            def.category == AffixCategories.itemSuffix;
        final isStatMechanic = def.mechanic is WeaponStatBonus;
        if (isItemPool != isStatMechanic) {
          throw ContentFieldException(
            'mechanic.kind',
            'item pools require weapon_stat_bonus; technique pools require heal / bank_progression',
          );
        }
      } on ContentFieldException catch (e) {
        throw ContentValidationException(defId, e);
      }
    }
  }

  @override
  void unregister(PluginContext context) => sdk.disposeAll();
}
```

- [ ] **Step 4: Extend the barrel**

```dart
// lib/affix_plugin.dart — add
export 'src/plugins/affix/affix_plugin.dart' show AffixPlugin;
```

- [ ] **Step 5: Run test to verify it passes**

Run: `dart test test/plugins/affix/affix_plugin_test.dart -r compact`
Expected: PASS (4 tests).

- [ ] **Step 6: Run the full affix suite + analyze**

Run: `dart analyze lib/src/plugins/affix lib/affix_plugin.dart && dart test test/plugins/affix -r compact`
Expected: analyze clean; all tests PASS.

- [ ] **Step 7: Commit**

```bash
git add lib/src/plugins/affix/affix_plugin.dart lib/affix_plugin.dart test/plugins/affix/affix_plugin_test.dart
git commit -m "feat(affix): AffixPlugin registration + content-parse validation"
```

---

## Task 5: `resolveRewardAffixes` — deterministic 2-slot selection

**Files:**
- Create: `lib/src/plugins/affix/affix_resolver.dart`
- Modify: `lib/affix_plugin.dart`
- Test: `test/plugins/affix/affix_resolver_test.dart`

**Interfaces:**
- Consumes: `RngService`, `ContentRegistry` (from `build_engine`); `weightedPick` (relative import `../../rng/weighted_pick.dart`); `AffixDefinition`, `affixDefinitionFromContent`, `AffixLean`, `AffixDomain`, `AffixPoolTags` (Tasks 2); `affixContentDefinitions` (Task 3, tests only).
- Produces:
  - `const double kNoAffixChance = 0.34;`
  - `class AffixRewardContext { const AffixRewardContext({required AffixDomain domain, required String? physiqueTradition}); final AffixDomain domain; final String? physiqueTradition; }`
  - `class AffixResolvedSlot { const AffixResolvedSlot({required int position, required String slotKind, required AffixDefinition? affix}); final int position; final String slotKind; final AffixDefinition? affix; }` — value equality on `(position, slotKind, affix?.id)`.
  - `class AffixResolution { const AffixResolution(this.slots); final List<AffixResolvedSlot> slots; }` — value equality element-wise; always `slots.length == 2`.
  - `AffixResolution resolveRewardAffixes({required AffixRewardContext ctx, required RngService rng, required ContentRegistry content})`.

- [ ] **Step 1: Write the failing test**

```dart
// test/plugins/affix/affix_resolver_test.dart
import 'package:build_engine/affix_plugin.dart';
import 'package:build_engine/build_engine.dart';
import 'package:test/test.dart';

ContentRegistry _content() => ContentRegistry()..loadAll(affixContentDefinitions);

class _CountingRng extends RngService {
  _CountingRng(int seed) : super(seed);
  int doubles = 0;
  @override
  double nextDouble() {
    doubles++;
    return super.nextDouble();
  }
}

AffixResolution _resolve(int seed, AffixDomain domain, String? tradition,
        {RngService? rng}) =>
    resolveRewardAffixes(
      ctx: AffixRewardContext(domain: domain, physiqueTradition: tradition),
      rng: rng ?? RngService(seed),
      content: _content(),
    );

void main() {
  test('deterministic: same seed + ctx => equal resolution', () {
    expect(_resolve(7, AffixDomain.item, 'western'),
        equals(_resolve(7, AffixDomain.item, 'western')));
  });

  test('always exactly 2 slots, positions 0/1, slotKinds prefix/suffix', () {
    final r = _resolve(1, AffixDomain.technique, null);
    expect(r.slots, hasLength(2));
    expect(r.slots[0].position, 0);
    expect(r.slots[0].slotKind, 'prefix');
    expect(r.slots[1].position, 1);
    expect(r.slots[1].slotKind, 'suffix');
  });

  test('all four (prefix?, suffix?) states occur across seeds, both domains', () {
    for (final domain in AffixDomain.values) {
      final seen = <String>{};
      for (var seed = 0; seed < 400; seed++) {
        final r = _resolve(seed, domain, null);
        seen.add('${r.slots[0].affix == null}/${r.slots[1].affix == null}');
      }
      expect(seen, containsAll(<String>{'true/true', 'true/false', 'false/true', 'false/false'}),
          reason: 'domain $domain must reach none / suffix-only / prefix-only / both');
    }
  });

  test('affinity weighting: western favours force, eastern favours flow', () {
    int forceCount(String? tradition) {
      var n = 0;
      for (var seed = 0; seed < 600; seed++) {
        for (final s in _resolve(seed, AffixDomain.item, tradition).slots) {
          if (s.affix?.lean == AffixLean.force) n++;
        }
      }
      return n;
    }

    expect(forceCount('western'), greaterThan(forceCount('eastern')));
    expect(forceCount('western'), greaterThan(forceCount(null)));
  });

  test('draw order + count: one nextDouble per no-affix slot, two per affixed slot', () {
    // seed chosen so both slots land affixed (verify, then assert count)
    for (var seed = 0; seed < 50; seed++) {
      final rng = _CountingRng(seed);
      final r = _resolve(seed, AffixDomain.item, null, rng: rng);
      final affixed = r.slots.where((s) => s.affix != null).length;
      final empty = 2 - affixed;
      expect(rng.doubles, empty * 1 + affixed * 2,
          reason: 'seed $seed: $empty empty (1 draw) + $affixed affixed (2 draws)');
    }
  });

  test('resolution is inert: reading slots consumes nothing / mutates nothing', () {
    final rng = _CountingRng(3);
    final r = _resolve(3, AffixDomain.item, null, rng: rng);
    final before = rng.doubles;
    r.slots.map((s) => s.affix?.id).toList();
    r.slots.map((s) => s.slotKind).toList();
    expect(rng.doubles, before);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `dart test test/plugins/affix/affix_resolver_test.dart -r compact`
Expected: FAIL — `resolveRewardAffixes` / `AffixResolution` undefined.

- [ ] **Step 3: Write `affix_resolver.dart`**

```dart
// lib/src/plugins/affix/affix_resolver.dart
import 'package:build_engine/build_engine.dart';

import '../../rng/weighted_pick.dart';
import 'affix_definition.dart';
import 'affix_types.dart';

/// Independent per-slot probability that a slot comes up empty — a plain,
/// unadorned piece. Ported from `reward_affix.dart`'s `kNoAffixChance`.
const double kNoAffixChance = 0.34;

const List<String> _slotKinds = ['prefix', 'suffix'];

/// What the resolver needs to know about the reward being generated.
/// [physiqueTradition] is resolved by the caller from the fighter's
/// physique (`'western'` / `'eastern'` / null); the resolver never reads
/// component state.
class AffixRewardContext {
  const AffixRewardContext({required this.domain, required this.physiqueTradition});

  final AffixDomain domain;
  final String? physiqueTradition;
}

/// One resolved slot. [slotKind] (`'prefix'` / `'suffix'`) is a
/// presentation hint for name assembly, not affix identity. [affix] is
/// null when this slot rolled empty.
class AffixResolvedSlot {
  const AffixResolvedSlot({
    required this.position,
    required this.slotKind,
    required this.affix,
  });

  final int position;
  final String slotKind;
  final AffixDefinition? affix;

  @override
  bool operator ==(Object other) =>
      other is AffixResolvedSlot &&
      other.position == position &&
      other.slotKind == slotKind &&
      other.affix?.id == affix?.id;

  @override
  int get hashCode => Object.hash(position, slotKind, affix?.id);
}

/// The immutable, ordered result of one reward's affix resolution —
/// always exactly two slots, `[prefix, suffix]`. Resolved once at reward
/// generation and carried by value through preview and TAKE.
class AffixResolution {
  const AffixResolution(this.slots);

  final List<AffixResolvedSlot> slots;

  @override
  bool operator ==(Object other) {
    if (other is! AffixResolution || other.slots.length != slots.length) {
      return false;
    }
    for (var i = 0; i < slots.length; i++) {
      if (slots[i] != other.slots[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hashAll(slots);
}

/// Deterministic engine-owned affix selection. Draws ONLY from [rng], in
/// the normative order: for each slot in position order — one
/// `nextDouble()` for the no-affix check, then, if kept, one weighted
/// pick (which itself draws one `nextDouble()`). Pools come from
/// `affix_pool:*` tags on [content].
AffixResolution resolveRewardAffixes({
  required AffixRewardContext ctx,
  required RngService rng,
  required ContentRegistry content,
}) {
  final AffixLean? favoured = switch (ctx.physiqueTradition) {
    'western' => AffixLean.force,
    'eastern' => AffixLean.flow,
    _ => null,
  };

  num weightOf(AffixDefinition d) {
    if (d.lean == AffixLean.neutral) return 2;
    if (favoured == null) return 2;
    return d.lean == favoured ? 3 : 1;
  }

  final slots = <AffixResolvedSlot>[];
  for (var i = 0; i < _slotKinds.length; i++) {
    final slotKind = _slotKinds[i];
    final poolTag = AffixPoolTags.forSlot(ctx.domain, slotKind);
    final pool = [
      for (final d in content.withTag(poolTag)) affixDefinitionFromContent(d),
    ];

    if (rng.nextDouble() < kNoAffixChance || pool.isEmpty) {
      slots.add(AffixResolvedSlot(position: i, slotKind: slotKind, affix: null));
      continue;
    }

    final chosen = weightedPick<AffixDefinition>(pool, weightOf, rng)!;
    slots.add(AffixResolvedSlot(position: i, slotKind: slotKind, affix: chosen));
  }
  return AffixResolution(slots);
}
```

- [ ] **Step 4: Extend the barrel**

```dart
// lib/affix_plugin.dart — add
export 'src/plugins/affix/affix_resolver.dart';
```

- [ ] **Step 5: Run test to verify it passes**

Run: `dart test test/plugins/affix/affix_resolver_test.dart -r compact`
Expected: PASS (6 tests).

- [ ] **Step 6: Commit**

```bash
git add lib/src/plugins/affix/affix_resolver.dart lib/affix_plugin.dart test/plugins/affix/affix_resolver_test.dart
git commit -m "feat(affix): resolveRewardAffixes — deterministic 2-slot selection"
```

---

## Task 6: `applyAffixMechanic` — canonical mechanical application

**Files:**
- Create: `lib/src/plugins/affix/affix_application.dart`
- Modify: `lib/affix_plugin.dart`
- Test: `test/plugins/affix/affix_application_test.dart`

**Interfaces:**
- Consumes: `PluginContext`, `EntityId`, `HealthComponent`, `ItemResources` (from `build_engine` / `item_plugin.dart`); `addItemStatBonuses`, `WeaponStatTags`, `itemDefinition` (from `item_plugin.dart`); `AffixDefinition`, `WeaponStatBonus`, `ImmediateHeal`, `BankProgression` (Tasks 1–2).
- Produces:
  - `sealed class AffixApplicationTarget { const AffixApplicationTarget(); }`
  - `class ItemInstanceTarget extends AffixApplicationTarget { const ItemInstanceTarget({required EntityId instance, required String itemId}); final EntityId instance; final String itemId; }`
  - `class CharacterTarget extends AffixApplicationTarget { const CharacterTarget({required EntityId character}); final EntityId character; }`
  - `({String stat}) applyAffixMechanic(AffixDefinition def, AffixApplicationTarget target, PluginContext context)` — `stat` is always non-null: the resolved weapon stat for `WeaponStatBonus`, `'heal'` for `ImmediateHeal`, `'bank_progression'` for `BankProgression`. A mechanic/target mismatch throws `ArgumentError`.

- [ ] **Step 1: Write the failing test**

```dart
// test/plugins/affix/affix_application_test.dart
import 'package:build_engine/affix_plugin.dart';
import 'package:build_engine/build_engine.dart';
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

AffixDefinition _keen(PluginContext ctx) {
  ctx.content.load({
    'id': 'af_keen',
    'type': 'affix',
    'tags': ['affix', 'affix_pool:item_prefix', 'lean:neutral'],
    'label': 'Keen',
    'category': 'item_prefix',
    'mechanic': {'kind': 'weapon_stat_bonus', 'amount': 3},
  });
  return affixDefinition('af_keen', ctx);
}

AffixDefinition _heal12(PluginContext ctx) {
  ctx.content.load({
    'id': 'af_grounding',
    'type': 'affix',
    'tags': ['affix', 'affix_pool:technique_prefix', 'lean:force'],
    'label': 'Grounding',
    'category': 'technique_prefix',
    'mechanic': {'kind': 'heal', 'amount': 12},
  });
  return affixDefinition('af_grounding', ctx);
}

AffixDefinition _bank2(PluginContext ctx) {
  ctx.content.load({
    'id': 'af_drilled',
    'type': 'affix',
    'tags': ['affix', 'affix_pool:technique_prefix', 'lean:neutral'],
    'label': 'Drilled',
    'category': 'technique_prefix',
    'mechanic': {'kind': 'bank_progression', 'amount': 2},
  });
  return affixDefinition('af_drilled', ctx);
}

void main() {
  test('WeaponStatBonus binds to the ItemInstance and returns the resolved stat', () {
    final ctx = _ctx();
    ItemPlugin().initialize(ctx);
    final owner = ctx.entities.create();
    final instance = ownItem(owner, ItemIds.knife, ctx); // knife has a 'blade' tag
    final r = applyAffixMechanic(
        _keen(ctx), ItemInstanceTarget(instance: instance, itemId: ItemIds.knife), ctx);
    expect(r.stat, 'blade');
    expect(ctx.components.get<ItemInstance>(instance)!.statBonuses['blade'], 3);
  });

  test('two WeaponStatBonus applications accumulate on the same copy', () {
    final ctx = _ctx();
    ItemPlugin().initialize(ctx);
    final owner = ctx.entities.create();
    final instance = ownItem(owner, ItemIds.knife, ctx);
    final target = ItemInstanceTarget(instance: instance, itemId: ItemIds.knife);
    applyAffixMechanic(_keen(ctx), target, ctx); // +3
    applyAffixMechanic(_keen(ctx), target, ctx); // +3
    expect(ctx.components.get<ItemInstance>(instance)!.statBonuses['blade'], 6);
  });

  test('ImmediateHeal raises HealthComponent.current, clamped, returns stat "heal"', () {
    final ctx = _ctx();
    final c = ctx.entities.create();
    ctx.components.add(c, const HealthComponent(current: 90, max: 100));
    final r = applyAffixMechanic(_heal12(ctx), CharacterTarget(character: c), ctx);
    expect(r.stat, 'heal');
    expect(ctx.components.get<HealthComponent>(c)!.current, 100); // clamped to max
  });

  test('BankProgression adds upgrade points, returns stat "bank_progression"', () {
    final ctx = _ctx();
    ItemPlugin().initialize(ctx); // defines the upgradePoints resource
    final c = ctx.entities.create();
    final r = applyAffixMechanic(_bank2(ctx), CharacterTarget(character: c), ctx);
    expect(r.stat, 'bank_progression');
    expect(ctx.resources.amount(c, ItemResources.upgradePoints), 2);
  });

  test('mechanic / target mismatch throws ArgumentError', () {
    final ctx = _ctx();
    ItemPlugin().initialize(ctx);
    final c = ctx.entities.create();
    expect(
        () => applyAffixMechanic(_keen(ctx), CharacterTarget(character: c), ctx),
        throwsArgumentError);
    final owner = ctx.entities.create();
    final instance = ownItem(owner, ItemIds.knife, ctx);
    expect(
        () => applyAffixMechanic(
            _heal12(ctx), ItemInstanceTarget(instance: instance, itemId: ItemIds.knife), ctx),
        throwsArgumentError);
  });
}
```

> Note for the implementer: if `ctx.resources.amount(...)` is not the accessor name in this engine, use whatever `test/resource/` tests use to read a pool value (e.g. `ctx.resources.balanceOf` / `.valueOf`). Check `lib/src/resource/` before writing the assertion.

- [ ] **Step 2: Run test to verify it fails**

Run: `dart test test/plugins/affix/affix_application_test.dart -r compact`
Expected: FAIL — `applyAffixMechanic` / `AffixApplicationTarget` undefined.

- [ ] **Step 3: Write `affix_application.dart`**

```dart
// lib/src/plugins/affix/affix_application.dart
import 'dart:math' as math;

import 'package:build_engine/build_engine.dart';
import 'package:build_engine/item_plugin.dart';

import 'affix_definition.dart';
import 'affix_mechanic.dart';

/// Where a resolved affix's mechanics land. Item-domain rewards pass an
/// [ItemInstanceTarget] (the freshly-owned copy); technique-domain
/// rewards pass a [CharacterTarget].
sealed class AffixApplicationTarget {
  const AffixApplicationTarget();
}

class ItemInstanceTarget extends AffixApplicationTarget {
  const ItemInstanceTarget({required this.instance, required this.itemId});
  final EntityId instance;
  final String itemId;
}

class CharacterTarget extends AffixApplicationTarget {
  const CharacterTarget({required this.character});
  final EntityId character;
}

/// Applies [def]'s single [AffixMechanic] to [target] and returns the
/// canonical `stat` string for the Almanac snapshot — always non-null:
/// the resolved weapon stat for [WeaponStatBonus], `'heal'` for
/// [ImmediateHeal], `'bank_progression'` for [BankProgression].
///
/// A mechanic / target mismatch throws [ArgumentError] — unreachable
/// from validated content (the `affix_pool:*` tag fixes the domain), a
/// belt-and-braces guard against a composition bug.
({String stat}) applyAffixMechanic(
  AffixDefinition def,
  AffixApplicationTarget target,
  PluginContext context,
) {
  final mechanic = def.mechanic;
  switch (mechanic) {
    case WeaponStatBonus(:final amount):
      if (target is! ItemInstanceTarget) {
        throw ArgumentError('WeaponStatBonus (${def.id}) needs an ItemInstanceTarget');
      }
      final stat = WeaponStatTags.matchOrFallback(
        itemDefinition(target.itemId, context).tags,
        'item:${target.itemId}',
      );
      addItemStatBonuses(target.instance, {stat: amount}, context);
      return (stat: stat);

    case ImmediateHeal(:final amount):
      if (target is! CharacterTarget) {
        throw ArgumentError('ImmediateHeal (${def.id}) needs a CharacterTarget');
      }
      final health = context.components.get<HealthComponent>(target.character);
      if (health != null) {
        context.components.add(
          target.character,
          HealthComponent(
            current: math.min(health.current + amount, health.max),
            max: health.max,
          ),
        );
      }
      return (stat: 'heal');

    case BankProgression(:final amount):
      if (target is! CharacterTarget) {
        throw ArgumentError('BankProgression (${def.id}) needs a CharacterTarget');
      }
      context.resources.add(target.character, ItemResources.upgradePoints, amount);
      return (stat: 'bank_progression');
  }
}
```

- [ ] **Step 4: Extend the barrel**

```dart
// lib/affix_plugin.dart — add
export 'src/plugins/affix/affix_application.dart'
    show applyAffixMechanic, AffixApplicationTarget, ItemInstanceTarget, CharacterTarget;
```

- [ ] **Step 5: Run test to verify it passes**

Run: `dart test test/plugins/affix/affix_application_test.dart -r compact`
Expected: PASS (5 tests).

- [ ] **Step 6: Commit**

```bash
git add lib/src/plugins/affix/affix_application.dart lib/affix_plugin.dart test/plugins/affix/affix_application_test.dart
git commit -m "feat(affix): applyAffixMechanic — weapon-stat / heal / bank application"
```

---

## Task 7: `acquireAffixes` + `AffixAcquisitionIdSource` + `AffixAcquisition`

**Files:**
- Create: `lib/src/plugins/affix/affix_acquisition.dart`
- Modify: `lib/affix_plugin.dart`
- Test: `test/plugins/affix/affix_acquisition_test.dart`

**Interfaces:**
- Consumes: `PluginContext`, `EntityId` (from `build_engine`); `AffixResolution`, `AffixResolvedSlot` (Task 5); `applyAffixMechanic`, `AffixApplicationTarget`, `ItemInstanceTarget`, `CharacterTarget` (Task 6); `AffixDefinition`, `AffixMechanic.amount` (Tasks 1–2).
- Produces:
  - `class RunRef { const RunRef({required String runId, required int runNumber}); final String runId; final int runNumber; }`
  - `class AffixAcquisitionIdSource { String next({required RunRef run, required int slotPosition}); }` — private `int _seq = 0`; returns `'${run.runId}:affix:$slotPosition:${_seq++}'`. The **only** `affixEventId` constructor. Deterministic, no RNG.
  - `class AffixAcquisition { const AffixAcquisition({required String affixId, required String affixEventId, required String runId, required int runNumber, required String stat, required num value, required String category}); ...fields... }` — plain engine record; **no `almanac.dart` import in this file**.
  - `List<AffixAcquisition> acquireAffixes({required AffixResolution resolution, required AffixApplicationTarget target, required AffixAcquisitionIdSource idSource, required RunRef run, required PluginContext context})` — for each non-null slot in position order: `applyAffixMechanic` → `idSource.next` → append an `AffixAcquisition`. No RNG, no Almanac.

- [ ] **Step 1: Write the failing test**

```dart
// test/plugins/affix/affix_acquisition_test.dart
import 'package:build_engine/affix_plugin.dart';
import 'package:build_engine/build_engine.dart';
import 'package:build_engine/item_plugin.dart';
import 'package:test/test.dart';

class _CountingRng extends RngService {
  _CountingRng() : super(1);
  int calls = 0;
  @override
  double nextDouble() {
    calls++;
    return super.nextDouble();
  }
}

PluginContext _ctx({RngService? rng}) {
  final events = EventBus();
  final entities = EntityRegistry(events);
  final components = ComponentStore();
  final r = rng ?? RngService(1);
  return PluginContext(
    entities: entities,
    components: components,
    events: events,
    rng: r,
    rules: RuleEngine(entities: entities, components: components, events: events, rng: r),
    queries: QueryEngine(QueryScope(components: components)),
    modifiers: ModifierCollection(),
    content: ContentRegistry(),
  );
}

AffixResolvedSlot _slot(int pos, String kind, AffixDefinition? d) =>
    AffixResolvedSlot(position: pos, slotKind: kind, affix: d);

void main() {
  test('one AffixAcquisition per non-null slot; empty slot yields nothing', () {
    final ctx = _ctx();
    ItemPlugin().initialize(ctx);
    AffixPlugin().initialize(ctx);
    final owner = ctx.entities.create();
    final instance = ownItem(owner, ItemIds.knife, ctx);

    final resolution = AffixResolution([
      _slot(0, 'prefix', affixDefinition('af_keen', ctx)),
      _slot(1, 'suffix', null),
    ]);
    final out = acquireAffixes(
      resolution: resolution,
      target: ItemInstanceTarget(instance: instance, itemId: ItemIds.knife),
      idSource: AffixAcquisitionIdSource(),
      run: const RunRef(runId: 'run-1', runNumber: 1),
      context: ctx,
    );

    expect(out, hasLength(1));
    expect(out.single.affixId, 'af_keen');
    expect(out.single.stat, 'blade');
    expect(out.single.value, 3);
    expect(out.single.category, 'item_prefix');
    expect(out.single.runId, 'run-1');
    expect(ctx.components.get<ItemInstance>(instance)!.statBonuses['blade'], 3);
  });

  test('within one logical run, genuine repeats get distinct affixEventIds', () {
    final ctx = _ctx();
    ItemPlugin().initialize(ctx);
    AffixPlugin().initialize(ctx);
    final owner = ctx.entities.create();
    final source = AffixAcquisitionIdSource();
    const run = RunRef(runId: 'run-1', runNumber: 1);

    List<AffixAcquisition> takeKeen() {
      final instance = ownItem(owner, ItemIds.knife, ctx);
      return acquireAffixes(
        resolution: AffixResolution([
          _slot(0, 'prefix', affixDefinition('af_keen', ctx)),
          _slot(1, 'suffix', null),
        ]),
        target: ItemInstanceTarget(instance: instance, itemId: ItemIds.knife),
        idSource: source,
        run: run,
        context: ctx,
      );
    }

    final first = takeKeen().single.affixEventId;
    final second = takeKeen().single.affixEventId;
    expect(first, isNot(second));
  });

  test('two slots in one call => two distinct affixEventIds (per slot)', () {
    final ctx = _ctx();
    ItemPlugin().initialize(ctx);
    AffixPlugin().initialize(ctx);
    final owner = ctx.entities.create();
    final instance = ownItem(owner, ItemIds.knife, ctx);
    final out = acquireAffixes(
      resolution: AffixResolution([
        _slot(0, 'prefix', affixDefinition('af_keen', ctx)),
        _slot(1, 'suffix', affixDefinition('af_of_the_ember', ctx)),
      ]),
      target: ItemInstanceTarget(instance: instance, itemId: ItemIds.knife),
      idSource: AffixAcquisitionIdSource(),
      run: const RunRef(runId: 'run-1', runNumber: 1),
      context: ctx,
    );
    expect(out.map((a) => a.affixEventId).toSet(), hasLength(2));
    expect(out.map((a) => a.affixId), ['af_keen', 'af_of_the_ember']);
  });

  test('acquireAffixes consumes no RNG', () {
    final rng = _CountingRng();
    final ctx = _ctx(rng: rng);
    ItemPlugin().initialize(ctx);
    AffixPlugin().initialize(ctx);
    final owner = ctx.entities.create();
    final instance = ownItem(owner, ItemIds.knife, ctx);
    final before = rng.calls;
    acquireAffixes(
      resolution: AffixResolution([
        _slot(0, 'prefix', affixDefinition('af_keen', ctx)),
        _slot(1, 'suffix', null),
      ]),
      target: ItemInstanceTarget(instance: instance, itemId: ItemIds.knife),
      idSource: AffixAcquisitionIdSource(),
      run: const RunRef(runId: 'run-1', runNumber: 1),
      context: ctx,
    );
    expect(rng.calls, before);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `dart test test/plugins/affix/affix_acquisition_test.dart -r compact`
Expected: FAIL — `acquireAffixes` / `AffixAcquisition` / `AffixAcquisitionIdSource` undefined.

- [ ] **Step 3: Write `affix_acquisition.dart`**

```dart
// lib/src/plugins/affix/affix_acquisition.dart
//
// NOTE: this file must NOT import `package:build_engine/almanac.dart`.
// It returns plain records; the composition boundary builds the Almanac
// value objects.
import 'package:build_engine/build_engine.dart';

import 'affix_application.dart';
import 'affix_resolver.dart';

/// A logical run's identity, carried into every acquisition. [runId] is
/// opaque and caller-supplied; distinct logical runs must supply
/// distinct [runId]s.
class RunRef {
  const RunRef({required this.runId, required this.runNumber});
  final String runId;
  final int runNumber;
}

/// The single owner of `affixEventId`. One instance per logical run,
/// created by the engine reward/run layer. Deterministic monotonic
/// counter — no RNG. The sequence makes acquisition ids distinct
/// *within* one logical run; it makes no cross-run guarantee (that is
/// the caller's `runId` contract).
class AffixAcquisitionIdSource {
  int _seq = 0;

  String next({required RunRef run, required int slotPosition}) =>
      '${run.runId}:affix:$slotPosition:${_seq++}';
}

/// A plain engine-domain result — one per acquired affix. Carries no
/// `almanac.dart` type; the composition boundary builds
/// `AffixObservation` / `AffixSnapshot` from these fields.
class AffixAcquisition {
  const AffixAcquisition({
    required this.affixId,
    required this.affixEventId,
    required this.runId,
    required this.runNumber,
    required this.stat,
    required this.value,
    required this.category,
  });

  final String affixId;
  final String affixEventId; // from AffixAcquisitionIdSource — opaque, never parsed
  final String runId;
  final int runNumber;
  final String stat; // resolved weapon stat, or 'heal' / 'bank_progression'
  final num value; // == the affix's AffixMechanic.amount
  final String category; // the affix definition's category, verbatim
}

/// Applies every non-null slot's canonical mechanics (in position
/// order), mints one `affixEventId` per acquired affix via [idSource],
/// and returns the plain records. Consumes no RNG and touches no
/// Almanac. A no-affix slot yields nothing.
List<AffixAcquisition> acquireAffixes({
  required AffixResolution resolution,
  required AffixApplicationTarget target,
  required AffixAcquisitionIdSource idSource,
  required RunRef run,
  required PluginContext context,
}) {
  final out = <AffixAcquisition>[];
  for (final slot in resolution.slots) {
    final affix = slot.affix;
    if (affix == null) continue;
    final stat = applyAffixMechanic(affix, target, context).stat;
    final eventId = idSource.next(run: run, slotPosition: slot.position);
    out.add(AffixAcquisition(
      affixId: affix.id,
      affixEventId: eventId,
      runId: run.runId,
      runNumber: run.runNumber,
      stat: stat,
      value: affix.mechanic.amount,
      category: affix.category,
    ));
  }
  return out;
}
```

- [ ] **Step 4: Extend the barrel**

```dart
// lib/affix_plugin.dart — add
export 'src/plugins/affix/affix_acquisition.dart';
```

- [ ] **Step 5: Run test to verify it passes**

Run: `dart test test/plugins/affix/affix_acquisition_test.dart -r compact`
Expected: PASS (4 tests).

- [ ] **Step 6: Assert the no-Almanac-import invariant**

Run: `grep -rn "almanac" lib/src/plugins/affix/`
Expected: **no output** (zero matches — no affix-plugin file imports or mentions the Almanac).

- [ ] **Step 7: Commit**

```bash
git add lib/src/plugins/affix/affix_acquisition.dart lib/affix_plugin.dart test/plugins/affix/affix_acquisition_test.dart
git commit -m "feat(affix): acquireAffixes + engine-owned AffixAcquisitionIdSource"
```

---

## Task 8: Finalize barrel + package-wide analyze

**Files:**
- Modify: `lib/affix_plugin.dart` (final review)
- Test: `test/plugins/affix/affix_barrel_test.dart`

**Interfaces:**
- Consumes: everything exported so far.
- Produces: a `lib/affix_plugin.dart` that exports exactly the surface in spec §10 and nothing from `src/plugins/almanac/`.

- [ ] **Step 1: Write the barrel smoke test**

```dart
// test/plugins/affix/affix_barrel_test.dart
// Every public symbol the spec §10 promises must resolve through the
// single barrel import — nothing else.
import 'package:build_engine/affix_plugin.dart';
import 'package:test/test.dart';

void main() {
  test('the barrel exposes the full §10 surface', () {
    // types
    AffixLean.neutral;
    AffixDomain.item;
    AffixCategories.itemPrefix;
    AffixPoolTags.forSlot(AffixDomain.item, 'prefix');
    // mechanic
    const AffixMechanic m = WeaponStatBonus(1);
    expect(m.amount, 1);
    expect(AffixMechanic.fromJson({'kind': 'heal', 'amount': 2}), isA<ImmediateHeal>());
    // definition + content
    expect(affixContentDefinitions, hasLength(33));
    expect(affixDefinitionFromContent, isNotNull);
    // resolver
    expect(kNoAffixChance, 0.34);
    const AffixRewardContext(domain: AffixDomain.item, physiqueTradition: null);
    // application
    const ItemInstanceTarget(instance: _fakeId, itemId: 'x');
    // application target types
    expect(CharacterTarget, isNotNull);
    expect(ItemInstanceTarget, isNotNull);
    expect(applyAffixMechanic, isNotNull);
    // acquisition
    const RunRef(runId: 'r', runNumber: 1);
    AffixAcquisitionIdSource();
    const AffixAcquisition(
      affixId: 'a', affixEventId: 'e', runId: 'r', runNumber: 1,
      stat: 's', value: 1, category: 'item_prefix');
    expect(acquireAffixes, isNotNull);
    expect(AffixPlugin().id, 'affix');
  });
}
```

- [ ] **Step 2: Run the test**

Run: `dart test test/plugins/affix/affix_barrel_test.dart -r compact`
Expected: PASS.

- [ ] **Step 3: Confirm the barrel matches spec §10 exactly**

Open `lib/affix_plugin.dart`. It must read (order not significant):

```dart
/// The Affix plugin's public surface — import this, never
/// `package:build_engine/src/plugins/affix/...` directly.
library;

export 'src/plugins/affix/affix_types.dart';
export 'src/plugins/affix/affix_mechanic.dart';
export 'src/plugins/affix/affix_definition.dart'
    show AffixDefinition, affixDefinitionFromContent, affixDefinition;
export 'src/plugins/affix/affix_content.dart' show affixContentDefinitions;
export 'src/plugins/affix/affix_resolver.dart';
export 'src/plugins/affix/affix_application.dart'
    show applyAffixMechanic, AffixApplicationTarget, ItemInstanceTarget, CharacterTarget;
export 'src/plugins/affix/affix_acquisition.dart';
export 'src/plugins/affix/affix_plugin.dart' show AffixPlugin;
```

No `export ... almanac ...` line anywhere.

- [ ] **Step 4: Package-wide analyze + full affix suite**

Run: `dart analyze && dart test test/plugins/affix -r compact`
Expected: `No issues found!`; all affix tests PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/affix_plugin.dart test/plugins/affix/affix_barrel_test.dart
git commit -m "feat(affix): finalize the affix_plugin.dart public barrel"
```

---

## Task 9: Headless harness — resolve + acquire + publish in `RewardStage`

**Files:**
- Modify: `lib/src/plugins/game/run_events.dart`, `lib/src/plugins/game/reward_stage.dart`, `lib/src/plugins/game/game_run.dart`
- Test: `test/plugins/game/affix_reward_wiring_test.dart`

**Interfaces:**
- Consumes: `AffixDomain`, `AffixRewardContext`, `resolveRewardAffixes`, `AffixApplicationTarget`, `ItemInstanceTarget`, `CharacterTarget`, `RunRef`, `AffixAcquisitionIdSource`, `AffixAcquisition`, `acquireAffixes` (Tasks 5–7); `ownItem` return value (an `EntityId`); `MartialTraditions.western` / `.eastern` (the `traditionId` local in `game_run.dart`).
- Produces:
  - `run_events.dart`: `class AffixAcquired { const AffixAcquired({required this.acquisition, required this.rewardBaseId}); final AffixAcquisition acquisition; final String rewardBaseId; }`
  - `reward_stage.dart`: `RewardStage` gains four required ctor params — `String? physiqueTradition`, `String runId`, `int runNumber`, `AffixAcquisitionIdSource affixIdSource`. `resolveReward`'s `RewardKind.itemOrTechnique` branch now resolves + acquires + publishes and appends `+<affixId>` per acquired affix to its return string (`item:iron_sword+af_keen+af_of_the_ember`).
  - `game_run.dart`: constructs one `AffixAcquisitionIdSource`, initializes `AffixPlugin` after `ConsumablePlugin`, and passes the four new params into `RewardStage`.

- [ ] **Step 1: Write the failing test**

```dart
// test/plugins/game/affix_reward_wiring_test.dart
import 'package:build_engine/affix_plugin.dart';
import 'package:build_engine/game.dart';
import 'package:test/test.dart';

void main() {
  test('a seed grants at least one affixed component; the reward string carries affix ids', () {
    // NeverReplacePolicy keeps reward choices deterministic; several seeds
    // guarantee at least one item/technique reward with an affix.
    final withAffix = <String>[];
    for (var seed = 0; seed < 25; seed++) {
      final result = runGame(seed, policy: const NeverReplacePolicy());
      withAffix.addAll(result.rewardsGranted.where((r) => r.contains('+af_')));
    }
    expect(withAffix, isNotEmpty,
        reason: 'across 25 seeds some item/technique reward must roll an affix');
    // shape: "<base>+af_x" or "<base>+af_x+af_y"
    for (final r in withAffix) {
      final parts = r.split('+');
      expect(parts.first, anyOf(startsWith('item:'), startsWith('technique:')));
      expect(parts.skip(1), everyElement(startsWith('af_')));
      expect(parts.skip(1).length, lessThanOrEqualTo(2));
    }
  });

  test('AffixAcquired fires with a canonical acquisition; determinism holds', () {
    final a = runGame(3, policy: const NeverReplacePolicy());
    final b = runGame(3, policy: const NeverReplacePolicy());
    expect(a.rewardsGranted, b.rewardsGranted,
        reason: 'affix resolution must not perturb the run RNG sequence');
  });
}
```

> Implementer note: if `NeverReplacePolicy` is not the exact policy name used by `test/plugins/game/run_game_almanac_validation_test.dart`, copy whatever deterministic policy those tests use.

- [ ] **Step 2: Run test to verify it fails**

Run: `dart test test/plugins/game/affix_reward_wiring_test.dart -r compact`
Expected: FAIL — `rewardsGranted` entries have no `+af_` segment (wiring absent).

- [ ] **Step 3: Add the `AffixAcquired` event**

In `lib/src/plugins/game/run_events.dart`, add the import and the class:

```dart
import 'package:build_engine/affix_plugin.dart';
```

```dart
/// One affix acquired on an item/technique reward. Telemetry only —
/// carries the whole canonical [AffixAcquisition] so the Almanac bridge
/// records it without reconstructing anything. Same tier as
/// [RewardSelected].
class AffixAcquired {
  const AffixAcquired({required this.acquisition, required this.rewardBaseId});

  final AffixAcquisition acquisition;

  /// The reward's base id string, e.g. `'item:iron_sword'`.
  final String rewardBaseId;
}
```

Add a row to the events-table doc comment at the top of the file:

```
/// | Affix acquired | [AffixAcquired] | new — one per acquired affix on an item/technique reward |
```

- [ ] **Step 4: Wire `RewardStage`**

In `lib/src/plugins/game/reward_stage.dart`:

Add the import:

```dart
import 'package:build_engine/affix_plugin.dart';
```

Add the four fields to the constructor:

```dart
  RewardStage({
    required this.character,
    required this.context,
    required this.recordingPolicy,
    required this.events,
    required this.tomeManager,
    required this.itemsDiscovered,
    required this.rewardPool,
    required this.physiqueTradition,
    required this.runId,
    required this.runNumber,
    required this.affixIdSource,
  });

  // ... existing fields ...

  /// `'western'` / `'eastern'` / null — the fighter's tradition, used
  /// only to weight the affix draw.
  final String? physiqueTradition;
  final String runId;
  final int runNumber;
  final AffixAcquisitionIdSource affixIdSource;
```

Replace the `RewardKind.itemOrTechnique` branch of `resolveReward` so the item and technique arms resolve + acquire + publish. The item arm captures `ownItem`'s return value; the technique arm targets the character:

```dart
      case RewardKind.itemOrTechnique:
        final entry = rewardPool[rewardIndex];
        rewardIndex++;
        if (entry.referenceType == itemReferenceType) {
          final item = itemDefinition(entry.contentId, context);
          final instance = ownItem(character, item.id, context);
          discoverItem(character, item, context);
          itemsDiscovered.add(item.id);
          if (isItemUsable(character, item, context)) {
            tomeManager.placeItem(item, '$stepName reward');
          }
          return 'item:${item.id}${_acquireRewardAffixes(
            AffixDomain.item,
            ItemInstanceTarget(instance: instance, itemId: item.id),
            'item:${item.id}',
          )}';
        } else if (entry.referenceType == consumableReferenceType) {
          final consumable = consumableDefinition(entry.contentId, context);
          tomeManager.placeConsumable(consumable, '$stepName reward');
          return 'consumable:${consumable.id}';
        } else {
          final technique = techniqueDefinition(entry.contentId, context);
          discoverTechnique(character, technique, context);
          return 'technique:${technique.id}${_acquireRewardAffixes(
            AffixDomain.technique,
            CharacterTarget(character: character),
            'technique:${technique.id}',
          )}';
        }
```

Add the private helper to `RewardStage`:

```dart
  /// Resolve the reward's affix slots (engine RNG), apply their canonical
  /// mechanics, mint acquisition identity, publish one [AffixAcquired]
  /// per acquired affix, and return the `+<affixId>` suffix for the
  /// reward string. Empty when no affix rolls.
  String _acquireRewardAffixes(
    AffixDomain domain,
    AffixApplicationTarget target,
    String rewardBaseId,
  ) {
    final resolution = resolveRewardAffixes(
      ctx: AffixRewardContext(domain: domain, physiqueTradition: physiqueTradition),
      rng: context.rng,
      content: context.content,
    );
    final acquisitions = acquireAffixes(
      resolution: resolution,
      target: target,
      idSource: affixIdSource,
      run: RunRef(runId: runId, runNumber: runNumber),
      context: context,
    );
    final suffix = StringBuffer();
    for (final acquisition in acquisitions) {
      events.publish(AffixAcquired(acquisition: acquisition, rewardBaseId: rewardBaseId));
      suffix.write('+${acquisition.affixId}');
    }
    return suffix.toString();
  }
```

- [ ] **Step 5: Wire `game_run.dart`**

In `lib/src/plugins/game/game_run.dart`:

Add the import (if `game.dart`'s barrels don't already surface it):

```dart
import 'package:build_engine/affix_plugin.dart';
```

Initialize the plugin right after `ConsumablePlugin().initialize(context);`:

```dart
  ConsumablePlugin().initialize(context);
  AffixPlugin().initialize(context);
```

Just before the `final rewardStage = RewardStage(` line, add:

```dart
  final affixIdSource = AffixAcquisitionIdSource();
  final affixRunId = runId ?? 'seed:$seed';
  final affixRunNumber = runNumber ?? 0;
```

Pass the four new params into the `RewardStage(` constructor call:

```dart
  final rewardStage = RewardStage(
    character: character,
    context: context,
    recordingPolicy: recordingPolicy,
    events: events,
    tomeManager: tomeManager,
    itemsDiscovered: itemsDiscovered,
    rewardPool: rewardPool,
    physiqueTradition: traditionId,
    runId: affixRunId,
    runNumber: affixRunNumber,
    affixIdSource: affixIdSource,
  );
```

(`traditionId` is the existing `MartialTraditions.western` / `.eastern` local — the harness's western/eastern signal. The resolver is origin-agnostic; the client will pass its physique-derived value.)

- [ ] **Step 6: Run test to verify it passes**

Run: `dart test test/plugins/game/affix_reward_wiring_test.dart -r compact`
Expected: PASS (2 tests).

- [ ] **Step 7: Run the game + reward suites unchanged**

Run: `dart analyze && dart test test/plugins/game test/reward -r compact`
Expected: analyze clean; all PASS (existing `run_game_*` determinism tests still green — the run RNG order is preserved because resolution draws come after each reward-pool pick).

> If an existing determinism test that hard-codes an expected `rewardsGranted` list now fails **only because affix `+af_*` segments were appended**, that is an expected, intended change to the reward-string format — update that test's expected strings to include the affix segments. Do **not** change any other assertion. If a determinism test fails for any other reason, stop and investigate.

- [ ] **Step 8: Commit**

```bash
git add lib/src/plugins/game/run_events.dart lib/src/plugins/game/reward_stage.dart lib/src/plugins/game/game_run.dart test/plugins/game/affix_reward_wiring_test.dart
git commit -m "feat(game): resolve + acquire reward affixes in RewardStage; AffixAcquired event"
```

---

## Task 10: Headless harness — record affixes in `HeadlessGameAlmanacBridge`

**Files:**
- Modify: `lib/src/plugins/game/almanac_bridge.dart`
- Test: `test/integration/affix_end_to_end_test.dart`

**Interfaces:**
- Consumes: `AffixAcquired` (Task 9); `AlmanacRecorder.recordAffixDiscovered`, `AffixObservation`, `AffixSnapshot` (from `almanac.dart`, already imported by this file).
- Produces: the bridge subscribes to `AffixAcquired`, builds `AffixObservation` / `AffixSnapshot` **from `e.acquisition`**, calls `recordAffixDiscovered`, and accumulates the `AffixSnapshot`s so `_buildSnapshot` passes real values to `AlmanacBuildRecord.affixes` and `buildDna(affixCategories: ...)` instead of the `const []` stubs.

- [ ] **Step 1: Write the failing test**

```dart
// test/integration/affix_end_to_end_test.dart
import 'package:build_engine/almanac.dart';
import 'package:build_engine/game.dart';
import 'package:test/test.dart';

void main() {
  test('runGame records acquired affixes into the Almanac', () {
    // Find a seed whose run grants at least one affix, then assert it landed.
    for (var seed = 0; seed < 25; seed++) {
      final recorder = AlmanacRecorder();
      final result = runGame(seed,
          policy: const NeverReplacePolicy(),
          almanac: recorder,
          runId: 'run-$seed',
          runNumber: 1);
      final rolledAffix = result.rewardsGranted.any((r) => r.contains('+af_'));
      if (!rolledAffix) continue;

      expect(recorder.state.affixes, isNotEmpty);
      final rec = recorder.state.affixes.first;
      expect(rec.discoveryObservations, isNotEmpty);
      expect(rec.snapshot.value, greaterThan(0));
      // build snapshots now carry affixes (no const [] stub)
      final anyBuildHasAffix = recorder.state.runs
          .expand((run) => run.buildRecords)
          .any((b) => b.affixes.isNotEmpty);
      expect(anyBuildHasAffix, isTrue);
      return; // asserted on the first affix-bearing seed
    }
    fail('no seed in 0..24 rolled an affix — widen the range');
  });

  test('re-recording the same acquisition is idempotent', () {
    for (var seed = 0; seed < 25; seed++) {
      final recorder = AlmanacRecorder();
      final result = runGame(seed,
          policy: const NeverReplacePolicy(),
          almanac: recorder,
          runId: 'run-$seed',
          runNumber: 1);
      if (!result.rewardsGranted.any((r) => r.contains('+af_'))) continue;

      final rec = recorder.state.affixes.first;
      final obs = rec.discoveryObservations.first;
      final before = rec.discoveryObservations.length;
      recorder.recordAffixDiscovered(
        affixId: rec.affixId,
        observation: obs,
        snapshot: rec.snapshot,
        timestamp: DateTime.utc(2026),
      );
      final after = recorder.state.affixes
          .firstWhere((a) => a.affixId == rec.affixId)
          .discoveryObservations
          .length;
      expect(after, before, reason: '(affixId, affixEventId) de-dupe holds');
      return;
    }
    fail('no seed in 0..24 rolled an affix — widen the range');
  });
}
```

> Implementer note: adjust `run.buildRecords` / `state.runs` accessor names to whatever `test/integration/almanac_run_history_test.dart` uses to walk build records.

- [ ] **Step 2: Run test to verify it fails**

Run: `dart test test/integration/affix_end_to_end_test.dart -r compact`
Expected: FAIL — `recorder.state.affixes` is empty (bridge doesn't subscribe).

- [ ] **Step 3: Wire the bridge**

In `lib/src/plugins/game/almanac_bridge.dart`:

Add the import:

```dart
import 'package:build_engine/affix_plugin.dart';
```

Add a run-local accumulator field next to the other run-local temporaries:

```dart
  final List<AffixSnapshot> _affixSnapshots = <AffixSnapshot>[];
```

In `attach`, add the subscription alongside the others:

```dart
    _subs.add(events.subscribe<AffixAcquired>(_onAffixAcquired));
```

Add the handler (first line `if (_disposed) return;`, like every other):

```dart
  void _onAffixAcquired(AffixAcquired e) {
    if (_disposed) return;
    final a = e.acquisition;
    final snapshot = AffixSnapshot(
      affixId: a.affixId,
      stat: a.stat,
      value: a.value,
      category: a.category,
    );
    _affixSnapshots.add(snapshot);
    _recorder.recordAffixDiscovered(
      affixId: a.affixId,
      observation: AffixObservation(
        affixEventId: a.affixEventId,
        runId: a.runId,
        runNumber: a.runNumber,
      ),
      snapshot: snapshot,
      timestamp: DateTime.now(),
    );
  }
```

In `_buildSnapshot`, replace the two stubs:

```dart
      affixes: const <AffixSnapshot>[],
```
becomes
```dart
      affixes: List<AffixSnapshot>.unmodifiable(_affixSnapshots),
```

and in the `buildDna(` call:

```dart
        affixCategories: const <String>[],
```
becomes
```dart
        affixCategories: <String>[
          for (final s in _affixSnapshots)
            if (s.category != null) s.category!,
        ],
```

- [ ] **Step 4: Run test to verify it passes**

Run: `dart test test/integration/affix_end_to_end_test.dart -r compact`
Expected: PASS (2 tests).

- [ ] **Step 5: Run the almanac + integration suites unchanged**

Run: `dart analyze && dart test test/plugins/almanac test/plugins/game test/integration -r compact`
Expected: analyze clean; all PASS. `run_game_almanac_validation_test.dart`'s "byte-identical" / determinism assertions still hold (affix recording is additive; the run's RNG and decision log are unchanged).

- [ ] **Step 6: Commit**

```bash
git add lib/src/plugins/game/almanac_bridge.dart test/integration/affix_end_to_end_test.dart
git commit -m "feat(game): record acquired affixes via HeadlessGameAlmanacBridge"
```

---

## Task 11: Full verification + acceptance sweep

**Files:** none (verification only) — plus the spec Status line.

- [ ] **Step 1: Whole-suite green**

Run: `dart analyze && dart test -r compact`
Expected: `No issues found!`; every test passes. Record the pass count. Confirm no pre-existing test was weakened, skipped, or rebaselined except the reward-string expectations noted in Task 9 Step 7.

- [ ] **Step 2: No-Almanac-coupling invariant**

Run: `grep -rn "almanac" lib/src/plugins/affix/`
Expected: no output.

- [ ] **Step 3: Acceptance sweep against spec §12**

Walk spec §12 and tick each box against a passing test (bullets that name the *client* — e.g. "no client-side type contains an acquisition-id allocator" — are out of scope for this engine plan; note them N/A):
- Identity & enumeration → `affix_content_test.dart`, `affix_plugin_test.dart`
- Selection (determinism, weighting, four states, draw order) → `affix_resolver_test.dart`
- Offer stability & purity → `affix_resolver_test.dart` (inert-resolution test), `affix_reward_wiring_test.dart` (determinism)
- Mechanics → `affix_application_test.dart`
- Acquisition identity (single owner, per-run uniqueness, no client allocator, no RNG) → `affix_acquisition_test.dart`
- Event & recording boundary (event carries the whole acquisition; no `almanac.dart` import; applied == recorded) → Step 2 + `affix_end_to_end_test.dart`
- Wiring & exports → `affix_barrel_test.dart`, `affix_end_to_end_test.dart`, `dart analyze`

List any box without a corresponding passing test and add the missing test before proceeding.

- [ ] **Step 4: Update the spec Status**

In `docs/superpowers/specs/2026-09-10-engine-affix-plugin-design.md`, change the `**Status:**` line to:

```
**Status:** implemented — <commit range>
```

- [ ] **Step 5: Commit**

```bash
git add docs/superpowers/specs/2026-09-10-engine-affix-plugin-design.md
git commit -m "docs(affix): mark the engine affix API implemented"
```

---

## Self-Review

**1. Spec coverage**

| Spec section | Task |
|---|---|
| §2 D1 dedicated plugin | Task 4 |
| §2 D2 `type: 'affix'` + pool enumeration | Tasks 3, 4 |
| §2 D3 `AffixMechanic` union | Task 1 |
| §2 D4 engine selection rule + content pools | Task 5 |
| §2 D5 immutable ordered 2-slot `AffixResolution` | Task 5 |
| §2 D6 one `affixEventId` per acquired affix | Task 7 |
| §2 D7 single-owner `AffixAcquisitionIdSource`, per-run uniqueness | Task 7 |
| §2 D8 resolve once / preview purity | Task 5 (inert-resolution test) |
| §2 D9 normative RNG draw order | Task 5 (counting-rng test) |
| §2 D10 no `recordAffixUsed` | not implemented (correct) |
| §2 D11 33-entry verbatim port | Task 3 |
| §2 D12 full harness wiring | Tasks 9, 10 |
| §2 D13 plain `AffixAcquisition`, no `almanac.dart` import | Task 7 (+ grep gates in Tasks 7, 11) |
| §2 D14 `AffixAcquired` carries the whole acquisition | Tasks 9, 10 |
| §2.1 lifecycle / phase contract | Tasks 5–10 collectively |
| §4 module files | Tasks 1–7 |
| §4.1 content shape | Task 3 |
| §5 selection & resolution | Task 5 |
| §6.1–6.2 targets + `applyAffixMechanic` | Task 6 |
| §6.4 `acquireAffixes` | Task 7 |
| §6.5 `AffixAcquisitionIdSource` | Task 7 |
| §7 harness wiring | Tasks 9, 10 |
| §8 ported content table | Task 3 |
| §9 content-parse validation | Task 4 |
| §10 public barrel | Tasks 1–8 (finalized Task 8) |
| §11 non-goals | respected (no schema change, no reward-resolver change, no `recordAffixUsed`, no second RNG) |
| §12 acceptance criteria | Task 11 sweep |
| §13 client follow-up | out of scope (client repo) |

No gaps.

**2. Placeholder scan**

No "TBD" / "handle edge cases" / "similar to Task N". Every code step carries the full code. Three implementer notes flag repo-detail lookups (`ctx.resources` accessor name, deterministic policy name, build-record accessor name, `EntityId` const-ness) — these are "verify the exact local name" notes, not missing content; each names the neighbouring test file that already uses the real name.

**3. Type consistency**

- `AffixDefinition` fields (`id`, `label`, `category`, `lean`, `mechanic`) — defined Task 2, consumed unchanged in Tasks 4, 5, 7.
- `AffixMechanic.amount` — defined Task 1, read in Tasks 6, 7.
- `AffixResolvedSlot` (`position`, `slotKind`, `affix`) / `AffixResolution` (`slots`) — defined Task 5, consumed Task 7.
- `applyAffixMechanic` returns `({String stat})` (non-null) everywhere — Tasks 6, 7, and the spec's §6.2 / §6.4 / §12 (fixed in the design commit preceding this plan).
- `AffixAcquisition` fields (`affixId`, `affixEventId`, `runId`, `runNumber`, `stat`, `value`, `category`) — defined Task 7, consumed identically in Tasks 9 (`AffixAcquired`) and 10 (bridge builds `AffixObservation` / `AffixSnapshot`).
- `AffixAcquisitionIdSource.next({required RunRef run, required int slotPosition})` — defined Task 7, called only inside `acquireAffixes` (Task 7); constructed in `game_run.dart` (Task 9), never called there.
- `RewardStage` new params (`physiqueTradition`, `runId`, `runNumber`, `affixIdSource`) — added Task 9, supplied by `game_run.dart` in the same task.
- `AffixAcquired` (`acquisition`, `rewardBaseId`) — defined Task 9, consumed Task 10.
- Barrel `package:build_engine/affix_plugin.dart` — grown one export per task (Tasks 1–7), frozen and audited against spec §10 in Task 8.

No mismatches.

---

## Execution Handoff

Plan saved to `docs/superpowers/plans/2026-09-10-engine-affix-plugin.md`.

**1. Subagent-Driven (recommended)** — fresh subagent per task, review between tasks. REQUIRED SUB-SKILL: `superpowers:subagent-driven-development`.

**2. Inline Execution** — `superpowers:executing-plans`, batch with checkpoints.
