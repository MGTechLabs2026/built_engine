import '../spatial/container.dart';

/// An owner's live Tome — pure state, attached via `ComponentStore` exactly
/// like any other component. [container] holds the actual placements;
/// [definitionId] identifies which `TomeDefinition` this was built from, so
/// `TomeService` can re-consult its `extraPlacementRules` for later
/// insert/move/validate calls.
///
/// The Tome is not an inventory — this is an active build configuration:
/// nothing here is combat logic, and nothing here is consumed directly by
/// Combat (see `ActiveBuild`/`BuildResolver`).
class TomeInstance {
  TomeInstance({required this.definitionId, required this.container});

  final String definitionId;
  final Container container;
}
