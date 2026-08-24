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

/// Every plugin barrel filename this test checks for — a real import
/// (the `package:build_engine/<name>` barrel form) always contains one
/// of these verbatim.
const _combatBarrel = 'combat_plugin.dart';
const _martialArtsBarrel = 'martial_arts_plugin.dart';
const _elementalBarrel = 'elemental_plugin.dart';
const _physiqueBarrel = 'physique_plugin.dart';
const _autoCombatBarrel = 'auto_combat_plugin.dart';
const _itemBarrel = 'item_plugin.dart';
const _pluginBarrels = [
  _combatBarrel,
  _martialArtsBarrel,
  _elementalBarrel,
  _physiqueBarrel,
  _autoCombatBarrel,
  _itemBarrel,
];

/// Asserts no `.dart` file under [directoryPath] imports the plugin
/// whose barrel filename is [barrel] and whose own source lives under
/// `lib/src/plugins/<pluginDirName>/`. Checks two forms: the barrel
/// import (`_assertNoSubstringInDirectory` against [barrel]) and a
/// relative escape into that plugin's directory (`'<pluginDirName>/'`).
/// Deliberately *not* the bare plugin name alone — a short, common word
/// like `elemental` can legitimately appear in prose (a doc comment
/// explaining an analogous mechanism in another plugin, by name, is not
/// a real dependency), so only import-shaped substrings are checked.
void _assertNoPluginImport(
  String pluginDirName,
  String barrel,
  String directoryPath,
) {
  _assertNoSubstringInDirectory(barrel, directoryPath);
  _assertNoSubstringInDirectory('$pluginDirName/', directoryPath);
}

void main() {
  group('G: neither content plugin imports the other', () {
    test('MartialArts does not reference Elemental', () {
      _assertNoPluginImport(
          'elemental', _elementalBarrel, 'lib/src/plugins/martial_arts');
    });

    test('Elemental does not reference MartialArts', () {
      _assertNoPluginImport('martial_arts', _martialArtsBarrel,
          'lib/src/plugins/elemental');
    });
  });

  group('MartialArts and Physique do not import each other', () {
    test('MartialArts does not reference Physique', () {
      _assertNoPluginImport(
          'physique', _physiqueBarrel, 'lib/src/plugins/martial_arts');
    });

    test('Physique does not reference MartialArts', () {
      _assertNoPluginImport('martial_arts', _martialArtsBarrel,
          'lib/src/plugins/physique');
    });

    test('Physique does not reference Combat', () {
      _assertNoPluginImport(
          'combat', _combatBarrel, 'lib/src/plugins/physique');
    });

    test('Physique does not reference Elemental', () {
      _assertNoPluginImport(
          'elemental', _elementalBarrel, 'lib/src/plugins/physique');
    });
  });

  group('Combat remains unaware of both content plugins', () {
    test('Combat does not reference MartialArts', () {
      _assertNoPluginImport(
          'martial_arts', _martialArtsBarrel, 'lib/src/plugins/combat');
    });

    test('Combat does not reference Elemental', () {
      _assertNoPluginImport(
          'elemental', _elementalBarrel, 'lib/src/plugins/combat');
    });

    test('Combat does not reference Physique', () {
      _assertNoPluginImport(
          'physique', _physiqueBarrel, 'lib/src/plugins/combat');
    });

    test('Combat does not reference AutoCombat', () {
      _assertNoPluginImport(
          'auto_combat', _autoCombatBarrel, 'lib/src/plugins/combat');
    });
  });

  group('Item plugin is fully decoupled from every other plugin', () {
    test('Item does not reference MartialArts', () {
      _assertNoPluginImport(
          'martial_arts', _martialArtsBarrel, 'lib/src/plugins/item');
    });

    test('Item does not reference Elemental', () {
      _assertNoPluginImport(
          'elemental', _elementalBarrel, 'lib/src/plugins/item');
    });

    test('Item does not reference Physique', () {
      _assertNoPluginImport(
          'physique', _physiqueBarrel, 'lib/src/plugins/item');
    });

    test('Item does not reference Combat', () {
      _assertNoPluginImport('combat', _combatBarrel, 'lib/src/plugins/item');
    });

    test('Item does not reference AutoCombat', () {
      _assertNoPluginImport(
          'auto_combat', _autoCombatBarrel, 'lib/src/plugins/item');
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
