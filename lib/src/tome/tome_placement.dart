import '../spatial/position.dart';
import '../spatial/slot.dart';
import 'build_component_ref.dart';

/// A read-model for one current Tome placement — what `TomeService.inspect`
/// returns. `slot`/`size`/`rotation` describe *where* in the Tome;
/// `buildComponentRef` describes *what*. [BuildResolver] discards the
/// where when producing an [ActiveBuild] — spatial layout is a Tome/UI
/// concern, not a Combat concern.
class TomePlacement {
  const TomePlacement({
    required this.slot,
    required this.buildComponentRef,
    required this.size,
    required this.rotation,
  });

  final SlotId slot;
  final BuildComponentRef buildComponentRef;
  final ItemSize size;
  final Rotation rotation;
}
