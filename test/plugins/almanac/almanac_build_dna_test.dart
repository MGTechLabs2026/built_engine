import 'package:build_engine/src/plugins/almanac/almanac_build_dna.dart';
import 'package:build_engine/src/plugins/almanac/almanac_models.dart';
import 'package:test/test.dart';

/// Independent FNV-1a 32-bit reference implementation, deliberately written
/// separately from the one under test. Trusted only because it reproduces the
/// published FNV-1a-32 test vectors (see the first test group). Two independent
/// implementations agreeing on the signature is the real cross-check.
int _fnv1a32(String s) {
  int hash = 0x811c9dc5;
  for (final int c in s.codeUnits) {
    hash ^= c;
    // Split-16-bit multiply by the FNV prime (0x0100 << 16 | 0x0193): keeps
    // every intermediate < 2^43 so the hash is exact on dart2js/wasm too.
    final int lo = (hash & 0xFFFF) * 0x0193;
    final int mid = ((hash >> 16) & 0xFFFF) * 0x0193 + (hash & 0xFFFF) * 0x0100;
    hash = ((mid << 16) + lo) & 0xFFFFFFFF;
  }
  return hash;
}

String _hex8(int v) => v.toRadixString(16).padLeft(8, '0');

void main() {
  group('_fnv1a32 reference impl', () {
    test('reproduces published FNV-1a-32 vectors', () {
      expect(_fnv1a32(''), 0x811c9dc5);
      expect(_fnv1a32('a'), 0xe40c292c);
      expect(_fnv1a32('foobar'), 0xbf9cf968);
    });
  });

  group('buildDna', () {
    BuildDna sample() => buildDna(
      lineageId: 'iron-lineage',
      physiqueId: 'jade-body',
      techniqueFamilies: <String>['strike', 'palm', 'strike'],
      itemIds: <String>['boots', 'ring'],
      affixCategories: <String>['offense', 'defense'],
      axisProfiles: <Map<String, num>>[
        <String, num>{'power': 4, 'speed': -2},
        <String, num>{'power': 1, 'guard': 3},
      ],
    );

    test('determinism: same inputs twice yield an identical BuildDna', () {
      expect(sample(), sample());
      expect(sample().tokens, sample().tokens);
      expect(sample().signature, sample().signature);
    });

    test(
      'reorder-invariance: shuffled iterables, a shuffled multi-key axis map, '
      'and a shuffled axis-map list give the same tokens and signature',
      () {
        final BuildDna a = buildDna(
          lineageId: 'lin',
          physiqueId: 'phy',
          techniqueFamilies: <String>['a', 'b', 'c'],
          itemIds: <String>['x', 'y', 'z'],
          affixCategories: <String>['p', 'q'],
          axisProfiles: <Map<String, num>>[
            // Multi-key literal, keys in deliberately non-sorted order.
            <String, num>{'zeta': 3, 'alpha': 1},
            <String, num>{'m': 2},
            <String, num>{'n': -3},
            <String, num>{'o': 1},
          ],
        );
        final BuildDna b = buildDna(
          lineageId: 'lin',
          physiqueId: 'phy',
          techniqueFamilies: <String>['c', 'a', 'b', 'a'],
          itemIds: <String>['z', 'x', 'y'],
          affixCategories: <String>['q', 'p'],
          axisProfiles: <Map<String, num>>[
            <String, num>{'o': 1},
            <String, num>{'n': -3},
            <String, num>{'m': 2},
            // Same map, keys in the opposite (sorted) order; list reordered too.
            <String, num>{'alpha': 1, 'zeta': 3},
          ],
        );
        expect(b.tokens, a.tokens);
        expect(b.signature, a.signature);
      },
    );

    test('change-sensitivity: adding an item id changes the signature', () {
      final BuildDna base = sample();
      final BuildDna changed = buildDna(
        lineageId: 'iron-lineage',
        physiqueId: 'jade-body',
        techniqueFamilies: <String>['strike', 'palm', 'strike'],
        itemIds: <String>['boots', 'ring', 'amulet'],
        affixCategories: <String>['offense', 'defense'],
        axisProfiles: <Map<String, num>>[
          <String, num>{'power': 4, 'speed': -2},
          <String, num>{'power': 1, 'guard': 3},
        ],
      );
      expect(changed.signature, isNot(base.signature));
    });

    test('change-sensitivity: bumping an axis to reorder the top-3 changes the '
        'signature', () {
      final BuildDna before = buildDna(
        lineageId: 'l',
        physiqueId: 'p',
        techniqueFamilies: const <String>[],
        itemIds: const <String>[],
        affixCategories: const <String>[],
        axisProfiles: <Map<String, num>>[
          <String, num>{'a': 10, 'b': 8, 'c': 5, 'd': 5},
        ],
      );
      final BuildDna after = buildDna(
        lineageId: 'l',
        physiqueId: 'p',
        techniqueFamilies: const <String>[],
        itemIds: const <String>[],
        affixCategories: const <String>[],
        axisProfiles: <Map<String, num>>[
          <String, num>{'a': 10, 'b': 8, 'c': 5, 'd': 6},
        ],
      );
      expect(after.signature, isNot(before.signature));
    });

    test('the signature is a content digest, never a build identity', () {
      final BuildDna dna = sample();
      // `buildId` is an opaque, caller-assigned token; the signature is a
      // derived 8-hex FNV digest of the token list. They are different kinds
      // of value and must not be conflated.
      for (final String buildId in const <String>[
        'run-1:finalBuild:0',
        'action-8f3a91',
        'iron-lineage',
      ]) {
        expect(dna.signature, isNot(equals(buildId)));
      }
      // The signature depends only on the DNA inputs — not on any identity —
      // so two builds differing solely in their buildId share it.
      expect(sample().signature, equals(dna.signature));
    });

    test('signature is lowercase hex of length 8', () {
      final String sig = sample().signature;
      expect(sig, hasLength(8));
      expect(sig, matches(RegExp(r'^[0-9a-f]{8}$')));
    });

    test('FNV cross-check against the independent reference on a fully '
        'predictable token list', () {
      final BuildDna dna = buildDna(
        lineageId: 'lin',
        physiqueId: 'phy',
        techniqueFamilies: <String>['b', 'a', 'a'],
        itemIds: <String>['z'],
        affixCategories: const <String>[],
        axisProfiles: <Map<String, num>>[
          <String, num>{'x': 2},
          <String, num>{'y': -5},
          <String, num>{'w': 1},
        ],
      );
      // Summed |value|: y=5, x=2, w=1 -> top-3 [y, x, w] -> re-sorted name ASC
      // [w, x, y].
      final List<String> expectedTokens = <String>[
        'LIN',
        'PHY',
        'A',
        'B',
        'Z',
        'W',
        'X',
        'Y',
      ];
      expect(dna.tokens, expectedTokens);
      expect(dna.signature, _hex8(_fnv1a32(expectedTokens.join('|'))));
    });

    test(
      'top-3 axis selection uses name-ASC tie-break at the rank-3 boundary',
      () {
        final BuildDna dna = buildDna(
          lineageId: 'l',
          physiqueId: 'p',
          techniqueFamilies: const <String>[],
          itemIds: const <String>[],
          affixCategories: <String>['zeta'],
          axisProfiles: <Map<String, num>>[
            <String, num>{'alpha': 10, 'bravo': 8, 'charlie': 5, 'delta': 5},
          ],
        );
        // alpha(10) > bravo(8) > charlie(5) == delta(5); charlie takes the last
        // slot by name ASC, delta is dropped.
        expect(dna.tokens, <String>[
          'L',
          'P',
          'ZETA',
          'ALPHA',
          'BRAVO',
          'CHARLIE',
        ]);
        final int affixIdx = dna.tokens.indexOf('ZETA');
        final List<String> axisTokens = dna.tokens.sublist(affixIdx + 1);
        expect(axisTokens, <String>['ALPHA', 'BRAVO', 'CHARLIE']);
        expect(axisTokens.every((String t) => t == t.toUpperCase()), isTrue);
        expect(dna.tokens, isNot(contains('DELTA')));
      },
    );
  });
}
