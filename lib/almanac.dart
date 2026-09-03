/// The Almanac's platform-neutral public surface — persistent cross-run
/// player history. Safe to import from any Dart target, web included:
/// nothing here requires `dart:io`. The file-backed repository
/// (`JsonFileAlmanacRepository`) is deliberately kept in the separate
/// `package:build_engine/almanac_file.dart` barrel so this one stays
/// web-safe — the same split `console_policy.dart` uses for
/// `ConsoleDecisionPolicy`.
library;

export 'src/plugins/almanac/almanac_models.dart';
export 'src/plugins/almanac/almanac_repository.dart';
export 'src/plugins/almanac/almanac_serialization.dart';
