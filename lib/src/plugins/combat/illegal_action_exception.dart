/// Thrown by `CombatSystem.executeAction` when it's called on a battle
/// that isn't active, or with an action whose actor isn't the entity
/// whose turn it currently is — a programmer-error/caller-misuse case,
/// mirroring `Container`'s `InvalidPlacementException` convention:
/// illegal *use* throws; a legal-but-unsuccessful outcome (failed
/// conditions) does not.
class IllegalActionException implements Exception {
  const IllegalActionException(this.message);

  final String message;

  @override
  String toString() => 'IllegalActionException: $message';
}
