/// `ConsoleDecisionPolicy` — a stdin/stdout `RunDecisionPolicy` for
/// driving a run interactively from a terminal or a piped script.
///
/// Kept out of `package:build_engine/game.dart` on purpose: it is the
/// only part of the engine that imports `dart:io`, and `game.dart` must
/// stay usable from web targets. Import this barrel only from a
/// stdio-capable entrypoint (a CLI tool or a VM test).
library;

export 'src/plugins/game/console_decision_policy.dart';
