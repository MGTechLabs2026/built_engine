import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('BuildActionInterpreter and its implementations live under lib/src/plugins/ '
      '(plugin-level, not Core)', () {
    for (final path in [
      'lib/src/plugins/build_interpretation/build_action_interpreter.dart',
      'lib/src/plugins/build_interpretation/technique_action_interpreter.dart',
      'lib/src/plugins/build_interpretation/item_action_interpreter.dart',
      'lib/src/plugins/build_interpretation/self_effect_action.dart',
      'lib/src/plugins/build_interpretation/composite_build_action_interpreter.dart',
    ]) {
      expect(File(path).existsSync(), isTrue, reason: '$path should exist');
    }
  });

  // Concrete content ids/labels, not generic words — `combat_action.dart`
  // and others legitimately say prose like "no martial-arts vocabulary"
  // as a negation, which must NOT trip this check; only an actual
  // hardcoded content reference should. `'item:iron_sword'` is
  // deliberately excluded — it's a pre-existing, already-audited
  // doc-comment example in `MasteryDefinition`/`DiscoveryComponent`
  // predating this milestone (and the Item plugin itself), not a real
  // dependency.
  const forbiddenContentIds = [
    'basic_punch', 'basic_slash', 'basic_guard',
    "'knife'", "'gloves'",
  ];

  test('Core has no martial-arts/weapon knowledge: no file outside lib/src/plugins/ '
      'references any concrete technique/item content id', () {
    final coreFiles = Directory('lib/src')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart') && !f.path.contains('${Platform.pathSeparator}plugins${Platform.pathSeparator}'));

    for (final forbidden in forbiddenContentIds) {
      for (final file in coreFiles) {
        expect(
          file.readAsStringSync(),
          isNot(contains(forbidden)),
          reason: '${file.path} must not reference "$forbidden"',
        );
      }
    }
  });

  test('Combat itself is untouched: no concrete content id in lib/src/plugins/combat/', () {
    final combatFiles = Directory('lib/src/plugins/combat')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'));

    for (final forbidden in forbiddenContentIds) {
      for (final file in combatFiles) {
        expect(
          file.readAsStringSync(),
          isNot(contains(forbidden)),
          reason: '${file.path} must not reference "$forbidden"',
        );
      }
    }
  });
}
