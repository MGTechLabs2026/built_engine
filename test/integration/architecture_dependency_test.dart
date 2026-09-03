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
const _techniqueBarrel = 'technique_plugin.dart';
const _buildInterpretationBarrel = 'build_interpretation.dart';
const _gameBarrel = 'game.dart';
const _almanacBarrel = 'almanac.dart';
const _almanacFileBarrel = 'almanac_file.dart';
const _pluginBarrels = [
  _combatBarrel,
  _martialArtsBarrel,
  _elementalBarrel,
  _physiqueBarrel,
  _autoCombatBarrel,
  _itemBarrel,
  _techniqueBarrel,
  _buildInterpretationBarrel,
  _gameBarrel,
  _almanacBarrel,
  _almanacFileBarrel,
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

  group('Technique plugin is fully decoupled from every other plugin', () {
    test('Technique does not reference MartialArts', () {
      _assertNoPluginImport(
          'martial_arts', _martialArtsBarrel, 'lib/src/plugins/technique');
    });

    test('Technique does not reference Elemental', () {
      _assertNoPluginImport(
          'elemental', _elementalBarrel, 'lib/src/plugins/technique');
    });

    test('Technique does not reference Physique', () {
      _assertNoPluginImport(
          'physique', _physiqueBarrel, 'lib/src/plugins/technique');
    });

    test('Technique does not reference Combat', () {
      _assertNoPluginImport('combat', _combatBarrel, 'lib/src/plugins/technique');
    });

    test('Technique does not reference AutoCombat', () {
      _assertNoPluginImport(
          'auto_combat', _autoCombatBarrel, 'lib/src/plugins/technique');
    });

    test('Technique does not reference Item', () {
      _assertNoPluginImport('item', _itemBarrel, 'lib/src/plugins/technique');
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

  group('audit A1 — the headless harness is top-of-graph, never depended on',
      () {
    // Nothing under lib/ except lib/src/plugins/game/ and lib/game.dart
    // itself may import the harness. It is a composition root — a plugin
    // or Core module pulling it back in would recreate the "two
    // divergent compositions" the A1 refactor removed.
    final nonGameDirs = [
      for (final d in Directory('lib/src').listSync().whereType<Directory>())
        if (!d.path.endsWith('game')) d.path,
      // lib/src itself minus plugins/game — but plugins/ has subdirs, so
      // check each non-game plugin dir explicitly too.
      for (final d in Directory('lib/src/plugins').listSync().whereType<Directory>())
        if (!d.path.endsWith('game')) d.path,
    ];
    for (final dir in nonGameDirs.toSet()) {
      test('$dir does not import game.dart or plugins/game/', () {
        _assertNoSubstringInDirectory("game.dart'", dir);
        _assertNoSubstringInDirectory('plugins/game/', dir);
      });
    }
  });

  group('audit A2 — style combat rules stay engine-pure', () {
    test('MartialArts (incl. style_combat.dart) references no Flutter/UI', () {
      _assertNoSubstringInDirectory('package:flutter/', 'lib/src/plugins/martial_arts');
      _assertNoSubstringInDirectory("import 'dart:ui'", 'lib/src/plugins/martial_arts');
    });
    test('style_combat.dart draws only on martial vocabulary — no RNG, no '
        'PluginContext', () {
      final src = File('lib/src/plugins/martial_arts/style_combat.dart')
          .readAsStringSync();
      expect(src, isNot(contains('RngService')));
      expect(src, isNot(contains('PluginContext')));
      expect(src, isNot(contains('context.rng')));
    });
  });

  group('audit A4 — TechniqueEvolved has one definition and one publisher', () {
    test('TechniqueEvolved is declared exactly once in lib/', () {
      var declarations = 0;
      for (final f in Directory('lib')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))) {
        declarations += RegExp(r'class TechniqueEvolved\b')
            .allMatches(f.readAsStringSync())
            .length;
      }
      expect(declarations, 1);
    });
    test('only resolveTechniqueEvolutionAfterTraining publishes it', () {
      final publishers = <String>[];
      for (final f in Directory('lib')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))) {
        final src = f.readAsStringSync();
        if (src.contains('publish(') &&
            RegExp(r'publish\(\s*TechniqueEvolved\(').hasMatch(src)) {
          publishers.add(f.path);
        }
      }
      expect(publishers, ['lib/src/plugins/technique/technique_evolution.dart']);
    });
  });

  group('Almanac: no gameplay plugin imports the Almanac', () {
    // The headless bridge in lib/src/plugins/game/ is the ONE sanctioned
    // dual-importer (gameplay plugin + Almanac); it is a composition root,
    // not a gameplay plugin, and audit A1 already fences it off. A gameplay
    // plugin reaching into cross-run player history would invert the
    // dependency arrow the Almanac design rests on.
    const gameplayPluginDirs = [
      'lib/src/plugins/technique',
      'lib/src/plugins/combat',
      'lib/src/plugins/martial_arts',
      'lib/src/plugins/item',
      'lib/src/plugins/physique',
      'lib/src/plugins/elemental',
      'lib/src/plugins/auto_combat',
    ];
    for (final dir in gameplayPluginDirs) {
      test('$dir does not reference the Almanac', () {
        _assertNoSubstringInDirectory(_almanacBarrel, dir); // 'almanac.dart'
        _assertNoSubstringInDirectory(_almanacFileBarrel, dir); // 'almanac_file.dart'
        _assertNoSubstringInDirectory('almanac/', dir); // escape into almanac/
      });
    }
  });
}
