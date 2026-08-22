/// Identifies where a [Modifier] came from, for later bulk removal via
/// `ModifierCollection.removeBySource`. Not tied to `EntityId` — a source
/// can be an item's data id, a rule's identifier, a plugin name, or any
/// other stable string key a caller chooses.
class ModifierSource {
  const ModifierSource(this.id);

  final String id;

  @override
  bool operator ==(Object other) => other is ModifierSource && other.id == id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'ModifierSource($id)';
}
