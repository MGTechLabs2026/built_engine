# SP4a (engine) — Consumable Almanac DNA — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Teach the in-engine Almanac an SP3-consumable occupant kind so `build_engine`'s own replay-equivalence coverage stops silently dropping consumable Tome placements.

**Architecture:** Three production changes — `buildDna()` gains a `consumableIds` token channel; `HeadlessGameAlmanacBridge._buildSnapshot` classifies a `consumable` placement as `occupantKind: 'consumable'` (fixing a latent `'empty'` + non-null-`occupantRefId` record) and feeds the DNA channel; `AlmanacRecorder._withDna` reads consumable slots when it back-fills an empty DNA. No new type, no serialization-schema change, no gameplay read, no RNG. Consumable placements ride in the existing `TomeLayoutSnapshot.slots` list and the existing `BuildDna.tokens` list.

**Tech Stack:** Dart 3.7 (`sdk: ^3.7.0`), `package:test` 1.25, `lints` 5. No new dependencies. `dart test <path>` / `dart analyze <paths>`.

**Spec:** `docs/superpowers/specs/2026-09-08-sp4a-engine-bump-design.md` (Part A, §4–§8). Read it alongside this plan; `§` references point into it. Brainstorm audit: `docs/superpowers/specs/2026-09-08-sp4a-engine-bump-notes.md`.

## Global Constraints

- **No new public type.** One parameter on the `buildDna(...)` function; one ternary arm + one list in `_buildSnapshot`; one comprehension in `_withDna`. `AlmanacBuildRecord`, `TomeSlotSnapshot`, `TomeLayoutSnapshot`, `AlmanacSerialization` are **not** modified except the `TomeSlotSnapshot` docstring line. (spec §2.2)
- **`buildDna`'s `consumableIds` is `required`** (not optional-with-default) — mirrors `techniqueFamilies` / `itemIds`. (spec §4.2)
- **Fixed token position: after `itemIds`, before `affixCategories`.** Documented in the docstring. (spec §4.2)
- **Backward-compatible signature.** A build with zero consumables must hash to the **same** `signature` as before this change. The existing `'FNV cross-check … fully predictable token list'` test in `almanac_build_dna_test.dart` is the proof: adding `consumableIds: const <String>[]` to its call must not change `expectedTokens` or the asserted signature. (spec §4.2)
- **A consumable placement has no per-copy state.** In `_buildSnapshot`: `occupantRefId: ref.contentId`, `instanceId: null`, and **no** `techniques` / `items` snapshot-list entry. (spec §4.3)
- **No RNG, no gameplay read, no new event, no new subscription, no recorder method.** (spec §2.2, §8)
- **Determinism is mandatory.** The existing `test/game/` seed-stable + replay assertions must pass unchanged — this change adds no gameplay and no randomness. A failure there is a real bug — STOP. (spec §6, §8)
- **`output/` artifacts are not regenerated** — no run behaviour changes. (spec §8)
- Commit after every task. Conventional-commit messages. Branch: `sp4a-engine-almanac-consumable-dna` (create from `main`).
- Every commit message ends with:
  ```
  Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
  Claude-Session: https://claude.ai/code/session_01E3k4BFeWXfPzkZzXinqTZk
  ```

---

## File Structure

**Modified — production:**
- `lib/src/plugins/almanac/almanac_build_dna.dart` — `buildDna()` gains `required Iterable<String> consumableIds`, tokenised between `itemIds` and `affixCategories`; docstring updated. (Task 1)
- `lib/src/plugins/game/almanac_bridge.dart` — `_buildSnapshot`: `consumable_plugin.dart` import; `occupantKind` gains a `'consumable'` arm; a `consumableIds` list collected in the placement loop and passed to `buildDna`. (Task 3)
- `lib/src/plugins/almanac/almanac_recorder.dart` — `_withDna` back-fill passes `consumableIds` derived from `record.tome.slots` where `occupantKind == 'consumable'`. (Task 4)
- `lib/src/plugins/almanac/almanac_models.dart` — `TomeSlotSnapshot` docstring line only (`'consumable'` added to the listed kinds). (Task 3)

**Modified — tests:**
- `test/plugins/almanac/almanac_build_dna_test.dart` — new consumable cases; 8 existing `buildDna(` calls gain `consumableIds: const <String>[]`. (Task 1)
- `test/integration/almanac_run_history_test.dart` — `_occupants` split into `_placedOccupants` / `_discoverableOccupants`; four call sites rewired; debt comment removed (Task 2); a consumable-coverage test added (Task 3).
- `test/plugins/almanac/almanac_build_snapshot_test.dart` — a back-fill test with a consumable slot. (Task 4)
- `test/plugins/almanac/almanac_adapter_parity_test.dart` — a `consumable` occupant in one fixture build; `_OccKind` gains `consumable`; `_buildRecordFor` gains a `consumable` branch. (Task 5)

**Modified — docs:**
- `CHANGELOG.md` — `### Changed — SP4a (Almanac consumable build-DNA)`. (Task 1 for the `buildDna` line; Task 3 for the bridge line)
- `ARCHITECTURE.md` — one sentence in the `**BuildDna` is a projection…` paragraph. (Task 3)

**New:** none.

---

## Task 1: `buildDna()` gains the `consumableIds` channel

**Files:**
- Modify: `lib/src/plugins/almanac/almanac_build_dna.dart:14-31` (signature + token list + docstring)
- Modify: `CHANGELOG.md` (Unreleased section)
- Test: `test/plugins/almanac/almanac_build_dna_test.dart`

**Interfaces:**
- Produces: `BuildDna buildDna({required String lineageId, required String physiqueId, required Iterable<String> techniqueFamilies, required Iterable<String> itemIds, required Iterable<String> consumableIds, required Iterable<String> affixCategories, required Iterable<Map<String, num>> axisProfiles})` — `consumableIds` tokens land in `BuildDna.tokens` between the last `itemIds` token and the first `affixCategories` token, each `.toUpperCase()`, sorted-unique.

- [ ] **Step 1: Add the new test cases**

Add these tests inside the existing `group('buildDna', () { … })` in `test/plugins/almanac/almanac_build_dna_test.dart`:

```dart
    test('consumable reorder-invariance: shuffled consumableIds give the same '
        'tokens and signature', () {
      final BuildDna a = buildDna(
        lineageId: 'lin',
        physiqueId: 'phy',
        techniqueFamilies: const <String>[],
        itemIds: const <String>[],
        consumableIds: <String>['heal_potion', 'firebomb', 'heal_potion'],
        affixCategories: const <String>[],
        axisProfiles: const <Map<String, num>>[],
      );
      final BuildDna b = buildDna(
        lineageId: 'lin',
        physiqueId: 'phy',
        techniqueFamilies: const <String>[],
        itemIds: const <String>[],
        consumableIds: <String>['firebomb', 'heal_potion'],
        affixCategories: const <String>[],
        axisProfiles: const <Map<String, num>>[],
      );
      expect(b.tokens, a.tokens);
      expect(b.signature, a.signature);
    });

    test('change-sensitivity: adding a consumable id changes the signature', () {
      final BuildDna base = buildDna(
        lineageId: 'lin',
        physiqueId: 'phy',
        techniqueFamilies: const <String>[],
        itemIds: <String>['boots'],
        consumableIds: const <String>[],
        affixCategories: const <String>[],
        axisProfiles: const <Map<String, num>>[],
      );
      final BuildDna changed = buildDna(
        lineageId: 'lin',
        physiqueId: 'phy',
        techniqueFamilies: const <String>[],
        itemIds: <String>['boots'],
        consumableIds: <String>['heal_potion'],
        affixCategories: const <String>[],
        axisProfiles: const <Map<String, num>>[],
      );
      expect(changed.signature, isNot(base.signature));
    });

    test('consumable tokens land between itemIds and affixCategories', () {
      final BuildDna dna = buildDna(
        lineageId: 'lin',
        physiqueId: 'phy',
        techniqueFamilies: const <String>[],
        itemIds: <String>['boots'],
        consumableIds: <String>['heal_potion'],
        affixCategories: <String>['offense'],
        axisProfiles: const <Map<String, num>>[],
      );
      expect(dna.tokens, <String>[
        'LIN',
        'PHY',
        'BOOTS',
        'HEAL_POTION',
        'OFFENSE',
      ]);
    });

    test('zero consumables: signature unchanged vs the pre-channel token list', () {
      // The channel is additive: an empty consumableIds contributes no
      // token, so this is byte-identical to the historical projection.
      final BuildDna dna = buildDna(
        lineageId: 'lin',
        physiqueId: 'phy',
        techniqueFamilies: <String>['b', 'a', 'a'],
        itemIds: <String>['z'],
        consumableIds: const <String>[],
        affixCategories: const <String>[],
        axisProfiles: <Map<String, num>>[
          <String, num>{'x': 2},
          <String, num>{'y': -5},
          <String, num>{'w': 1},
        ],
      );
      final List<String> expectedTokens = <String>[
        'LIN', 'PHY', 'A', 'B', 'Z', 'W', 'X', 'Y',
      ];
      expect(dna.tokens, expectedTokens);
      expect(dna.signature, _hex8(_fnv1a32(expectedTokens.join('|'))));
    });
```

- [ ] **Step 2: Run the test file — expect a compile failure**

Run: `dart test test/plugins/almanac/almanac_build_dna_test.dart`
Expected: FAIL — compile error, `buildDna` has no named parameter `consumableIds` (the new tests and, once you touch them in Step 4, the existing calls).

- [ ] **Step 3: Add the parameter and token to `buildDna`**

In `lib/src/plugins/almanac/almanac_build_dna.dart`, change the signature and token list:

```dart
BuildDna buildDna({
  required String lineageId,
  required String physiqueId,
  required Iterable<String> techniqueFamilies,
  required Iterable<String> itemIds,
  required Iterable<String> consumableIds,
  required Iterable<String> affixCategories,
  required Iterable<Map<String, num>> axisProfiles,
}) {
  final List<String> tokens = <String>[
    lineageId.toUpperCase(),
    physiqueId.toUpperCase(),
    ..._sortedUniqueUpper(techniqueFamilies),
    ..._sortedUniqueUpper(itemIds),
    ..._sortedUniqueUpper(consumableIds),
    ..._sortedUniqueUpper(affixCategories),
    ..._topAxisTokens(axisProfiles),
  ];
  return BuildDna(tokens: tokens, signature: _fnv1a32Hex(tokens.join('|')));
}
```

And update the docstring (lines 3–13) — change the parenthetical list to name the consumable channel and its fixed position:

```dart
/// [BuildDna.tokens] is a canonical, order-independent projection of a build's
/// defining ids: lineage, physique, then sorted-unique technique families,
/// item ids, consumable ids, and affix categories (in that fixed order —
/// the order is part of the signature), then up to three dominant axis
/// names. Their `|`-joined form is hashed with FNV-1a (32-bit) into
/// [BuildDna.signature], lowercase 8-char hex. A derived projection only —
/// never an identity or dedup key.
```

- [ ] **Step 4: Add `consumableIds: const <String>[]` to the 8 existing `buildDna(` calls in the test file**

In `test/plugins/almanac/almanac_build_dna_test.dart`, every existing `buildDna(...)` call currently passes `itemIds:` then `affixCategories:`. Insert `consumableIds: const <String>[],` between them at each site:
- `sample()` — line ~34
- `a` in the reorder-invariance test — line ~56
- `b` in the reorder-invariance test — line ~70
- `changed` in "adding an item id" — line ~91
- `before` in "bumping an axis" — line ~107
- `after` in "bumping an axis" — line ~117
- `dna` in "FNV cross-check … predictable token list" — line ~155 (do **not** touch `expectedTokens` or the asserted signature — that is the backward-compat proof)
- `dna` in "top-3 axis selection … tie-break" — line ~186

- [ ] **Step 5: Run the test file — expect PASS**

Run: `dart test test/plugins/almanac/almanac_build_dna_test.dart`
Expected: PASS (all cases, including the unchanged FNV cross-check).

- [ ] **Step 6: Fix the two production call sites so the package compiles**

`buildDna` has two non-test callers. Give each a temporary empty channel now; Tasks 3 and 4 replace them with the real feed.

In `lib/src/plugins/game/almanac_bridge.dart` (the `buildDna(` call at ~line 413), add between `itemIds:` and `affixCategories:`:

```dart
        consumableIds: const <String>[],
```

In `lib/src/plugins/almanac/almanac_recorder.dart` (the `buildDna(` call in `_withDna`, ~line 591), add between `itemIds:` and `affixCategories:`:

```dart
        consumableIds: const <String>[],
```

- [ ] **Step 7: Run analyze + the full Almanac suite**

Run: `dart analyze lib test/plugins/almanac test/integration/almanac_run_history_test.dart`
Expected: no issues.
Run: `dart test test/plugins/almanac`
Expected: PASS (behaviour is unchanged — both production callers pass an empty channel).

- [ ] **Step 8: CHANGELOG**

In `CHANGELOG.md`, under `## Unreleased`, add a new section (place it above `### Added — Tiered Component Effects (SP1)`):

```markdown
### Changed — SP4a (Almanac consumable build-DNA)

- **`buildDna(...)` gained a required `consumableIds` channel** — sorted-unique
  upper-cased tokens at a fixed position (after `itemIds`, before
  `affixCategories`). A build with zero consumables hashes to the **same**
  `signature` as before (the channel is additive), so no stored `BuildDna` is
  invalidated.
```

- [ ] **Step 9: Commit**

```bash
git add lib/src/plugins/almanac/almanac_build_dna.dart \
        lib/src/plugins/game/almanac_bridge.dart \
        lib/src/plugins/almanac/almanac_recorder.dart \
        test/plugins/almanac/almanac_build_dna_test.dart \
        CHANGELOG.md
git commit -m "feat(almanac): buildDna gains a consumableIds channel (SP4a)

Fixed token position after itemIds, before affixCategories. Additive:
zero-consumable builds keep their signature. Production callers pass an
empty channel for now — real feed lands with the bridge/recorder tasks.

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01E3k4BFeWXfPzkZzXinqTZk"
```

---

## Task 2: Split the run-history occupant projection (behaviour-neutral refactor)

Prepares `almanac_run_history_test.dart` for the bridge change in Task 3. Today no slot has `occupantKind == 'consumable'` (the bridge emits `'empty'` for consumables), so both new helpers behave exactly like the current `_occupants` at every site — this task changes no assertion outcome.

**Files:**
- Modify: `test/integration/almanac_run_history_test.dart:33-53` (the `_occupants` helper + its doc comment), and its four call sites (lines ~190, ~411, ~502, ~563)

**Interfaces:**
- Consumes: nothing from earlier tasks.
- Produces (test-local): `Set<String?> _placedOccupants(AlmanacBuildRecord b)` — every non-empty placement (`occupantKind != 'empty'`), consumables included once Task 3 lands. `Set<String?> _discoverableOccupants(AlmanacBuildRecord b)` — item + technique placements only.

- [ ] **Step 1: Replace the helper and its doc comment**

In `test/integration/almanac_run_history_test.dart`, replace the block at lines ~33–53 (the doc comment starting "Item/technique occupants only." through the end of the `_occupants` definition) with:

```dart
/// Item + technique occupants — the *discoverable kit*. Consumables are
/// deliberately excluded: they are real Tome occupants but carry no
/// discovery subject, so a discovery-delta assertion must not see them.
Set<String?> _discoverableOccupants(AlmanacBuildRecord b) => {
  for (final s in b.tome.slots)
    if (s.occupantRefId != null &&
        (s.occupantKind == 'item' || s.occupantKind == 'technique'))
      s.occupantRefId,
};

/// Every non-empty placement — consumables included. The full placed set
/// the replay-equivalence projection must reproduce byte-for-byte.
Set<String?> _placedOccupants(AlmanacBuildRecord b) => {
  for (final s in b.tome.slots)
    if (s.occupantRefId != null && s.occupantKind != 'empty') s.occupantRefId,
};
```

(The `_ForceItemReward` class immediately above stays. The removed doc comment is the one that ends "SP4 must teach the bridge a `'consumable'` occupantKind *and* restore consumable coverage to this almanac-side projection." — delete it entirely; this task and Task 3 are that work.)

- [ ] **Step 2: Rewire the four call sites**

- Line ~190, inside the replay-equivalence `project()` (the `'build|…'` row): `_occupants(b)` → `_placedOccupants(b)`.
- Line ~411, `newlyPlaced.addAll(_occupants(b).difference(_occupants(initial)))`: both → `_discoverableOccupants`.
- Line ~502, `expect(_occupants(finalBuild).containsAll(_occupants(initial)), isTrue)`: both → `_placedOccupants`.
- Line ~563, `_occupants(chain[i]).containsAll(_occupants(chain[i - 1]))`: both → `_placedOccupants`.

The local `Map<String, String?> occupied(AlmanacBuildRecord b)` inside the postTraining test (~line 542) is left unchanged — it already filters `!= 'empty'` and its monotonic check is unaffected by a persistent consumable placement.

- [ ] **Step 3: Run the integration test — expect PASS (unchanged)**

Run: `dart test test/integration/almanac_run_history_test.dart`
Expected: PASS — identical outcomes; no slot is `'consumable'` yet, so `_placedOccupants` == the old `_occupants` and `_discoverableOccupants` drops nothing that was there.

- [ ] **Step 4: Commit**

```bash
git add test/integration/almanac_run_history_test.dart
git commit -m "test(almanac): split run-history occupant projection for consumables (SP4a)

_placedOccupants (every non-empty placement) vs _discoverableOccupants
(item/technique only). Behaviour-neutral now; the bridge task makes
consumable slots real and _placedOccupants starts covering them. Removes
the b0ee428 SP4-debt comment.

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01E3k4BFeWXfPzkZzXinqTZk"
```

---

## Task 3: Bridge emits `occupantKind: 'consumable'` and feeds the DNA channel

**Files:**
- Modify: `lib/src/plugins/game/almanac_bridge.dart` (imports line ~1-6; `_buildSnapshot` lines ~337-426)
- Modify: `lib/src/plugins/almanac/almanac_models.dart` (`TomeSlotSnapshot` docstring, ~line 392-394)
- Modify: `CHANGELOG.md`, `ARCHITECTURE.md`
- Test: `test/plugins/almanac/almanac_build_snapshot_test.dart` (a bridge-independent slot-kind assertion is not possible here — see Step 1), `test/integration/almanac_run_history_test.dart` (new consumable-coverage test)

**Interfaces:**
- Consumes: `_placedOccupants` / `_discoverableOccupants` from Task 2; `buildDna(..., consumableIds:, ...)` from Task 1.
- Consumes from engine surface: `consumableReferenceType` (from `package:build_engine/consumable_plugin.dart`), `rewardPoolConsumableIds` (from `package:build_engine/game.dart`, already imported by the integration test).
- Produces: `TomeSlotSnapshot` with `occupantKind == 'consumable'`, `occupantRefId == <contentId>`, `instanceId == null` for every consumable Tome placement; the snapshot's `BuildDna` reflects those ids.

- [ ] **Step 1: Write the failing consumable-coverage integration test**

Add to `test/integration/almanac_run_history_test.dart`, as a new `test(...)` in the same top-level `group`/`main` body (place it after the "same seed + same policy + same runId replayed" test, ~line 208):

```dart
  test('a consumable Tome placement is recorded as occupantKind "consumable" '
      'and feeds the build DNA + replay-equivalence projection', () {
    // Sweep for the first seed whose forced item/technique rewards land a
    // consumable on the Tome (the reward pool is one flat list; a draw can
    // yield any of the three reference types).
    int? seedWithConsumable;
    AlmanacState? stateWithConsumable;
    for (var seed = 1; seed <= 40; seed++) {
      final recorder = AlmanacRecorder();
      runGame(
        seed,
        policy: const _ForceItemReward(),
        almanac: recorder,
        runId: 'cs',
        runNumber: 1,
      );
      final hasConsumableSlot = recorder.state.builds.any(
        (b) => b.tome.slots.any((s) => s.occupantKind == 'consumable'),
      );
      if (hasConsumableSlot) {
        seedWithConsumable = seed;
        stateWithConsumable = recorder.state;
        break;
      }
    }
    expect(
      seedWithConsumable,
      isNotNull,
      reason: 'no seed in 1..40 placed a consumable under _ForceItemReward — '
          'the reward pool or policy changed; pick a new sweep or a '
          'consumable-forcing fixture',
    );
    final state = stateWithConsumable!;

    // Every consumable slot is well-formed: real refId, null instanceId,
    // and its id is a known reward-pool consumable.
    final consumableSlots = [
      for (final b in state.builds)
        for (final s in b.tome.slots)
          if (s.occupantKind == 'consumable') s,
    ];
    expect(consumableSlots, isNotEmpty);
    for (final s in consumableSlots) {
      expect(s.occupantRefId, isNotNull);
      expect(rewardPoolConsumableIds, contains(s.occupantRefId));
      expect(s.instanceId, isNull);
    }

    // The consumable id is in the placed-occupant projection and in the
    // build DNA token list of the record that holds it.
    final holder = state.builds.firstWhere(
      (b) => b.tome.slots.any((s) => s.occupantKind == 'consumable'),
    );
    final consumableId = holder.tome.slots
        .firstWhere((s) => s.occupantKind == 'consumable')
        .occupantRefId!;
    expect(_placedOccupants(holder), contains(consumableId));
    expect(_discoverableOccupants(holder), isNot(contains(consumableId)));
    expect(holder.dna.tokens, contains(consumableId.toUpperCase()));

    // A second identical run replays to an equivalent projection.
    final again = AlmanacRecorder();
    runGame(
      seedWithConsumable!,
      policy: const _ForceItemReward(),
      almanac: again,
      runId: 'cs',
      runNumber: 1,
    );
    List<String> project(AlmanacState s) => [
      for (final b in s.builds)
        'build|${b.runId}|${b.phase}|${b.sequence}|${b.dna.signature}|'
            '${(_placedOccupants(b).whereType<String>().toList()..sort()).join(",")}',
    ];
    expect(project(again.state), equals(project(state)));
  });
```

- [ ] **Step 2: Run it — expect FAIL**

Run: `dart test test/integration/almanac_run_history_test.dart -n "occupantKind \"consumable\""`
Expected: FAIL — `seedWithConsumable` is `null` (the bridge still emits `'empty'` for consumable placements), so the `isNotNull` expectation fails.

- [ ] **Step 3: Add the import**

In `lib/src/plugins/game/almanac_bridge.dart`, add to the import block (after `technique_plugin.dart`, ~line 6):

```dart
import 'package:build_engine/consumable_plugin.dart';
```

- [ ] **Step 4: Classify the consumable slot and collect its id**

In `_buildSnapshot` (`lib/src/plugins/game/almanac_bridge.dart`, ~line 337 onward):

Add a local list beside `slots` / `techniques` / `items` (~line 338-342):

```dart
    final List<String> consumableIds = <String>[];
```

In the placement loop, after `final bool isItem = ref.referenceType == itemReferenceType;` (~line 347), add:

```dart
      final bool isConsumable = ref.referenceType == consumableReferenceType;
```

Change the `occupantKind` expression in the `slots.add(TomeSlotSnapshot(...))` call (~line 351-357) to:

```dart
          occupantKind:
              isTechnique
                  ? 'technique'
                  : isItem
                  ? 'item'
                  : isConsumable
                  ? 'consumable'
                  : 'empty',
```

Immediately after the `slots.add(...)` call closes (before the `if (isTechnique && …)` block, ~line 361), add:

```dart
      if (isConsumable) {
        consumableIds.add(ref.contentId);
      }
```

(Leave `occupantRefId: ref.contentId` and `instanceId: ref.instanceEntityId?.value.toString()` as they are — `instanceEntityId` is null for a consumable ref, so `instanceId` is null. Do **not** add a `techniques` or `items` entry for a consumable.)

- [ ] **Step 5: Feed the DNA channel**

In the `return AlmanacBuildRecord(...)` at the end of `_buildSnapshot`, in the `dna: buildDna(...)` call, replace the temporary `consumableIds: const <String>[],` (added in Task 1 Step 6) with:

```dart
        consumableIds: consumableIds,
```

- [ ] **Step 6: Run the new test — expect PASS**

Run: `dart test test/integration/almanac_run_history_test.dart -n "occupantKind \"consumable\""`
Expected: PASS.

- [ ] **Step 7: Run the full integration file + Almanac suite + analyze**

Run: `dart test test/integration/almanac_run_history_test.dart test/plugins/almanac`
Expected: PASS. In particular the existing "same seed + same policy + same runId replayed" test still passes (its `project()` now includes consumable ids on both the `once()` and `twice()` sides — still equal).
Run: `dart analyze lib test`
Expected: no issues.

- [ ] **Step 8: Docstring + CHANGELOG + ARCHITECTURE**

In `lib/src/plugins/almanac/almanac_models.dart`, the `TomeSlotSnapshot` docstring (~line 392-394) currently reads "`[occupantKind]` is `'technique'`, `'item'`, or `'empty'`." — change to:

```dart
/// One slot of a tome layout. [occupantKind] is `'technique'`, `'item'`,
/// `'consumable'`, or `'empty'`. A `'consumable'` slot carries a real
/// [occupantRefId] but a null [instanceId] — a consumable has no per-copy
/// instanced entity (its charges are a per-fight resource, not stored state).
```

In `CHANGELOG.md`, extend the `### Changed — SP4a (Almanac consumable build-DNA)` section from Task 1 with a second bullet:

```markdown
- **`HeadlessGameAlmanacBridge` now records a consumable Tome placement as
  `occupantKind: 'consumable'`** (previously an inconsistent `'empty'` with a
  non-null `occupantRefId`) and feeds its content id into the `consumableIds`
  DNA channel. `instanceId` is null for a consumable slot; no per-copy
  `items` / `techniques` snapshot entry is emitted.
```

In `ARCHITECTURE.md`, the `**BuildDna` is a projection, not an identity.**` paragraph (~line 780-784) — append one sentence:

```markdown
The shape covered is lineage, physique, technique families, item ids,
consumable ids, and affix categories; a Tome slot's `occupantKind` is one
of `technique` / `item` / `consumable` / `empty`, and a `consumable` slot
records its content id but no per-copy instance.
```

- [ ] **Step 9: Commit**

```bash
git add lib/src/plugins/game/almanac_bridge.dart \
        lib/src/plugins/almanac/almanac_models.dart \
        test/integration/almanac_run_history_test.dart \
        CHANGELOG.md ARCHITECTURE.md
git commit -m "feat(almanac): record consumable Tome placements (SP4a)

_buildSnapshot classifies a consumable ref as occupantKind 'consumable'
(was an inconsistent 'empty' + non-null refId) and feeds its id into the
buildDna consumableIds channel. instanceId null; no per-copy snapshot
entry. Replay-equivalence coverage restored via _placedOccupants.

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01E3k4BFeWXfPzkZzXinqTZk"
```

---

## Task 4: Recorder DNA back-fill reads consumable slots

`AlmanacRecorder._withDna` re-derives `BuildDna` when a record arrives with an empty `dna` (`record.dna.tokens.isEmpty`). It composes the DNA from `record.techniques` / `record.items` / `record.affixes` — none of which carry consumables. Make it read `record.tome.slots` for `occupantKind == 'consumable'` so a back-filled DNA matches what the bridge would have computed. Uses only existing record data — no new field (spec §4.2 refinement: `record.tome.slots` *is* an already-projected field).

**Files:**
- Modify: `lib/src/plugins/almanac/almanac_recorder.dart` (`_withDna`, the `buildDna(` call ~line 591-607)
- Test: `test/plugins/almanac/almanac_build_snapshot_test.dart`

**Interfaces:**
- Consumes: `buildDna(..., consumableIds:, ...)` from Task 1; `occupantKind == 'consumable'` slots from Task 3.
- Produces: `_withDna` back-fill now includes consumable-slot content ids in the recomputed `BuildDna`.

- [ ] **Step 1: Write the failing test**

In `test/plugins/almanac/almanac_build_snapshot_test.dart`, add a test in the `group('build snapshots', () { … })`, right after the existing `'an empty DNA is back-filled from the snapshot contents'` test (~line 168):

```dart
    test('an empty DNA back-fill includes consumable slots from the tome '
        'layout', () {
      final recorder =
          AlmanacRecorder()..recordBuildSnapshot(
            buildRecordWithoutDna(
              runId: 'run-1',
              buildId: 'b0',
              lineageId: 'western',
              physiqueId: 'phy-a',
              items: [itemSnapshot(definitionId: 'iron_sword')],
              tome: TomeLayoutSnapshot(
                width: 2,
                height: 1,
                slots: const [
                  TomeSlotSnapshot(
                    slotId: 's0',
                    occupantKind: 'item',
                    occupantRefId: 'iron_sword',
                  ),
                  TomeSlotSnapshot(
                    slotId: 's1',
                    occupantKind: 'consumable',
                    occupantRefId: 'heal_potion',
                  ),
                ],
              ),
            ),
          );

      final dna = recorder.state.builds.single.dna;
      expect(dna.tokens, [
        'WESTERN',
        'PHY-A',
        'IRON_SWORD',
        'HEAL_POTION',
      ]);
      expect(dna.signature, isNotEmpty);
    });
```

- [ ] **Step 2: Run it — expect FAIL**

Run: `dart test test/plugins/almanac/almanac_build_snapshot_test.dart -n "includes consumable slots"`
Expected: FAIL — `dna.tokens` is `['WESTERN','PHY-A','IRON_SWORD']` (no `HEAL_POTION`), because `_withDna` passes `consumableIds: const <String>[]`.

- [ ] **Step 3: Feed consumable slots in `_withDna`**

In `lib/src/plugins/almanac/almanac_recorder.dart`, in the `_withDna` method's `buildDna(...)` call, replace the temporary `consumableIds: const <String>[],` (Task 1 Step 6) with:

```dart
        consumableIds: [
          for (final TomeSlotSnapshot s in record.tome.slots)
            if (s.occupantKind == 'consumable' && s.occupantRefId != null)
              s.occupantRefId!,
        ],
```

(`TomeSlotSnapshot` is already visible — `almanac_recorder.dart` imports `almanac_models.dart`. Confirm the import symbol name if analyze complains.)

- [ ] **Step 4: Run it — expect PASS**

Run: `dart test test/plugins/almanac/almanac_build_snapshot_test.dart`
Expected: PASS (the new test and the pre-existing `'an empty DNA is back-filled…'` test, whose expected token list is unchanged because it has no consumable slot).

- [ ] **Step 5: Run analyze + the Almanac suite**

Run: `dart analyze lib/src/plugins/almanac test/plugins/almanac`
Expected: no issues.
Run: `dart test test/plugins/almanac`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add lib/src/plugins/almanac/almanac_recorder.dart \
        test/plugins/almanac/almanac_build_snapshot_test.dart
git commit -m "fix(almanac): DNA back-fill reads consumable tome slots (SP4a)

_withDna now derives consumableIds from record.tome.slots where
occupantKind == 'consumable', so a back-filled DNA matches the bridge's.
No new record field — reads existing slot data.

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01E3k4BFeWXfPzkZzXinqTZk"
```

---

## Task 5: Adapter-parity fixture covers a consumable occupant

`almanac_adapter_parity_test.dart` proves the recorder contract holds against a synthetic, hand-built record path (the shape a future `TomeClientAlmanacAdapter` must match). Add a `consumable` occupant to one fixture build so parity is proven with the new kind present. The parity projection (`~line 758`) is already generic over `occupantKind` — only the fixture construction needs a branch.

**Files:**
- Modify: `test/plugins/almanac/almanac_adapter_parity_test.dart` (`_OccKind` enum; `_Occ` construction in whichever fixture list feeds `_buildRecordFor`; the occupant loop in `_buildRecordFor`, ~line 267-305)

**Interfaces:**
- Consumes: `occupantKind == 'consumable'` semantics from Task 3 (real refId, null instanceId, no per-copy entry).
- Produces: at least one `AlmanacBuildRecord` in the parity fixture with a `'consumable'` slot; parity assertions still pass.

- [ ] **Step 1: Read the fixture structure**

Run: `sed -n '1,120p' test/plugins/almanac/almanac_adapter_parity_test.dart` and locate `enum _OccKind`, the type `_Occ`, and the `_SnapshotBuild` list(s) whose `.occupants` feed `_buildRecordFor`. Identify one build step that currently has only item/technique occupants and has a spare slot id.

- [ ] **Step 2: Add the enum value**

In `enum _OccKind { … }` add `consumable`.

- [ ] **Step 3: Add a `consumable` branch in `_buildRecordFor`**

In `_buildRecordFor` (`~line 267`), the occupant loop is `if (o.kind == _OccKind.technique) { … } else { …item… }`. Change the tail to an explicit three-way:

```dart
    if (o.kind == _OccKind.technique) {
      // …unchanged…
    } else if (o.kind == _OccKind.consumable) {
      slots.add(
        TomeSlotSnapshot(
          slotId: o.slotId,
          occupantKind: 'consumable',
          occupantRefId: o.refKey,
        ),
      );
      // no techniques / itemSnaps entry — a consumable has no per-copy state
    } else {
      // …unchanged item branch…
    }
```

- [ ] **Step 4: Put a consumable occupant in one fixture build**

In the chosen `_SnapshotBuild`'s `occupants` list, add one `_Occ` of kind `_OccKind.consumable` with a fresh `slotId` and a `refKey` like `'heal_potion'`. If `_Occ`'s constructor requires a matching entry in a `tech` / `items` context map, a consumable needs neither — confirm the constructor tolerates a `refKey` with no context-map entry (it should, since the `consumable` branch never indexes `tech[...]` / `items[...]`). If the constructor asserts membership, relax it for the `consumable` kind.

- [ ] **Step 5: Run the parity test — expect PASS**

Run: `dart test test/plugins/almanac/almanac_adapter_parity_test.dart`
Expected: PASS — the synthetic path and the recorder still project the consumable slot identically (`'<slot>:consumable:heal_potion:<null-instance>'` on both sides), and DNA parity holds because both compute `consumableIds` from the same slots.

- [ ] **Step 6: Run analyze + the Almanac suite once more**

Run: `dart analyze test/plugins/almanac && dart test test/plugins/almanac`
Expected: no issues; PASS.

- [ ] **Step 7: Commit**

```bash
git add test/plugins/almanac/almanac_adapter_parity_test.dart
git commit -m "test(almanac): adapter parity covers a consumable occupant (SP4a)

_OccKind.consumable + a consumable slot in one fixture build; the
generic parity projection already handles the kind. Proves the recorder
contract holds with occupantKind 'consumable' present.

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01E3k4BFeWXfPzkZzXinqTZk"
```

---

## Task 6: Full-suite green + determinism sign-off

**Files:** none (verification only).

- [ ] **Step 1: Analyze the whole package**

Run: `dart analyze`
Expected: no issues.

- [ ] **Step 2: Run the full test suite**

Run: `dart test`
Expected: all PASS. Pay attention to `test/game/` — the seed-stable and replay-equivalence assertions there must be **unchanged** (this plan adds no gameplay, no RNG). If any `test/game/` determinism assertion fails, STOP — it is a real bug, not a fixture to update (spec §6, §8).

- [ ] **Step 3: Confirm no `output/` drift**

Run: `git status --porcelain output/`
Expected: empty — no regenerated artifacts (spec §8).

- [ ] **Step 4: Final review of the diff**

Run: `git diff main...HEAD --stat`
Expected files only: `almanac_build_dna.dart`, `almanac_bridge.dart`, `almanac_recorder.dart`, `almanac_models.dart`, the four test files, `CHANGELOG.md`, `ARCHITECTURE.md`. No production file outside `lib/src/plugins/almanac/` and `lib/src/plugins/game/almanac_bridge.dart`.

- [ ] **Step 5: Commit (if Steps 1–4 produced any touch-up), else push the branch**

```bash
git push -u origin sp4a-engine-almanac-consumable-dna
```

Then open the PR (title: `SP4a (engine): consumable Almanac build-DNA`), linking `docs/superpowers/specs/2026-09-08-sp4a-engine-bump-design.md`.

---

## Self-Review

**1. Spec coverage** (`2026-09-08-sp4a-engine-bump-design.md` §4–§8):

| Spec item | Task |
|-----------|------|
| §4.2 `buildDna` `consumableIds` channel, required, fixed position, backward-compatible signature | Task 1 |
| §4.2 both `buildDna` call sites updated (bridge + recorder) | Task 1 Step 6 (temporary) → Task 3 Step 5 (bridge real) / Task 4 Step 3 (recorder real) |
| §4.3 bridge `occupantKind: 'consumable'`, `instanceId: null`, no per-copy entry | Task 3 Steps 3–4 |
| §4.3 bridge feeds `consumableIds` from `placements` | Task 3 Steps 4–5 |
| §4.4 `_occupants` split; sites rewired; debt comment removed | Task 2 |
| §4.4 positive coverage: a `'consumable'` slot exists in the replay run; both `project()` passes equal | Task 3 Step 1 |
| §4.5 CHANGELOG entry | Task 1 Step 8 + Task 3 Step 8 |
| §4.5 ARCHITECTURE occupant-kind line | Task 3 Step 8 |
| §4.5 `TomeSlotSnapshot` docstring | Task 3 Step 8 |
| §6 `almanac_build_dna_test` cases (backward-compat, order-invariance, position, change-sensitivity) | Task 1 Step 1 |
| §6 `almanac_build_snapshot_test` consumable slot → DNA | Task 4 Step 1 |
| §6 `almanac_adapter_parity_test` consumable slot | Task 5 |
| §6 `almanac_run_history_test` split + positive assertion | Tasks 2, 3 |
| §6 determinism (`test/game/`) unchanged | Task 6 Step 2 |
| §6 Almanac→plugin dependency guard still passes | Task 6 Step 2 (part of `dart test`; no new Almanac-module→plugin edge is added — the bridge already imports plugins) |
| §7 files list | matches this plan's File Structure |
| §8 no gameplay / no RNG / no `output/` drift / zero-consumable byte-identical | Global Constraints + Task 6 Steps 2–3 |
| D5 — no typed `ConsumablePlacementSnapshot` | honoured: no `almanac_models.dart` structural change |

No gaps.

**2. Placeholder scan:** every code step has literal code. The two `consumableIds: const <String>[]` interim values in Task 1 Step 6 are explicit, compilable, and replaced by name in Tasks 3 and 4 — not "TODO"s.

**3. Type consistency:** `consumableIds` (param name) used identically in Tasks 1, 3, 4. `_placedOccupants` / `_discoverableOccupants` (Task 2) used with those exact names in Task 3. `_OccKind.consumable` (Task 5) matches the `enum _OccKind` reference. `occupantKind == 'consumable'` (string literal) identical across Tasks 2–5. `TomeSlotSnapshot` field names (`slotId`, `occupantKind`, `occupantRefId`, `instanceId`) match `almanac_models.dart` and every fixture.
