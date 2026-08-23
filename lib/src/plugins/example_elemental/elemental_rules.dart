import 'package:build_engine/build_engine.dart';

import 'elemental_effects.dart';

/// This example plugin's one cross-cutting interaction: "water conducts"
/// — an entity already tagged `status:soaked` that takes damage also
/// gets shocked. Reacts to Core's own `EntityDamaged` event (published
/// by core's `Damage` effect) — needs no Combat dependency at all,
/// unlike MartialArts' `EntityDamaged` rules.
List<Rule> buildElementalRules() => [
      Rule(
        trigger: EntityDamaged,
        subjectOf: (event) => (event as EntityDamaged).id,
        conditions: const [StatusActive('status:soaked')],
        effects: const [ApplyElementalStatus('lightning')],
      ),
    ];
