import 'dart:io';

import 'package:test/test.dart';

/// The neutral public surface and its backing module. Paths are relative to
/// the package root (the working directory under `dart test` in this repo).
const _almanacBarrel = 'lib/almanac.dart';
const _almanacDir = 'lib/src/plugins/almanac';
const _fileRepo = 'lib/src/plugins/almanac/almanac_file_repository.dart';

/// Drops full-line `//` / `///` comments so the directive scans below match
/// real `import` / `export` statements only. The committed headers of
/// `lib/almanac.dart`, `almanac_models.dart`, `almanac_repository.dart` and
/// `almanac_queries.dart` all mention `dart:io` and `almanac_file` in prose —
/// documentation of the split, not directives — and a bare `contains()` would
/// wrongly flag them. Block `/* */` comments do not occur in these files.
String _codeOnly(String source) => source
    .split('\n')
    .where((line) => !line.trimLeft().startsWith('//'))
    .join('\n');

/// Matches an `import 'dart:io'` / `import "dart:io"` directive at line start.
final _importDartIo = RegExp(
  r'''^\s*import\s+['"]dart:io['"]''',
  multiLine: true,
);

/// Matches an `export '<...>almanac_file<...>'` directive at line start.
final _exportAlmanacFile = RegExp(
  r'''^\s*export\s+['"][^'"]*almanac_file''',
  multiLine: true,
);

/// Enumerates a file's own `import` / `export` targets (group 2 = the URI).
final _anyDirective = RegExp(
  r'''^\s*(import|export)\s+['"]([^'"]+)['"]''',
  multiLine: true,
);

/// Resolves a relative directive [target] against the directory of [fromFile].
/// The Almanac barrel + module use only bare sibling / sub-path imports (no
/// `..`), so a plain join is exact.
String _resolve(String fromFile, String target) =>
    '${File(fromFile).parent.path}/$target';

/// The transitive set of in-repo `.dart` files reachable from [entry] via
/// `import` / `export` directives, restricted to the Almanac module (the
/// barrel's own path is dropped). `dart:` and `package:` targets are ignored.
Set<String> _reachableAlmanacFiles(String entry) {
  final seen = <String>{};
  final queue = <String>[entry];
  while (queue.isNotEmpty) {
    final path = queue.removeLast();
    if (!seen.add(path)) continue;
    final file = File(path);
    if (!file.existsSync()) continue;
    final code = _codeOnly(file.readAsStringSync());
    for (final match in _anyDirective.allMatches(code)) {
      final target = match.group(2)!;
      if (target.startsWith('dart:') || target.startsWith('package:')) continue;
      queue.add(_resolve(path, target));
    }
  }
  seen.remove(entry);
  return seen.where((p) => p.contains('/almanac/')).toSet();
}

/// Every `.dart` file physically under [_almanacDir].
List<File> _almanacDartFiles() =>
    Directory(_almanacDir)
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .toList();

void main() {
  group('almanac platform-neutral surface', () {
    test(
      'lib/almanac.dart declares no dart:io import and no almanac_file export',
      () {
        final code = _codeOnly(File(_almanacBarrel).readAsStringSync());
        expect(
          _importDartIo.hasMatch(code),
          isFalse,
          reason: 'the neutral barrel must not import dart:io',
        );
        expect(
          _exportAlmanacFile.hasMatch(code),
          isFalse,
          reason: 'the neutral barrel must not re-export the dart:io file repo',
        );
      },
    );

    test('nothing reachable from lib/almanac.dart imports dart:io', () {
      final reachable = _reachableAlmanacFiles(_almanacBarrel);
      expect(
        reachable,
        isNotEmpty,
        reason: 'the reachability walk resolved no Almanac files — broken scan',
      );
      for (final path in reachable) {
        // The file repo is the sanctioned dart:io island and is NOT on the
        // neutral surface (barrel does not export it) — exclude it here.
        if (path.endsWith('almanac_file_repository.dart')) continue;
        final code = _codeOnly(File(path).readAsStringSync());
        expect(
          _importDartIo.hasMatch(code),
          isFalse,
          reason: '$path is on the neutral surface and must not import dart:io',
        );
      }
    });

    test(
      'almanac_file_repository.dart is the sole dart:io island in the module',
      () {
        final withDartIo = <String>[
          for (final file in _almanacDartFiles())
            if (_importDartIo.hasMatch(_codeOnly(file.readAsStringSync())))
              file.path,
        ]..sort();
        expect(withDartIo, [_fileRepo]);
      },
    );
  });
}
