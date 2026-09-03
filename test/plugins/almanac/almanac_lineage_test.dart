/// Phase 5.3 — `getRunsForLineage` + `lineageStatistics` across two lineages.
///
/// The state below has:
///   lin-west : 3 runs (2 won, 1 lost), physiques phy-a / phy-b, 3 builds,
///              discoveries — 2 distinct techniques, 1 item, 1 affix.
///   lin-east : 2 runs (1 won, 1 abandoned), physique phy-a only, 1 build,
///              discoveries — 1 technique (duplicate contentId rows), 0 items,
///              0 affixes.
/// A discovery row on an unknown run must be ignored by the per-lineage count.
library;

import 'package:build_engine/src/plugins/almanac/almanac_models.dart';
import 'package:build_engine/src/plugins/almanac/almanac_queries.dart';
import 'package:test/test.dart';

import 'support/almanac_fixtures.dart';

AlmanacState _state() => AlmanacState(
  runs: [
    runRecord(
      runId: 'w1',
      runNumber: 1,
      lineageId: 'lin-west',
      physiqueId: 'phy-a',
      outcome: RunOutcome.won,
    ),
    runRecord(
      runId: 'e1',
      runNumber: 2,
      lineageId: 'lin-east',
      physiqueId: 'phy-a',
      outcome: RunOutcome.won,
    ),
    runRecord(
      runId: 'w2',
      runNumber: 3,
      lineageId: 'lin-west',
      physiqueId: 'phy-b',
      outcome: RunOutcome.lost,
    ),
    runRecord(
      runId: 'e2',
      runNumber: 4,
      lineageId: 'lin-east',
      physiqueId: 'phy-a',
      outcome: RunOutcome.abandoned,
    ),
    runRecord(
      runId: 'w3',
      runNumber: 5,
      lineageId: 'lin-west',
      physiqueId: 'phy-a',
      outcome: RunOutcome.won,
    ),
  ],
  builds: [
    buildRecord(runId: 'w1', buildId: 'w1-b0', lineageId: 'lin-west'),
    buildRecord(runId: 'w2', buildId: 'w2-b0', lineageId: 'lin-west'),
    buildRecord(runId: 'w3', buildId: 'w3-b0', lineageId: 'lin-west'),
    buildRecord(runId: 'e1', buildId: 'e1-b0', lineageId: 'lin-east'),
  ],
  discoveries: [
    // lin-west (runs w1 / w2 / w3)
    discoveryRecord(
      discoveryId: 'wd1',
      type: AlmanacDiscoveryType.technique,
      contentId: 'fam-fist',
      runId: 'w1',
    ),
    discoveryRecord(
      discoveryId: 'wd2',
      type: AlmanacDiscoveryType.technique,
      contentId: 'fam-palm',
      runId: 'w2',
    ),
    discoveryRecord(
      discoveryId: 'wd3',
      type: AlmanacDiscoveryType.item,
      contentId: 'item-belt',
      runId: 'w3',
    ),
    discoveryRecord(
      discoveryId: 'wd4',
      type: AlmanacDiscoveryType.affix,
      contentId: 'af-sharp',
      runId: 'w3',
    ),
    // lin-east (runs e1 / e2) — same contentId discovered twice.
    discoveryRecord(
      discoveryId: 'ed1',
      type: AlmanacDiscoveryType.technique,
      contentId: 'fam-step',
      runId: 'e1',
    ),
    discoveryRecord(
      discoveryId: 'ed2',
      type: AlmanacDiscoveryType.technique,
      contentId: 'fam-step',
      runId: 'e2',
    ),
    // A row whose run is not in any lineage set here — must be ignored.
    discoveryRecord(
      discoveryId: 'orphan',
      type: AlmanacDiscoveryType.technique,
      contentId: 'fam-ghost',
      runId: 'run-unknown',
    ),
  ],
);

void main() {
  final queries = AlmanacQueries(_state());

  test('getRunsForLineage returns exactly the lineage runs, in order', () {
    expect(queries.getRunsForLineage('lin-west').map((r) => r.runId), [
      'w1',
      'w2',
      'w3',
    ]);
    expect(queries.getRunsForLineage('lin-east').map((r) => r.runId), [
      'e1',
      'e2',
    ]);
    expect(queries.getRunsForLineage('lin-none'), isEmpty);
    // Every returned run actually carries the queried lineageId.
    expect(
      queries
          .getRunsForLineage('lin-west')
          .every((r) => r.lineageId == 'lin-west'),
      isTrue,
    );
  });

  test('lineageStatistics for lin-west is fully record-derived', () {
    final stats = queries.lineageStatistics('lin-west');
    expect(stats.runs, 3);
    expect(stats.wins, 2);
    expect(stats.losses, 1);
    expect(stats.techniquesDiscovered, 2); // fam-fist, fam-palm
    expect(stats.itemsDiscovered, 1); // item-belt
    expect(stats.affixesDiscovered, 1); // af-sharp
    expect(stats.buildsUsed, 3);
    expect(stats.physiquesUsed, 2); // phy-a, phy-b
  });

  test('lineageStatistics for lin-east dedupes discovery contentIds', () {
    final stats = queries.lineageStatistics('lin-east');
    expect(stats.runs, 2);
    expect(stats.wins, 1);
    expect(stats.losses, 0); // abandoned is neither a win nor a loss
    expect(stats.techniquesDiscovered, 1); // fam-step twice -> one distinct
    expect(stats.itemsDiscovered, 0);
    expect(stats.affixesDiscovered, 0);
    expect(stats.buildsUsed, 1);
    expect(stats.physiquesUsed, 1); // phy-a only
  });

  test('an unknown lineage is all zeros', () {
    expect(
      queries.lineageStatistics('lin-missing'),
      const LineageStatistics(
        runs: 0,
        wins: 0,
        losses: 0,
        techniquesDiscovered: 0,
        itemsDiscovered: 0,
        affixesDiscovered: 0,
        buildsUsed: 0,
        physiquesUsed: 0,
      ),
    );
  });

  test('the orphan discovery row is never attributed to a lineage', () {
    final west = queries.lineageStatistics('lin-west');
    final east = queries.lineageStatistics('lin-east');
    // fam-ghost (runId run-unknown) contributes to neither.
    expect(west.techniquesDiscovered + east.techniquesDiscovered, 3);
  });

  test('getRunsForLineage is deterministic across calls', () {
    final q = AlmanacQueries(_state());
    expect(
      q.getRunsForLineage('lin-west').map((r) => r.runId).toList(),
      q.getRunsForLineage('lin-west').map((r) => r.runId).toList(),
    );
  });
}
