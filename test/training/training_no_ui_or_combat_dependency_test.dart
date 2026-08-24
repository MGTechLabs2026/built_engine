import 'dart:io';

import 'package:test/test.dart';

void main() {
  final files = Directory('lib/src/training')
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'));

  for (final forbidden in ['flutter', 'dart:ui', 'combat_plugin.dart', 'plugins/combat']) {
    test('no file under lib/src/training references "$forbidden"', () {
      for (final file in files) {
        expect(
          file.readAsStringSync(),
          isNot(contains(forbidden)),
          reason: '${file.path} must not reference "$forbidden"',
        );
      }
    });
  }
}
