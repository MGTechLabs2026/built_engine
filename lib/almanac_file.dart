/// `JsonFileAlmanacRepository` — a `dart:io` file-backed `AlmanacRepository`.
/// Kept out of `package:build_engine/almanac.dart` on purpose: it is the
/// only Almanac file that imports `dart:io`, and the neutral barrel must
/// stay usable from web targets. Import this only from a file-capable
/// host (a CLI tool, a VM test, or a desktop client).
library;

export 'src/plugins/almanac/almanac_file_repository.dart';
