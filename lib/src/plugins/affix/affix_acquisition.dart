// lib/src/plugins/affix/affix_acquisition.dart
//
// NOTE: this file must NOT import the Almanac barrel
// (`package:build_engine/almanac`) or anything under `src/plugins/almanac`.
// It returns plain records; the composition boundary builds the Almanac
// value objects.
import 'package:build_engine/build_engine.dart';

import 'affix_application.dart';
import 'affix_resolver.dart';

/// A logical run's identity, carried into every acquisition. [runId] is
/// opaque and caller-supplied; distinct logical runs must supply
/// distinct [runId]s.
class RunRef {
  const RunRef({required this.runId, required this.runNumber});
  final String runId;
  final int runNumber;
}

/// The single owner of `affixEventId`. One instance per logical run,
/// created by the engine reward/run layer. Deterministic monotonic
/// counter — no RNG. The sequence makes acquisition ids distinct
/// *within* one logical run; it makes no cross-run guarantee (that is
/// the caller's `runId` contract).
class AffixAcquisitionIdSource {
  int _seq = 0;

  String next({required RunRef run, required int slotPosition}) =>
      '${run.runId}:affix:$slotPosition:${_seq++}';
}

/// A plain engine-domain result — one per acquired affix. Carries no
/// Almanac-module type; the composition boundary builds
/// `AffixObservation` / `AffixSnapshot` from these fields.
class AffixAcquisition {
  const AffixAcquisition({
    required this.affixId,
    required this.affixEventId,
    required this.runId,
    required this.runNumber,
    required this.stat,
    required this.value,
    required this.category,
  });

  final String affixId;
  final String affixEventId; // from AffixAcquisitionIdSource — opaque, never parsed
  final String runId;
  final int runNumber;
  final String stat; // mechanic kind: 'weapon_stat_bonus' / 'heal' / 'bank_progression'
  final num value; // == the affix's AffixMechanic.amount
  final String category; // the affix definition's category, verbatim
}

/// Applies every non-null slot's canonical mechanics (in position
/// order), mints one `affixEventId` per acquired affix via [idSource],
/// and returns the plain records. Consumes no RNG and touches no
/// Almanac. A no-affix slot yields nothing.
List<AffixAcquisition> acquireAffixes({
  required AffixResolution resolution,
  required AffixApplicationTarget target,
  required AffixAcquisitionIdSource idSource,
  required RunRef run,
  required PluginContext context,
}) {
  final out = <AffixAcquisition>[];
  for (final slot in resolution.slots) {
    final affix = slot.affix;
    if (affix == null) continue;
    final stat = applyAffixMechanic(affix, target, context).stat;
    final eventId = idSource.next(run: run, slotPosition: slot.position);
    out.add(AffixAcquisition(
      affixId: affix.id,
      affixEventId: eventId,
      runId: run.runId,
      runNumber: run.runNumber,
      stat: stat,
      value: affix.mechanic.amount,
      category: affix.category,
    ));
  }
  return out;
}
