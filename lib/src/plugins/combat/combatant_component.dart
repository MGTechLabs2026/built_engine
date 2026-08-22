/// Marks an entity as a participant in Combat and carries the data its
/// turn order and win/loss grouping need. `team` and `initiative` are
/// arbitrary values a caller/content plugin chooses — Combat never
/// interprets what a team name means beyond grouping and comparing it.
class CombatantComponent {
  const CombatantComponent({required this.team, this.initiative = 0});

  /// An arbitrary label used to group participants for win/loss
  /// determination. Combat never interprets its value.
  final String team;

  /// Turn order: a battle's participants act in descending order of this
  /// value; ties break by the order given to `CombatSystem.startBattle`.
  final num initiative;

  /// A plain, stable structure — no engine-wide Serialization
  /// integration, matching `Container.toJson`'s module-local precedent.
  Map<String, dynamic> toJson() => {'team': team, 'initiative': initiative};

  factory CombatantComponent.fromJson(Map<String, dynamic> json) =>
      CombatantComponent(
        team: json['team'] as String,
        initiative: json['initiative'] as num,
      );
}
