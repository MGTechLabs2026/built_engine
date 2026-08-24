/// One enemy's combat stats — plain data, the game layer's own concept
/// (Core/Combat never see this type, only the `AttackAction` a step in
/// `game_run.dart` builds from it).
class Enemy {
  const Enemy({
    required this.id,
    required this.health,
    required this.damage,
    required this.damageStat,
    required this.initiative,
  });

  final String id;
  final num health;
  final num damage;
  final String damageStat;
  final num initiative;
}
