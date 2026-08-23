/// The four physique types this plugin implements. Not components — a
/// physique is data, attached to a character via a [PhysiqueComponent]
/// holding only this stable id.
abstract final class PhysiqueTypes {
  static const sturdy = 'sturdy';
  static const power = 'power';
  static const burst = 'burst';
  static const endurance = 'endurance';

  /// All four ids, in a fixed order — `initializePhysique` indexes into
  /// this list via `RngService.nextInt`, so this order is part of what
  /// makes a given seed's outcome deterministic.
  static const all = [sturdy, power, burst, endurance];
}

/// The two broad martial traditions `physique_content.dart`'s synergy
/// modifiers gate on — `ARCHITECTURE_AUDIT.md`'s Observation A/C flagged
/// these as raw literals carried over unaddressed from the original
/// Observation B fix. This is the entire interoperability contract with
/// MartialArts' own tradition tags (`martial_vocabulary.dart`'s
/// `MartialTraditions`) — two independent constant classes with matching
/// *values*, not a shared import, is deliberate: Physique still never
/// imports MartialArts (see `ARCHITECTURE.md`'s Physique section); it
/// only agrees on the tag *names*.
abstract final class PhysiqueTraditions {
  static const western = 'western';
  static const eastern = 'eastern';
}
