import 'package:build_engine/build_engine.dart';

/// The item entities currently equipped on a combatant, in equip order.
/// Plugin-local state — this is what a future query or UI would read to
/// answer "what is this combatant wearing."
class MartialLoadoutComponent {
  const MartialLoadoutComponent({required this.equippedItems});

  final List<EntityId> equippedItems;

  /// A plain, stable structure — no engine-wide Serialization
  /// integration, matching `CombatStateComponent`'s module-local
  /// precedent.
  Map<String, dynamic> toJson() =>
      {'equippedItems': [for (final id in equippedItems) id.value]};

  factory MartialLoadoutComponent.fromJson(Map<String, dynamic> json) =>
      MartialLoadoutComponent(
        equippedItems: [
          for (final value in json['equippedItems'] as List<dynamic>)
            EntityId(value as int),
        ],
      );
}
