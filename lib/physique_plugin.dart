/// Public API for PhysiquePlugin — a character's body type
/// (Sturdy/Power/Burst/Endurance). Depends on nothing but Core; never
/// imports MartialArtsPlugin or CombatPlugin. Import this, not
/// `lib/src/...` directly.
library;

export 'src/plugins/physique/physique_component.dart';
export 'src/plugins/physique/physique_types.dart';
