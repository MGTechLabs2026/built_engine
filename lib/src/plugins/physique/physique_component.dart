/// A character's assigned physique — deliberately minimal: only the
/// stable [physiqueId] (see `PhysiqueTypes`). Everything else about a
/// physique (tags, primary affinity, synergy modifiers) is data, held
/// in `ContentRegistry`/`ModifierCollection` and resolved from this id
/// when needed, never duplicated onto the component itself.
class PhysiqueComponent {
  const PhysiqueComponent(this.physiqueId);

  final String physiqueId;
}
