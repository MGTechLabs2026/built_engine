import 'dart:io';

import 'package:test/test.dart';

/// Asserts no `.dart` file under [directoryPath] contains [forbidden]
/// anywhere in its text. Run from the package root (as `dart test`
/// always is in this repo), so these paths are relative to it.
void _assertNoSubstringInDirectory(String forbidden, String directoryPath) {
  final dir = Directory(directoryPath);
  final files = dir
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'));
  for (final file in files) {
    final content = file.readAsStringSync();
    expect(
      content,
      isNot(contains(forbidden)),
      reason: '${file.path} must not reference "$forbidden"',
    );
  }
}

/// Every plugin barrel filename — a Core service directory referencing
/// any of these by name (whether via a relative escape or the
/// `package:build_engine/<name>` form) would be exactly the coupling
/// this test exists to forbid, and neither import form contains the
/// bare `plugins/` substring the directory-scan checks below look for.
const _pluginBarrels = [
  'combat_plugin.dart',
  'martial_arts_plugin.dart',
  'example_elemental_plugin.dart',
];

void main() {
  group('G: neither content plugin imports the other', () {
    test('MartialArts does not reference ExampleElemental', () {
      _assertNoSubstringInDirectory(
          'example_elemental', 'lib/src/plugins/martial_arts');
    });

    test('ExampleElemental does not reference MartialArts', () {
      _assertNoSubstringInDirectory(
          'martial_arts', 'lib/src/plugins/example_elemental');
    });
  });

  group('Combat remains unaware of both content plugins', () {
    test('Combat does not reference MartialArts', () {
      _assertNoSubstringInDirectory(
          'martial_arts', 'lib/src/plugins/combat');
    });

    test('Combat does not reference ExampleElemental', () {
      _assertNoSubstringInDirectory(
          'example_elemental', 'lib/src/plugins/combat');
    });
  });

  group('H: Core does not import either content plugin', () {
    // Enumerated, not hardcoded, so a future new core-service directory
    // (e.g. a Scheduler or Serialization pass) is automatically covered
    // rather than silently unguarded. `plugins` itself is the one
    // subdirectory of `lib/src` that legitimately isn't a Core service.
    final coreDirectories = Directory('lib/src')
        .listSync()
        .whereType<Directory>()
        .where((d) => !d.path.endsWith('plugins'))
        .map((d) => d.path)
        .toList()
      ..sort();

    for (final directory in coreDirectories) {
      test('$directory does not reference plugins/', () {
        _assertNoSubstringInDirectory('plugins/', directory);
      });

      for (final barrel in _pluginBarrels) {
        test('$directory does not reference $barrel', () {
          _assertNoSubstringInDirectory(barrel, directory);
        });
      }
    }
  });
}
