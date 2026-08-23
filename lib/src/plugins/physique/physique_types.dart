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
