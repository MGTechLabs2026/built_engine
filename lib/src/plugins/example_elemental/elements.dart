import 'package:build_engine/build_engine.dart';

import 'elemental_affinity_component.dart';

/// The three elements this example plugin's vertical slice implements.
/// Not components — an element is a marker tag (`element:<id>`) granted
/// by [attuneToElement], mirroring `MartialStyles`/`learnStyle`.
abstract final class Elements {
  static const fire = 'fire';
  static const water = 'water';
  static const lightning = 'lightning';
}

RuleContext _standaloneContext(EntityId subject, PluginContext context) =>
    RuleContext(
      subject: subject,
      triggerEvent: const Object(),
      entities: context.entities,
      components: context.components,
      events: context.events,
      rng: context.rng,
      eventCounts: context.rules.eventCounts,
    );

/// Grants [entity] the `element:<element>` tag and merges [affinity] into
/// its `ElementalAffinityComponent` (creating the component if absent,
/// preserving any other element's existing affinity).
void attuneToElement(
  EntityId entity,
  String element,
  num affinity,
  PluginContext context,
) {
  final existing =
      context.components.get<ElementalAffinityComponent>(entity);
  context.components.add(
    entity,
    ElementalAffinityComponent({
      ...?existing?.affinities,
      element: affinity,
    }),
  );
  AddTag('element:$element').apply(_standaloneContext(entity, context));
}
