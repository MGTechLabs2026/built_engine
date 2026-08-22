import 'package:build_engine/build_engine.dart';

/// A battle's turn order and status, attached to a dedicated battle
/// entity (not to any participant) — a battle is itself an `EntityId`, so
/// multiple concurrent battles need no extra machinery.
class CombatStateComponent {
  const CombatStateComponent({
    required this.participants,
    required this.currentTurnIndex,
    required this.round,
    required this.active,
  });

  /// Fixed initiative order, set once by `CombatSystem.startBattle`.
  final List<EntityId> participants;

  /// Index into [participants] of whoever's turn it currently is.
  final int currentTurnIndex;

  /// Increments each time [currentTurnIndex] wraps back to 0.
  final int round;

  /// `false` once the battle has ended (a `BattleWon`/`BattleLost` pair
  /// has been published).
  final bool active;

  /// A plain, stable structure — no engine-wide Serialization
  /// integration, matching `Container.toJson`'s module-local precedent.
  Map<String, dynamic> toJson() => {
        'participants': [for (final id in participants) id.value],
        'currentTurnIndex': currentTurnIndex,
        'round': round,
        'active': active,
      };

  factory CombatStateComponent.fromJson(Map<String, dynamic> json) =>
      CombatStateComponent(
        participants: [
          for (final value in json['participants'] as List<dynamic>)
            EntityId(value as int),
        ],
        currentTurnIndex: json['currentTurnIndex'] as int,
        round: json['round'] as int,
        active: json['active'] as bool,
      );
}
