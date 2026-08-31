# Changelog

`build_engine` is consumed as a pinned git dependency, so this file
tracks **public-surface changes** a consumer must know about when
bumping the pin. Newest first.

## Unreleased

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
