import 'dart:io';

import 'package:test/test.dart';

/// The Almanac composition module. Paths are relative to the package root,
/// which is always the working directory under `dart test` in this repo.
const _almanacDir = 'lib/src/plugins/almanac';
const _almanacBarrel = 'lib/almanac.dart';
const _almanacBridge = 'lib/src/plugins/game/almanac_bridge.dart';

/// Every `.dart` file under [_almanacDir], sorted for deterministic output.
/// Guarded non-empty so the loop-based tests below can never pass vacuously
/// if the directory path breaks or the module is emptied.
List<File> _almanacDartFiles() {
  final files =
      Directory(_almanacDir)
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));
  expect(
    files,
    isNotEmpty,
    reason: 'no almanac .dart files found under $_almanacDir — broken path',
  );
  return files;
}

/// Drops every full-line `//` / `///` comment so a substring / directive scan
/// sees code only. The committed Almanac doc comments legitimately mention
/// phrases like `plugins/almanac/`, `` `GamePlugin` `` and "no randomness" in
/// prose; those are documentation, not dependencies, and must not trip a guard.
/// (Block `/* */` comments do not occur in these files, and the directives are
/// kept comment-free, so a line filter is sufficient.)
String _codeOnly(String source) => source
    .split('\n')
    .where((line) => !line.trimLeft().startsWith('//'))
    .join('\n');

void main() {
  group('almanac architecture', () {
    // §13.1 — Almanac imports Core only. No gameplay-plugin barrel filename,
    // no `plugins/` relative-path segment, no escape into the headless bridge.
    // It MAY reference `package:build_engine/build_engine.dart`, `dart:convert`,
    // and — in `almanac_file_repository.dart` only — `dart:io`.
    test(
      'every file imports Core only (no gameplay plugin, no plugins/ path)',
      () {
        const forbidden = [
          'combat_plugin.dart',
          'martial_arts_plugin.dart',
          'elemental_plugin.dart',
          'physique_plugin.dart',
          'auto_combat_plugin.dart',
          'item_plugin.dart',
          'technique_plugin.dart',
          'build_interpretation.dart',
          'game.dart',
          'plugins/',
          'src/plugins/game/',
        ];
        for (final file in _almanacDartFiles()) {
          final code = _codeOnly(file.readAsStringSync());
          for (final needle in forbidden) {
            expect(
              code,
              isNot(contains(needle)),
              reason: '${file.path} references "$needle"',
            );
          }
        }
      },
    );

    // §13.2 — the neutral barrel must not re-export the `dart:io` file repo.
    // Directive-shaped: the barrel's header names `almanac_file.dart` in prose.
    test('lib/almanac.dart does not export almanac_file*', () {
      final code = _codeOnly(File(_almanacBarrel).readAsStringSync());
      expect(
        RegExp(
          r'''^\s*export\s+['"][^'"]*almanac_file''',
          multiLine: true,
        ).hasMatch(code),
        isFalse,
        reason: 'the neutral barrel must not re-export the dart:io file repo',
      );
    });

    // §13.3 — recorder + queries (and, for robustness, every Almanac file) draw
    // on no randomness. The Almanac is a pure projection of recorded history.
    test('recorder, queries and every almanac file are RNG-free', () {
      const rngNeedles = [
        'RngService',
        'context.rng',
        'Random(',
        'math.Random',
      ];
      for (final file in _almanacDartFiles()) {
        final code = _codeOnly(file.readAsStringSync());
        for (final needle in rngNeedles) {
          expect(
            code,
            isNot(contains(needle)),
            reason: '${file.path} references "$needle"',
          );
        }
      }
    });

    // §13.4 — no id parsing. Almanac ids are opaque: relationships are stored
    // as explicit fields, never recovered by slicing a string. This is a SOURCE
    // scan, additional to the behavioural `almanac_id_opacity_test.dart`.
    test('no id string-parsing anywhere under the almanac dir', () {
      const idParseNeedles = [
        '.split(',
        '.startsWith(',
        '.substring(',
        'RegExp(',
      ];
      for (final file in _almanacDartFiles()) {
        final code = _codeOnly(file.readAsStringSync());
        for (final needle in idParseNeedles) {
          expect(
            code,
            isNot(contains(needle)),
            reason: '${file.path} uses "$needle" — Almanac ids are opaque',
          );
        }
      }
    });

    // §13.5 — no UI / platform dependency. Only `almanac_file_repository.dart`
    // touches a platform library at all, and that one is `dart:io`.
    test('no Flutter / Flame / Devvit / dart:ui / dart:html dependency', () {
      const platformNeedles = [
        'package:flutter/',
        "import 'dart:ui'",
        "import 'dart:html'",
        'devvit',
        'flame',
      ];
      for (final file in _almanacDartFiles()) {
        final code = _codeOnly(file.readAsStringSync());
        for (final needle in platformNeedles) {
          expect(
            code,
            isNot(contains(needle)),
            reason: '${file.path} references "$needle"',
          );
        }
      }
    });

    // §13.1 (last table row) — `almanac_bridge.dart` keeps every subscription
    // on the instance: no `static` field of a subscription type, and no
    // library-scope `subscribe(` / `EventSubscription` (every subscription is
    // created inside a method body and stored on `this`, so `detach()` can
    // cancel all of them and there is no module-level listener).
    test('almanac_bridge.dart has no static or library-scope subscription', () {
      final code = _codeOnly(File(_almanacBridge).readAsStringSync());

      // No `static` declaration whose type is a subscription.
      expect(
        RegExp(
          r'^\s*static\b[^\n]*\b(Event|Stream)Subscription\b',
          multiLine: true,
        ).hasMatch(code),
        isFalse,
        reason: 'a subscription must never be static on the bridge',
      );

      // Every `subscribe(` call and every `EventSubscription` mention sits
      // inside a class/method body — i.e. is indented. A column-0 occurrence
      // would be a library-scope (module-level) listener.
      final libraryScope = RegExp(
        r'''^[^\s/][^\n]*(subscribe\(|EventSubscription)''',
        multiLine: true,
      );
      expect(
        libraryScope.hasMatch(code),
        isFalse,
        reason: 'almanac_bridge.dart has a library-scope subscription',
      );
    });

    // §13.6 — the Almanac is a plain composition module, never a `GamePlugin`.
    test('no file declares a GamePlugin', () {
      final gamePluginDecl = RegExp(r'(implements|extends|with)\s+GamePlugin');
      for (final file in _almanacDartFiles()) {
        final code = _codeOnly(file.readAsStringSync());
        expect(
          gamePluginDecl.hasMatch(code),
          isFalse,
          reason: '${file.path} declares a GamePlugin',
        );
      }
    });
  });
}
