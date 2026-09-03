/// Almanac v1 — the `dart:io` file-backed repository.
///
/// This is the ONLY file under `lib/src/plugins/almanac/` that imports
/// `dart:io`. It is exported solely by `package:build_engine/almanac_file.dart`
/// so the neutral `almanac.dart` barrel stays usable from web targets.
library;

import 'dart:io';

import 'almanac_models.dart';
import 'almanac_repository.dart';
import 'almanac_serialization.dart';

/// An [AlmanacRepository] backed by a single JSON [File].
///
/// `save` is crash-safe by construction (§8.5): it serializes the *complete*
/// state first — a serialization failure aborts before any file is touched —
/// then writes a sibling `<path>.tmp` and `renameSync`s it over the target (a
/// POSIX-atomic replace; best-effort on Windows). A crash therefore leaves
/// either the previous complete file or the new complete file, never a
/// half-written one, and no `.tmp` remains after success.
class JsonFileAlmanacRepository implements AlmanacRepository {
  JsonFileAlmanacRepository(this._file);

  final File _file;

  @override
  AlmanacState load() =>
      _file.existsSync()
          ? AlmanacSerialization.decode(_file.readAsStringSync())
          : AlmanacState.empty();

  @override
  void save(AlmanacState state) {
    // Serialize the COMPLETE state before touching the filesystem: a
    // serialization error aborts here, leaving any on-disk Almanac intact.
    final payload = AlmanacSerialization.encode(state);
    _file.parent.createSync(recursive: true);
    // Atomic replace: write a sibling temp file, then rename it over the
    // target. No `.tmp` survives a successful save.
    final tmp = File('${_file.path}.tmp');
    tmp.writeAsStringSync(payload, flush: true);
    tmp.renameSync(_file.path);
  }
}
