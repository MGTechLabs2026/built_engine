import '../spatial/container.dart';
import '../spatial/placement_rule.dart';

/// The shape of a Tome — what `Container` layout backs it, plus any
/// content-specific placement constraints — registered once via
/// `TomeService.defineTome`, not per-owner.
///
/// Deliberately builds on `Container.grid`/`Container.namedSlots` directly
/// rather than re-deriving slot layout — no `TomeGrid`/`BackpackGrid`
/// duplicate of what `Container` already does.
class TomeDefinition {
  const TomeDefinition({
    required this.id,
    required Container Function() buildContainer,
    this.extraPlacementRules = const [],
  }) : _buildContainer = buildContainer;

  /// A grid-shaped Tome — see `Container.grid`.
  factory TomeDefinition.grid({
    required String id,
    required int width,
    required int height,
    List<PlacementRule> extraPlacementRules = const [],
  }) =>
      TomeDefinition(
        id: id,
        buildContainer: () => Container.grid(width, height),
        extraPlacementRules: extraPlacementRules,
      );

  /// A named-slot Tome — see `Container.namedSlots`.
  factory TomeDefinition.namedSlots({
    required String id,
    required Iterable<String> slotIds,
    List<PlacementRule> extraPlacementRules = const [],
  }) =>
      TomeDefinition(
        id: id,
        buildContainer: () => Container.namedSlots(slotIds),
        extraPlacementRules: extraPlacementRules,
      );

  final String id;
  final List<PlacementRule> extraPlacementRules;
  final Container Function() _buildContainer;

  /// Builds a fresh [Container] matching this definition's shape — called
  /// once per `TomeService.createTome`.
  Container buildContainer() => _buildContainer();
}
