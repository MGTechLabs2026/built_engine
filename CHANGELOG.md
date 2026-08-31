# Changelog

`build_engine` is consumed as a pinned git dependency, so this file
tracks **public-surface changes** a consumer must know about when
bumping the pin. Newest first.

## Unreleased

### Added — public API (audit A1/A2/A4 refactor)

- **`resolveTechniqueEvolutionAfterTraining(owner, technique, profile, context)`**
  on `package:build_engine/technique_plugin.dart` — the one authoritative
  post-training evolution step. It no-ops unless the technique is learned
  and has candidates, runs the pure `evolveTechnique` resolver (one
  `context.rng` draw when eligible), and **publishes `TechniqueEvolved`
  exactly once** on success. It is now the *sole* publisher of that
  event: `TrainingStage` and any embedding client must call this instead
  of open-coding the resolver + publish. `evolveTechnique` stays public
  for callers wanting the raw draw without the gate or the event.
- **`StyleCombatRules(fighterTags)` + `BurstChainState`** on
  `package:build_engine/martial_arts_plugin.dart` — the engine-owned
  style-scoped combat rules (off-specialty damage penalty, Shaolin
  Conditioning, Kunlun Burst Chain), previously implemented only in the
  client. Pure, deterministic, no RNG/PluginContext/Flutter. Keys off
  `spec:*` tags + `styleAlignedFamilies`, never a style-id switch.
- **`package:build_engine/game.dart` is documented as a headless
  reference / balance-simulation harness**, not the authoritative run.
  No API change — the docstrings now state that a consuming client owns
  run composition/sequencing/presentation and the engine owns the domain
  rules both consume.

### Changed — public barrels

- **`TechniqueEvolved` moved to the Technique plugin.** It was defined in
  the internal `src/plugins/game/run_events.dart` and reachable only via
  an `implementation_imports` path or the `dart:io`-tainted `game.dart`.
  It now lives in `src/plugins/technique/technique_events.dart` and is
  exported by `package:build_engine/technique_plugin.dart`. Same class,
  same `fromId` / `toId`. **Migration:** import it from
  `technique_plugin.dart`.
- **`ConsoleDecisionPolicy` removed from `package:build_engine/game.dart`.**
  It is the only `dart:io` import in `lib/`, so `game.dart` is now
  web-safe. **Migration:** stdio entrypoints import
  `package:build_engine/console_policy.dart`.

### Changed — behaviour-neutral

- Every technique — base **and** evolved — now gets a MASTERY rank axis
  at `TechniquePlugin.initialize` (previously only the three base forms).
  The LEARNING axis stays base-only. Thresholds are unchanged and now
  named in `technique_vocabulary.dart` (`techniqueMasteryThresholds`,
  `techniqueLearningThresholds`) as the single source of truth.
