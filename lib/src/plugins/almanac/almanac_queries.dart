/// Almanac v1 — the read-only query API (Phase 5).
///
/// [AlmanacQueries] is a pure view over a single [AlmanacState]: construct it
/// with a state, ask questions, get copies back. It never mutates the state,
/// holds no other collaborators, and imports the domain model only — no
/// recorder, no repository, no `dart:io` / `dart:convert`, no RNG.
///
/// Every relationship is resolved by explicit-field equality on opaque id
/// strings; nothing here ever splits, slices, or prefix-matches an id. Every
/// `List` result is a fresh `List.unmodifiable`; every aggregate is a small
/// immutable value object. Given one state, two identical calls return an
/// equal list in an identical order — source-list insertion order, or an
/// explicit `(count desc, id asc)` comparator where results are re-sorted.
library;

import 'almanac_models.dart';

/// A read-only view over one [AlmanacState]. Stateless apart from the state it
/// wraps; safe to construct per call.
class AlmanacQueries {
  AlmanacQueries(this._state);

  final AlmanacState _state;

  // ---------------------------------------------------------------------------
  // Runs
  // ---------------------------------------------------------------------------

  /// Every run, in insertion order.
  List<AlmanacRunRecord> getRunHistory() =>
      List<AlmanacRunRecord>.unmodifiable(_state.runs);

  /// The run with [runId], or `null` if none.
  AlmanacRunRecord? getRun(String runId) =>
      _firstWhereOrNull(_state.runs, (r) => r.runId == runId);

  /// Runs whose `lineageId` equals [lineageId], in insertion order.
  List<AlmanacRunRecord> getLineageHistory(String lineageId) =>
      _runsForLineage(lineageId);

  /// Alias of [getLineageHistory] — runs whose `lineageId` equals [lineageId].
  List<AlmanacRunRecord> getRunsForLineage(String lineageId) =>
      _runsForLineage(lineageId);

  /// Runs whose `physiqueId` equals [physiqueId], in insertion order.
  List<AlmanacRunRecord> getRunsForPhysique(String physiqueId) =>
      List<AlmanacRunRecord>.unmodifiable([
        for (final run in _state.runs)
          if (run.physiqueId == physiqueId) run,
      ]);

  // ---------------------------------------------------------------------------
  // Builds
  // ---------------------------------------------------------------------------

  /// Every build snapshot, in insertion order.
  List<AlmanacBuildRecord> getBuildHistory() =>
      List<AlmanacBuildRecord>.unmodifiable(_state.builds);

  /// The build matching BOTH `runId == runId` AND `buildId == buildId` — the
  /// composite key, never a `buildId`-only scan. `null` if none matches.
  AlmanacBuildRecord? getBuild(String runId, String buildId) =>
      _firstWhereOrNull(
        _state.builds,
        (b) => b.runId == runId && b.buildId == buildId,
      );

  /// Builds whose `runId` equals [runId], in insertion order.
  List<AlmanacBuildRecord> getBuildsForRun(String runId) =>
      List<AlmanacBuildRecord>.unmodifiable([
        for (final build in _state.builds)
          if (build.runId == runId) build,
      ]);

  // ---------------------------------------------------------------------------
  // Techniques
  // ---------------------------------------------------------------------------

  /// The cross-run history of the technique instance [instanceId], or `null`.
  AlmanacTechniqueRecord? getTechniqueHistory(String instanceId) =>
      _firstWhereOrNull(_state.techniques, (t) => t.instanceId == instanceId);

  /// Every stored inspiration ancestry whose `resultInstanceId` equals
  /// [instanceId] — the "what inspired this instance" view — in insertion
  /// order.
  List<TechniqueInspirationHistory> getTechniqueInspirations(
    String instanceId,
  ) => List<TechniqueInspirationHistory>.unmodifiable([
    for (final history in _state.inspirations)
      if (history.resultInstanceId == instanceId) history,
  ]);

  /// Runs whose `runId` appears among the technique instance's
  /// `usageObservations` (matched on `observation.runId == run.runId`), in
  /// run insertion order. Empty when the technique is unknown.
  List<AlmanacRunRecord> getRunsUsingTechnique(String instanceId) {
    final technique = getTechniqueHistory(instanceId);
    final usedRunIds = <String>{
      if (technique != null)
        for (final observation in technique.usageObservations)
          observation.runId,
    };
    return List<AlmanacRunRecord>.unmodifiable([
      for (final run in _state.runs)
        if (usedRunIds.contains(run.runId)) run,
    ]);
  }

  /// Builds whose `techniques` list contains a snapshot with `instanceId ==
  /// instanceId`, in build insertion order.
  List<AlmanacBuildRecord> getBuildsUsingTechnique(String instanceId) =>
      List<AlmanacBuildRecord>.unmodifiable([
        for (final build in _state.builds)
          if (build.techniques.any((t) => t.instanceId == instanceId)) build,
      ]);

  // ---------------------------------------------------------------------------
  // Affixes
  // ---------------------------------------------------------------------------

  /// The cross-run history of the affix [affixId], or `null`.
  AlmanacAffixRecord? getAffixHistory(String affixId) =>
      _firstWhereOrNull(_state.affixes, (a) => a.affixId == affixId);

  // ---------------------------------------------------------------------------
  // Discoveries
  // ---------------------------------------------------------------------------

  /// Every discovery, in insertion order.
  List<AlmanacDiscoveryRecord> getDiscoveries() =>
      List<AlmanacDiscoveryRecord>.unmodifiable(_state.discoveries);

  /// The last [limit] discoveries by insertion order (all of them when there
  /// are fewer than [limit]; empty when [limit] <= 0).
  List<AlmanacDiscoveryRecord> getRecentDiscoveries({int limit = 20}) {
    final all = _state.discoveries;
    final take = limit < 0 ? 0 : limit;
    final start = all.length > take ? all.length - take : 0;
    return List<AlmanacDiscoveryRecord>.unmodifiable(all.sublist(start));
  }

  // ---------------------------------------------------------------------------
  // Aggregates
  // ---------------------------------------------------------------------------

  /// Record-derived roll-up for one lineage. No stored counters are read; each
  /// field is recomputed from the run / build / discovery lists.
  LineageStatistics lineageStatistics(String lineageId) {
    final runs = _runsForLineage(lineageId);
    final runIds = <String>{for (final run in runs) run.runId};
    var wins = 0;
    var losses = 0;
    for (final run in runs) {
      if (run.outcome == RunOutcome.won) wins++;
      if (run.outcome == RunOutcome.lost) losses++;
    }
    var buildsUsed = 0;
    for (final build in _state.builds) {
      if (build.lineageId == lineageId) buildsUsed++;
    }
    return LineageStatistics(
      runs: runs.length,
      wins: wins,
      losses: losses,
      techniquesDiscovered: _distinctDiscoveryContent(
        AlmanacDiscoveryType.technique,
        runIds,
      ),
      itemsDiscovered: _distinctDiscoveryContent(
        AlmanacDiscoveryType.item,
        runIds,
      ),
      affixesDiscovered: _distinctDiscoveryContent(
        AlmanacDiscoveryType.affix,
        runIds,
      ),
      buildsUsed: buildsUsed,
      physiquesUsed: <String>{for (final run in runs) run.physiqueId}.length,
    );
  }

  /// `(instanceId, totalUsage)` for every technique, ordered `(totalUsage
  /// desc, instanceId asc)`, capped at [limit].
  List<MapEntry<String, int>> mostUsedTechniques({int limit = 10}) => _topBy([
    for (final t in _state.techniques) MapEntry(t.instanceId, t.totalUsage),
  ], limit);

  /// `(affixId, timesUsed)` for every affix, ordered `(timesUsed desc, affixId
  /// asc)`, capped at [limit].
  List<MapEntry<String, int>> mostUsedAffixes({int limit = 10}) => _topBy([
    for (final a in _state.affixes) MapEntry(a.affixId, a.timesUsed),
  ], limit);

  /// For each [AlmanacDiscoveryType] key in [known], how many DISTINCT
  /// `contentId`s of that type have been discovered vs how many the caller
  /// listed as knowable. `fraction` is `0.0` when the known total is `0`.
  Map<AlmanacDiscoveryType, DiscoveryCompletion> discoveryCompletion({
    required Map<AlmanacDiscoveryType, Set<String>> known,
  }) {
    final result = <AlmanacDiscoveryType, DiscoveryCompletion>{};
    for (final entry in known.entries) {
      final type = entry.key;
      final total = entry.value.length;
      final discovered =
          <String>{
            for (final discovery in _state.discoveries)
              if (discovery.type == type) discovery.contentId,
          }.length;
      result[type] = DiscoveryCompletion(
        discovered: discovered,
        total: total,
        fraction: total == 0 ? 0.0 : discovered / total,
      );
    }
    return Map<AlmanacDiscoveryType, DiscoveryCompletion>.unmodifiable(result);
  }

  // ---------------------------------------------------------------------------
  // Internals
  // ---------------------------------------------------------------------------

  List<AlmanacRunRecord> _runsForLineage(String lineageId) =>
      List<AlmanacRunRecord>.unmodifiable([
        for (final run in _state.runs)
          if (run.lineageId == lineageId) run,
      ]);

  int _distinctDiscoveryContent(
    AlmanacDiscoveryType type,
    Set<String> runIds,
  ) =>
      <String>{
        for (final discovery in _state.discoveries)
          if (discovery.type == type && runIds.contains(discovery.runId))
            discovery.contentId,
      }.length;

  List<MapEntry<String, int>> _topBy(
    List<MapEntry<String, int>> entries,
    int limit,
  ) {
    entries.sort((a, b) {
      final byCount = b.value.compareTo(a.value);
      return byCount != 0 ? byCount : a.key.compareTo(b.key);
    });
    final take = limit < 0 ? 0 : limit;
    final capped = entries.length > take ? entries.sublist(0, take) : entries;
    return List<MapEntry<String, int>>.unmodifiable(capped);
  }

  static T? _firstWhereOrNull<T>(Iterable<T> items, bool Function(T) test) {
    for (final item in items) {
      if (test(item)) return item;
    }
    return null;
  }
}

/// Record-derived statistics for one lineage. Immutable; equal by value.
class LineageStatistics {
  const LineageStatistics({
    required this.runs,
    required this.wins,
    required this.losses,
    required this.techniquesDiscovered,
    required this.itemsDiscovered,
    required this.affixesDiscovered,
    required this.buildsUsed,
    required this.physiquesUsed,
  });

  /// Runs recorded for this lineage.
  final int runs;

  /// Runs with `outcome == RunOutcome.won`.
  final int wins;

  /// Runs with `outcome == RunOutcome.lost`.
  final int losses;

  /// Distinct technique `contentId`s discovered on this lineage's runs.
  final int techniquesDiscovered;

  /// Distinct item `contentId`s discovered on this lineage's runs.
  final int itemsDiscovered;

  /// Distinct affix `contentId`s discovered on this lineage's runs.
  final int affixesDiscovered;

  /// Build snapshots recorded with this `lineageId`.
  final int buildsUsed;

  /// Distinct `physiqueId`s across this lineage's runs.
  final int physiquesUsed;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LineageStatistics &&
          other.runs == runs &&
          other.wins == wins &&
          other.losses == losses &&
          other.techniquesDiscovered == techniquesDiscovered &&
          other.itemsDiscovered == itemsDiscovered &&
          other.affixesDiscovered == affixesDiscovered &&
          other.buildsUsed == buildsUsed &&
          other.physiquesUsed == physiquesUsed;

  @override
  int get hashCode => Object.hash(
    runs,
    wins,
    losses,
    techniquesDiscovered,
    itemsDiscovered,
    affixesDiscovered,
    buildsUsed,
    physiquesUsed,
  );

  @override
  String toString() =>
      'LineageStatistics(runs: $runs, wins: $wins, losses: $losses, '
      'techniquesDiscovered: $techniquesDiscovered, '
      'itemsDiscovered: $itemsDiscovered, '
      'affixesDiscovered: $affixesDiscovered, buildsUsed: $buildsUsed, '
      'physiquesUsed: $physiquesUsed)';
}

/// Progress toward a knowable set of one discovery type. Immutable; equal by
/// value.
class DiscoveryCompletion {
  const DiscoveryCompletion({
    required this.discovered,
    required this.total,
    required this.fraction,
  });

  /// Distinct `contentId`s of this type seen in the state.
  final int discovered;

  /// Size of the caller-supplied knowable set for this type.
  final int total;

  /// `discovered / total`, or `0.0` when [total] is `0`.
  final double fraction;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DiscoveryCompletion &&
          other.discovered == discovered &&
          other.total == total &&
          other.fraction == fraction;

  @override
  int get hashCode => Object.hash(discovered, total, fraction);

  @override
  String toString() =>
      'DiscoveryCompletion(discovered: $discovered, total: $total, '
      'fraction: $fraction)';
}
