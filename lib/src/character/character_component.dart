/// Marks an entity as a character for the current run. Carries no data of
/// its own — its presence on an entity is the entire identity signal.
/// Everything else a character needs (physique, resources, item mastery,
/// learned techniques, Tome, progression, combat state, ...) is a separate
/// component attached by a later plugin; Core knows only that the entity
/// is a character, never what kind.
class CharacterComponent {
  const CharacterComponent();
}
