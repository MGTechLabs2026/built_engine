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

  group('H: Core does not import either content plugin', () {
    const coreDirectories = [
      'lib/src/component',
      'lib/src/components',
      'lib/src/content',
      'lib/src/entity',
      'lib/src/event',
      'lib/src/modifier',
      'lib/src/plugin',
      'lib/src/query',
      'lib/src/rng',
      'lib/src/rule',
      'lib/src/spatial',
    ];

    for (final directory in coreDirectories) {
      test('$directory does not reference plugins/', () {
        _assertNoSubstringInDirectory('plugins/', directory);
      });
    }
  });
}
