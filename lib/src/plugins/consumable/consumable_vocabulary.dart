/// Stable ids + keys for the Consumable plugin — a typo is a compile
/// error, not a silent string mismatch (same rationale as `ItemIds`).
const consumableReferenceType = 'consumable';

/// The per-fight charge pool key on the build owner — one per content id.
/// Every hung copy of the same consumable sums into this one pool
/// (`ConsumableBinder.grant`). Defined `max: double.infinity` (SP3 §5.1.1):
/// the value is an aggregate, not a single copy's capacity.
String consumableChargeResource(String contentId) => 'consumable:$contentId';

abstract final class ConsumableIds {
  static const healPotion = 'heal_potion';
  static const firebomb = 'firebomb';
  static const powerTonic = 'power_tonic';
  static const cleanseTonic = 'cleanse_tonic';
}
