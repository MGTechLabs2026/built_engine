// Locks the public boundary for technique-domain events: they are
// reachable from `package:build_engine/technique_plugin.dart` (never an
// `src/plugins/game/...` internal path), and `TechniqueEvolved` is
// published exactly once per successful evolution and never otherwise.
import 'package:build_engine/build_engine.dart' show EventBus;
import 'package:build_engine/game.dart' show runGame;
import 'package:build_engine/technique_plugin.dart';
import 'package:test/test.dart';

import '../../support/policies.dart';

void main() {
  group('public API', () {
    test('TechniqueEvolved is exported by technique_plugin.dart with '
        'fromId / toId', () {
      const e = TechniqueEvolved(fromId: 'basic_punch', toId: 'light_punch');
      expect(e.fromId, 'basic_punch');
      expect(e.toId, 'light_punch');
      // Immutable value type — identical construction compares by ref
      // only (no ==), but the fields never change.
      expect(e, isA<TechniqueEvolved>());
    });

    test('TechniqueAddedToTome is also on the public technique surface', () {
      expect(TechniqueAddedToTome, isNotNull);
    });
  });

  group('publishing semantics (via runGame)', () {
    test('one TechniqueEvolved per successful evolution, and none without — '
        'fromId/toId always name a real pair', () {
      var anyEvolved = false;
      var anyNotEvolved = false;

      for (var seed = 1; seed <= 20; seed++) {
        final captured = <TechniqueEvolved>[];
        final events = EventBus()..subscribe<TechniqueEvolved>(captured.add);

        final result = runGame(
          seed,
          policy: TrainAfterFirstCombatPolicy(),
          eventBus: events,
        );

        // Published exactly when evolution occurred — not twice, not for
        // plain learning, not for discovery: the count tracks the run's
        // own evolution tally.
        expect(
          captured.length,
          result.techniquesEvolved.length,
          reason: 'seed $seed: one event per evolution',
        );

        for (final e in captured) {
          expect(e.fromId, isNotEmpty);
          expect(e.toId, isNotEmpty);
          expect(e.fromId, isNot(equals(e.toId)));
          expect(result.techniquesEvolved, contains(e.toId));
        }

        if (captured.isEmpty) {
          anyNotEvolved = true;
        } else {
          anyEvolved = true;
        }
      }

      expect(anyEvolved, isTrue,
          reason: 'some sampled run evolves a technique and fires the event');
      expect(anyNotEvolved, isTrue,
          reason: 'some sampled run evolves nothing and fires no event');
    });
  });
}
